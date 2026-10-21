package main

import "core:testing"
import "../game"

SECOND :: 1_000_000_000

@(test)
first_advance_only_starts_the_clock :: proc(t: ^testing.T) {
	bg := background_make()
	background_advance(&bg, 5 * SECOND)
	testing.expect_value(t, bg.offset, 0)
}

@(test)
drift_follows_speed_and_wraps :: proc(t: ^testing.T) {
	bg := background_make()
	bg.speed = 40
	background_advance(&bg, SECOND)
	for i in 1 ..= 10 {
		background_advance(&bg, SECOND + u64(i) * SECOND / 10)
	}
	testing.expect(t, abs(bg.offset - 40) < 0.01, "one second at 40 units/s")

	// 320 units at 40/s is 8 s: whole laps leave the offset unchanged.
	for i in 1 ..= 32 {
		background_advance(&bg, 2 * SECOND + u64(i) * SECOND / 4)
	}
	testing.expect(t, abs(bg.offset - 40) < 0.01, "wraps within the world width")
	testing.expect(t, bg.offset >= 0 && bg.offset < game.WORLD_WIDTH, "offset in range")
}

@(test)
speed_change_does_not_jump :: proc(t: ^testing.T) {
	bg := background_make()
	bg.speed = 10
	background_advance(&bg, SECOND)
	background_advance(&bg, 2 * SECOND)
	before := bg.offset
	bg.speed = 0
	background_advance(&bg, 3 * SECOND)
	testing.expect_value(t, bg.offset, before)
}

@(test)
long_gap_is_clamped :: proc(t: ^testing.T) {
	bg := background_make()
	bg.speed = 10
	background_advance(&bg, SECOND)
	background_advance(&bg, 60 * SECOND)
	testing.expect(t, abs(bg.offset - 2.5) < 0.01, "gap clamped to BACKGROUND_MAX_STEP_NS")
}
