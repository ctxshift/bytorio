#include "game.h"
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>

int main(int argc, char** argv) {
    if (argc != 3) return 2;
    std::ifstream source_file(argv[1], std::ios::binary), inputs(argv[2]);
    if (!source_file || !inputs) return 2;
    const std::string source((std::istreambuf_iterator<char>(source_file)), {});
    auto game = std::make_unique<console::Game>();
    if (!game->load(source) || !game->draw()) { std::cerr << game->error(); return 1; }
    unsigned mask;
    while (inputs >> mask) {
        if (mask > 31) return 2;
        console::Input input;
        input.left=mask&1; input.right=mask&2; input.up=mask&4; input.down=mask&8; input.action=mask&16;
        if (!game->update(input) || !game->draw()) { std::cerr << game->error(); return 1; }
        std::cout << "{\"hash\":" << game->frame_hash() << ",\"sounds\":" << game->sound_calls() << "}\n";
    }
    return inputs.eof() ? 0 : 2;
}
