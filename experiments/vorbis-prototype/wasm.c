// Throwaway memory-backed libvorbisfile bridge, one decoder per worker.
#include <emscripten.h>
#include <malloc.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <vorbis/vorbisfile.h>

static OggVorbis_File decoder;
static unsigned char* source;
static size_t length, position;
static int opened;
static float output[2048];

static size_t read_bytes(void* target, size_t size, size_t count, void* unused) {
    (void)unused;
    if (!size)
        return 0;
    size_t available = (length - position) / size;
    if (count > available)
        count = available;
    memcpy(target, source + position, count * size);
    position += count * size;
    return count;
}

static int seek_bytes(void* unused, ogg_int64_t offset, int origin) {
    (void)unused;
    ogg_int64_t base = origin == SEEK_SET ? 0 : origin == SEEK_CUR ? position : length;
    if (offset < -base || offset > (ogg_int64_t)length - base)
        return -1;
    position = (size_t)(base + offset);
    return 0;
}

static long tell_bytes(void* unused) {
    (void)unused;
    return (long)position;
}

EMSCRIPTEN_KEEPALIVE void probe_close(void) {
    if (opened)
        ov_clear(&decoder);
    opened = 0;
}

EMSCRIPTEN_KEEPALIVE int probe_open(unsigned char* data, int bytes) {
    probe_close();
    source = data;
    length = bytes;
    position = 0;
    ov_callbacks callbacks = {read_bytes, seek_bytes, NULL, tell_bytes};
    int result = ov_open_callbacks(source, &decoder, NULL, 0, callbacks);
    if (result)
        return result;
    opened = 1;
    if (ov_info(&decoder, -1)->channels < 1 || ov_info(&decoder, -1)->channels > 2) {
        probe_close();
        return OV_EIMPL;
    }
    return 0;
}

EMSCRIPTEN_KEEPALIVE int probe_seek(double frame) {
    return ov_pcm_seek(&decoder, (ogg_int64_t)frame);
}

EMSCRIPTEN_KEEPALIVE int probe_rate(void) {
    return ov_info(&decoder, -1)->rate;
}

EMSCRIPTEN_KEEPALIVE int probe_channels(void) {
    return ov_info(&decoder, -1)->channels;
}

EMSCRIPTEN_KEEPALIVE float* probe_output(void) {
    return output;
}

EMSCRIPTEN_KEEPALIVE int probe_used(void) {
    return mallinfo().uordblks;
}

EMSCRIPTEN_KEEPALIVE int probe_read(int count) {
    if (count < 1 || count > 1024)
        return OV_EINVAL;
    float** pcm;
    int section;
    long frames = ov_read_float(&decoder, &pcm, count, &section);
    int channels = probe_channels();
    if (channels < 1 || channels > 2)
        return OV_EIMPL;
    for (int i = 0; i < frames; i++)
        for (int ch = 0; ch < channels; ch++)
            output[i * channels + ch] = pcm[ch][i];
    return (int)frames;
}
