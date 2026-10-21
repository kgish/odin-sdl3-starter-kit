package game

import "core:testing"

STEP_NS :: NS_PER_SECOND / 60

@(private = "file")
make_test_timestep :: proc() -> Timestep {
	return timestep_make(60, 250_000_000, 5)
}

// --- Input ------------------------------------------------------------------

@(test)
press_sets_held_and_pressed_once :: proc(t: ^testing.T) {
	input: Input
	input_press(&input, .Left)
	input_press(&input, .Left) // repeat
	step := input_consume(&input)
	testing.expect_value(t, step.held, Actions{.Left})
	testing.expect_value(t, step.pressed, Actions{.Left})

	step = input_consume(&input)
	testing.expect_value(t, step.held, Actions{.Left})
	testing.expect_value(t, step.pressed, Actions{})
}

@(test)
release_reports_transition :: proc(t: ^testing.T) {
	input: Input
	input_press(&input, .Up)
	_ = input_consume(&input)
	input_release(&input, .Up)
	input_release(&input, .Up) // duplicate
	step := input_consume(&input)
	testing.expect_value(t, step.held, Actions{})
	testing.expect_value(t, step.released, Actions{.Up})
}

@(test)
tap_between_steps_is_not_lost :: proc(t: ^testing.T) {
	// Pressed and released during render-only iterations (zero sim steps).
	input: Input
	input_press(&input, .Confirm)
	input_release(&input, .Confirm)
	step := input_consume(&input)
	testing.expect_value(t, step.held, Actions{})
	testing.expect_value(t, step.pressed, Actions{.Confirm})
	testing.expect_value(t, step.released, Actions{.Confirm})
}

@(test)
pressed_is_not_repeated_across_catch_up_steps :: proc(t: ^testing.T) {
	input: Input
	input_press(&input, .Pause)
	seen := 0
	for _ in 0 ..< 3 {
		if .Pause in input_consume(&input).pressed do seen += 1
	}
	testing.expect_value(t, seen, 1)
}

@(test)
focus_loss_clears_held :: proc(t: ^testing.T) {
	input: Input
	input_press(&input, .Right)
	input_reset(&input)
	step := input_consume(&input)
	testing.expect_value(t, step.held, Actions{})
	testing.expect_value(t, step.pressed, Actions{})
	// After refocus the key can be pressed again as a fresh transition.
	input_press(&input, .Right)
	testing.expect_value(t, input_consume(&input).pressed, Actions{.Right})
}

// --- Timestep ---------------------------------------------------------------

@(test)
first_advance_only_sets_baseline :: proc(t: ^testing.T) {
	ts := make_test_timestep()
	testing.expect_value(t, timestep_advance(&ts, 5 * NS_PER_SECOND), 0)
	testing.expect_value(t, ts.accumulator_ns, 0)
}

@(test)
accumulates_partial_steps :: proc(t: ^testing.T) {
	ts := make_test_timestep()
	_ = timestep_advance(&ts, 0)
	testing.expect_value(t, timestep_advance(&ts, STEP_NS / 2), 0)
	testing.expect_value(t, timestep_advance(&ts, STEP_NS), 1)
	testing.expect_value(t, timestep_advance(&ts, STEP_NS * 3), 2)
	testing.expect(t, timestep_alpha(ts) >= 0 && timestep_alpha(ts) < 1)
}

@(test)
large_elapsed_time_is_clamped :: proc(t: ^testing.T) {
	ts := make_test_timestep()
	_ = timestep_advance(&ts, 0)
	// 10 s pause in a debugger: clamped to 250 ms = 15 steps, then capped at 5.
	steps := timestep_advance(&ts, 10 * NS_PER_SECOND)
	testing.expect_value(t, steps, 5)
	testing.expect_value(t, ts.dropped_steps, 10)
	testing.expect(t, ts.accumulator_ns < ts.step_ns)
}

@(test)
overload_keeps_fraction :: proc(t: ^testing.T) {
	ts := make_test_timestep()
	_ = timestep_advance(&ts, 0)
	steps := timestep_advance(&ts, 7 * STEP_NS + STEP_NS / 2)
	testing.expect_value(t, steps, 5)
	testing.expect_value(t, ts.dropped_steps, 2)
	testing.expect_value(t, ts.accumulator_ns, STEP_NS / 2)
}

@(test)
reset_prevents_catch_up_after_pause :: proc(t: ^testing.T) {
	ts := make_test_timestep()
	_ = timestep_advance(&ts, 0)
	_ = timestep_advance(&ts, STEP_NS / 2)
	timestep_reset(&ts)
	testing.expect_value(t, timestep_advance(&ts, 60 * NS_PER_SECOND), 0)
	testing.expect_value(t, timestep_advance(&ts, 60 * NS_PER_SECOND + STEP_NS), 1)
}

@(test)
non_monotonic_time_is_ignored :: proc(t: ^testing.T) {
	ts := make_test_timestep()
	_ = timestep_advance(&ts, NS_PER_SECOND)
	testing.expect_value(t, timestep_advance(&ts, 0), 0)
	testing.expect_value(t, ts.accumulator_ns, 0)
}

// --- State machine and simulation -------------------------------------------

@(test)
state_transitions :: proc(t: ^testing.T) {
	confirm := Step_Input{pressed = {.Confirm}}
	pause := Step_Input{pressed = {.Pause}}
	none := Step_Input{}

	testing.expect_value(t, next_state(.Menu, none), State.Menu)
	testing.expect_value(t, next_state(.Menu, pause), State.Menu)
	testing.expect_value(t, next_state(.Menu, confirm), State.Playing)
	testing.expect_value(t, next_state(.Playing, confirm), State.Playing)
	testing.expect_value(t, next_state(.Playing, pause), State.Paused)
	testing.expect_value(t, next_state(.Paused, pause), State.Playing)
	testing.expect_value(t, next_state(.Paused, confirm), State.Playing)
}

@(test)
simulation_is_deterministic :: proc(t: ^testing.T) {
	run :: proc(seed: u64) -> Game {
		g := game_make(seed)
		game_update(&g, {pressed = {.Confirm}}, 1.0 / 60)
		for i in 0 ..< 600 {
			held: Actions = {.Right} if i % 120 < 60 else {.Down}
			game_update(&g, {held = held}, 1.0 / 60)
		}
		return g
	}
	a, b := run(42), run(42)
	testing.expect_value(t, a.tick, 601) // the step that enters Playing also simulates
	testing.expect_value(t, a.player.pos, b.player.pos)
	testing.expect_value(t, a.ball.pos, b.ball.pos)
	testing.expect(t, run(7).ball.pos != a.ball.pos, "different seeds should diverge")
}

@(test)
paused_game_does_not_advance :: proc(t: ^testing.T) {
	g := game_make(1)
	game_update(&g, {pressed = {.Confirm}}, 1.0 / 60)
	game_update(&g, {pressed = {.Pause}}, 1.0 / 60)
	testing.expect_value(t, g.state, State.Paused)
	tick, ball := g.tick, g.ball.pos
	for _ in 0 ..< 10 {
		game_update(&g, {held = {.Left}}, 1.0 / 60)
	}
	testing.expect_value(t, g.tick, tick)
	testing.expect_value(t, g.ball.pos, ball)
}

@(test)
bodies_stay_in_world :: proc(t: ^testing.T) {
	g := game_make(3)
	game_update(&g, {pressed = {.Confirm}}, 1.0 / 60)
	for _ in 0 ..< 2000 {
		game_update(&g, {held = {.Left, .Up}}, 1.0 / 60)
		for b in ([]Body{g.player, g.ball}) {
			half := b.size / 2
			testing.expect(t, b.pos.x >= half && b.pos.x <= WORLD_WIDTH - half)
			testing.expect(t, b.pos.y >= half && b.pos.y <= WORLD_HEIGHT - half)
		}
	}
	testing.expect_value(t, g.player.pos, [2]f32{PLAYER_SIZE / 2, PLAYER_SIZE / 2})
}

@(test)
bounces_are_counted_once_per_hit :: proc(t: ^testing.T) {
	g := game_make(1)
	game_update(&g, {pressed = {.Confirm}}, 1.0 / 60)
	g.ball.pos = {WORLD_WIDTH - BALL_SIZE, WORLD_HEIGHT / 2}
	g.ball.vel = {BALL_SPEED, 0}

	game_update(&g, {}, 1.0 / 60) // still inside
	testing.expect_value(t, g.bounces, 0)
	for _ in 0 ..< 3 {
		game_update(&g, {}, 1.0 / 60)
	}
	testing.expect_value(t, g.bounces, 1) // hit the right edge once, now moving away
	testing.expect(t, g.ball.vel.x < 0)

	game_update(&g, {pressed = {.Pause}}, 1.0 / 60)
	g.ball.pos = {BALL_SIZE / 2, WORLD_HEIGHT / 2}
	for _ in 0 ..< 10 {
		game_update(&g, {}, 1.0 / 60)
	}
	testing.expect_value(t, g.bounces, 1) // paused: no movement, no bounces
}

@(test)
ball_reflects_off_paddle :: proc(t: ^testing.T) {
	g := game_make(1)
	game_update(&g, {pressed = {.Confirm}}, 1.0 / 60)
	reach: f32 = (BALL_SIZE + PLAYER_SIZE) / 2
	// Ball approaching the paddle's right side, level with it.
	g.ball.pos = g.player.pos + {reach + 1, 0}
	g.ball.vel = {-BALL_SPEED, 0}
	bounces := g.bounces

	for _ in 0 ..< 3 {
		game_update(&g, {}, 1.0 / 60)
	}
	testing.expect_value(t, g.paddle_hits, 1)
	testing.expect_value(t, g.bounces, bounces) // not a wall hit
	testing.expect(t, g.ball.vel.x > 0)
	testing.expect(t, g.ball.pos.x >= g.player.pos.x + reach) // pushed clear

	for _ in 0 ..< 5 {
		game_update(&g, {}, 1.0 / 60)
	}
	testing.expect_value(t, g.paddle_hits, 1) // separating: no repeat hits
}

@(test)
paddle_pushing_a_departing_ball_is_not_a_hit :: proc(t: ^testing.T) {
	g := game_make(1)
	game_update(&g, {pressed = {.Confirm}}, 1.0 / 60)
	reach: f32 = (BALL_SIZE + PLAYER_SIZE) / 2
	// Ball moving slowly right, paddle chasing it faster from the left.
	g.ball.pos = g.player.pos + {reach + 0.5, 0}
	g.ball.vel = {10, 0}

	game_update(&g, {held = {.Right}}, 1.0 / 60)
	testing.expect_value(t, g.paddle_hits, 0)
	testing.expect(t, g.ball.vel.x > 0)
	testing.expect(t, g.ball.pos.x - g.player.pos.x >= reach)
}

@(test)
render_position_interpolates :: proc(t: ^testing.T) {
	b := Body{prev_pos = {0, 0}, pos = {10, 20}}
	testing.expect_value(t, body_render_pos(b, 0), [2]f32{0, 0})
	testing.expect_value(t, body_render_pos(b, 0.5), [2]f32{5, 10})
}
