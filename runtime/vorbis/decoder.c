#include "limits.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <vorbis/vorbisfile.h>

#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#define API EMSCRIPTEN_KEEPALIVE
#else
#define API
#endif

typedef struct {
    OggVorbis_File decoder;
    unsigned char* bytes;
    size_t size, offset;
    int live;
    uint32_t cursor, cached_start, cached_end;
    float loop_cache[oggChunkFrames * 2];
} Stream;

static Stream streams[maxOggStreams];
static size_t retained;

static size_t read_bytes(void* target, size_t size, size_t count, void* source) {
    Stream* stream = source;
    if (!size)
        return 0;
    size_t available = (stream->size - stream->offset) / size;
    if (count > available)
        count = available;
    memcpy(target, stream->bytes + stream->offset, count * size);
    stream->offset += count * size;
    return count;
}

static int seek_bytes(void* source, ogg_int64_t offset, int origin) {
    Stream* stream = source;
    ogg_int64_t base;
    if (origin == SEEK_SET)
        base = 0;
    else if (origin == SEEK_CUR)
        base = stream->offset;
    else if (origin == SEEK_END)
        base = stream->size;
    else
        return -1;
    if (offset < -base || offset > (ogg_int64_t)stream->size - base)
        return -1;
    stream->offset = (size_t)(base + offset);
    return 0;
}

static long tell_bytes(void* source) {
    return (long)((Stream*)source)->offset;
}

static Stream* lookup(int handle) {
    if (handle < 1 || handle > maxOggStreams || !streams[handle - 1].live)
        return NULL;
    return &streams[handle - 1];
}

API void vorbis_close(int handle) {
    Stream* stream = lookup(handle);
    if (!stream)
        return;
    ov_clear(&stream->decoder);
    retained -= stream->size;
    free(stream->bytes);
    memset(stream, 0, sizeof(*stream));
}

API int vorbis_open(const unsigned char* bytes, int size) {
    if (!bytes || size <= 0 || size > maxOggSourceBytes || retained + size > maxOggEncodedBytes)
        return 0;
    for (int index = 0; index < maxOggStreams; index++) {
        Stream* stream = &streams[index];
        if (stream->live)
            continue;
        stream->bytes = malloc((size_t)size);
        if (!stream->bytes)
            return 0;
        memcpy(stream->bytes, bytes, (size_t)size);
        stream->size = size;
        stream->offset = 0;
        ov_callbacks callbacks = {read_bytes, seek_bytes, NULL, tell_bytes};
        if (ov_open_callbacks(stream, &stream->decoder, NULL, 0, callbacks)) {
            free(stream->bytes);
            memset(stream, 0, sizeof(*stream));
            return 0;
        }
        stream->live = 1;
        retained += size;
        vorbis_info* info = ov_info(&stream->decoder, -1);
        ogg_int64_t frames = ov_pcm_total(&stream->decoder, -1);
        if (ov_streams(&stream->decoder) != 1 || info->rate != audioRate || info->channels < 1 ||
            info->channels > 2 || frames <= 0 || frames > UINT32_MAX) {
            vorbis_close(index + 1);
            return 0;
        }
        return index + 1;
    }
    return 0;
}

API double vorbis_frames(int handle) {
    Stream* stream = lookup(handle);
    return stream ? (double)ov_pcm_total(&stream->decoder, -1) : 0;
}

API int vorbis_seek(int handle, double frame) {
    Stream* stream = lookup(handle);
    if (!stream || !(frame >= 0 && frame <= UINT32_MAX) || frame != (double)(uint32_t)frame)
        return 0;
    if (ov_pcm_seek(&stream->decoder, (ogg_int64_t)frame) != 0)
        return 0;
    stream->cursor = (uint32_t)frame;
    return 1;
}

static int decode_frames(Stream* stream, float* output, int count) {
    if (!stream || !output || count < 1 || count > oggChunkFrames)
        return -1;
    float** pcm;
    int section;
    long frames = ov_read_float(&stream->decoder, &pcm, count, &section);
    vorbis_info* info = ov_info(&stream->decoder, -1);
    if (frames < 0 || info->channels < 1 || info->channels > 2 || info->rate != audioRate)
        return -1;
    for (int i = 0; i < frames; i++) {
        output[i * 2] = pcm[0][i];
        output[i * 2 + 1] = pcm[info->channels - 1][i];
    }
    stream->cursor += (uint32_t)frames;
    return (int)frames;
}

// A short loop is cached in one bounded block. Even a one-frame loop then
// fills a normal queue chunk without thousands of seeks or snapshot leases.
API int vorbis_read(int handle, float* output, int count, uint32_t start, uint32_t end) {
    Stream* stream = lookup(handle);
    if (!stream || !output || count < 1 || count > oggChunkFrames)
        return -1;
    if (!end)
        return decode_frames(stream, output, count);
    if (start >= end || stream->cursor > end || end > (uint32_t)ov_pcm_total(&stream->decoder, -1))
        return -1;
    uint32_t length = end - start;
    if (length <= oggChunkFrames && (stream->cached_start != start || stream->cached_end != end)) {
        uint32_t restore = stream->cursor;
        if (!vorbis_seek(handle, start))
            return -1;
        int filled = 0;
        while (filled < (int)length) {
            int frames =
                decode_frames(stream, stream->loop_cache + filled * 2, (int)length - filled);
            if (frames <= 0)
                return -1;
            filled += frames;
        }
        if (!vorbis_seek(handle, restore))
            return -1;
        stream->cached_start = start;
        stream->cached_end = end;
    }
    int written = 0;
    while (written < count) {
        if (length <= oggChunkFrames && stream->cursor >= start) {
            uint32_t at = (stream->cursor - start) % length;
            int frames = count - written;
            if ((uint32_t)frames > length - at)
                frames = (int)(length - at);
            memcpy(output + written * 2, stream->loop_cache + at * 2, (size_t)frames * 8);
            stream->cursor = start + (at + frames) % length;
            written += frames;
            continue;
        }
        if (stream->cursor == end && !vorbis_seek(handle, start))
            return -1;
        uint32_t boundary = length <= oggChunkFrames ? start : end;
        int frames = count - written;
        if ((uint32_t)frames > boundary - stream->cursor)
            frames = (int)(boundary - stream->cursor);
        frames = decode_frames(stream, output + written * 2, frames);
        if (frames <= 0)
            return -1;
        written += frames;
    }
    return written;
}
