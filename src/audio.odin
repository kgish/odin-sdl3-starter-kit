package main

import "core:log"
import "core:math"
import sdl "vendor:sdl3"

BEEP_RATE     :: 48_000 // samples per second, mono f32
BEEP_SECONDS  :: 0.06
BEEP_VOLUME   :: 0.2
// Skip a beep rather than let them pile up if the device falls behind.
BEEP_MAX_QUEUED :: BEEP_RATE / 10 * size_of(f32)

Sound :: enum u8 {
	Wall,   // ball hits a world edge
	Paddle, // ball hits the player's paddle
}

// Pitch of each sound; the paddle is an octave above the wall.
@(rodata)
SOUND_HZ := [Sound]f32 {
	.Wall   = 880,
	.Paddle = 1760,
}

// Sound output. Optional: if no audio device can be opened the game runs
// silently. `stream` is created in audio_open and destroyed only in
// audio_close; destroying it also closes the device SDL opened for it.
Audio :: struct {
	stream: ^sdl.AudioStream,
	sounds: [Sound][]f32,
}

// Returns false (after logging why) if sound is unavailable.
audio_open :: proc(audio: ^Audio) -> bool {
	if !sdl.InitSubSystem({.AUDIO}) {
		log.warnf("audio disabled: SDL_InitSubSystem(AUDIO) failed: %s", sdl.GetError())
		return false
	}
	spec := sdl.AudioSpec{format = .F32, channels = 1, freq = BEEP_RATE}
	audio.stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, nil, nil)
	if audio.stream == nil {
		log.warnf("audio disabled: OpenAudioDeviceStream failed: %s", sdl.GetError())
		return false
	}
	log.debug("created audio stream")
	// Device streams start paused.
	if !sdl.ResumeAudioStreamDevice(audio.stream) {
		log.warnf("ResumeAudioStreamDevice failed: %s", sdl.GetError())
	}
	for &samples, sound in audio.sounds {
		samples = make_beep(SOUND_HZ[sound])
	}
	log.infof("audio driver: %s", sdl.GetCurrentAudioDriver())
	return true
}

audio_close :: proc(audio: ^Audio) {
	if audio.stream != nil {
		sdl.DestroyAudioStream(audio.stream)
		audio.stream = nil
		log.debug("destroyed audio stream")
	}
	for &samples in audio.sounds {
		delete(samples)
		samples = nil
	}
}

// Queues one sound. SDL copies the samples, so `audio.sounds` stays ours.
audio_play :: proc(audio: ^Audio, sound: Sound) {
	if audio.stream == nil || sdl.GetAudioStreamQueued(audio.stream) > BEEP_MAX_QUEUED {
		return
	}
	samples := audio.sounds[sound]
	if !sdl.PutAudioStreamData(audio.stream, raw_data(samples), i32(len(samples) * size_of(f32))) {
		log.warnf("PutAudioStreamData failed: %s", sdl.GetError())
	}
}

// A short sine tone with a quick fade in and out to avoid clicks.
@(private = "file")
make_beep :: proc(hz: f32) -> []f32 {
	n :: int(BEEP_RATE * BEEP_SECONDS)
	fade :: BEEP_RATE / 200 // 5 ms
	samples := make([]f32, n)
	for &s, i in samples {
		envelope := min(f32(1), f32(i) / fade, f32(n - 1 - i) / fade)
		s = BEEP_VOLUME * envelope * math.sin(2 * math.PI * hz * f32(i) / BEEP_RATE)
	}
	return samples
}
