// Startup adapter: the pure-Odin equivalent of SDL_main.h with
// SDL_MAIN_USE_CALLBACKS defined (see SDL_main_impl.h in the locked SDL release).
//
//     main()      -> SDL_RunApp(argc, argv, SDL_main)   platform setup
//     SDL_main()  -> SDL_EnterAppMainCallbacks(...)     SDL owns the loop
//
// Odin's own entry point has already initialized the runtime before main runs,
// so the callbacks can safely call Odin code once they restore `context`.
package main

import "base:runtime"
import "core:c"
import "core:log"
import "core:mem"
import "core:os"
import sdl "vendor:sdl3"

// Exit code reported when a debug build leaks Odin allocations.
EXIT_LEAK :: 3

// The context every SDL callback runs with. Set once in main before SDL can
// call back, never mutated afterwards.
g_context: runtime.Context

main :: proc() {
	os.exit(int(run()))
}

run :: proc() -> (rc: c.int) {
	logger := log.create_console_logger(.Debug when ODIN_DEBUG else .Info)
	defer log.destroy_console_logger(logger)
	context.logger = logger

	when ODIN_DEBUG {
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		context.allocator = mem.tracking_allocator(&tracking)
		defer {
			if report_leaks(&tracking) && rc == 0 {
				rc = EXIT_LEAK
			}
			mem.tracking_allocator_destroy(&tracking)
		}
	}

	g_context = context

	when ODIN_OS == .Windows {
		// Like SDL's WinMain/main shim: SDL rebuilds argv from the command line.
		return sdl.RunApp(0, nil, sdl_main, nil)
	} else {
		return sdl.RunApp(c.int(len(runtime.args__)), raw_data(runtime.args__), sdl_main, nil)
	}
}

sdl_main :: proc "c" (argc: c.int, argv: [^]cstring) -> c.int {
	return sdl.EnterAppMainCallbacks(argc, argv, app_init_c, app_iterate_c, app_event_c, app_quit_c)
}

// Logs leaked and wrongly freed Odin allocations; returns true if there were any.
// Native SDL allocations are not visible here; use native tools for those.
report_leaks :: proc(tracking: ^mem.Tracking_Allocator) -> bool {
	free_all(context.temp_allocator)
	for _, entry in tracking.allocation_map {
		log.errorf("leaked %v bytes at %v", entry.size, entry.location)
	}
	for entry in tracking.bad_free_array {
		log.errorf("bad free of %p at %v", entry.memory, entry.location)
	}
	return len(tracking.allocation_map) > 0 || len(tracking.bad_free_array) > 0
}
