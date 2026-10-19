#include "game.h"

#include <SDL3/SDL.h>
#include <SDL3/SDL_main.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>
#ifdef __EMSCRIPTEN__
#include <emscripten.h>

EM_JS(void, web_sound, (const float* samples, int count), {
    globalThis.playerAudio.play(HEAPF32.subarray(samples >> 2, (samples >> 2) + count));
});
EM_JS(void, web_status, (const char* error, unsigned ticks, unsigned sprites, unsigned sounds, unsigned hash, int spriteX), {
    globalThis.playerStatus = { ready: true, error: UTF8ToString(error), ticks, sprites, sounds, hash: hash >>> 0, spriteX };
    document.getElementById('status').textContent = error && UTF8ToString(error)
        ? UTF8ToString(error) : (globalThis.playerInstructions || 'Arrows / WASD: move · Space / tap: sound');
    document.getElementById('start').disabled = !!UTF8ToString(error);
});
static bool started = false;
static bool manual = false;
extern "C" EMSCRIPTEN_KEEPALIVE void player_start() { started = true; }
#else
static bool started = true;
#endif

namespace {
struct Audio {
    const console::Game* game = nullptr;
    std::atomic<bool> trigger{false};
    std::atomic<unsigned> nonzero_frames{0};
    std::size_t cursor = console::sample_count;
    SDL_AudioStream* stream = nullptr;

    static void SDLCALL fill(void* context, SDL_AudioStream* stream, int additional, int) {
        auto& audio = *static_cast<Audio*>(context);
        std::array<float, 1024> buffer{};
        while (additional > 0) {
            if (audio.trigger.exchange(false)) audio.cursor = 0;
            const auto frames = std::min(buffer.size(), static_cast<std::size_t>((additional + 3) / 4));
            unsigned nonzero = 0;
            for (std::size_t i = 0; i < frames; ++i) {
                buffer[i] = audio.cursor < console::sample_count ? audio.game->sample()[audio.cursor++] : 0;
                if (buffer[i] != 0) ++nonzero;
            }
            audio.nonzero_frames.fetch_add(nonzero);
            const int bytes = static_cast<int>(frames * sizeof(float));
            if (!SDL_PutAudioStreamData(stream, buffer.data(), bytes)) break;
            additional -= bytes;
        }
    }

    ~Audio() { if (stream) SDL_DestroyAudioStream(stream); }
};

struct App {
    console::Game game;
    Audio audio;
    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    SDL_Texture* texture = nullptr;
    SDL_Gamepad* gamepad = nullptr;
    bool running = true;
    bool focused = true;
    bool smoke = false;
    int frame_limit = 0;
    int frames = 0;
    double previous = 0;
    double accumulator = 0;
    std::string capture;
    std::string platform_error;

    ~App() {
        // Destroy the audio stream while its Game sample storage is still alive.
        if (audio.stream) { SDL_DestroyAudioStream(audio.stream); audio.stream = nullptr; }
        if (gamepad) SDL_CloseGamepad(gamepad);
        if (texture) SDL_DestroyTexture(texture);
        if (renderer) SDL_DestroyRenderer(renderer);
        if (window) SDL_DestroyWindow(window);
        SDL_Quit();
    }

    bool fail(const std::string& error) {
        platform_error = error;
        std::cerr << "player: " << error << '\n';
        if (window) SDL_SetWindowTitle(window, error.c_str());
        running = false;
        return false;
    }

    bool init(const std::string& script) {
        if (!SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMEPAD
#ifndef __EMSCRIPTEN__
            | SDL_INIT_AUDIO
#endif
            )) return fail(SDL_GetError());
        SDL_WindowFlags window_flags = SDL_WINDOW_RESIZABLE;
#ifdef __EMSCRIPTEN__
        // Request ES 3 explicitly so SDL does not probe WebGL 1 in a WebGL 2-only build.
        if (!SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES)
            || !SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3)
            || !SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0)) return fail(SDL_GetError());
        window_flags |= SDL_WINDOW_OPENGL;
#endif
        window = SDL_CreateWindow("Console player", console::width * 3, console::height * 3, window_flags);
        if (!window) return fail(SDL_GetError());
        renderer = SDL_CreateRenderer(window, nullptr);
        if (!renderer) return fail(SDL_GetError());
        SDL_SetRenderVSync(renderer, 1);
        if (!SDL_SetRenderLogicalPresentation(renderer, console::width, console::height, SDL_LOGICAL_PRESENTATION_INTEGER_SCALE))
            return fail(SDL_GetError());
        texture = SDL_CreateTexture(renderer, SDL_PIXELFORMAT_RGBA32, SDL_TEXTUREACCESS_STREAMING, console::width, console::height);
        if (!texture || !SDL_SetTextureScaleMode(texture, SDL_SCALEMODE_NEAREST)) return fail(SDL_GetError());
        int count = 0;
        SDL_JoystickID* pads = SDL_GetGamepads(&count);
        if (count > 0) gamepad = SDL_OpenGamepad(pads[0]);
        SDL_free(pads);

        std::ifstream file(script, std::ios::binary | std::ios::ate);
        if (!file) return fail("cannot open game source: " + script);
        const auto size = file.tellg();
        if (size < 0 || size > 256 * 1024) return fail("game source exceeds 256 KiB prototype limit");
        file.seekg(0);
        const std::string source((std::istreambuf_iterator<char>(file)), {});
        if (!game.load(source, "main.luau") || !game.draw()) return fail(game.error());
        audio.game = &game;
#ifndef __EMSCRIPTEN__
        const SDL_AudioSpec spec{SDL_AUDIO_F32, 1, console::sample_rate};
        audio.stream = SDL_OpenAudioDeviceStream(SDL_AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, Audio::fill, &audio);
        if (!audio.stream || !SDL_ResumeAudioStreamDevice(audio.stream)) return fail(SDL_GetError());
#endif
        previous = static_cast<double>(SDL_GetTicksNS()) / 1e9;
        return true;
    }

    console::Input input() const {
        console::Input result;
        if (!focused && !smoke) return result;
        const bool* keys = SDL_GetKeyboardState(nullptr);
        result.left = keys[SDL_SCANCODE_LEFT] || keys[SDL_SCANCODE_A];
        result.right = keys[SDL_SCANCODE_RIGHT] || keys[SDL_SCANCODE_D];
        result.up = keys[SDL_SCANCODE_UP] || keys[SDL_SCANCODE_W];
        result.down = keys[SDL_SCANCODE_DOWN] || keys[SDL_SCANCODE_S];
        result.action = keys[SDL_SCANCODE_SPACE];
        if (gamepad) {
            result.left |= SDL_GetGamepadButton(gamepad, SDL_GAMEPAD_BUTTON_DPAD_LEFT);
            result.right |= SDL_GetGamepadButton(gamepad, SDL_GAMEPAD_BUTTON_DPAD_RIGHT);
            result.up |= SDL_GetGamepadButton(gamepad, SDL_GAMEPAD_BUTTON_DPAD_UP);
            result.down |= SDL_GetGamepadButton(gamepad, SDL_GAMEPAD_BUTTON_DPAD_DOWN);
            result.action |= SDL_GetGamepadButton(gamepad, SDL_GAMEPAD_BUTTON_SOUTH);
        }
        float x = 0, y = 0;
        const auto buttons = SDL_GetMouseState(&x, &y);
        SDL_RenderCoordinatesFromWindow(renderer, x, y, &result.pointer_x, &result.pointer_y);
        result.pointer = (buttons & SDL_BUTTON_LMASK) && result.pointer_x >= 0 && result.pointer_x < console::width
            && result.pointer_y >= 0 && result.pointer_y < console::height;
        if (smoke) { result = {}; result.right = frames < 60; result.action = frames == 60; }
        return result;
    }

    void frame() {
        SDL_Event event;
        while (SDL_PollEvent(&event)) {
            if (event.type == SDL_EVENT_QUIT) running = false;
            if (event.type == SDL_EVENT_WINDOW_FOCUS_LOST) { focused = false; accumulator = 0; }
            if (event.type == SDL_EVENT_WINDOW_FOCUS_GAINED) { focused = true; accumulator = 0; }
            if (event.type == SDL_EVENT_GAMEPAD_ADDED && !gamepad) gamepad = SDL_OpenGamepad(event.gdevice.which);
            if (event.type == SDL_EVENT_GAMEPAD_REMOVED && gamepad && SDL_GetGamepadID(gamepad) == event.gdevice.which) {
                SDL_CloseGamepad(gamepad); gamepad = nullptr;
            }
        }
        const double now = static_cast<double>(SDL_GetTicksNS()) / 1e9;
        const double delta = std::clamp(now - previous, 0.0, 0.1);
        previous = now;
        if (running && started && (focused || smoke)
#ifdef __EMSCRIPTEN__
            && !manual
#endif
        ) {
            accumulator += smoke ? 1.0 / 60.0 : delta;
            int steps = 0;
            while (accumulator >= 1.0 / 60.0 && steps++ < 5) {
                if (!game.update(input())) { fail(game.error()); break; }
                accumulator -= 1.0 / 60.0;
            }
            if (steps >= 5) accumulator = 0;
            if (running && !game.draw()) fail(game.error());
            if (running && game.take_sound()) {
#ifdef __EMSCRIPTEN__
                web_sound(game.sample().data(), console::sample_count);
#else
                audio.trigger.store(true);
#endif
            }
        }
        if (!SDL_UpdateTexture(texture, nullptr, game.pixels().data(), console::width * 4)
            || !SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255) || !SDL_RenderClear(renderer)
            || !SDL_RenderTexture(renderer, texture, nullptr, nullptr) || !SDL_RenderPresent(renderer)) fail(SDL_GetError());
#ifdef __EMSCRIPTEN__
        web_status(platform_error.c_str(), static_cast<unsigned>(game.ticks()), static_cast<unsigned>(game.sprite_calls()),
            static_cast<unsigned>(game.sound_calls()), game.frame_hash(), game.sprite_x());
#endif
        if (started) ++frames;
        if (frame_limit && frames >= frame_limit) running = false;
    }

    bool save_capture() const {
        if (capture.empty()) return true;
        SDL_Surface* surface = SDL_CreateSurfaceFrom(console::width, console::height, SDL_PIXELFORMAT_RGBA32,
            const_cast<std::uint32_t*>(game.pixels().data()), console::width * 4);
        if (!surface) return false;
        const bool saved = SDL_SaveBMP(surface, capture.c_str());
        SDL_DestroySurface(surface);
        return saved;
    }
};
}

#ifdef __EMSCRIPTEN__
static App* browser_app = nullptr;
extern "C" EMSCRIPTEN_KEEPALIVE void player_step(unsigned mask) {
    if (!manual || !browser_app || !browser_app->running || mask > 31) return;
    console::Input input;
    input.left=mask&1; input.right=mask&2; input.up=mask&4; input.down=mask&8; input.action=mask&16;
    if (!browser_app->game.update(input) || !browser_app->game.draw()) browser_app->fail(browser_app->game.error());
    if (browser_app->game.take_sound()) web_sound(browser_app->game.sample().data(), console::sample_count);
    web_status(browser_app->platform_error.c_str(), static_cast<unsigned>(browser_app->game.ticks()),
        static_cast<unsigned>(browser_app->game.sprite_calls()), static_cast<unsigned>(browser_app->game.sound_calls()),
        browser_app->game.frame_hash(), browser_app->game.sprite_x());
}
#endif

int main(int argc, char** argv) {
    auto app = std::make_unique<App>();
#ifdef __EMSCRIPTEN__
    std::string script = "/game/main.luau";
#else
    std::string script = std::string(SDL_GetBasePath()) + "game/main.luau";
#endif
    for (int i = 1; i < argc; ++i) {
        const std::string arg = argv[i];
        if (arg == "--smoke") { app->smoke = true; app->frame_limit = 120; }
#ifdef __EMSCRIPTEN__
        else if (arg == "--manual") manual = true;
#endif
        else if (arg == "--script" && i + 1 < argc) script = argv[++i];
        else if (arg == "--capture" && i + 1 < argc) app->capture = argv[++i];
        else { std::cerr << "Usage: player [--script file] [--smoke] [--capture output.bmp]\n"; return 2; }
    }
    if (!app->init(script)) {
#ifdef __EMSCRIPTEN__
        web_status(app->platform_error.c_str(), 0, 0, 0, 0, 0);
#endif
        return 1;
    }
#ifdef __EMSCRIPTEN__
    browser_app = app.release();
    emscripten_set_main_loop_arg([](void* context) {
        auto* current = static_cast<App*>(context);
        current->frame();
        if (!current->running) { emscripten_cancel_main_loop(); delete current; }
    }, browser_app, 0, true);
#else
    while (app->running) { app->frame(); SDL_Delay(1); }
    if (!app->save_capture()) return 1;
    std::cout << "{\"ticks\":" << app->game.ticks() << ",\"sprites\":" << app->game.sprite_calls()
        << ",\"sounds\":" << app->game.sound_calls() << ",\"hash\":" << app->game.frame_hash()
        << ",\"audioNonzeroFrames\":" << app->audio.nonzero_frames.load() << "}\n";
    if (!app->platform_error.empty()) return 1;
    if (app->smoke && (app->game.ticks() != 120 || app->game.sound_calls() < 2 || !app->audio.nonzero_frames.load())) return 1;
#endif
    return 0;
}
