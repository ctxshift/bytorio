// Throwaway Windows/libvorbis probe; no console ABI or production code changes.
// Windows multimedia headers require this include order.
// clang-format off
#include <windows.h>
#include <mmsystem.h>
#include <mmreg.h>
// clang-format on
#include <psapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <vorbis/vorbisfile.h>

static double now_ms(void) {
    LARGE_INTEGER counter, frequency;
    QueryPerformanceCounter(&counter);
    QueryPerformanceFrequency(&frequency);
    return 1000.0 * (double)counter.QuadPart / (double)frequency.QuadPart;
}

static SIZE_T private_bytes(void) {
    PROCESS_MEMORY_COUNTERS_EX memory;
    GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS*)&memory, sizeof(memory));
    return memory.PrivateUsage;
}

int main(int argc, char** argv) {
    if (argc < 4)
        return 2;
    OggVorbis_File file;
    SIZE_T baseline = private_bytes(), peak = baseline;
    double started = now_ms(), max_decode_ms = 0;
    if (ov_fopen(argv[1], &file) != 0)
        return 3;
    vorbis_info* info = ov_info(&file, -1);
    int channels = info->channels, rate = info->rate;
    if (channels < 1 || channels > 2)
        return 4;
    int loop = atoi(argv[3]);
    ogg_int64_t first = (ogg_int64_t)(rate * 150.25), end = (ogg_int64_t)(rate * 152.75);
    ogg_int64_t total = 0;
    FILE* output = fopen(argv[2], "wb");
    if (!output)
        return 5;
    float interleaved[2048];
    int section = 0;
    double seek_ms = 0;
    int iterations = loop ? 4 : 1;
    for (int pass = 0; pass < iterations; pass++) {
        if (loop) {
            double start = now_ms();
            if (ov_pcm_seek(&file, first) != 0)
                return 6;
            seek_ms += now_ms() - start;
        }
        while (1) {
            float** pcm;
            int count = 1024;
            if (loop) {
                ogg_int64_t remaining = end - ov_pcm_tell(&file);
                if (remaining <= 0)
                    break;
                if (remaining < count)
                    count = (int)remaining;
            }
            double start = now_ms();
            long frames = ov_read_float(&file, &pcm, count, &section);
            double elapsed = now_ms() - start;
            if (elapsed > max_decode_ms)
                max_decode_ms = elapsed;
            if (frames < 0)
                return 7;
            if (!frames)
                break;
            for (int i = 0; i < frames; i++)
                for (int ch = 0; ch < channels; ch++)
                    interleaved[i * channels + ch] = pcm[ch][i];
            fwrite(interleaved, sizeof(float), frames * channels, output);
            total += frames;
            SIZE_T current = private_bytes();
            if (current > peak)
                peak = current;
        }
    }
    fclose(output);
    ov_clear(&file);
    SIZE_T after = private_bytes();
    SIZE_T reset_peak = after;
    for (int iteration = 0; iteration < 128; iteration++) {
        if (ov_fopen(argv[1], &file) != 0)
            return 14;
        float** pcm;
        if (ov_read_float(&file, &pcm, 1024, &section) < 0)
            return 15;
        SIZE_T current = private_bytes();
        if (current > reset_peak)
            reset_peak = current;
        ov_clear(&file);
    }
    SIZE_T reset_after = private_bytes();
    // Exercise native output using bounded queued blocks, never a whole-track buffer.
    int played = 0;
    if (argc > 4) {
        WAVEFORMATEX format = {WAVE_FORMAT_IEEE_FLOAT,
                               (WORD)channels,
                               rate,
                               rate * channels * 4,
                               (WORD)(channels * 4),
                               32,
                               0};
        HWAVEOUT device;
        HANDLE event = CreateEvent(NULL, FALSE, FALSE, NULL);
        if (waveOutOpen(&device, WAVE_MAPPER, &format, (DWORD_PTR)event, 0, CALLBACK_EVENT) !=
            MMSYSERR_NOERROR)
            return 8;
        if (ov_fopen(argv[1], &file) != 0)
            return 10;
        if (loop && ov_pcm_seek(&file, first) != 0)
            return 11;
        char capture_path[4096];
        snprintf(capture_path, sizeof(capture_path), "%s.played", argv[2]);
        FILE* capture = fopen(capture_path, "wb");
        float buffers[4][4096];
        WAVEHDR headers[4] = {0};
        for (int slot = 0; slot < 4; slot++) {
            headers[slot].lpData = (LPSTR)buffers[slot];
            headers[slot].dwBufferLength = sizeof(buffers[slot]);
            waveOutPrepareHeader(device, &headers[slot], sizeof(WAVEHDR));
        }
        for (int block = 0; block < rate * channels * 8 / 4096; block++) {
            int slot = block % 4;
            while ((headers[slot].dwFlags & WHDR_INQUEUE) != 0)
                WaitForSingleObject(event, 1000);
            size_t count = 0;
            while (count < 4096) {
                int wanted = (4096 - (int)count) / channels;
                if (loop) {
                    ogg_int64_t remaining = end - ov_pcm_tell(&file);
                    if (!remaining) {
                        if (ov_pcm_seek(&file, first) != 0)
                            return 12;
                        remaining = end - first;
                    }
                    if (remaining < wanted)
                        wanted = (int)remaining;
                }
                float** pcm;
                long decoded = ov_read_float(&file, &pcm, wanted, &section);
                if (decoded < 0)
                    return 13;
                if (!decoded)
                    break;
                for (int frame = 0; frame < decoded; frame++)
                    for (int ch = 0; ch < channels; ch++)
                        buffers[slot][count++] = pcm[ch][frame];
            }
            if (!count)
                break;
            fwrite(buffers[slot], sizeof(float), count, capture);
            headers[slot].dwBufferLength = (DWORD)(count * sizeof(float));
            if (waveOutWrite(device, &headers[slot], sizeof(WAVEHDR)) != MMSYSERR_NOERROR)
                return 9;
            played += (int)count / channels;
        }
        for (int slot = 0; slot < 4; slot++) {
            while (headers[slot].dwFlags & WHDR_INQUEUE)
                WaitForSingleObject(event, 1000);
            waveOutUnprepareHeader(device, &headers[slot], sizeof(WAVEHDR));
        }
        fclose(capture);
        ov_clear(&file);
        waveOutClose(device);
        CloseHandle(event);
    }
    printf("{\"frames\":%lld,\"rate\":%d,\"channels\":%d,\"elapsedMs\":%.3f,\"maxDecodeMs\":%.3f,"
           "\"seekMs\":%.3f,\"baselinePrivateBytes\":%llu,\"peakPrivateBytes\":%llu,"
           "\"afterPrivateBytes\":%llu,\"resetPeakPrivateBytes\":%llu,\"resetAfterPrivateBytes\":%"
           "llu,\"playedFrames\":%d}\n",
           total, rate, channels, now_ms() - started, max_decode_ms, seek_ms,
           (unsigned long long)baseline, (unsigned long long)peak, (unsigned long long)after,
           (unsigned long long)reset_peak, (unsigned long long)reset_after, played);
    return 0;
}
