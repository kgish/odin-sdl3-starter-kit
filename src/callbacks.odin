package main

import "core:c"
import sdl "vendor:sdl3"

// Foreign boundary: SDL calls these with the C ABI and no Odin context.
// Each one restores g_context and forwards to an ordinary Odin procedure.

app_init_c :: proc "c" (appstate: ^rawptr, argc: c.int, argv: [^]cstring) -> sdl.AppResult {
	context = g_context
	return app_init(appstate, argv[:argc])
}

app_iterate_c :: proc "c" (appstate: rawptr) -> sdl.AppResult {
	context = g_context
	return app_iterate((^App_State)(appstate))
}

// Only SDL's main-thread event pump delivers events here: this app never
// pushes events from worker threads. If you add workers, hand their results
// over through a synchronized queue drained in app_iterate instead.
app_event_c :: proc "c" (appstate: rawptr, event: ^sdl.Event) -> sdl.AppResult {
	context = g_context
	return app_event((^App_State)(appstate), event)
}

app_quit_c :: proc "c" (appstate: rawptr, result: sdl.AppResult) {
	context = g_context
	app_quit((^App_State)(appstate), result)
}
