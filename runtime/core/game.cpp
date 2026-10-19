#include "game.h"

#include <lua.h>
#include <lualib.h>
#include <luacode.h>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>

namespace console {
namespace {
constexpr std::array<const char*, 16> sprite_rows = {
    "................", ".....######.....", "...##########...", "..############..",
    "..##..####..##..", ".###..####..###.", ".##############.", ".##############.",
    ".####......####.", "..####....####..", "..############..", "...##########...",
    "....########....", "...###....###...", "..###......###..", "................"};

std::uint32_t rgba(int r, int g, int b) {
    // RGBA byte order, independent of the host's integer endianness.
    const unsigned char bytes[4] = {static_cast<unsigned char>(r),
        static_cast<unsigned char>(g), static_cast<unsigned char>(b), 255};
    std::uint32_t value;
    std::memcpy(&value, bytes, 4);
    return value;
}

int bounded_integer(lua_State* state, int arg, int low, int high) {
    const double value = luaL_checknumber(state, arg);
    if (!std::isfinite(value) || value < low || value > high)
        luaL_argerror(state, arg, "value outside supported range");
    return static_cast<int>(value);
}
}

Game::Game(std::size_t heap_limit) : heap_limit_(heap_limit) {
    for (int i = 0; i < sample_count; ++i) {
        const double t = static_cast<double>(i) / sample_rate;
        const double envelope = std::min(1.0, t * 100.0) * (1.0 - static_cast<double>(i) / sample_count);
        sample_[i] = static_cast<float>(0.22 * envelope * std::sin(6.283185307179586 * (660.0 * t + 440.0 * t * t)));
    }
}

Game::~Game() { if (state_) lua_close(state_); }

void* Game::allocate(void* context, void* ptr, std::size_t old_size, std::size_t size) {
    auto& game = *static_cast<Game*>(context);
    const std::size_t previous = ptr ? old_size : 0;
    if (size == 0) {
        game.heap_bytes_ -= previous;
        std::free(ptr);
        return nullptr;
    }
    const std::size_t retained = game.heap_bytes_ - previous;
    if (size > game.heap_limit_ || retained > game.heap_limit_ - size) return nullptr;
    void* next = std::realloc(ptr, size);
    if (next) game.heap_bytes_ = retained + size;
    return next;
}

Game& Game::self(lua_State* state) {
    return *static_cast<Game*>(lua_callbacks(state)->userdata);
}

void Game::interrupt(lua_State* state, int gc) {
    if (gc >= 0) return;
    if (std::chrono::steady_clock::now() > self(state).deadline_)
        luaL_errorL(state, "script exceeded callback time limit");
}

bool Game::load(std::string_view source, const char* name) {
    if (state_) { error_ = "a Game instance can only load one module"; return false; }
    if (source.size() > 256 * 1024) { error_ = "source exceeds 256 KiB prototype limit"; return false; }
    // Initialization needs headroom; the allocator limit applies to game execution too.
    if (heap_limit_ < 1024 * 1024) { error_ = "VM heap limit must be at least 1 MiB"; return false; }
    state_ = lua_newstate(allocate, this);
    if (!state_) { error_ = "cannot allocate Luau VM"; return false; }
    lua_callbacks(state_)->userdata = this;
    lua_callbacks(state_)->interrupt = interrupt;
    luaL_openlibs(state_);
    const luaL_Reg api[] = {{"clear", clear}, {"sprite", sprite}, {"button", button},
        {"pointer", pointer}, {"sound", sound}, {nullptr, nullptr}};
    luaL_register(state_, "console", api);
    lua_setreadonly(state_, -1, true);
    lua_pop(state_, 1);
    luaL_sandbox(state_);
    luaL_sandboxthread(state_);

    std::size_t size = 0;
    char* bytecode = luau_compile(source.data(), source.size(), nullptr, &size);
    if (!bytecode) { error_ = "source compilation failed"; return false; }
    const int status = luau_load(state_, name, bytecode, size, 0);
    std::free(bytecode);
    if (status != 0) return fail("cannot load source");
    deadline_ = std::chrono::steady_clock::now() + std::chrono::milliseconds(100);
    if (lua_pcall(state_, 0, 1, 0) != 0) return fail("module initialization failed");
    if (!lua_istable(state_, -1)) { error_ = "game module must return a table"; return false; }
    module_ = lua_ref(state_, -1);
    lua_pop(state_, 1);
    for (const char* callback : {"init", "update", "draw"}) {
        lua_getref(state_, module_);
        lua_getfield(state_, -1, callback);
        const bool valid = lua_isfunction(state_, -1);
        lua_pop(state_, 2);
        if (!valid) { error_ = std::string("game module requires function: ") + callback; return false; }
    }
    return call("init");
}

bool Game::fail(const char* fallback) {
    const char* message = lua_tostring(state_, -1);
    error_ = message ? message : fallback;
    lua_settop(state_, 0);
    return false;
}

bool Game::call(const char* callback, bool with_delta) {
    if (!state_ || module_ < 0 || !error_.empty()) return false;
    lua_getref(state_, module_);
    lua_getfield(state_, -1, callback);
    lua_remove(state_, -2);
    if (with_delta) lua_pushnumber(state_, 1.0 / 60.0);
    deadline_ = std::chrono::steady_clock::now() + std::chrono::milliseconds(100);
    if (lua_pcall(state_, with_delta ? 1 : 0, 0, 0) != 0) return fail("callback failed");
    return true;
}

bool Game::update(const Input& input) {
    input_ = input;
    if (!call("update", true)) return false;
    ++ticks_;
    return true;
}

bool Game::draw() { return call("draw"); }
bool Game::take_sound() { const bool pending = sound_pending_; sound_pending_ = false; return pending; }

int Game::clear(lua_State* state) {
    const auto color = rgba(bounded_integer(state, 1, 0, 255), bounded_integer(state, 2, 0, 255),
        bounded_integer(state, 3, 0, 255));
    self(state).pixels_.fill(color);
    return 0;
}

int Game::sprite(lua_State* state) {
    auto& game = self(state);
    const int x = bounded_integer(state, 1, -4096, 4096);
    const int y = bounded_integer(state, 2, -4096, 4096);
    game.sprite_x_ = x;
    for (int row = 0; row < 16; ++row)
        for (int col = 0; col < 16; ++col)
            if (sprite_rows[row][col] == '#' && x + col >= 0 && x + col < width && y + row >= 0 && y + row < height)
                game.pixels_[(y + row) * width + x + col] = rgba(112, 240, 192);
    ++game.sprite_calls_;
    return 0;
}

int Game::button(lua_State* state) {
    const auto& input = self(state).input_;
    const char* name = luaL_checkstring(state, 1);
    bool value = false;
    if (std::strcmp(name, "left") == 0) value = input.left;
    else if (std::strcmp(name, "right") == 0) value = input.right;
    else if (std::strcmp(name, "up") == 0) value = input.up;
    else if (std::strcmp(name, "down") == 0) value = input.down;
    else if (std::strcmp(name, "action") == 0) value = input.action;
    else luaL_argerror(state, 1, "unknown button");
    lua_pushboolean(state, value);
    return 1;
}

int Game::pointer(lua_State* state) {
    const auto& input = self(state).input_;
    lua_pushboolean(state, input.pointer);
    lua_pushnumber(state, input.pointer_x);
    lua_pushnumber(state, input.pointer_y);
    return 3;
}

int Game::sound(lua_State* state) {
    self(state).sound_pending_ = true;
    ++self(state).sound_calls_;
    return 0;
}

std::uint32_t Game::frame_hash() const {
    std::uint32_t hash = 2166136261u;
    const auto* bytes = reinterpret_cast<const unsigned char*>(pixels_.data());
    for (std::size_t i = 0; i < pixels_.size() * 4; ++i) hash = (hash ^ bytes[i]) * 16777619u;
    return hash;
}
}
