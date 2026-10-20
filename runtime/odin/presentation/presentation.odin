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

floor_div :: proc(value, divisor: int) -> int {
    quotient := value / divisor
    return quotient - 1 if value < 0 && value % divisor != 0 else quotient
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
    shift_x := int(math.round(registry.preview_residual[0] * f64(scale)))
    shift_y := int(math.round(registry.preview_residual[1] * f64(scale)))
    out_width, out_height := width * scale, height * scale
    // Both world samples and unshifted HUD pixels are constant over integer
    // rectangles. Split at either grid's boundary, shade once, then copy rows.
    for y := 0; y < out_height; {
        sy := floor_div(y + shift_y, scale) + 1
        hud_y := y / scale
        next_y := min(out_height, sy * scale - shift_y, (hud_y + 1) * scale)
        row := state.pixels[y * out_width:(y + 1) * out_width]
        for x := 0; x < out_width; {
            sx := floor_div(x + shift_x, scale) + 1
            hud_x := x / scale
            next_x := min(out_width, sx * scale - shift_x, (hud_x + 1) * scale)
            at := hud_y * width + hud_x
            color: u32
            if registry.preview_mask[at] != 0 {
                color = registry.output[at]
            } else {
                color = resources.u32le(registry.preview, (sy * (width + 2) + sx) * 4)
                color = resources.over(color, registry.preview_background)
            }
            for &pixel in row[x:next_x] { pixel = color }
            x = next_x
        }
        for copy_y := y + 1; copy_y < next_y; copy_y += 1 {
            copy(state.pixels[copy_y * out_width:(copy_y + 1) * out_width], row)
        }
        y = next_y
    }
    state.width, state.height, state.active = out_width, height * scale, true
    return state.pixels
}
