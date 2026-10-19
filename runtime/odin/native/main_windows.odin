package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:strconv"
import sdl "vendor:sdl3"
import abi "../abi"
import core "../core"
import guest "../guest"

App :: struct {
    game: guest.Game,
    frame: abi.Frame,
    window: ^sdl.Window,
    renderer: ^sdl.Renderer,
    texture: ^sdl.Texture,
    audio: ^sdl.AudioStream,
    gamepad: ^sdl.Gamepad,
    focused: bool,
    sounds_played, audio_queued: u32,
}

error :: proc(message: string) -> int {
    fmt.eprintf("player: %s\n", message)
    return 1
}

cleanup :: proc(app: ^App) {
    if app.audio != nil { sdl.DestroyAudioStream(app.audio) }
    if app.gamepad != nil { sdl.CloseGamepad(app.gamepad) }
    if app.texture != nil { sdl.DestroyTexture(app.texture) }
    if app.renderer != nil { sdl.DestroyRenderer(app.renderer) }
    if app.window != nil { sdl.DestroyWindow(app.window) }
    sdl.Quit()
    guest.close(&app.game)
}

input :: proc(app: ^App) -> abi.Input {
    result: abi.Input
    if !app.focused { return result }
    keys := sdl.GetKeyboardState(nil)
    if keys[sdl.Scancode.LEFT] || keys[sdl.Scancode.A] { result.buttons |= 1 }
    if keys[sdl.Scancode.RIGHT] || keys[sdl.Scancode.D] { result.buttons |= 2 }
    if keys[sdl.Scancode.UP] || keys[sdl.Scancode.W] { result.buttons |= 4 }
    if keys[sdl.Scancode.DOWN] || keys[sdl.Scancode.S] { result.buttons |= 8 }
    if keys[sdl.Scancode.SPACE] { result.buttons |= 16 }
    if app.gamepad != nil {
        if sdl.GetGamepadButton(app.gamepad, .DPAD_LEFT) { result.buttons |= 1 }
        if sdl.GetGamepadButton(app.gamepad, .DPAD_RIGHT) { result.buttons |= 2 }
        if sdl.GetGamepadButton(app.gamepad, .DPAD_UP) { result.buttons |= 4 }
        if sdl.GetGamepadButton(app.gamepad, .DPAD_DOWN) { result.buttons |= 8 }
        if sdl.GetGamepadButton(app.gamepad, .SOUTH) { result.buttons |= 16 }
    }
    x, y, lx, ly: f32
    buttons := sdl.GetMouseState(&x, &y)
    if sdl.RenderCoordinatesFromWindow(app.renderer, x, y, &lx, &ly) {
        result.pointer = .LEFT in buttons && lx >= 0 && lx < abi.WIDTH && ly >= 0 && ly < abi.HEIGHT
        result.x, result.y = f64(lx), f64(ly)
    }
    return result
}

draw :: proc(app: ^App) -> bool {
    if !guest.draw(&app.game, &app.frame) { return false }
    return render_current(app)
}
render_current :: proc(app: ^App) -> bool {
    if !core.render(app.frame) {return guest.fail(&app.game,"invalid frame command")}
    valid := core.render_batch(app.game.batch[:app.game.count],app.game.text[:app.game.text_size]) if app.game.stride == 32 else core.render_commands(app.game.commands[:app.game.count])
    if !valid {return guest.fail(&app.game,"invalid frame command")}
    return true
}

run :: proc() -> int {
    app := new(App)
    defer free(app)
    defer cleanup(app)
    base := sdl.GetBasePath()
    if base == nil { return error("cannot locate player directory") }
    game_path := fmt.tprintf("%sgame.wasm", base)
    capture := ""
    replay_path := ""
    source_path := ""
    benchmark_path := ""
    unmetered := false
    no_executor_cache := false
    cache_config := ""
    smoke, check_only := false, false
    for i := 1; i < len(os.args); i += 1 {
        switch os.args[i] {
        case "--smoke": smoke = true
        case "--check": check_only = true
        case "--benchmark-unmetered": unmetered = true
        case "--no-executor-cache": no_executor_cache = true
        case "--game", "--capture", "--replay", "--source", "--benchmark", "--executor-cache":
            option := os.args[i]
            i += 1
            if i >= len(os.args) { return error("missing option argument") }
            if option == "--game" { game_path = os.args[i]
            } else if option == "--source" { source_path = os.args[i]
            } else if option == "--executor-cache" {cache_config = os.args[i]
            } else if option == "--benchmark" { benchmark_path = os.args[i]; check_only = true
            } else if option == "--replay" { replay_path = os.args[i]; check_only = true
            } else { capture = os.args[i] }
        case: return error("usage: player [--game file.wasm] [--source game.luau] [--smoke|--check|--replay inputs|--benchmark inputs [--benchmark-unmetered]] [--capture output.bmp]")
        }
    }
    if unmetered && benchmark_path == "" { return error("unmetered execution is limited to the development benchmark") }
    startup_start := clock_ms()
    baseline_working,_ := process_memory()
    bytes, read_error := os.read_entire_file(game_path, context.allocator)
    if read_error != nil { return error("cannot read game module") }
    defer delete(bytes)
    source: []u8
    if source_path != "" {
        source_error: os.Error
        source, source_error = os.read_entire_file(source_path, context.allocator)
        if source_error != nil { return error("cannot read Luau source") }
        if len(source) == 0 { return error("Luau source is empty") }
    }
    defer delete(source)
    if len(source) > 0 && !no_executor_cache && cache_config == "" {
        directory := fmt.tprintf("%sexecutor-cache",base)
        if os.make_directory_all(directory) != nil {return error("cannot create executor cache directory")}
        cache_config = fmt.tprintf("%sexecutor-cache.toml",base)
        config_text := fmt.tprintf("[cache]\ndirectory = %q\nfiles-total-size-soft-limit = \"64Mi\"\n",directory)
        if os.write_entire_file(cache_config,config_text) != nil {return error("cannot write executor cache configuration")}
    }
    if no_executor_cache {cache_config = ""}
    if !guest.load(&app.game, bytes, source, !unmetered, cache_config) { return error(app.game.error) }
    core.init()
    asset_size,graphics_ok := guest.read_graphics(&app.game)
    if !graphics_ok {return error(app.game.error)}
    if asset_size > 0 && !core.load_graphics(app.game.assets[:asset_size]) {return error("invalid graphics assets")}
    if !draw(app) { return error(app.game.error) }
    if benchmark_path != "" { return benchmark(app,benchmark_path,clock_ms()-startup_start,baseline_working) }
    if replay_path != "" {
        data, replay_error := os.read_entire_file(replay_path, context.allocator)
        if replay_error != nil { return error("cannot read input replay") }
        defer delete(data)
        for field in strings.fields(string(data)) {
            mask, ok := strconv.parse_u64(field)
            if !ok || mask > 31 { return error("invalid input replay") }
            if !guest.update(&app.game, abi.Input{buttons=u32(mask)}) || !draw(app) { return error(app.game.error) }
            fmt.printf("{{\"hash\":%d,\"sounds\":%d}}\n", core.hash(), app.frame.sounds)
        }
        return 0
    }

    if !check_only {
        if !sdl.Init({.VIDEO, .AUDIO, .GAMEPAD}) { return error(string(sdl.GetError())) }
        app.window = sdl.CreateWindow("Console player — Odin", abi.WIDTH * 3, abi.HEIGHT * 3, {.RESIZABLE})
        if app.window == nil { return error(string(sdl.GetError())) }
        app.renderer = sdl.CreateRenderer(app.window, nil)
        if app.renderer == nil { return error(string(sdl.GetError())) }
        _ = sdl.SetRenderVSync(app.renderer, 1)
        if !sdl.SetRenderLogicalPresentation(app.renderer, abi.WIDTH, abi.HEIGHT, .INTEGER_SCALE) { return error(string(sdl.GetError())) }
        app.texture = sdl.CreateTexture(app.renderer, .RGBA32, .STREAMING, abi.WIDTH, abi.HEIGHT)
        if app.texture == nil || !sdl.SetTextureScaleMode(app.texture, .NEAREST) { return error(string(sdl.GetError())) }
        spec := sdl.AudioSpec{format = .F32, channels = 1, freq = core.SAMPLE_RATE}
        app.audio = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, nil, nil)
        if app.audio == nil || !sdl.ResumeAudioStreamDevice(app.audio) { return error(string(sdl.GetError())) }
        pad_count: i32
        pads := sdl.GetGamepads(&pad_count)
        if pad_count > 0 { app.gamepad = sdl.OpenGamepad(pads[0]) }
        sdl.free(pads)
    }

    app.focused = true
    running := true
    previous := f64(sdl.GetTicksNS()) / 1e9
    accumulator: f64
    for running {
        event: sdl.Event
        if !check_only {
            for sdl.PollEvent(&event) {
                #partial switch event.type {
                case .QUIT: running = false
                case .WINDOW_FOCUS_LOST: app.focused = false; accumulator = 0
                case .WINDOW_FOCUS_GAINED: app.focused = true; accumulator = 0
                case .GAMEPAD_ADDED:
                    if app.gamepad == nil { app.gamepad = sdl.OpenGamepad(event.gdevice.which) }
                case .GAMEPAD_REMOVED:
                    if app.gamepad != nil && sdl.GetGamepadID(app.gamepad) == event.gdevice.which {
                        sdl.CloseGamepad(app.gamepad); app.gamepad = nil
                    }
                }
            }
        }
        now := f64(sdl.GetTicksNS()) / 1e9
        delta := clamp(now - previous, 0, 0.1)
        previous = now
        if smoke || check_only { accumulator += 1.0 / 60.0 }
        else if app.focused { accumulator += delta }
        steps := 0
        for accumulator >= 1.0 / 60.0 && steps < 5 {
            keys: abi.Input
            if smoke || check_only { keys = abi.smoke_input(app.frame.ticks) } else { keys = input(app) }
            if !guest.update(&app.game, keys) || !draw(app) { return error(app.game.error) }
            accumulator -= 1.0 / 60.0
            steps += 1
        }
        if steps == 5 { accumulator = 0 }
        if !check_only {
            if app.frame.sounds != app.sounds_played {
                _ = sdl.ClearAudioStream(app.audio)
                if !sdl.PutAudioStreamData(app.audio, &core.sample, size_of(core.sample)) { return error(string(sdl.GetError())) }
                app.audio_queued += core.SAMPLE_COUNT
                app.sounds_played = app.frame.sounds
            }
            if !sdl.UpdateTexture(app.texture, nil, &core.pixels, abi.WIDTH * 4) ||
                !sdl.SetRenderDrawColor(app.renderer, 0, 0, 0, 255) || !sdl.RenderClear(app.renderer) ||
                !sdl.RenderTexture(app.renderer, app.texture, nil, nil) || !sdl.RenderPresent(app.renderer) {
                return error(string(sdl.GetError()))
            }
            sdl.Delay(1)
        }
        if (smoke || check_only) && app.frame.ticks >= 120 { running = false }
    }
    if capture != "" && !check_only {
        surface := sdl.CreateSurfaceFrom(abi.WIDTH, abi.HEIGHT, .RGBA32, &core.pixels, abi.WIDTH * 4)
        if surface == nil { return error(string(sdl.GetError())) }
        saved := sdl.SaveBMP(surface, strings.clone_to_cstring(capture, context.temp_allocator))
        sdl.DestroySurface(surface)
        if !saved { return error(string(sdl.GetError())) }
    }
    // Double braces escape Odin's formatting syntax in the JSON report.
    fmt.printf("{{\"ticks\":%d,\"sounds\":%d,\"hash\":%d,\"spriteX\":%d,\"spriteY\":%d,\"audioQueuedFrames\":%d}}\n",
        app.frame.ticks, app.frame.sounds, core.hash(), app.frame.sprite_x, app.frame.sprite_y, app.audio_queued)
    return 0
}

main :: proc() {
    status := run()
    if status != 0 { os.exit(status) }
}
