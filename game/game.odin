// SDL-independent simulation. Replace this package's contents when starting a
// real game; keep the boundary: plain values in, plain values out.
package game

import "core:math"
import "core:math/linalg"
import "core:math/rand"

WORLD_WIDTH  :: 320
WORLD_HEIGHT :: 180

PLAYER_SIZE  :: 12
PLAYER_SPEED :: 120 // world units per second
BALL_SIZE    :: 6
BALL_SPEED   :: 90  // at the start of each round
// Each paddle hit multiplies the ball's speed, up to BALL_MAX_SPEED.
BALL_SPEEDUP   :: 1.1
BALL_MAX_SPEED :: 1000

// Ranges accepted by game_set_tuning.
BALL_MIN_SPEED  :: 20
BALL_SIZE_MIN   :: 2
BALL_SIZE_MAX   :: 24
PLAYER_SIZE_MIN :: 4
PLAYER_SIZE_MAX :: 48

// The ball moves in sub-steps of at most this distance, half the smallest
// ball + paddle overlap span, so it cannot pass through the paddle between
// collision checks at any speed or simulation rate.
BALL_MAX_SUBSTEP :: f32(BALL_SIZE_MIN + PLAYER_SIZE_MIN) / 2

// Adjustable parameters (the tuning panel edits these).
Tuning :: struct {
	ball_speed:  f32, // launch speed of each round, before paddle speed-ups
	ball_size:   f32,
	player_size: f32,
}

TUNING_DEFAULT :: Tuning{ball_speed = BALL_SPEED, ball_size = BALL_SIZE, player_size = PLAYER_SIZE}

State :: enum u8 {
	Menu,
	Playing,
	Paused,
}

Body :: struct {
	pos:      [2]f32,
	prev_pos: [2]f32,
	vel:      [2]f32,
	size:     f32,
}

Game :: struct {
	state:  State,
	tick:   u64,
	seed:   u64,
	rng:    rand.Default_Random_State,
	player: Body,
	ball:   Body,
	tuning: Tuning,
	// Times the ball has hit a world edge or the player's paddle. They only
	// ever increase, so the platform layer can compare them across
	// iterations to trigger sounds.
	bounces:     u64,
	paddle_hits: u64,
}

// Creates a game whose behaviour depends only on `seed` and the inputs fed to update.
game_make :: proc(seed: u64) -> Game {
	g := Game{seed = seed, rng = rand.create(seed), tuning = TUNING_DEFAULT}
	game_reset_round(&g)
	return g
}

game_reset_round :: proc(g: ^Game) {
	gen := rand.default_random_generator(&g.rng)

	g.player = Body{size = g.tuning.player_size}
	g.player.pos = {WORLD_WIDTH / 2, WORLD_HEIGHT / 2}
	g.player.prev_pos = g.player.pos

	angle := rand.float32_range(0.2, 1.2, gen) // avoid near-axis launches
	sx: f32 = 1 if rand.int_max(2, gen) == 0 else -1
	sy: f32 = 1 if rand.int_max(2, gen) == 0 else -1
	g.ball = Body{size = g.tuning.ball_size}
	g.ball.pos = {WORLD_WIDTH / 4, WORLD_HEIGHT / 4}
	g.ball.prev_pos = g.ball.pos
	g.ball.vel = {sx * linalg.cos(angle), sy * linalg.sin(angle)} * g.tuning.ball_speed
}

// Clamps `t` to the accepted ranges and applies it immediately: sizes change
// now (bodies are kept inside the world), and a new launch speed also
// rescales the ball's current speed, keeping its direction.
game_set_tuning :: proc(g: ^Game, t: Tuning) {
	t := t
	t.ball_speed = clamp(t.ball_speed, BALL_MIN_SPEED, BALL_MAX_SPEED)
	t.ball_size = clamp(t.ball_size, BALL_SIZE_MIN, BALL_SIZE_MAX)
	t.player_size = clamp(t.player_size, PLAYER_SIZE_MIN, PLAYER_SIZE_MAX)

	if t.ball_speed != g.tuning.ball_speed {
		if speed := linalg.length(g.ball.vel); speed > 0 {
			g.ball.vel *= t.ball_speed / speed
		}
	}
	g.tuning = t
	g.ball.size = t.ball_size
	g.player.size = t.player_size
	clamp_to_world(&g.ball)
	clamp_to_world(&g.player)
}

// Current speed of the ball in world units per second.
game_ball_speed :: proc(g: Game) -> f32 {
	return linalg.length(g.ball.vel)
}

// Applies one state-machine transition for the given step input.
// Returns the new state; separated from update so it can be tested alone.
next_state :: proc(state: State, input: Step_Input) -> State {
	switch state {
	case .Menu:
		if .Confirm in input.pressed do return .Playing
	case .Playing:
		if .Pause in input.pressed do return .Paused
	case .Paused:
		if .Pause in input.pressed || .Confirm in input.pressed do return .Playing
	}
	return state
}

// Advances the simulation by exactly one fixed step of `dt` seconds.
game_update :: proc(g: ^Game, input: Step_Input, dt: f32) {
	g.player.prev_pos = g.player.pos
	g.ball.prev_pos = g.ball.pos

	prev := g.state
	g.state = next_state(g.state, input)
	if prev == .Menu && g.state == .Playing {
		game_reset_round(g)
	}
	if g.state != .Playing {
		return
	}
	g.tick += 1

	dir: [2]f32
	if .Left  in input.held do dir.x -= 1
	if .Right in input.held do dir.x += 1
	if .Up    in input.held do dir.y -= 1
	if .Down  in input.held do dir.y += 1
	if dir != 0 {
		dir = linalg.normalize(dir)
	}
	g.player.pos += dir * PLAYER_SPEED * dt
	clamp_to_world(&g.player)

	substeps := max(1, int(math.ceil(linalg.length(g.ball.vel) * dt / BALL_MAX_SUBSTEP)))
	sub_dt := dt / f32(substeps)
	for _ in 0 ..< substeps {
		g.ball.pos += g.ball.vel * sub_dt
		if bounce_in_world(&g.ball) {
			g.bounces += 1
		}
		if bounce_off_body(&g.ball, g.player) {
			g.paddle_hits += 1
			g.ball.vel = speed_up(g.ball.vel)
			// The paddle may have pushed the ball against a wall.
			clamp_to_world(&g.ball)
		}
	}
}

// Position to draw a body at, blending the last two steps by `alpha`.
body_render_pos :: proc(b: Body, alpha: f32) -> [2]f32 {
	return linalg.lerp(b.prev_pos, b.pos, alpha)
}

@(private)
clamp_to_world :: proc(b: ^Body) {
	half := b.size / 2
	b.pos.x = clamp(b.pos.x, half, WORLD_WIDTH - half)
	b.pos.y = clamp(b.pos.y, half, WORLD_HEIGHT - half)
}

// Reflects `b` off the world edges. Returns true if it hit one (a corner
// counts as a single hit).
@(private)
bounce_in_world :: proc(b: ^Body) -> (hit: bool) {
	half := b.size / 2
	if b.pos.x < half || b.pos.x > WORLD_WIDTH - half {
		b.vel.x = -b.vel.x
		hit = true
	}
	if b.pos.y < half || b.pos.y > WORLD_HEIGHT - half {
		b.vel.y = -b.vel.y
		hit = true
	}
	clamp_to_world(b)
	return
}

// If `b` overlaps `paddle`, pushes it out along the axis of least overlap and
// reflects its velocity on that axis. Returns true only when the ball was
// moving towards the paddle, so a ball the paddle pushes from behind (or
// one still separating) is moved but does not count as a hit.
@(private)
bounce_off_body :: proc(b: ^Body, paddle: Body) -> (hit: bool) {
	reach := (b.size + paddle.size) / 2
	delta := b.pos - paddle.pos
	overlap := reach - [2]f32{abs(delta.x), abs(delta.y)}
	if overlap.x <= 0 || overlap.y <= 0 {
		return false
	}
	axis := 0 if overlap.x < overlap.y else 1
	side: f32 = 1 if delta[axis] >= 0 else -1
	b.pos[axis] = paddle.pos[axis] + side * reach
	if b.vel[axis] * side < 0 {
		b.vel[axis] = -b.vel[axis]
		hit = true
	}
	return
}

// Velocity `vel` made BALL_SPEEDUP times faster, but no faster than BALL_MAX_SPEED.
@(private)
speed_up :: proc(vel: [2]f32) -> [2]f32 {
	speed := linalg.length(vel)
	if speed == 0 {
		return vel
	}
	return vel * (min(speed * BALL_SPEEDUP, BALL_MAX_SPEED) / speed)
}
