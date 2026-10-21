package main

import "../game"
import sdl "vendor:sdl3"

// Physical key bindings. Scancodes are layout-independent positions, which is
// what movement keys want; text entry would use SDL text input events instead.
@(rodata)
KEY_BINDINGS := [?]struct {
	scancode: sdl.Scancode,
	action:   game.Action,
}{
	{.LEFT,   .Left},
	{.A,      .Left},
	{.RIGHT,  .Right},
	{.D,      .Right},
	{.UP,     .Up},
	{.W,      .Up},
	{.DOWN,   .Down},
	{.S,      .Down},
	{.RETURN, .Confirm},
	{.SPACE,  .Confirm},
	{.P,      .Pause},
}

handle_key :: proc(input: ^game.Input, key: sdl.KeyboardEvent) {
	if key.repeat {
		return
	}
	for binding in KEY_BINDINGS {
		if binding.scancode != key.scancode {
			continue
		}
		if key.down {
			game.input_press(input, binding.action)
		} else {
			game.input_release(input, binding.action)
		}
	}
}
