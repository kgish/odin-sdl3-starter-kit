package game

NS_PER_SECOND :: 1_000_000_000

// Fixed simulation step with variable render cadence.
//
// Overload policy: when more than `max_updates` steps are owed in one
// iteration, the excess whole steps are dropped (the simulation runs slower
// than real time) and counted in `dropped_steps`. The fractional remainder is
// kept so interpolation stays smooth.
Timestep :: struct {
	step_ns:        i64,
	max_elapsed_ns: i64,
	max_updates:    int,
	accumulator_ns: i64,
	last_ns:        u64,
	has_last:       bool,
	dropped_steps:  u64,
}

timestep_make :: proc(step_hz: int, max_elapsed_ns: i64, max_updates: int) -> Timestep {
	assert(step_hz > 0)
	assert(max_elapsed_ns > 0)
	assert(max_updates > 0)
	return Timestep{
		step_ns        = NS_PER_SECOND / i64(step_hz),
		max_elapsed_ns = max_elapsed_ns,
		max_updates    = max_updates,
	}
}

// Feeds a monotonic timestamp and returns how many fixed steps to run now.
// The first call only establishes the baseline and returns 0.
timestep_advance :: proc(ts: ^Timestep, now_ns: u64) -> int {
	if !ts.has_last {
		ts.last_ns = now_ns
		ts.has_last = true
		return 0
	}

	elapsed := i64(now_ns - ts.last_ns) if now_ns > ts.last_ns else 0
	ts.last_ns = now_ns
	ts.accumulator_ns += min(elapsed, ts.max_elapsed_ns)

	steps := int(ts.accumulator_ns / ts.step_ns)
	if steps > ts.max_updates {
		ts.dropped_steps += u64(steps - ts.max_updates)
		steps = ts.max_updates
		ts.accumulator_ns %= ts.step_ns
	} else {
		ts.accumulator_ns -= i64(steps) * ts.step_ns
	}
	return steps
}

// Interpolation factor in [0, 1) between the previous and current state.
timestep_alpha :: proc(ts: Timestep) -> f32 {
	return f32(f64(ts.accumulator_ns) / f64(ts.step_ns))
}

timestep_dt :: proc(ts: Timestep) -> f32 {
	return f32(f64(ts.step_ns) / NS_PER_SECOND)
}

// Forgets the baseline and pending time. Call on pause, minimize or resume so
// the next iteration does not try to catch up on the time spent away.
timestep_reset :: proc(ts: ^Timestep) {
	ts.has_last = false
	ts.accumulator_ns = 0
}
