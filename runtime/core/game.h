#pragma once

#include <array>
#include <chrono>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

struct lua_State;

namespace console {
inline constexpr int width = 384;
inline constexpr int height = 216;
inline constexpr int sample_rate = 48000;
inline constexpr int sample_count = sample_rate / 3;

struct Input {
    bool left = false;
    bool right = false;
    bool up = false;
    bool down = false;
    bool action = false;
    bool pointer = false;
    float pointer_x = 0;
    float pointer_y = 0;
};

class Game {
public:
    explicit Game(std::size_t heap_limit = 8 * 1024 * 1024);
    ~Game();
    Game(const Game&) = delete;
    Game& operator=(const Game&) = delete;

    bool load(std::string_view source, const char* name = "main.luau");
    bool update(const Input& input);
    bool draw();
    const std::string& error() const { return error_; }
    const auto& pixels() const { return pixels_; }
    const auto& sample() const { return sample_; }
    std::size_t heap_bytes() const { return heap_bytes_; }
    std::uint64_t ticks() const { return ticks_; }
    std::uint64_t sprite_calls() const { return sprite_calls_; }
    std::uint64_t sound_calls() const { return sound_calls_; }
    int sprite_x() const { return sprite_x_; }
    bool take_sound();
    std::uint32_t frame_hash() const;

private:
    static void* allocate(void* context, void* ptr, std::size_t old_size, std::size_t size);
    static void interrupt(lua_State* state, int gc);
    static Game& self(lua_State* state);
    static int clear(lua_State* state);
    static int sprite(lua_State* state);
    static int button(lua_State* state);
    static int pointer(lua_State* state);
    static int sound(lua_State* state);
    bool call(const char* callback, bool with_delta = false);
    bool fail(const char* fallback);

    lua_State* state_ = nullptr;
    int module_ = -1;
    std::size_t heap_limit_;
    std::size_t heap_bytes_ = 0;
    std::chrono::steady_clock::time_point deadline_;
    std::string error_;
    Input input_;
    bool sound_pending_ = false;
    std::uint64_t ticks_ = 0;
    std::uint64_t sprite_calls_ = 0;
    std::uint64_t sound_calls_ = 0;
    int sprite_x_ = 0;
    std::array<std::uint32_t, width * height> pixels_{};
    std::array<float, sample_count> sample_{};
};
}
