# Vorbis reference fixture

`tone.ogg` is a generated stereo signal: 440 Hz at amplitude 0.3 on the left,
659 Hz at amplitude 0.2 on the right, 48 kHz, half a second. It contains no
third-party recording. `reference.f32` uses FFmpeg's independent native Vorbis
decoder; it omits the final 128 padding frames, which the comparison skips.

Regeneration commands (FFmpeg with libvorbis encoding support):

```sh
ffmpeg -v error -y -f lavfi -i "aevalsrc=0.3*sin(2*PI*440*t)|0.2*sin(2*PI*659*t):s=48000:d=0.5" -c:a libvorbis -q:a 4 tone.ogg
ffmpeg -v error -y -c:a vorbis -i tone.ogg -f f32le reference.f32
```
