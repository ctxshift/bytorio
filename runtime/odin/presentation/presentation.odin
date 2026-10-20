package presentation

import core "../core"
import resources "../resources"
import "core:math"

// Host presentation storage is separate from cartridge targets and capped at
// 1920x1080. It never changes framebuffer readbacks or gameplay coordinates.
State :: struct {
    pixels:        []u32,
    width, height: int,
    active:        bool,
}
close :: proc(state: ^State) {
    when ODIN_ARCH == .wasm32 { context.allocator = resources.wasm_allocator() }
    delete(state.pixels)
    state^ = {}
}

prepare :: proc(
    state: ^State,
    registry: ^resources.Registry,
    available_width, available_height: int,
) -> []u32 {
    when ODIN_ARCH == .wasm32 { context.allocator = resources.wasm_allocator() }
    state.active = false
    state.width, state.height = core.width, core.height
    if !registry.has_output || !registry.preview_enabled {
        return core.pixels[:core.width * core.height]
    }
    width, height := registry.output_width, registry.output_height
    scale := max(
        1,
        min(6, 1920 / width, 1080 / height, available_width / width, available_height / height),
    )
    if scale <= 1 { return core.pixels[:core.width * core.height] }
    count := width * height * scale * scale
    if len(state.pixels) != count {
        delete(state.pixels)
        state.pixels = make([]u32, count)
    }
    dx := math.round(registry.preview_residual[0] * f64(scale)) / f64(scale)
    dy := math.round(registry.preview_residual[1] * f64(scale)) / f64(scale)
    out_width := width * scale
    for y in 0 ..< height * scale {
        sy := int(math.floor((f64(y) + 0.5) / f64(scale) + 1 + dy))
        for x in 0 ..< out_width {
            at := (y / scale) * width + x / scale
            color: u32
            if registry.preview_mask[at] != 0 {
                color = registry.output[at]
            } else {
                sx := int(math.floor((f64(x) + 0.5) / f64(scale) + 1 + dx))
                color = resources.u32le(registry.preview, (sy * (width + 2) + sx) * 4)
                color = resources.over(color, registry.preview_background)
            }
            state.pixels[y * out_width + x] = color
        }
    }
    state.width, state.height, state.active = out_width, height * scale, true
    return state.pixels
}
