// PROTOTYPE: a player-supplied Luau compiler/VM behind the cartridge ABI.
#include <lua.h>
#include <lualib.h>
#include <luacode.h>
#include <emscripten/emscripten.h>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <cstddef>

namespace {
struct Frame { std::uint32_t version, clear; std::int32_t sprite_x,sprite_y; std::uint32_t ticks,sounds; double x,y; };
struct Command { std::int32_t x,y,w,h; std::uint32_t color; };
static_assert(sizeof(Frame)==40 && offsetof(Frame,x)==24);
static_assert(sizeof(Command)==20);
constexpr std::size_t source_capacity=256*1024, heap_limit=4*1024*1024, max_commands=16384;
char source[source_capacity], error[1024];
std::uint32_t source_size, buttons, command_count;
std::size_t heap_bytes, peak_heap_bytes;
Command commands[max_commands];
Frame frame;
lua_State* state;
int module=-1;

void fail(const char* message) { std::snprintf(error,sizeof(error),"%s",message?message:"Luau callback failed"); }
void* allocate(void*,void* ptr,std::size_t old_size,std::size_t size) {
    const auto previous=ptr?old_size:0;
    if(!size) {heap_bytes-=previous;std::free(ptr);return nullptr;}
    const auto retained=heap_bytes-previous;
    if(size>heap_limit || retained>heap_limit-size)return nullptr;
    void* result=std::realloc(ptr,size);
    if(result){heap_bytes=retained+size;peak_heap_bytes=std::max(heap_bytes,peak_heap_bytes);}
    return result;
}
int integer(lua_State* L,int arg,int low,int high) {
    const double value=luaL_checknumber(L,arg);
    if(!std::isfinite(value)||value<low||value>high)luaL_argerror(L,arg,"value outside supported range");
    return static_cast<int>(value);
}
int clear(lua_State* L) {
    const auto r=integer(L,1,0,255),g=integer(L,2,0,255),b=integer(L,3,0,255);
    frame.clear=0xff000000u | (b<<16) | (g<<8) | r;
    return 0;
}
int rect(lua_State* L) {
    const auto x=integer(L,1,-4096,4096),y=integer(L,2,-4096,4096),w=integer(L,3,0,4096),h=integer(L,4,0,4096);
    const double color=luaL_checknumber(L,5);
    if(!std::isfinite(color)||color<0||color>4294967295.0)luaL_argerror(L,5,"invalid RGBA color");
    if(w==0||h==0||x>=384||y>=216||x+w<=0||y+h<=0)return 0;
    if(command_count==max_commands)luaL_error(L,"display list limit exceeded");
    commands[command_count++]={x,y,w,h,static_cast<std::uint32_t>(color)};
    return 0;
}
int button(lua_State* L) {
    const char* name=luaL_checkstring(L,1);
    unsigned mask=0;
    if(!std::strcmp(name,"left"))mask=1;else if(!std::strcmp(name,"right"))mask=2;
    else if(!std::strcmp(name,"up"))mask=4;else if(!std::strcmp(name,"down"))mask=8;
    else if(!std::strcmp(name,"action"))mask=16;else luaL_argerror(L,1,"unknown button");
    lua_pushboolean(L,(buttons&mask)!=0);return 1;
}
int sound(lua_State*) {++frame.sounds;return 0;}
bool call(const char* name,bool delta=false) {
    if(!state||module<0||error[0])return false;
    lua_getref(state,module);lua_getfield(state,-1,name);lua_remove(state,-2);
    if(delta)lua_pushnumber(state,1.0/60.0);
    if(lua_pcall(state,delta?1:0,0,0)!=0){fail(lua_tostring(state,-1));lua_settop(state,0);return false;}
    return true;
}
}

extern "C" {
EMSCRIPTEN_KEEPALIVE std::uint32_t game_abi(){return 1;}
EMSCRIPTEN_KEEPALIVE std::uint32_t game_frame_size(){return sizeof(Frame);}
EMSCRIPTEN_KEEPALIVE char* game_source_buffer(){return source;}
EMSCRIPTEN_KEEPALIVE std::uint32_t game_source_capacity(){return source_capacity;}
EMSCRIPTEN_KEEPALIVE void game_source_size(std::uint32_t size){source_size=size;}
EMSCRIPTEN_KEEPALIVE std::uint32_t game_error_length(){return std::strlen(error);}
EMSCRIPTEN_KEEPALIVE const char* game_error(){return error;}
EMSCRIPTEN_KEEPALIVE std::uint32_t game_heap_bytes(){return heap_bytes;}
EMSCRIPTEN_KEEPALIVE std::uint32_t game_heap_peak(){return peak_heap_bytes;}
EMSCRIPTEN_KEEPALIVE void game_init(){
    if(state)lua_close(state);
    state=nullptr;module=-1;heap_bytes=peak_heap_bytes=0;buttons=command_count=0;error[0]=0;
    frame={1,0xff322015,-4096,-4096,0,0,0,0};
    if(!source_size||source_size>source_capacity){fail("invalid Luau source size");return;}
    state=lua_newstate(allocate,nullptr);
    if(!state){fail("cannot allocate Luau VM");return;}
    luaL_openlibs(state);
    const luaL_Reg api[]={{"clear",clear},{"rect",rect},{"button",button},{"sound",sound},{nullptr,nullptr}};
    luaL_register(state,"console",api);lua_setreadonly(state,-1,true);lua_pop(state,1);
    luaL_sandbox(state);luaL_sandboxthread(state);
    std::size_t size=0;
    lua_CompileOptions options{};options.optimizationLevel=2;options.debugLevel=1;
    char* bytecode=luau_compile(source,source_size,&options,&size);
    if(!bytecode){fail("source compilation failed");return;}
    const int status=luau_load(state,"main.luau",bytecode,size,0);std::free(bytecode);
    if(status||lua_pcall(state,0,1,0)){fail(lua_tostring(state,-1));return;}
    if(!lua_istable(state,-1)){fail("game module must return a table");return;}
    module=lua_ref(state,-1);lua_pop(state,1);call("init");
}
EMSCRIPTEN_KEEPALIVE void game_update(std::uint32_t mask,std::uint32_t,double,double){buttons=mask;if(call("update",true))++frame.ticks;}
EMSCRIPTEN_KEEPALIVE const Frame* game_draw(){command_count=0;call("draw");return &frame;}
EMSCRIPTEN_KEEPALIVE const Command* game_commands(){return commands;}
EMSCRIPTEN_KEEPALIVE std::uint32_t game_command_count(){return command_count;}
}
