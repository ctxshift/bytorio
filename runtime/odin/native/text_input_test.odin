package main

import abi "../abi"
import "core:testing"
import sdl "vendor:sdl3"

send_text_key :: proc(app: ^App, key: sdl.Scancode, modifiers: sdl.Keymod = {}) {
    event: sdl.Event
    event.key = {
        type     = .KEY_DOWN,
        windowID = sdl.GetWindowID(app.window),
        scancode = key,
        mod      = modifiers,
    }
    text_event(app, &event)
}

@(test)
native_text_events :: proc(t: ^testing.T) {
    testing.expect(t, sdl.Init({.VIDEO}))
    defer sdl.Quit()
    app := new(App)
    defer free(app)
    app.window = sdl.CreateWindow("Text input conformance", 640, 360, {.HIDDEN})
    testing.expect(t, app.window != nil)
    if app.window == nil { return }
    defer sdl.DestroyWindow(app.window)
    app.focused = true
    app.logical_width, app.logical_height = 640, 360
    packet := abi.Text_Packet {
        header = {
            version   = 1,
            id        = 1,
            flags     = 1,
            max_bytes = 12,
            x         = 10,
            y         = 20,
            width     = 100,
            height    = 20,
        },
    }
    bytes := (cast(^[size_of(abi.Text_Packet)]u8)&packet)[:abi.TEXT_INPUT_HEADER_BYTES]
    testing.expect(t, abi.text_configure(&app.game.text_input, bytes))
    sync_text_input(app)
    testing.expect(t, sdl.TextInputActive(app.window))
    event: sdl.Event
    event.text = {
        type     = .TEXT_INPUT,
        windowID = sdl.GetWindowID(app.window),
        text     = "Aé🙂",
    }
    testing.expect(t, sdl.PushEvent(&event))
    found := false
    for sdl.PollEvent(&event) {
        text_event(app, &event)
        if event.type == .TEXT_INPUT { found = true }
    }
    testing.expect(t, found, "real SDL event queue delivered committed UTF-8")
    testing.expect_value(t, string(app.game.text_input.packet.bytes[:7]), "Aé🙂")
    event.edit = {
        type     = .TEXT_EDITING,
        windowID = sdl.GetWindowID(app.window),
        text     = "候",
    }
    text_event(app, &event)
    text_key(app, .BACKSPACE)
    text_key(app, .RETURN)
    testing.expect_value(t, app.game.text_input.packet.header.length, u32(7))
    testing.expect(t, abi.text_active(&app.game.text_input), "IME Enter does not submit")
    event.edit.text = ""
    text_event(app, &event)
    text_key(app, .BACKSPACE)
    testing.expect_value(t, string(app.game.text_input.packet.bytes[:3]), "Aé")
    testing.expect_value(t, app.game.text_input.packet.header.length, u32(3))
    text_key(app, .RETURN)
    testing.expect(t, !abi.text_active(&app.game.text_input))
    testing.expect(t, app.game.text_input.packet.header.flags & abi.TEXT_INPUT_SUBMITTED != 0)
    sync_text_input(app)
    testing.expect(t, !sdl.TextInputActive(app.window))
    event.text = {
        type     = .TEXT_INPUT,
        windowID = sdl.GetWindowID(app.window),
        text     = "stale",
    }
    testing.expect(t, sdl.PushEvent(&event))
    testing.expect(t, abi.text_configure(&app.game.text_input, bytes))
    sync_text_input(app)
    for sdl.PollEvent(&event) { text_event(app, &event) }
    testing.expect_value(t, app.game.text_input.packet.header.length, u32(0))
    text_key(app, .ESCAPE)
    testing.expect(t, app.game.text_input.packet.header.flags & abi.TEXT_INPUT_CANCELLED != 0)
    testing.expect(t, abi.text_configure(&app.game.text_input, bytes))
    testing.expect(t, abi.text_replace(&app.game.text_input, transmute([]u8)string("Aé🙂Z")))
    send_text_key(app, .HOME)
    send_text_key(app, .RIGHT)
    send_text_key(app, .RIGHT, sdl.KMOD_SHIFT)
    testing.expect_value(t, app.game.text_input.packet.header.start, u32(1))
    testing.expect_value(t, app.game.text_input.packet.header.end, u32(3))
    send_text_key(app, .DELETE)
    testing.expect_value(t, string(app.game.text_input.packet.bytes[:6]), "A🙂Z")
    send_text_key(app, .HOME)
    send_text_key(app, .DELETE)
    testing.expect_value(t, string(app.game.text_input.packet.bytes[:5]), "🙂Z")
    send_text_key(app, .END)
    send_text_key(app, .LEFT, sdl.KMOD_SHIFT)
    testing.expect_value(t, app.game.text_input.packet.header.start, u32(4))
    testing.expect_value(t, app.game.text_input.packet.header.end, u32(5))
    // The conformance runner uses SDL's dummy driver, keeping its clipboard local.
    if string(sdl.GetCurrentVideoDriver()) == "dummy" {
        testing.expect(t, sdl.SetClipboardText("é"))
        send_text_key(app, .V, sdl.KMOD_CTRL)
        testing.expect_value(t, string(app.game.text_input.packet.bytes[:6]), "🙂é")
        send_text_key(app, .A, sdl.KMOD_CTRL)
        testing.expect(t, sdl.SetClipboardText("01234567890123456"))
        send_text_key(app, .V, sdl.KMOD_CTRL)
        testing.expect_value(t, app.game.text_input.packet.header.length, u32(6))
        testing.expect_value(t, app.game.text_input.packet.header.start, u32(0))
        testing.expect_value(t, app.game.text_input.packet.header.end, u32(6))
        testing.expect(t, sdl.SetClipboardText("R"))
        send_text_key(app, .V, sdl.KMOD_CTRL)
        testing.expect_value(t, string(app.game.text_input.packet.bytes[:1]), "R")
        testing.expect_value(t, app.game.text_input.packet.header.length, u32(1))
    }
}
