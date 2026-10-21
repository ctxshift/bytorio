package guest

import abi "../abi"
import "base:runtime"
import "core:crypto/hash"
import "core:fmt"
import "core:os"

Save_State :: struct {
    write_allowed:   bool,
    bytes:           [abi.MAX_SAVE_BYTES]u8,
    length, status:  u32,
    directory, path: string,
}

save_open :: proc(state: ^Save_State, identity: []u8) {
    state.write_allowed = true
    state.status = abi.SAVE_ERROR
    if len(identity) == 0 { return }
    directory := os.get_env("BYTORIO_SAVE_DIRECTORY", context.allocator)
    if directory == "" {
        base := os.get_env("LOCALAPPDATA", context.allocator)
        defer delete(base)
        if base == "" { return }
        directory = fmt.aprintf("%s/Bytorio/saves", base)
    }
    state.directory = directory
    digest: [32]u8
    hash.hash_bytes_to_buffer(.SHA256, identity, digest[:])
    name: [64]u8
    digits := "0123456789abcdef"
    for byte, i in digest {
        name[i * 2] = digits[byte >> 4]
        name[i * 2 + 1] = digits[byte & 15]
    }
    state.path = fmt.aprintf("%s/%s.sav", directory, string(name[:]))
    state.status = abi.SAVE_EMPTY
    if !os.exists(state.path) { return }
    file, open_error := os.open(state.path)
    if open_error != nil { state.status = abi.SAVE_ERROR; return }
    defer os.close(file)
    length, size_error := os.file_size(file)
    if size_error != nil || length <= 0 || length > abi.MAX_SAVE_BYTES {
        state.status = abi.SAVE_ERROR
        return
    }
    count, read_error := os.read(file, state.bytes[:int(length)])
    if read_error != nil || count != int(length) { state.status = abi.SAVE_ERROR; return }
    state.length, state.status = u32(length), abi.SAVE_READY
}

save_write_bytes :: proc(state: ^Save_State, bytes: []u8) -> u32 {
    if len(bytes) == 0 ||
       len(bytes) > abi.MAX_SAVE_BYTES ||
       state.path == "" { return abi.SAVE_ERROR }
    if os.mkdir_all(state.directory) != nil { state.status = abi.SAVE_ERROR; return state.status }
    temporary := fmt.aprintf("%s.%d.tmp", state.path, os.get_pid())
    defer delete(temporary)
    // Keep the committed file intact until the complete replacement is ready.
    if os.write_entire_file(temporary, bytes) != nil || os.rename(temporary, state.path) != nil {
        _ = os.remove(temporary)
        state.status = abi.SAVE_ERROR
        return state.status
    }
    copy(state.bytes[:], bytes)
    state.length, state.status = u32(len(bytes)), abi.SAVE_READY
    return state.status
}

define_save_imports :: proc(game: ^Game) -> bool {
    names := [4]string{"save_size", "save_status", "save_read", "save_write"}
    for name, i in names {
        params, results: TypeVec
        count := 0 if i < 2 else 2
        wasm_valtype_vec_new_uninitialized(&params, uint(count))
        wasm_valtype_vec_new_uninitialized(&results, 1)
        for j in 0 ..< count { params.data[j] = wasm_valtype_new(0) }
        results.data[0] = wasm_valtype_new(0)
        signature := wasm_functype_new(&params, &results)
        callback := save_size_callback
        if i == 1 { callback = save_status_callback }
        if i == 2 { callback = save_read_callback }
        if i == 3 { callback = save_write_callback }
        result := wasmtime_linker_define_func(
            game.linker,
            raw_data(string("env")),
            3,
            raw_data(name),
            uint(len(name)),
            signature,
            callback,
            game,
            nil,
        )
        wasm_functype_delete(signature)
        if !check(game, result, nil) { return false }
    }
    return true
}

save_size_callback :: proc "c" (
    environment, _caller: rawptr,
    _args: [^]Val,
    _nargs: uint,
    results: [^]Val,
    _nresults: uint,
) -> Trap {
    results[0].kind, results[0].of.i32 = 0, i32((^Game)(environment).save.length)
    return nil
}
save_status_callback :: proc "c" (
    environment, _caller: rawptr,
    _args: [^]Val,
    _nargs: uint,
    results: [^]Val,
    _nresults: uint,
) -> Trap {
    results[0].kind, results[0].of.i32 = 0, i32((^Game)(environment).save.status)
    return nil
}

save_memory :: proc(caller: rawptr, pointer, length: u32) -> ([]u8, bool) {
    if length > abi.MAX_SAVE_BYTES { return nil, false }
    external: Extern
    if !wasmtime_caller_export_get(
        caller,
        raw_data(string("memory")),
        6,
        &external,
    ) { return nil, false }
    defer wasmtime_extern_delete(&external)
    if external.kind != 3 { return nil, false }
    ctx := wasmtime_caller_context(caller)
    if u64(pointer) + u64(length) >
       u64(wasmtime_memory_data_size(ctx, &external.of.memory)) { return nil, false }
    return wasmtime_memory_data(ctx, &external.of.memory)[pointer:pointer + length], true
}

save_read_callback :: proc "c" (
    environment, caller: rawptr,
    args: [^]Val,
    _nargs: uint,
    results: [^]Val,
    _nresults: uint,
) -> Trap {
    context = runtime.default_context()
    results[0].kind, results[0].of.i32 = 0, 0
    state := &(^Game)(environment).save
    bytes, ok := save_memory(caller, u32(args[0].of.i32), u32(args[1].of.i32))
    if ok && u32(len(bytes)) >= state.length {
        copy(bytes, state.bytes[:state.length])
        results[0].of.i32 = i32(state.length)
    }
    return nil
}
save_write_callback :: proc "c" (
    environment, caller: rawptr,
    args: [^]Val,
    _nargs: uint,
    results: [^]Val,
    _nresults: uint,
) -> Trap {
    context = runtime.default_context()
    results[0].kind, results[0].of.i32 = 0, abi.SAVE_ERROR
    bytes, ok := save_memory(caller, u32(args[0].of.i32), u32(args[1].of.i32))
    state := &(^Game)(environment).save
    if ok && len(bytes) > 0 && state.write_allowed {
        state.write_allowed = false
        results[0].of.i32 = i32(save_write_bytes(state, bytes))
    }
    return nil
}
