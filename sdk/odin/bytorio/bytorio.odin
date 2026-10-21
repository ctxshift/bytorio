package bytorio

import abi "../../../runtime/odin/abi"
import g "../../../runtime/odin/graphics"
import w "../../../runtime/odin/resource_protocol"
import gfx "../gfx"
import resources "../resource"
import "base:runtime"

PROFILE :: #config(CONSOLE_PROFILE, 1)
#assert(
    PROFILE == 1 ||
    PROFILE == abi.PROFILE_RESOURCE ||
    PROFILE == abi.PROFILE_3D ||
    PROFILE == abi.PROFILE_TEXTURED_3D ||
    PROFILE == abi.PROFILE_ALPHA_3D ||
    PROFILE == abi.PROFILE_EFFECTS_3D,
)
when PROFILE == abi.PROFILE_EFFECTS_3D {
    VERSION :: "0.6.0"
    VERSION_WORD :: u32(abi.EFFECTS_3D_SDK)
} else when PROFILE == abi.PROFILE_ALPHA_3D {
    VERSION :: "0.5.0"
    VERSION_WORD :: u32(abi.ALPHA_3D_SDK)
} else when PROFILE == abi.PROFILE_TEXTURED_3D {
    VERSION :: "0.4.0"
    VERSION_WORD :: u32(abi.TEXTURED_3D_SDK)
} else when PROFILE == abi.PROFILE_3D {
    VERSION :: "0.3.0"
    VERSION_WORD :: u32(abi.PREVIEW_3D_SDK)
} else when PROFILE == abi.PROFILE_RESOURCE {
    VERSION :: "0.2.0"
    VERSION_WORD :: u32(abi.RESOURCE_SDK_VERSION)
} else {
    VERSION :: "0.1.0"
    VERSION_WORD :: u32(256)
}
DT :: 1.0 / 60.0
Capabilities :: struct {
    input_version:                                                       u32,
    profile, abi, sdk, features, protocol:                               u32,
    resource_bytes, slots, payload_bytes, audio_rate, audio_lead_frames: u32,
}
capabilities :: proc() -> Capabilities {
    resource := PROFILE != 1
    return {
        abi.INPUT_VERSION,
        u32(PROFILE),
        u32(abi.RESOURCE_ABI_VERSION) if resource else 1,
        VERSION_WORD,
        game_required_features(),
        game_resource_protocol() if resource else 0,
        w.maxResourceBytes,
        w.maxSlots,
        w.maxPayload,
        w.audioRate,
        w.audioLeadFrames,
    }
}
Button :: enum u32 {
    Left         = 1,
    Right        = 2,
    Up           = 4,
    Down         = 8,
    Action       = 16,
    MoveLeft     = abi.BUTTON_MOVE_LEFT,
    MoveRight    = abi.BUTTON_MOVE_RIGHT,
    MoveUp       = abi.BUTTON_MOVE_UP,
    MoveDown     = abi.BUTTON_MOVE_DOWN,
    PanLeft      = abi.BUTTON_PAN_LEFT,
    PanRight     = abi.BUTTON_PAN_RIGHT,
    PanUp        = abi.BUTTON_PAN_UP,
    PanDown      = abi.BUTTON_PAN_DOWN,
    RotateLeft   = abi.BUTTON_ROTATE_LEFT,
    RotateRight  = abi.BUTTON_ROTATE_RIGHT,
    Reset        = abi.BUTTON_RESET,
    PointerLeft  = abi.BUTTON_POINTER_LEFT,
    PointerRight = abi.BUTTON_POINTER_RIGHT,
    PointerHover = abi.BUTTON_POINTER_HOVER,
    WheelUp      = abi.BUTTON_WHEEL_UP,
    WheelDown    = abi.BUTTON_WHEEL_DOWN,
    Inventory    = abi.BUTTON_INVENTORY,
    Character    = abi.BUTTON_CHARACTER,
    Skills       = abi.BUTTON_SKILLS,
    Quest        = abi.BUTTON_QUEST,
    Map          = abi.BUTTON_MAP,
    Potion1      = abi.BUTTON_POTION_1,
    Potion2      = abi.BUTTON_POTION_2,
    Potion3      = abi.BUTTON_POTION_3,
    Potion4      = abi.BUTTON_POTION_4,
    Shift        = abi.BUTTON_SHIFT,
    Escape       = abi.BUTTON_ESCAPE,
}
Display :: enum u32 {
    High = abi.DISPLAY_HIGH,
    Low  = abi.DISPLAY_LOW,
}
Callbacks :: struct {
    init:   proc(),
    update: proc(dt: f64),
    draw:   proc(),
}
Config :: struct {
    graphics: []u8,
    display:  Display,
}

callbacks: Callbacks
graphics: []u8
frame: abi.Frame
held, down, up, clock, random_state: u32
pointer_active: bool
pointer_hover: bool
pointer_x, pointer_y: f64
diagnostic: [1024]u8
diagnostic_size: u32

fail :: proc(message: string) {
    if diagnostic_size != 0 {

        return
    }
    diagnostic_size = u32(min(len(message), len(diagnostic)))
    for i in 0 ..< int(diagnostic_size) {

        diagnostic[i] = message[i]
    }
}
valid :: proc(ok: bool, message: string) -> bool {
    if diagnostic_size != 0 {

        return false
    }
    if !ok {

        fail(message)
        return false
    }
    return true
}
coordinates :: proc(x, y: int) -> bool {
    return valid(
        x >= abi.COORDINATE_MIN &&
        x <= abi.COORDINATE_MAX &&
        y >= abi.COORDINATE_MIN &&
        y <= abi.COORDINATE_MAX,
        "coordinates outside supported range",
    )
}

// Called by the generated entry point. Game authors provide ordinary callbacks.
start :: proc(hooks: Callbacks, config: Config) {
    when ODIN_ARCH == .wasm32 {

        context.allocator = runtime.default_wasm_allocator()
    }
    callbacks, graphics = hooks, config.graphics
    diagnostic_size = 0
    held, down, up, clock = 0, 0, 0, 0
    pointer_active = false
    pointer_hover = false
    pointer_x, pointer_y = 0, 0
    random_state = abi.DEFAULT_RANDOM_SEED
    frame = {
        version  = abi.VERSION,
        clear    = abi.DEFAULT_CLEAR_COLOR,
        sprite_x = abi.COORDINATE_MIN,
        sprite_y = abi.COORDINATE_MIN,
    }
    g.begin()
    mode := abi.DISPLAY_HIGH if u32(config.display) == 0 else u32(config.display)
    if !valid(g.set_display(mode), "unsupported display mode") {

        return
    }
    if !valid(
        len(graphics) > 0 && len(graphics) <= abi.MAX_GRAPHICS_BYTES,
        "invalid graphics packet length",
    ) {

        return
    }
    if !valid(
        hooks.init != nil && hooks.update != nil && hooks.draw != nil,
        "missing game callback",
    ) {

        return
    }
    resources.begin(0)
    callbacks.init()
    resources.end()
}
display :: proc(mode: Display) {
    if diagnostic_size == 0 && !g.set_display(u32(mode)) {

        fail("unsupported display mode")
    }
}
size :: proc() -> (int, int) {

    return int(
        g.display_mode >> abi.DISPLAY_DIMENSION_BITS,
    ), int(g.display_mode & abi.DISPLAY_DIMENSION_MASK)
}
rgb :: proc(r, g, b: int) -> u32 {
    if !valid(
        r >= 0 && r <= 255 && g >= 0 && g <= 255 && b >= 0 && b <= 255,
        "color channel outside supported range",
    ) {

        return abi.COLOR_OPAQUE_BLACK
    }
    return abi.COLOR_OPAQUE_BLACK | u32(b) << 16 | u32(g) << 8 | u32(r)
}
clear :: proc(color: u32) {
    if valid(color >> 24 == 255, "colors must be opaque") {
        if resources.active_pass != 0 {

            gfx.clear(gfx.current_pass(), color)
        } else {

            frame.clear = color
        }
    }
}
rect :: proc(x, y, w, h: int, color: u32) {
    if coordinates(x, y) &&
       valid(color >> 24 == 255, "colors must be opaque") &&
       valid(
           w >= 0 && w <= abi.COORDINATE_MAX && h >= 0 && h <= abi.COORDINATE_MAX,
           "rectangle dimensions outside supported range",
       ) {

        if resources.active_pass != 0 {

            gfx.rect(gfx.current_pass(), f64(x), f64(y), f64(w), f64(h), color)
        } else {

            g.rect(x, y, w, h, color)
        }
    }
}
sprite :: proc(id, x, y: int, scale := 1) {
    if coordinates(x, y) &&
       valid(id >= 0 && id < 256 && scale >= 1 && scale <= 8, "invalid sprite ID or scale") {

        if resources.active_pass != 0 {

            gfx.sprite(gfx.current_pass(), id, f64(x), f64(y), f64(16 * scale), f64(16 * scale))
        } else {

            g.sprite(id, x, y, scale)
        }
    }
}
sprite_size :: proc(id, x, y, w, h: int) {
    if coordinates(x, y) &&
       valid(
           id >= 0 && id < 256 && w >= 1 && w <= 128 && h >= 1 && h <= 128,
           "invalid sprite ID or size",
       ) {

        if resources.active_pass != 0 {

            gfx.sprite(gfx.current_pass(), id, f64(x), f64(y), f64(w), f64(h))
        } else {

            g.sprite_size(id, x, y, w, h)
        }
    }
}
text :: proc(value: string, x, y: int, color: u32) {
    if !coordinates(x, y) ||
       !valid(color >> 24 == 255, "colors must be opaque") ||
       !valid(len(value) <= abi.MAX_TEXT_BYTES_PER_COMMAND, "text command exceeds 1024 bytes") {

        return
    }
    for char in value {

        if !valid(char >= 0 && char < 128, "text must be ASCII") {

            return
        }
    }
    if resources.active_pass != 0 {

        gfx.text(gfx.current_pass(), value, f64(x), f64(y), color)
    } else {

        g.text(value, x, y, color)
    }
}
buttons :: proc() -> u32 {

    return held & abi.LEGACY_BUTTON_MASK
}
all_buttons :: proc() -> u32 { return held }
button :: proc(key: Button) -> bool {

    return held & u32(key) != 0
}
pressed :: proc(key: Button) -> bool {

    return down & u32(key) != 0
}
released :: proc(key: Button) -> bool {

    return up & u32(key) != 0
}
pointer :: proc() -> (bool, f64, f64) {

    return pointer_active, pointer_x if pointer_active else 0, pointer_y if pointer_active else 0
}
pointer_position :: proc() -> (bool, f64, f64) {
    return pointer_hover, pointer_x, pointer_y
}
wheel :: proc() -> i32 {
    return i32(button(.WheelUp)) - i32(button(.WheelDown))
}
ticks :: proc() -> u32 {

    return clock
}
sound :: proc() {

    if diagnostic_size == 0 {

        frame.sounds += 1
    }
}
seed :: proc(value: u32) {

    random_state = abi.RANDOM_ZERO_SEED_FALLBACK if value == 0 else value
}
random_u32 :: proc() -> u32 {
    random_state ~= random_state << 13
    random_state ~= random_state >> 17
    random_state ~= random_state << 5
    return random_state
}
debug_position :: proc(x, y: f64) {
    if valid(
        x >= abi.COORDINATE_MIN &&
        x <= abi.COORDINATE_MAX &&
        y >= abi.COORDINATE_MIN &&
        y <= abi.COORDINATE_MAX,
        "invalid development position",
    ) {

        frame.x, frame.y = x, y
    }
}

@(export)
game_abi :: proc "c" () -> u32 {

    return abi.RESOURCE_ABI_VERSION if PROFILE != 1 else abi.VERSION
}
@(export)
game_profile :: proc "c" () -> u32 { return PROFILE }
@(export)
game_required_features :: proc "c" () -> u32 {
    if PROFILE == abi.PROFILE_EFFECTS_3D { return abi.EFFECTS_3D_FEATURES }
    if PROFILE == abi.PROFILE_ALPHA_3D { return abi.ALPHA_3D_FEATURES }
    if PROFILE == abi.PROFILE_TEXTURED_3D { return abi.TEXTURED_3D_FEATURES }
    return(
        abi.PREVIEW_3D_FEATURES if PROFILE == abi.PROFILE_3D else abi.RESOURCE_FEATURES if PROFILE == abi.PROFILE_RESOURCE else 0 \
    )
}
@(export)
game_sdk_version :: proc "c" () -> u32 {

    return VERSION_WORD
}
@(export)
game_frame_size :: proc "c" () -> u32 {

    return abi.FRAME_BYTES
}
@(export)
game_display_mode :: proc "c" () -> u32 {

    return g.display_mode
}
@(export)
game_update :: proc "c" (mask, active: u32, x, y: f64) {
    context = runtime.default_context()
    when ODIN_ARCH == .wasm32 {

        context.allocator = runtime.default_wasm_allocator()
    }
    if diagnostic_size != 0 {

        return
    }
    next := mask & abi.INPUT_BUTTON_MASK
    down, up = next &~ held, held &~ next
    held = next
    width, height := size()
    in_bounds := x >= 0 && x < f64(width) && y >= 0 && y < f64(height)
    pointer_active = active != 0 && in_bounds
    pointer_hover = (pointer_active || button(.PointerHover)) && in_bounds
    pointer_x, pointer_y = 0, 0
    if pointer_hover {

        pointer_x, pointer_y = x, y
    }
    clock += 1
    resources.begin(u64(clock))
    callbacks.update(DT)
    resources.end()
    frame.ticks = clock
}
@(export)
game_draw :: proc "c" () -> u32 {
    context = runtime.default_context()
    when ODIN_ARCH == .wasm32 {

        context.allocator = runtime.default_wasm_allocator()
    }
    g.begin()
    resources.begin_draw(u64(clock))
    if diagnostic_size == 0 {

        callbacks.draw()
    }
    resources.end()
    if g.overflow {

        fail("graphics batch capacity exceeded")
    }
    return u32(uintptr(&frame))
}
@(export)
game_commands :: proc "c" () -> u32 {

    return u32(uintptr(&g.commands))
}
@(export)
game_command_count :: proc "c" () -> u32 {

    return g.count
}
@(export)
game_command_stride :: proc "c" () -> u32 {

    return 32
}
@(export)
game_text :: proc "c" () -> u32 {

    return u32(uintptr(&g.text_bytes))
}
@(export)
game_text_size :: proc "c" () -> u32 {

    return g.text_count
}
@(export)
game_assets :: proc "c" () -> u32 {

    return u32(uintptr(raw_data(graphics)))
}
@(export)
game_assets_size :: proc "c" () -> u32 {

    return u32(len(graphics))
}
@(export)
game_error :: proc "c" () -> u32 {

    return u32(uintptr(&diagnostic))
}
@(export)
game_error_length :: proc "c" () -> u32 {
    context = runtime.default_context()
    if resources.error != "" {

        fail(resources.error)
    }
    return diagnostic_size
}
@(export)
game_resource_protocol :: proc "c" () -> u32 {
    if PROFILE == abi.PROFILE_EFFECTS_3D { return abi.EFFECTS_3D_PROTOCOL }
    if PROFILE == abi.PROFILE_ALPHA_3D { return abi.ALPHA_3D_PROTOCOL }
    if PROFILE == abi.PROFILE_TEXTURED_3D { return abi.TEXTURED_3D_PROTOCOL }
    return abi.PREVIEW_3D_PROTOCOL if PROFILE == abi.PROFILE_3D else abi.RESOURCE_PROTOCOL
}
@(export)
game_resource_configure :: proc "c" (session: u32) -> u32 {
    context = runtime.default_context()
    return u32(resources.configure(session))
}
@(export)
game_commit :: proc "c" () -> u32 {
    context = runtime.default_context()
    return resources.commit()
}
@(export)
game_commit_size :: proc "c" () -> u32 {

    return resources.packet_size()
}
@(export)
game_commit_ack :: proc "c" (sequence: u32) -> u32 {
    context = runtime.default_context()
    return u32(resources.ack(sequence))
}
@(export)
game_resource_mailbox :: proc "c" () -> u32 {

    return u32(uintptr(&resources.packet))
}
@(export)
game_resource_mailbox_capacity :: proc "c" () -> u32 {

    return w.mailboxCapacity
}
@(export)
game_resource_mailbox_size :: proc "c" (size: u32) -> u32 {
    if size > w.mailboxCapacity {

        return 0
    }
    resources.mailbox_size = size
    return 1
}
