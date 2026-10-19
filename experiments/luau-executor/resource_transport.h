#pragma once
#include <cstdint>
#include <lua.h>
namespace resource_transport {
void begin(std::uint64_t tick, unsigned phase = 1);
void end();
const char* error();
int session(lua_State*);
int emit(lua_State*);
int results(lua_State*);
}
