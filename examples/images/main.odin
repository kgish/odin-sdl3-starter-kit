// Optional example: load a PNG with SDL3_image and draw it with SDL's 2D renderer.
//
// Self-contained on purpose: it uses the same startup adapter as src/main.odin
// (see the comments there) so it can be copied or deleted independently.
// Build: scripts/build.sh debug images   (needs scripts/bootstrap.sh --with-image)
package images_example

import "base:runtime"
import "core:c"
import "core:log"
import "core:math"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strconv"
import "core:strings"
import sdl "vendor:sdl3"
import img "vendor:sdl3/image"

EXIT_LEAK :: 3
LOGICAL_W :: 320
LOGICAL_H :: 180

_ :: mem // only used by debug builds

g_context: runtime.Context

App :: struct {
	frames:       int,
	smoke_frames: int,
	screenshot:   string, // borrowed from argv
	asset_dir:    string,
	window:       ^sdl.Window,
	renderer:     ^sdl.Renderer,
	sprite:       ^sdl.Texture,
	sprite_size:  [2]f32,
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
	v, iv := sdl.GetVersion(), img.Version()
	log.infof("SDL %v.%v.%v, SDL_image %v.%v.%v (bindings %v.%v.%v)",
		sdl.VERSIONNUM_MAJOR(v), sdl.VERSIONNUM_MINOR(v), sdl.VERSIONNUM_MICRO(v),
		sdl.VERSIONNUM_MAJOR(iv), sdl.VERSIONNUM_MINOR(iv), sdl.VERSIONNUM_MICRO(iv),
		img.MAJOR_VERSION, img.MINOR_VERSION, img.PATCHLEVEL)

	app.window = sdl.CreateWindow("SDL3_image example", 960, 540, {.RESIZABLE, .HIGH_PIXEL_DENSITY})
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

	path := filepath.join({app.asset_dir, "images", "slime.png"}, context.temp_allocator) or_else ""
	app.sprite = img.LoadTexture(app.renderer, strings.clone_to_cstring(path, context.temp_allocator))
	if app.sprite == nil {
		log.errorf("failed to load image %s: %s", path, sdl.GetError())
		return .FAILURE
	}
	// Keep pixel art crisp when scaled up.
	sdl.SetTextureScaleMode(app.sprite, .PIXELART)
	sdl.GetTextureSize(app.sprite, &app.sprite_size.x, &app.sprite_size.y)
	log.infof("loaded image %vx%v from %s", app.sprite_size.x, app.sprite_size.y, path)
	return .CONTINUE
}

app_iterate :: proc "c" (appstate: rawptr) -> sdl.AppResult {
	context = g_context
	defer free_all(context.temp_allocator)
	app := (^App)(appstate)
	app.frames += 1

	t := f32(f64(sdl.GetTicksNS()) / 1e9)
	r := app.renderer
	sdl.SetRenderDrawColor(r, 30, 34, 48, 255)
	sdl.RenderClear(r)

	// A row of sprites at increasing integer scales, bobbing out of phase.
	x: f32 = 16
	for scale in 1 ..= 5 {
		size := app.sprite_size * f32(scale)
		bob := math.sin(t * 3 + f32(scale)) * 6
		dst := sdl.FRect{x, LOGICAL_H / 2 - size.y / 2 + bob, size.x, size.y}
		sdl.RenderTexture(r, app.sprite, nil, &dst)
		x += size.x + 12
	}
	// One rotated copy to show RenderTextureRotated.
	dst := sdl.FRect{LOGICAL_W - 56, 16, 40, 40}
	sdl.RenderTextureRotated(r, app.sprite, nil, &dst, f64(t * 90), nil, .NONE)

	sdl.SetRenderDrawColor(r, 230, 230, 230, 255)
	sdl.RenderDebugText(r, 8, LOGICAL_H - 16, "SDL3_image + stb_image  ESC: quit")
	if app.screenshot != "" && app.frames == app.smoke_frames {
		save_screenshot(r, app.screenshot)
	}
	if !sdl.RenderPresent(r) {
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

// Reverse order of creation; tolerates partial initialization.
app_quit :: proc "c" (appstate: rawptr, result: sdl.AppResult) {
	context = g_context
	app := (^App)(appstate)
	if app == nil do return
	if app.sprite != nil {
		sdl.DestroyTexture(app.sprite)
		log.debug("destroyed texture")
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
