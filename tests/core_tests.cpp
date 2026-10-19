#include "game.h"

#include <cmath>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>

namespace {
int failures = 0;
void check(bool condition, const char* message) {
    if (!condition) { std::cerr << "FAIL: " << message << '\n'; ++failures; }
}
}

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    std::ifstream file(argv[1], std::ios::binary);
    const std::string source((std::istreambuf_iterator<char>(file)), {});
    {
        auto storage = std::make_unique<console::Game>();
        auto& game = *storage;
        check(game.load(source), "example loads");
        check(game.sound_calls() == 1 && game.take_sound(), "init triggers sample");
        check(!game.take_sound(), "sound requests are consumed once");
        check(game.draw(), "example draws");
        const auto initial = game.frame_hash();
        console::Input input;
        input.right = true;
        input.action = true;
        for (int i = 0; i < 60; ++i) check(game.update(input), "fixed update succeeds");
        check(game.draw() && initial != game.frame_hash(), "input moves rendered sprite");
        check(game.sprite_x() >= 283 && game.sprite_x() <= 284, "right input moves sprite by 100 logical pixels");
        check(game.ticks() == 60 && game.sound_calls() == 2, "held action triggers only one additional sound");
        float peak = 0;
        for (float value : game.sample()) peak = std::max(peak, std::abs(value));
        check(peak > 0.1f && peak < 1.0f, "shared PCM is non-silent and bounded");
        check(game.heap_bytes() < 8 * 1024 * 1024, "VM stays inside heap cap");
    }
    {
        auto storage = std::make_unique<console::Game>();
        auto& game = *storage;
        check(!game.load("return {", "syntax.luau"), "syntax error is rejected");
        check(game.error().find("syntax.luau") != std::string::npos, "syntax diagnostics identify source");
    }
    {
        auto storage = std::make_unique<console::Game>();
        auto& game = *storage;
        check(game.load("return {init=function() end, update=function() error('intentional failure') end, draw=function() end}", "failure.luau"), "failure fixture loads");
        check(!game.update({}) && game.error().find("intentional failure") != std::string::npos, "callback error is controlled");
    }
    {
        auto storage = std::make_unique<console::Game>();
        auto& game = *storage;
        check(!game.load("while true do end", "loop.luau"), "runaway top-level code is interrupted");
        check(game.error().find("time limit") != std::string::npos, "timeout has a useful diagnostic");
    }
    {
        auto storage = std::make_unique<console::Game>(1024 * 1024);
        auto& game = *storage;
        check(!game.load("local t = {}; while true do table.insert(t, string.rep('x', 16384)) end", "memory.luau"), "heap exhaustion is controlled");
        check(game.error().find("memory") != std::string::npos, "heap exhaustion reports memory error");
        check(game.heap_bytes() <= 1024 * 1024, "allocator enforces cap");
    }
    {
        auto storage = std::make_unique<console::Game>();
        auto& game = *storage;
        check(!game.load("return {init=function() console.sprite(0/0,0) end, update=function() end, draw=function() end}"), "non-finite drawing coordinates rejected");
    }
    if (failures) return 1;
    std::cout << "core contract passed: source, input, sprite, PCM, errors, timeout, heap cap\n";
}
