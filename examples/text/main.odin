// Optional example: render text with SDL3_ttf's renderer text engine.
//
// Self-contained on purpose: it uses the same startup adapter as src/main.odin
// (see the comments there) so it can be copied or deleted independently.
// Build: scripts/build.sh debug text   (needs scripts/bootstrap.sh --with-text)
//
// The locked SDL3_ttf is built without HarfBuzz, so text is laid out without
// complex shaping: fine for Latin text, not for e.g. Arabic or Devanagari.
package text_example

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

EXIT_LEAK :: 3
LOGICAL_W :: 640
LOGICAL_H :: 360
FONT_SIZE :: 16

TITLE :: "Odin + SDL3_ttf"
BODY  :: "The quick brown fox jumps over the lazy dog. Text objects are created once and redrawn every frame; only the counter below changes."

_ :: mem // only used by debug builds

g_context: runtime.Context

App :: struct {
	frames:       int,
	smoke_frames: int,
	screenshot:   string, // borrowed from argv
	asset_dir:    string,
	window:       ^sdl.Window,
	renderer:     ^sdl.Renderer,
	ttf_ready:    bool,
	font:         ^ttf.Font,
	engine:       ^ttf.TextEngine,
	title:        ^ttf.Text,
	body:         ^ttf.Text,
	counter:      ^ttf.Text,
}

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
			free_all(context.temp_allocator)
			if (len(tracking.allocation_map) > 0 || len(tracking.bad_free_array) > 0) && rc == 0 {
				log.error("leaked Odin allocations")
				rc = EXIT_LEAK
			}
			mem.tracking_allocator_destroy(&tracking)
		}
	}

	g_context = context
	when ODIN_OS == .Windows {
		return sdl.RunApp(0, nil, sdl_main, nil)
	} else {
		return sdl.RunApp(c.int(len(runtime.args__)), raw_data(runtime.args__), sdl_main, nil)
	}
}

sdl_main :: proc "c" (argc: c.int, argv: [^]cstring) -> c.int {
	return sdl.EnterAppMainCallbacks(argc, argv, app_init, app_iterate, app_event, app_quit)
}

app_init :: proc "c" (appstate: ^rawptr, argc: c.int, argv: [^]cstring) -> sdl.AppResult {
	context = g_context
	defer free_all(context.temp_allocator)

	app := new(App)
	appstate^ = app

	asset_override := ""
	for arg in argv[1:argc] {
		key, _, value := strings.partition(string(arg), "=")
		switch key {
		case "--frames": app.smoke_frames = strconv.parse_int(value) or_else -1
		case "--assets": asset_override = value
		case "--screenshot": app.screenshot = value
		case:
			log.errorf("unknown option %q (expected --frames=N, --assets=DIR or --screenshot=FILE.bmp)", arg)
			return .FAILURE
		}
	}
	if app.smoke_frames < 0 {
		log.error("--frames must be a non-negative integer")
		return .FAILURE
	}
	if asset_override != "" {
		app.asset_dir = strings.clone(asset_override)
	} else {
		app.asset_dir, _ = filepath.join({string(sdl.GetBasePath()), "assets"})
	}

	if !sdl.Init({.VIDEO}) {
		log.errorf("SDL_Init failed: %s", sdl.GetError())
		return .FAILURE
	}
	if !ttf.Init() {
		log.errorf("TTF_Init failed: %s", sdl.GetError())
		return .FAILURE
	}
	app.ttf_ready = true
	log_versions()

	app.window = sdl.CreateWindow("SDL3_ttf example", 960, 540, {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if app.window == nil {
		log.errorf("CreateWindow failed: %s", sdl.GetError())
		return .FAILURE
	}
	app.renderer = sdl.CreateRenderer(app.window, nil)
	if app.renderer == nil {
		log.errorf("CreateRenderer failed: %s", sdl.GetError())
		return .FAILURE
	}
	if !sdl.SetRenderVSync(app.renderer, 1) {
		sdl.SetHint(sdl.HINT_MAIN_CALLBACK_RATE, "120")
	}
	sdl.SetRenderLogicalPresentation(app.renderer, LOGICAL_W, LOGICAL_H, .LETTERBOX)

	path := filepath.join({app.asset_dir, "fonts", "PressStart2P-Regular.ttf"}, context.temp_allocator) or_else ""
	app.font = ttf.OpenFont(strings.clone_to_cstring(path, context.temp_allocator), FONT_SIZE)
	if app.font == nil {
		log.errorf("failed to load font %s: %s", path, sdl.GetError())
		return .FAILURE
	}
	log.infof("loaded font %s", path)
	// This pixel font has no built-in line gap; add one for wrapped text.
	ttf.SetFontLineSkip(app.font, FONT_SIZE * 3 / 2)

	app.engine = ttf.CreateRendererTextEngine(app.renderer)
	if app.engine == nil {
		log.errorf("CreateRendererTextEngine failed: %s", sdl.GetError())
		return .FAILURE
	}

	ok: bool
	if app.title, ok = make_text(app, TITLE, {255, 210, 90}); !ok do return .FAILURE
	if app.body, ok = make_text(app, BODY, {220, 220, 220}); !ok do return .FAILURE
	if app.counter, ok = make_text(app, "", {120, 220, 160}); !ok do return .FAILURE
	if !ttf.SetTextWrapWidth(app.body, LOGICAL_W - 64) {
		log.warnf("SetTextWrapWidth failed: %s", sdl.GetError())
	}
	return .CONTINUE
}

app_iterate :: proc "c" (appstate: rawptr) -> sdl.AppResult {
	context = g_context
	defer free_all(context.temp_allocator)
	app := (^App)(appstate)
	app.frames += 1

	// Only the counter changes; the other Text objects keep their cached layout.
	counter := fmt.tprintf("frame %d", app.frames)
	if !ttf.SetTextString(app.counter, raw_data(counter), len(counter)) {
		log.errorf("SetTextString failed: %s", sdl.GetError())
		return .FAILURE
	}

	r := app.renderer
	sdl.SetRenderDrawColor(r, 24, 26, 36, 255)
	sdl.RenderClear(r)
	ok := ttf.DrawRendererText(app.title, 32, 32) &&
	      ttf.DrawRendererText(app.body, 32, 80) &&
	      ttf.DrawRendererText(app.counter, 32, LOGICAL_H - 48)
	if ok && app.screenshot != "" && app.frames == app.smoke_frames {
		save_screenshot(r, app.screenshot)
	}
	ok = ok && sdl.RenderPresent(r)
	if !ok {
		log.errorf("render failed: %s", sdl.GetError())
		return .FAILURE
	}

	if app.smoke_frames > 0 && app.frames >= app.smoke_frames {
		log.infof("smoke run complete after %v frames", app.frames)
		return .SUCCESS
	}
	return .CONTINUE
}

app_event :: proc "c" (appstate: rawptr, event: ^sdl.Event) -> sdl.AppResult {
	#partial switch event.type {
	case .QUIT:
		return .SUCCESS
	case .KEY_DOWN:
		if event.key.scancode == .ESCAPE do return .SUCCESS
	}
	return .CONTINUE
}

// Reverse order of creation: text objects, then the engine (it uses the
// renderer), the font, TTF itself, and finally renderer and window.
app_quit :: proc "c" (appstate: rawptr, result: sdl.AppResult) {
	context = g_context
	app := (^App)(appstate)
	if app == nil do return
	for text in ([]^ttf.Text{app.counter, app.body, app.title}) {
		if text != nil do ttf.DestroyText(text)
	}
	if app.engine != nil {
		ttf.DestroyRendererTextEngine(app.engine)
		log.debug("destroyed text engine")
	}
	if app.font != nil {
		ttf.CloseFont(app.font)
		log.debug("closed font")
	}
	if app.ttf_ready {
		ttf.Quit()
	}
	if app.renderer != nil {
		sdl.DestroyRenderer(app.renderer)
		log.debug("destroyed renderer")
	}
	if app.window != nil {
		sdl.DestroyWindow(app.window)
		log.debug("destroyed window")
	}
	delete(app.asset_dir)
	free(app)
	log.infof("quit: %v", result)
}

@(private = "file")
make_text :: proc(app: ^App, s: string, color: [3]u8) -> (^ttf.Text, bool) {
	text := ttf.CreateText(app.engine, app.font, raw_data(s), len(s))
	if text == nil {
		log.errorf("CreateText failed: %s", sdl.GetError())
		return nil, false
	}
	ttf.SetTextColor(text, color.r, color.g, color.b, 255)
	return text, true
}

@(private = "file")
log_versions :: proc() {
	v, tv := sdl.GetVersion(), ttf.Version()
	ft: [3]c.int
	ttf.GetFreeTypeVersion(&ft[0], &ft[1], &ft[2])
	log.infof("SDL %v.%v.%v, SDL_ttf %v.%v.%v (bindings %v.%v.%v), FreeType %v.%v.%v",
		sdl.VERSIONNUM_MAJOR(v), sdl.VERSIONNUM_MINOR(v), sdl.VERSIONNUM_MICRO(v),
		sdl.VERSIONNUM_MAJOR(tv), sdl.VERSIONNUM_MINOR(tv), sdl.VERSIONNUM_MICRO(tv),
		ttf.MAJOR_VERSION, ttf.MINOR_VERSION, ttf.PATCHLEVEL, ft[0], ft[1], ft[2])
}

// Saves the current frame as a BMP (core SDL only) for headless visual checks.
@(private = "file")
save_screenshot :: proc(r: ^sdl.Renderer, path: string) {
	surface := sdl.RenderReadPixels(r, nil)
	if surface == nil {
		log.errorf("RenderReadPixels failed: %s", sdl.GetError())
		return
	}
	defer sdl.DestroySurface(surface)
	if !sdl.SaveBMP(surface, strings.clone_to_cstring(path, context.temp_allocator)) {
		log.errorf("SaveBMP failed: %s", sdl.GetError())
		return
	}
	log.infof("saved screenshot %s", path)
}
