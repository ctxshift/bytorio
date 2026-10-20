package main
import gpu "../gpu/native"
import presentation "../presentation"

import abi "../abi"
import core "../core"
import guest "../guest"
import resources "../resources"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import windows "core:sys/windows"
import "core:time"

clock_ms :: proc() -> f64 {

    return time.duration_seconds(time.tick_since(time.Tick{})) * 1000
}
process_memory :: proc() -> (working, peak: uint) {
    counters := windows.PROCESS_MEMORY_COUNTERS {
        cb = size_of(windows.PROCESS_MEMORY_COUNTERS),
    }
    if !bool(
        windows.GetProcessMemoryInfo(windows.GetCurrentProcess(), &counters, size_of(counters)),
    ) {

        return 0, 0
    }
    return counters.WorkingSetSize, counters.PeakWorkingSetSize
}

// PROTOTYPE: CPU work only, with display/audio presentation excluded.
benchmark :: proc(app: ^App, path: string, startup_ms: f64, baseline_working: uint) -> int {
    bytes, read_error := os.read_entire_file(path, context.allocator)
    if read_error != nil {

        return error("cannot read benchmark replay")
    }
    defer delete(bytes)
    masks := make([dynamic]u32)
    defer delete(masks)
    for field in strings.fields(string(bytes)) {
        mask, ok := strconv.parse_u64(field)
        if !ok || mask > abi.INPUT_BUTTON_MASK {

            return error("invalid benchmark input")
        }
        append(&masks, u32(mask))
    }
    if len(masks) == 0 || len(masks) > 10000 {

        return error("invalid benchmark length")
    }
    timings := make([dynamic][3]f64, 0, len(masks) * 5)
    defer delete(timings)
    hashes := make([dynamic]u32, 0, len(masks))
    sounds := make([dynamic]u32, 0, len(masks))
    defer delete(hashes)
    defer delete(sounds)
    peak_heap: u32
    for pass in 0 ..< 7 {
        if !guest.initialize(&app.game) {

            return error(app.game.error)
        }
        for mask in masks {
            t0 := clock_ms()
            if !guest.update(&app.game, abi.Input{buttons = mask}) {

                return error(app.game.error)
            }
            t1 := clock_ms()
            if !guest.draw(&app.game, &app.frame) {

                return error(app.game.error)
            }
            t2 := clock_ms()
            if !render_current(app) {

                return error("invalid benchmark frame")
            }
            if app.gpu_enabled {
                if !gpu.present(
                    &app.game.resources,
                    core.pixels[:core.width * core.height],
                    core.width,
                    core.height,
                    1920,
                    1080,
                ) { return error("GPU benchmark presentation failed") }
            } else if app.game.resources.smooth_pan {
                app.present_pixels = presentation.prepare(
                    &app.presenter,
                    &app.game.resources,
                    1920,
                    1080,
                )
            }
            t3 := clock_ms()
            if pass >= 2 {

                append(&timings, [3]f64{t1 - t0, t2 - t1, t3 - t2})
            }
            if pass == 2 {

                append(&hashes, core.hash())
                append(&sounds, app.frame.sounds)
            }
        }
        peak_heap = max(peak_heap, guest.heap_query(&app.game, "game_heap_peak"))
    }
    working, peak_working := process_memory()
    fmt.printf(
        "{{\"startup\":{{\"totalMs\":%.6f,\"compileMs\":%.6f,\"instantiateMs\":%.6f,\"gameInitMs\":%.6f}},",
        startup_ms,
        app.game.compile_ms,
        app.game.instantiate_ms,
        app.game.initialize_ms,
    )
    fmt.printf(
        "\"memory\":{{\"currentLinear\":%d,\"heapBytes\":%d,\"heapPeak\":%d,\"baselineWorking\":%d,\"working\":%d,\"peakWorking\":%d}},",
        guest.memory_bytes(&app.game),
        guest.heap_query(&app.game, "game_heap_bytes"),
        peak_heap,
        baseline_working,
        working,
        peak_working,
    )
    stats := app.game.resources.stats
    if app.gpu_enabled {
        counts := gpu.statistics()
        fmt.printf(
            "\"gpuStats\":{{\"meshUploads\":%d,\"cacheHits\":%d,\"uploadBytes\":%d,\"gpuPresentation\":true}},",
            counts[0],
            counts[1],
            counts[2],
        )
    }
    storage := resources.mesh_storage(&app.game.resources)
    fmt.printf(
        "\"resourceStats\":{{\"currentResourceBytes\":%d,\"peakResourceBytes\":%d,\"packetBytes\":%d,\"hostCopyBytes\":%d,\"triangles\":%d,\"voxelCells\":%d,\"voxelFaces\":%d,\"voxelRebuilds\":%d,\"sourceBytes\":%d,\"geometryBytes\":%d,\"depthBytes\":%d}},",
        app.game.resources.bytes,
        stats.peak_bytes,
        stats.packet_bytes,
        stats.copy_bytes,
        stats.triangles,
        stats.voxel_cells,
        stats.voxel_faces,
        stats.voxel_rebuilds,
        storage[0],
        storage[1],
        storage[2],
    )
    fmt.printf(
        "\"metered\":%t,\"executorCacheEnabled\":%t,\"commandCount\":%d,\"timings\":[",
        app.game.metered,
        app.game.cache_enabled,
        app.game.count,
    )
    for row, i in timings {
        if i > 0 {

            fmt.print(",")
        }
        fmt.printf("[%.6f,%.6f,%.6f]", row[0], row[1], row[2])
    }
    fmt.print("],\"traces\":[")
    for hash, i in hashes {
        if i > 0 {

            fmt.print(",")
        }
        fmt.printf("{{\"hash\":%d,\"sounds\":%d}}", hash, sounds[i])
    }
    fmt.println("]}")
    return 0
}
