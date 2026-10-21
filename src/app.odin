package main

import "core:fmt"
import "core:log"
import "core:os"
import "../game"
import sdl "vendor:sdl3"

APP_NAME       :: "Odin SDL3 Starter"
APP_VERSION    :: "0.1.0"
APP_IDENTIFIER :: "org.example.odin-sdl3-starter"

// Everything the application owns. Allocated in app_init, freed in app_quit.
//
// Ownership: `window`, `renderer` and `audio` are created in app_init and
// destroyed only in app_quit (audio, renderer, then window). SDL itself is shut down by SDL after app_quit
// returns, so there is no SDL_Quit call here.
App_State :: struct {
	cfg:       Config,
	asset_dir: string,
	window:    ^sdl.Window,
	renderer:  ^sdl.Renderer,
	audio:     Audio,
	// Game hit counters already answered with a sound.
	bounces_heard:     u64,
	paddle_hits_heard: u64,
	input:     game.Input,
	timestep:  game.Timestep,
	game:      game.Game,
	// True while minimized or hidden: skip simulation and rendering.
	suspended: bool,
	frames:    int,
	dropped_reported: u64,
}

app_init :: proc(appstate: ^rawptr, argv: []cstring) -> sdl.AppResult {
	defer free_all(context.temp_allocator)

	// Publish state before anything can fail, so app_quit can clean up.
	state := new(App_State)
	appstate^ = state

	args := make([]string, max(len(argv) - 1, 0), context.temp_allocator)
	for &arg, i in args {
		arg = string(argv[i + 1])
	}
	cfg, cfg_err, bad := config_parse(args)
	if cfg_err != .None {
		log.errorf("invalid configuration (%v): %q", cfg_err, bad)
		return .FAILURE
	}
	state.cfg = cfg

	// Metadata
	if !sdl.SetAppMetadata(APP_NAME, APP_VERSION, APP_IDENTIFIER) {
		log.warnf("SetAppMetadata failed: %s", sdl.GetError())
	}
	if injected_failure(state, .Metadata) do return .FAILURE

	// Video
	if !sdl.Init({.VIDEO, .EVENTS}) {
		log.errorf("SDL_Init failed: %s", sdl.GetError())
		return .FAILURE
	}
	log_versions()
	if injected_failure(state, .Video) do return .FAILURE

	// Window
	state.window = sdl.CreateWindow(APP_NAME, cfg.window_width, cfg.window_height, {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if state.window == nil {
		log.errorf("CreateWindow failed: %s", sdl.GetError())
		return .FAILURE
	}
	log.debug("created window")
	if injected_failure(state, .Window) do return .FAILURE

	// Renderer
	state.renderer = sdl.CreateRenderer(state.window, nil)
	if state.renderer == nil {
		log.errorf("CreateRenderer failed: %s", sdl.GetError())
		return .FAILURE
	}
	log.debugf("created renderer")
	log.infof("renderer: %s", sdl.GetRendererName(state.renderer))
	configure_pacing(state)
	// Render in world units; SDL scales to the window's pixel size (high DPI aware).
	if !sdl.SetRenderLogicalPresentation(state.renderer, game.WORLD_WIDTH, game.WORLD_HEIGHT, .LETTERBOX) {
		log.warnf("SetRenderLogicalPresentation failed: %s", sdl.GetError())
	}
	if injected_failure(state, .Renderer) do return .FAILURE

	// Audio (optional: the game still runs without a sound device)
	if cfg.sound {
		audio_open(&state.audio)
	} else {
		log.info("audio disabled (--mute)")
	}
	if injected_failure(state, .Audio) do return .FAILURE

	// Game
	state.asset_dir = resolve_asset_dir(string(sdl.GetBasePath()), cfg.asset_dir)
	if !os.is_dir(state.asset_dir) {
		log.warnf("asset directory not found: %s", state.asset_dir)
	}
	state.game = game.game_make(cfg.seed)
	state.timestep = game.timestep_make(cfg.sim_hz, i64(cfg.max_elapsed_ms) * 1_000_000, cfg.max_updates)
	if injected_failure(state, .Game) do return .FAILURE

	log.info("initialized")
	return .CONTINUE
}

app_iterate :: proc(state: ^App_State) -> sdl.AppResult {
	// Frame scratch boundary: nothing temp-allocated may outlive one callback.
	defer free_all(context.temp_allocator)

	state.frames += 1
	if state.cfg.push_quit_at > 0 && state.frames == state.cfg.push_quit_at {
		quit := sdl.Event{type = .QUIT}
		if !sdl.PushEvent(&quit) {
			log.errorf("PushEvent failed: %s", sdl.GetError())
			return .FAILURE
		}
	}

	if state.suspended {
		// Nothing is visible and vsync may not block while minimized.
		sdl.DelayNS(10_000_000)
	} else {
		steps := game.timestep_advance(&state.timestep, sdl.GetTicksNS())
		dt := game.timestep_dt(state.timestep)
		for _ in 0 ..< steps {
			game.game_update(&state.game, game.input_consume(&state.input), dt)
		}
		// At most one sound of each kind per iteration, however many hits the
		// steps produced.
		if state.game.bounces != state.bounces_heard {
			state.bounces_heard = state.game.bounces
			audio_play(&state.audio, .Wall)
		}
		if state.game.paddle_hits != state.paddle_hits_heard {
			state.paddle_hits_heard = state.game.paddle_hits
			audio_play(&state.audio, .Paddle)
		}
		if state.timestep.dropped_steps != state.dropped_reported {
			log.debugf("overloaded: dropped %v steps total", state.timestep.dropped_steps)
			state.dropped_reported = state.timestep.dropped_steps
		}
		if !render(state, game.timestep_alpha(state.timestep)) {
			log.errorf("render failed: %s", sdl.GetError())
			return .FAILURE
		}
	}

	if state.cfg.smoke_frames > 0 && state.frames >= state.cfg.smoke_frames {
		log.infof("smoke run complete after %v frames (tick %v)", state.frames, state.game.tick)
		return .SUCCESS
	}
	return .CONTINUE
}

// The event pointer is borrowed for this call only; copy what must be kept.
app_event :: proc(state: ^App_State, event: ^sdl.Event) -> sdl.AppResult {
	#partial switch event.type {
	case .QUIT:
		log.info("quit requested")
		return .SUCCESS
	case .KEY_DOWN, .KEY_UP:
		if event.key.scancode == .ESCAPE && event.key.down {
			log.info("quit requested (escape)")
			return .SUCCESS
		}
		handle_key(&state.input, event.key)
	case .WINDOW_FOCUS_LOST:
		game.input_reset(&state.input)
	case .WINDOW_MINIMIZED, .WINDOW_HIDDEN:
		state.suspended = true
		game.timestep_reset(&state.timestep)
	case .WINDOW_RESTORED, .WINDOW_SHOWN:
		state.suspended = false
		game.timestep_reset(&state.timestep)
	case .DID_ENTER_FOREGROUND:
		game.timestep_reset(&state.timestep)
	}
	return .CONTINUE
}

// Called exactly once, even when app_init failed part way. `state` may be nil
// if allocation itself failed.
app_quit :: proc(state: ^App_State, result: sdl.AppResult) {
	if state == nil {
		return
	}
	audio_close(&state.audio)
	if state.renderer != nil {
		sdl.DestroyRenderer(state.renderer)
		state.renderer = nil
		log.debug("destroyed renderer")
	}
	if state.window != nil {
		sdl.DestroyWindow(state.window)
		state.window = nil
		log.debug("destroyed window")
	}
	delete(state.asset_dir)
	free(state)
	log.infof("quit: %v", result)
}

@(private = "file")
injected_failure :: proc(state: ^App_State, stage: Init_Stage) -> bool {
	if state.cfg.fail_after != stage {
		return false
	}
	log.errorf("injected failure after stage %v", stage)
	return true
}

@(private = "file")
configure_pacing :: proc(state: ^App_State) {
	if state.cfg.vsync && sdl.SetRenderVSync(state.renderer, 1) {
		log.info("pacing: vsync")
		return
	}
	// Without vsync, let SDL cap the callback rate instead of sleeping ourselves.
	rate := state.cfg.fallback_hz
	if !sdl.SetHint(sdl.HINT_MAIN_CALLBACK_RATE, fmt.ctprintf("%d", rate)) {
		log.warnf("could not set callback rate: %s", sdl.GetError())
	}
	log.infof("pacing: %v Hz callback rate (vsync %s)", rate, "disabled" if !state.cfg.vsync else "unavailable")
}

@(private = "file")
log_versions :: proc() {
	v := sdl.GetVersion()
	log.infof("SDL runtime %v.%v.%v (%s), bindings %v.%v.%v",
		sdl.VERSIONNUM_MAJOR(v), sdl.VERSIONNUM_MINOR(v), sdl.VERSIONNUM_MICRO(v), sdl.GetRevision(),
		sdl.MAJOR_VERSION, sdl.MINOR_VERSION, sdl.MICRO_VERSION)
	log.infof("video driver: %s", sdl.GetCurrentVideoDriver())
}
