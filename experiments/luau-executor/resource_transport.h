#pragma once
#include <cstdint>
#include <lua.h>
namespace resource_transport {
void begin(std::uint64_t tick);
void end();
const char* error();
int session(lua_State*);
int emit(lua_State*);
}
