/* Test-only CoreAudio tap: never write files or allocate in the render callback. */
#include <AudioToolbox/AudioToolbox.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <mach/mach_time.h>

#define STREAMS 8
#define SAMPLE_CAPACITY (48000u * 120u * 2u)
#define TICK_CAPACITY 60000u
struct tick { double sample; uint64_t host; uint32_t frames, status; };
struct capture {
    AudioUnit unit;
    AURenderCallback callback;
    void *user;
    float *samples;
    struct tick *ticks;
    size_t sample_count, tick_count;
    unsigned overflow, unsupported;
    AudioStreamBasicDescription format;
};
static mach_timebase_info_data_t timebase;
static uint64_t continuous_offset;
__attribute__((constructor)) static void loaded(void) {
    mach_timebase_info(&timebase);
    continuous_offset = mach_continuous_time() - mach_absolute_time();
    if (getenv("NP_AUDIO_CAPTURE_DIR")) fprintf(stderr, "MEDIA_CAPTURE_LOADED pid=%d\n", getpid());
}
static struct capture streams[STREAMS];
static unsigned stream_count;
static void save(unsigned index);

static OSStatus record(void *user, AudioUnitRenderActionFlags *flags,
                       const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    struct capture *capture = user;
    OSStatus result = capture->callback(capture->user, flags, time, bus, frames, data);
    if (capture->tick_count < TICK_CAPACITY) {
        capture->ticks[capture->tick_count++] = (struct tick){time->mSampleTime, time->mHostTime, frames, (uint32_t)result};
    } else capture->overflow = 1;
    if (!data || data->mNumberBuffers != 1 || !data->mBuffers[0].mData ||
        !(capture->format.mFormatFlags & kAudioFormatFlagIsFloat) || capture->format.mBitsPerChannel != 32) {
        capture->unsupported = 1;
        return result;
    }
    size_t count = data->mBuffers[0].mDataByteSize / sizeof(float);
    if (count <= SAMPLE_CAPACITY - capture->sample_count) {
        memcpy(capture->samples + capture->sample_count, data->mBuffers[0].mData, count * sizeof(float));
        capture->sample_count += count;
    } else capture->overflow = 1;
    return result;
}

static OSStatus capture_set(AudioUnit unit, AudioUnitPropertyID property, AudioUnitScope scope,
                            AudioUnitElement element, const void *data, UInt32 size) {
    if (getenv("NP_AUDIO_CAPTURE_DIR") && property == kAudioUnitProperty_SetRenderCallback &&
        size == sizeof(AURenderCallbackStruct) && stream_count < STREAMS) {
        const AURenderCallbackStruct *original = data;
        if (!original->inputProc) return AudioUnitSetProperty(unit, property, scope, element, data, size);
        struct capture *capture = &streams[stream_count];
        UInt32 format_size = sizeof(capture->format);
        OSStatus status = AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                                               kAudioUnitScope_Input, element, &capture->format, &format_size);
        if (status) { fprintf(stderr, "MEDIA_CAPTURE_FORMAT_ERROR status=%d\n", (int)status); return AudioUnitSetProperty(unit, property, scope, element, data, size); }
        capture->samples = calloc(SAMPLE_CAPACITY, sizeof(float));
        capture->ticks = calloc(TICK_CAPACITY, sizeof(struct tick));
        if (!capture->samples || !capture->ticks) {
            free(capture->samples); free(capture->ticks);
            return AudioUnitSetProperty(unit, property, scope, element, data, size);
        }
        capture->callback = original->inputProc; capture->user = original->inputProcRefCon;
        capture->unit = unit;
        AURenderCallbackStruct replacement = {record, capture};
        status = AudioUnitSetProperty(unit, property, scope, element, &replacement, sizeof(replacement));
        if (!status) ++stream_count;
        else { free(capture->samples); free(capture->ticks); }
        return status;
    }
    return AudioUnitSetProperty(unit, property, scope, element, data, size);
}

__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement, *original; } interpose = {
    (const void *)capture_set, (const void *)AudioUnitSetProperty
};

static OSStatus capture_stop(AudioUnit unit) {
    OSStatus status = AudioOutputUnitStop(unit);
    if (!status) for (unsigned i = 0; i < stream_count; ++i) if (streams[i].unit == unit) save(i);
    return status;
}
__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement, *original; } stop_interpose = {
    (const void *)capture_stop, (const void *)AudioOutputUnitStop
};

static void save(unsigned i) {
    const char *directory = getenv("NP_AUDIO_CAPTURE_DIR");
    if (!directory) return;
        struct capture *capture = &streams[i]; char path[4096]; FILE *file;
        snprintf(path, sizeof(path), "%s/render-%d-%u.f32", directory, getpid(), i);
        if ((file = fopen(path, "wb"))) { fwrite(capture->samples, sizeof(float), capture->sample_count, file); fclose(file); }
        snprintf(path, sizeof(path), "%s/render-%d-%u.timing", directory, getpid(), i);
        if ((file = fopen(path, "wb"))) { fwrite(capture->ticks, sizeof(struct tick), capture->tick_count, file); fclose(file); }
        snprintf(path, sizeof(path), "%s/render-%d-%u.json", directory, getpid(), i);
        if ((file = fopen(path, "w"))) {
            fprintf(file, "{\"rate\":%.0f,\"channels\":%u,\"samples\":%zu,\"ticks\":%zu,\"overflow\":%u,\"unsupported\":%u,\"timebaseNumer\":%u,\"timebaseDenom\":%u,\"continuousOffset\":%llu}\n",
                    capture->format.mSampleRate, (unsigned)capture->format.mChannelsPerFrame,
                    capture->sample_count, capture->tick_count, capture->overflow, capture->unsupported,
                    timebase.numer, timebase.denom, (unsigned long long)continuous_offset);
            fclose(file);
        }
}

__attribute__((destructor)) static void finish(void) {
    for (unsigned i = 0; i < stream_count; ++i) save(i);
}
