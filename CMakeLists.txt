cmake_minimum_required(VERSION 3.24)
project(console_runtime LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
include(FetchContent)
include(CTest)
set(CONSOLE_GAME_SOURCE "${CMAKE_CURRENT_SOURCE_DIR}/examples/hello/main.luau" CACHE FILEPATH "Luau cartridge source")

set(LUAU_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LUAU_BUILD_WEB OFF CACHE BOOL "" FORCE)
FetchContent_Declare(luau
    GIT_REPOSITORY https://github.com/luau-lang/luau.git
    GIT_TAG 9d7748a4f324213a18cb8283fa2a77c330225fa0)

set(SDL_SHARED OFF CACHE BOOL "" FORCE)
set(SDL_STATIC ON CACHE BOOL "" FORCE)
set(SDL_TEST_LIBRARY OFF CACHE BOOL "" FORCE)
set(SDL_TESTS OFF CACHE BOOL "" FORCE)
set(SDL_EXAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_Declare(SDL3
    GIT_REPOSITORY https://github.com/libsdl-org/SDL.git
    GIT_TAG 829a65d769d935c4852f8159e964312c0957260a)
FetchContent_MakeAvailable(luau SDL3)

add_library(console_core runtime/core/game.cpp)
target_include_directories(console_core PUBLIC runtime/core)
target_link_libraries(console_core PRIVATE Luau.Compiler Luau.VM)

add_executable(player runtime/platform/main.cpp)
target_link_libraries(player PRIVATE console_core SDL3::SDL3-static)
add_custom_command(TARGET player POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:player>/licenses"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${luau_SOURCE_DIR}/LICENSE.txt"
        "$<TARGET_FILE_DIR:player>/licenses/luau.txt"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different "${sdl3_SOURCE_DIR}/LICENSE.txt"
        "$<TARGET_FILE_DIR:player>/licenses/sdl3.txt")
if(MSVC)
    target_compile_options(console_core PRIVATE /W4)
    target_compile_options(player PRIVATE /W4)
else()
    target_compile_options(console_core PRIVATE -Wall -Wextra -Wpedantic)
    target_compile_options(player PRIVATE -Wall -Wextra -Wpedantic)
endif()

if(EMSCRIPTEN)
    set_target_properties(player PROPERTIES SUFFIX ".html")
    # Luau uses C++ exceptions for protected calls; enable catches in the libraries too.
    foreach(component console_core player Luau.VM Luau.Compiler Luau.Ast Luau.Bytecode Luau.Common)
        target_compile_options(${component} PRIVATE -fexceptions)
    endforeach()
    target_link_options(player PRIVATE
        -fexceptions
        "--shell-file=${CMAKE_CURRENT_SOURCE_DIR}/runtime/platform/web/shell.html"
        "--preload-file=${CONSOLE_GAME_SOURCE}@/game/main.luau"
        "-sMIN_WEBGL_VERSION=2" "-sMAX_WEBGL_VERSION=2"
        "-sALLOW_MEMORY_GROWTH=1" "-sMAXIMUM_MEMORY=134217728"
        "-sASSERTIONS=1" "-sENVIRONMENT=web" "-sEXIT_RUNTIME=1")
    set_property(TARGET player APPEND PROPERTY LINK_DEPENDS
        "${CMAKE_CURRENT_SOURCE_DIR}/runtime/platform/web/shell.html"
        "${CONSOLE_GAME_SOURCE}")
else()
    add_custom_target(player_game
        COMMAND ${CMAKE_COMMAND} -E make_directory "$<TARGET_FILE_DIR:player>/game"
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            "${CONSOLE_GAME_SOURCE}"
            "$<TARGET_FILE_DIR:player>/game/main.luau")
    add_dependencies(player player_game)
    if(BUILD_TESTING)
        add_executable(core_tests tests/core_tests.cpp)
        target_link_libraries(core_tests PRIVATE console_core)
        add_executable(rpg_replay tests/rpg_replay.cpp)
        target_link_libraries(rpg_replay PRIVATE console_core)
        add_test(NAME core_contract COMMAND core_tests
            "${CMAKE_CURRENT_SOURCE_DIR}/examples/hello/main.luau")
        set_tests_properties(core_contract PROPERTIES TIMEOUT 15)
    endif()
endif()
