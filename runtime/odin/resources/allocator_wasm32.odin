package resources

import "base:runtime"

wasm_allocator :: proc() -> runtime.Allocator {
    return runtime.default_wasm_allocator()
}
