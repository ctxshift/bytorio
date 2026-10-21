// Generated SDK entry point.
package main
import "assets"
import "base:runtime"
import byt "sdk:bytorio"
@(export)
game_init :: proc "c" () {
    context = runtime.default_context()
    byt.start(
        byt.Callbacks{init = init, update = update, draw = draw},
        byt.Config{graphics = assets.raster[:], display = .Low},
    )
}
