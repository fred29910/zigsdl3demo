#define MA_NO_NULL
#define MA_NO_DECODING
#define MA_NO_ENCODING
#define MA_NO_RESOURCE_MANAGER
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

enum {
    SampleRate = 48000,
    FireFrames = SampleRate * 120 / 1000,
    HitFrames = SampleRate * 100 / 1000,
};

typedef struct {
    ma_audio_buffer buffer;
    ma_sound sound;
} Voice;

typedef struct {
    ma_engine engine;
    Voice fire;
    Voice hit;
    float fire_samples[FireFrames];
    float hit_samples[HitFrames];
} DemoAudio;

static void make_clips(DemoAudio *audio)
{
    const float tau = 6.28318530718f;
    uint32_t noise_seed = 1;
    float low_noise = 0;
    for (unsigned i = 0; i < FireFrames; ++i) {
        const float t = (float)i / SampleRate;
        noise_seed = noise_seed * 1664525u + 1013904223u;
        const float noise = (float)(noise_seed >> 8) / 8388608.0f - 1.0f;
        low_noise += 0.27f * (noise - low_noise);
        const float decay = expf(-38.0f * t) * (float)(FireFrames - 1 - i) / FireFrames;
        audio->fire_samples[i] = decay * (0.44f * low_noise + 0.32f * sinf(tau * t * (115.0f - 260.0f * t)));
    }
    for (unsigned i = 0; i < HitFrames; ++i) {
        const float t = (float)i / SampleRate;
        const float decay = expf(-29.0f * t) * (float)(HitFrames - 1 - i) / HitFrames;
        audio->hit_samples[i] = decay * (0.25f * sinf(tau * 1175.0f * t) + 0.10f * sinf(tau * 1740.0f * t));
    }
}

static ma_result init_voice(Voice *voice, ma_engine *engine, const float *samples, ma_uint64 count)
{
    ma_audio_buffer_config config = ma_audio_buffer_config_init(ma_format_f32, 1, count, samples, NULL);
    config.sampleRate = SampleRate;
    ma_result result = ma_audio_buffer_init(&config, &voice->buffer);
    if (result != MA_SUCCESS)
        return result;
    result = ma_sound_init_from_data_source(engine, &voice->buffer, MA_SOUND_FLAG_NO_SPATIALIZATION, NULL, &voice->sound);
    if (result != MA_SUCCESS)
        ma_audio_buffer_uninit(&voice->buffer);
    return result;
}

static void uninit_voice(Voice *voice)
{
    ma_sound_uninit(&voice->sound);
    ma_audio_buffer_uninit(&voice->buffer);
}

DemoAudio *demo_audio_create(void)
{
    DemoAudio *audio = malloc(sizeof(*audio));
    if (!audio)
        return NULL;

    ma_engine_config config = ma_engine_config_init();
    config.channels = 2;
    config.sampleRate = SampleRate;
    config.periodSizeInMilliseconds = 10;
    config.noAutoStart = MA_TRUE;
    if (ma_engine_init(&config, &audio->engine) != MA_SUCCESS)
        goto free_audio;

    make_clips(audio);
    if (init_voice(&audio->fire, &audio->engine, audio->fire_samples, FireFrames) != MA_SUCCESS)
        goto uninit_engine;
    if (init_voice(&audio->hit, &audio->engine, audio->hit_samples, HitFrames) != MA_SUCCESS)
        goto uninit_fire;
    if (ma_engine_start(&audio->engine) != MA_SUCCESS)
        goto uninit_hit;
    return audio;

uninit_hit:
    uninit_voice(&audio->hit);
uninit_fire:
    uninit_voice(&audio->fire);
uninit_engine:
    ma_engine_uninit(&audio->engine);
free_audio:
    free(audio);
    return NULL;
}

void demo_audio_destroy(DemoAudio *audio)
{
    ma_engine_stop(&audio->engine);
    uninit_voice(&audio->hit);
    uninit_voice(&audio->fire);
    ma_engine_uninit(&audio->engine);
    free(audio);
}

static void play(Voice *voice)
{
    ma_sound_seek_to_pcm_frame(&voice->sound, 0);
    ma_sound_start(&voice->sound);
}

void demo_audio_play_shot(DemoAudio *audio, int hit)
{
    play(&audio->fire);
    if (hit)
        play(&audio->hit);
}

void demo_audio_set_volume(DemoAudio *audio, float volume_01)
{
    if (!audio)
        return;
    if (volume_01 < 0.0f)
        volume_01 = 0.0f;
    if (volume_01 > 1.0f)
        volume_01 = 1.0f;
    ma_engine_set_volume(&audio->engine, volume_01);
}
