# Separate audio production from device delivery

Keep stream timing, queue bounds and loop position in the shared runtime while
host producers decode bounded PCM chunks outside the audio device callback.
Connect the browser game Worker directly to AudioWorklet for refill traffic, so
UI-thread work does not schedule audio production and device callbacks do not
wait for codec work.
This isolates UI stalls but does not eliminate starvation from a blocked game
Worker or native host loop.

Scheduling and current host adapters: [Ogg streaming](../ogg-streaming-integration.md).
