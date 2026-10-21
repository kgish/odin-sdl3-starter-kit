package main

import "core:log"
import "core:math"
import "core:path/filepath"
import "core:strings"
import "../game"
import sdl "vendor:sdl3"

BACKGROUND_FILE :: "backgrounds/blue-nebula.bmp"
// Brightness of the image in percent, applied as a color mod. The image is
// already dark, so the default is full brightness; the panel adjusts it (0..100).
BACKGROUND_BRIGHTNESS :: 100
// Leftward drift in world units per second; the image tiles horizontally.
// The tuning panel adjusts `speed` within 0..BACKGROUND_SCROLL_MAX.
BACKGROUND_SCROLL_SPEED :: 4
BACKGROUND_SCROLL_MAX   :: 60
// Longest frame gap the drift follows, so a stall does not jump the image.
BACKGROUND_MAX_STEP_NS :: 250_000_000

// The scrolling backdrop. `texture` is optional: nil when the image is missing,
// and render then uses the clear color. It is created in background_load and
// destroyed only in background_destroy. The drift is cosmetic, not simulation
// state, so it keeps moving while the game is paused.
Background :: struct {
	texture:    ^sdl.Texture,
	speed:      f32, // world units per second
	brightness: f32, // percent
	offset:     f32, // 0 ..< WORLD_WIDTH
	last_ns:    u64, // 0 until the first advance
}

background_make :: proc() -> Background {
	return {speed = BACKGROUND_SCROLL_SPEED, brightness = BACKGROUND_BRIGHTNESS}
}

// Loads the texture from `asset_dir`. BMP keeps this in core SDL, so the
// baseline does not link SDL_image. A missing or unreadable file is not fatal.
background_load :: proc(bg: ^Background, renderer: ^sdl.Renderer, asset_dir: string) {
	path, _ := filepath.join({asset_dir, BACKGROUND_FILE}, context.temp_allocator)
	surface := sdl.LoadBMP(strings.clone_to_cstring(path, context.temp_allocator))
	if surface == nil {
		log.warnf("background not loaded (%s): %s", path, sdl.GetError())
		return
	}
	defer sdl.DestroySurface(surface)

	bg.texture = sdl.CreateTextureFromSurface(renderer, surface)
	if bg.texture == nil {
		log.warnf("CreateTextureFromSurface (background) failed: %s", sdl.GetError())
		return
	}
	log.infof("loaded background %vx%v", surface.w, surface.h)
}

background_destroy :: proc(bg: ^Background) {
	if bg.texture != nil {
		sdl.DestroyTexture(bg.texture)
		bg.texture = nil
		log.debug("destroyed background")
	}
}

// Moves the drift on to `now_ns` (monotonic) at the current speed. Speed
// changes take effect from here on, without a jump.
background_advance :: proc(bg: ^Background, now_ns: u64) {
	if bg.last_ns != 0 && now_ns > bg.last_ns {
		dt := f32(min(now_ns - bg.last_ns, BACKGROUND_MAX_STEP_NS)) / 1e9
		bg.offset = math.mod(bg.offset + bg.speed * dt, f32(game.WORLD_WIDTH))
	}
	bg.last_ns = now_ns
}

// Maps a brightness percentage to a texture color mod value (0..255).
background_color_mod :: proc(brightness: f32) -> u8 {
	return u8(math.round(clamp(brightness, 0, 100) * 2.55))
}

// Draws the texture stretched to the world size as two side-by-side copies,
// so the seam wraps around.
background_draw :: proc(bg: Background, r: ^sdl.Renderer) -> bool {
	if bg.texture == nil {
		return true
	}
	m := background_color_mod(bg.brightness)
	sdl.SetTextureColorMod(bg.texture, m, m, m) or_return
	W :: f32(game.WORLD_WIDTH)
	dst := sdl.FRect{-bg.offset, 0, W, game.WORLD_HEIGHT}
	sdl.RenderTexture(r, bg.texture, nil, &dst) or_return
	dst.x += W
	return sdl.RenderTexture(r, bg.texture, nil, &dst)
}
