// Generated SDK entry point.
package main
import "base:runtime"
import console "sdk:console"
import "assets"
@(export) game_init :: proc "c" () {
 context=runtime.default_context()
 console.start(console.Callbacks{init=init,update=update,draw=draw},console.Config{graphics=assets.raster[:],display=.Low})
}
