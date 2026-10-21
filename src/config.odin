package main

import "core:path/filepath"
import "core:strconv"
import "core:strings"

// Initialization stages, in order. `--fail-after=<stage>` injects a failure
// right after the named stage succeeds, to exercise partial cleanup.
Init_Stage :: enum u8 {
	None,
	Metadata,
	Video,
	Window,
	Renderer,
	Game,
}

Config :: struct {
	window_width:   i32,
	window_height:  i32,
	sim_hz:         int,
	max_elapsed_ms: int,
	max_updates:    int,
	vsync:          bool,
	// Callback rate used when vsync is disabled or unavailable.
	fallback_hz:    int,
	seed:           u64,
	// Testing hooks; zero/None disables them.
	smoke_frames:   int,
	push_quit_at:   int,
	fail_after:     Init_Stage,
	// Development override for the asset directory. Borrowed from argv.
	asset_dir:      string,
}

Config_Error :: enum u8 {
	None,
	Unknown_Option,
	Bad_Value,
	Out_Of_Range,
}

config_default :: proc() -> Config {
	return Config{
		window_width   = 1280,
		window_height  = 720,
		sim_hz         = 60,
		max_elapsed_ms = 250,
		max_updates    = 5,
		vsync          = true,
		fallback_hz    = 120,
		seed           = 0x5eed,
	}
}

// Parses `--key=value` options (argv without the program name) over the defaults.
// On error, `bad` is the offending argument.
config_parse :: proc(args: []string) -> (cfg: Config, err: Config_Error, bad: string) {
	cfg = config_default()
	for arg in args {
		key, _, value := strings.partition(arg, "=")
		ok := true
		switch key {
		case "--frames":       cfg.smoke_frames, ok = strconv.parse_int(value)
		case "--push-quit-at": cfg.push_quit_at, ok = strconv.parse_int(value)
		case "--seed":         cfg.seed, ok = strconv.parse_u64(value)
		case "--sim-hz":       cfg.sim_hz, ok = strconv.parse_int(value)
		case "--no-vsync":     cfg.vsync = false
		case "--assets":       cfg.asset_dir = value; ok = value != ""
		case "--fail-after":   cfg.fail_after, ok = parse_stage(value)
		case:
			return cfg, .Unknown_Option, arg
		}
		if !ok {
			return cfg, .Bad_Value, arg
		}
	}
	return cfg, config_validate(cfg), ""
}

config_validate :: proc(cfg: Config) -> Config_Error {
	switch {
	case cfg.window_width <= 0 || cfg.window_height <= 0,
	     cfg.sim_hz < 1 || cfg.sim_hz > 1000,
	     cfg.max_elapsed_ms < 1,
	     cfg.max_updates < 1,
	     cfg.fallback_hz < 1,
	     cfg.smoke_frames < 0,
	     cfg.push_quit_at < 0:
		return .Out_Of_Range
	}
	return .None
}

// Picks the asset directory: an explicit override wins, otherwise `assets`
// next to the executable. Never depends on the working directory.
resolve_asset_dir :: proc(base_dir, override: string, allocator := context.allocator) -> string {
	if override != "" {
		return strings.clone(override, allocator)
	}
	path, _ := filepath.join({base_dir, "assets"}, allocator)
	return path
}

@(private = "file")
parse_stage :: proc(s: string) -> (Init_Stage, bool) {
	switch s {
	case "metadata": return .Metadata, true
	case "video":    return .Video, true
	case "window":   return .Window, true
	case "renderer": return .Renderer, true
	case "game":     return .Game, true
	}
	return .None, false
}
