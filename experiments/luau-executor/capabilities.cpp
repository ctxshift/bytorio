// PROTOTYPE: satisfy libc internally without granting host OS capabilities.
#include <cstdint>
extern "C" {
void emscripten_notify_memory_growth(std::uint32_t) {}
std::uint16_t __wasi_fd_close(std::uint32_t) {return 8;}
std::uint16_t __wasi_fd_write(std::uint32_t,const void*,std::uint32_t,std::uint32_t*) {return 8;}
std::uint16_t __wasi_clock_time_get(std::uint32_t,std::uint64_t,std::uint64_t*) {return 76;}
std::uint16_t __wasi_environ_sizes_get(std::uint32_t* count,std::uint32_t* bytes) {*count=0;*bytes=0;return 0;}
std::uint16_t __wasi_environ_get(void*,void*) {return 0;}
}
