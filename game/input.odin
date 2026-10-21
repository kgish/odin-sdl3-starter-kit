package game

// Abstract game actions. The platform layer maps physical keys to these;
// nothing in this package knows about SDL scancodes.
Action :: enum u8 {
	Left,
	Right,
	Up,
	Down,
	Confirm,
	Pause,
}

Actions :: bit_set[Action]

// Input accumulates transitions between simulation steps.
//
// `held` reflects the current physical state. `pressed` and `released` latch
// transitions until a simulation step consumes them, so a tap that starts and
// ends within one render-only iteration is still seen exactly once.
Input :: struct {
	held:     Actions,
	pressed:  Actions,
	released: Actions,
}

// The input one simulation step observes.
Step_Input :: struct {
	held:     Actions,
	pressed:  Actions,
	released: Actions,
}

input_press :: proc(input: ^Input, action: Action) {
	if action in input.held {
		return // key repeat or duplicate event; not a new transition
	}
	input.held += {action}
	input.pressed += {action}
}

input_release :: proc(input: ^Input, action: Action) {
	if action not_in input.held {
		return
	}
	input.held -= {action}
	input.released += {action}
}

// Clears held actions without generating transitions. Call on focus loss so
// keys released while another window has focus do not stay stuck down.
input_reset :: proc(input: ^Input) {
	input^ = {}
}

// Returns the input for one simulation step and clears the one-shot
// transitions, so catch-up steps in the same iteration do not repeat them.
input_consume :: proc(input: ^Input) -> Step_Input {
	step := Step_Input{input.held, input.pressed, input.released}
	input.pressed = {}
	input.released = {}
	return step
}
