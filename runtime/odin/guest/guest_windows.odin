package guest

import "core:mem"
import "core:strings"
import "core:math"
import "base:runtime"
import abi "../abi"

Game :: struct {
    engine: Engine,
    store: Store,
    ctx: Context,
    module: Module,
    linker: Linker,
    instance: Instance,
    memory: Memory,
    init, update, draw: Func,
    error: string,
}

close :: proc(game: ^Game) {
    if game.store != nil { wasmtime_store_delete(game.store) }
    if game.linker != nil { wasmtime_linker_delete(game.linker) }
    if game.module != nil { wasmtime_module_delete(game.module) }
    if game.engine != nil { wasm_engine_delete(game.engine) }
    delete(game.error)
    game^ = {}
}

fail :: proc(game: ^Game, message: string) -> bool {
    delete(game.error)
    game.error = strings.clone(message)
    return false
}

check :: proc(game: ^Game, error: Error, trap: Trap) -> bool {
    if error == nil && trap == nil { return true }
    message: ByteVec
    if error != nil { wasmtime_error_message(error, &message) }
    else { wasm_trap_message(trap, &message) }
    result := fail(game, string(message.data[:message.size]))
    wasm_byte_vec_delete(&message)
    if error != nil { wasmtime_error_delete(error) }
    if trap != nil { wasm_trap_delete(trap) }
    return result
}

call :: proc(game: ^Game, function: ^Func, args: []Val, result: []Val) -> bool {
    if !check(game, wasmtime_context_set_fuel(game.ctx, 2_000_000), nil) { return false }
    trap: Trap
    error := wasmtime_func_call(game.ctx, function, raw_data(args), uint(len(args)), raw_data(result), uint(len(result)), &trap)
    return check(game, error, trap)
}

function :: proc(game: ^Game, name: string, result: ^Func) -> bool {
    value: Extern
    if !wasmtime_instance_export_get(game.ctx, &game.instance, raw_data(name), uint(len(name)), &value) {
        return fail(game, "missing required game export")
    }
    defer wasmtime_extern_delete(&value)
    if value.kind != 0 { return fail(game, "required game export is not a function") }
    result^ = value.of.function
    return true
}

load :: proc(game: ^Game, bytes: []u8) -> bool {
    if len(bytes) == 0 || len(bytes) > abi.MAX_GAME_BYTES { return fail(game, "game module exceeds prototype size limit") }
    config := wasm_config_new()
    wasmtime_config_consume_fuel_set(config, true)
    wasmtime_config_max_wasm_stack_set(config, 256 * 1024)
    game.engine = wasm_engine_new_with_config(config)
    game.store = wasmtime_store_new(game.engine, nil, nil)
    game.ctx = wasmtime_store_context(game.store)
    wasmtime_store_limiter(game.store, abi.MAX_MEMORY_BYTES, 1024, 1, 1, 1)
    if !check(game, wasmtime_module_new(game.engine, raw_data(bytes), uint(len(bytes)), &game.module), nil) { return false }
    // Odin's freestanding math.sin lowers to this one explicitly allowed import.
    game.linker = wasmtime_linker_new(game.engine)
    params, results: TypeVec
    wasm_valtype_vec_new_uninitialized(&params, 1)
    wasm_valtype_vec_new_uninitialized(&results, 1)
    params.data[0], results.data[0] = wasm_valtype_new(3), wasm_valtype_new(3)
    function_type := wasm_functype_new(&params, &results)
    defer wasm_functype_delete(function_type)
    if !check(game, wasmtime_linker_define_func(game.linker, raw_data(string("env")), 3,
        raw_data(string("sin")), 3, function_type, sine, nil, nil), nil) { return false }
    if !check(game, wasmtime_context_set_fuel(game.ctx, 2_000_000), nil) { return false }
    trap: Trap
    error := wasmtime_linker_instantiate(game.linker, game.ctx, game.module, &game.instance, &trap)
    if !check(game, error, trap) { return false }

    functions := [3]string{"game_init", "game_update", "game_draw"}
    for name in functions {
        target := &game.init
        if name == "game_update" { target = &game.update }
        if name == "game_draw" { target = &game.draw }
        if !function(game, name, target) { return false }
    }
    queries := [2]string{"game_abi", "game_frame_size"}
    for name, index in queries {
        query: Func
        if !function(game, name, &query) { return false }
        result: [1]Val
        if !call(game, &query, nil, result[:]) { return false }
        expected := i32(abi.VERSION)
        if index == 1 { expected = abi.FRAME_BYTES }
        if result[0].kind != 0 || result[0].of.i32 != expected { return fail(game, "unsupported game ABI or frame size") }
    }
    memory: Extern
    if !wasmtime_instance_export_get(game.ctx, &game.instance, raw_data(string("memory")), 6, &memory) {
        return fail(game, "game must export memory")
    }
    defer wasmtime_extern_delete(&memory)
    if memory.kind != 3 { return fail(game, "game memory export has wrong type") }
    game.memory = memory.of.memory
    memory_type := wasmtime_memory_type(game.ctx, &game.memory)
    defer wasm_memorytype_delete(memory_type)
    maximum: u64
    if !wasmtime_memorytype_maximum(memory_type, &maximum) || maximum > abi.MAX_MEMORY_BYTES / 65536 ||
        wasmtime_memorytype_is64(memory_type) || wasmtime_memorytype_isshared(memory_type) ||
        wasmtime_memorytype_page_size(memory_type) != 65536 {
        return fail(game, "game memory must declare an 8 MiB maximum or less")
    }
    return call(game, &game.init, nil, nil)
}

sine :: proc "c" (_environment, _caller: rawptr, args: [^]Val, _nargs: uint, results: [^]Val, _nresults: uint) -> Trap {
    context = runtime.default_context()
    results[0].kind, results[0].of.f64 = 3, math.sin(args[0].of.f64)
    return nil
}

update :: proc(game: ^Game, input: abi.Input) -> bool {
    args: [4]Val
    args[0].kind, args[0].of.i32 = 0, i32(input.buttons)
    args[1].kind, args[1].of.i32 = 0, i32(input.pointer)
    args[2].kind, args[2].of.f64 = 3, input.x
    args[3].kind, args[3].of.f64 = 3, input.y
    return call(game, &game.update, args[:], nil)
}

draw :: proc(game: ^Game, frame: ^abi.Frame) -> bool {
    result: [1]Val
    if !call(game, &game.draw, nil, result[:]) { return false }
    if result[0].kind != 0 { return fail(game, "game_draw must return a frame offset") }
    offset := uint(u32(result[0].of.i32))
    size := wasmtime_memory_data_size(game.ctx, &game.memory)
    if offset > size || size - offset < abi.FRAME_BYTES { return fail(game, "frame offset outside guest memory") }
    data := wasmtime_memory_data(game.ctx, &game.memory)
    mem.copy(frame, &data[offset], abi.FRAME_BYTES)
    return true
}
