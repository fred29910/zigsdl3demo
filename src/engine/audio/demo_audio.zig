//! Optional playback for accepted shots in the training range.
pub const DemoAudio = opaque {
    extern fn demo_audio_create() ?*DemoAudio;
    extern fn demo_audio_destroy(audio: *DemoAudio) void;
    extern fn demo_audio_play_shot(audio: *DemoAudio, hit: c_int) void;
    extern fn demo_audio_set_volume(audio: *DemoAudio, volume: f32) void;

    pub fn init() ?*DemoAudio {
        return demo_audio_create();
    }

    pub fn deinit(self: *DemoAudio) void {
        demo_audio_destroy(self);
    }

    pub fn playShot(self: *DemoAudio, hit: bool) void {
        demo_audio_play_shot(self, @intFromBool(hit));
    }

    pub fn setVolume(self: *DemoAudio, volume01: f32) void {
        demo_audio_set_volume(self, volume01);
    }
};
