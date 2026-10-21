package main

import "core:log"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

BACKGROUND_FILE :: "backgrounds/blue-nebula.bmp"
// Color mod applied to the background so it stays behind the game (0..255).
BACKGROUND_DIM :: 110

// Loads the background texture from `asset_dir`. BMP keeps this in core SDL,
// so the baseline does not link SDL_image. A missing or unreadable file is
// not fatal: the caller keeps a nil texture and render falls back to the
// clear color. The texture is destroyed only in background_destroy.
background_load :: proc(renderer: ^sdl.Renderer, asset_dir: string) -> ^sdl.Texture {
	path, _ := filepath.join({asset_dir, BACKGROUND_FILE}, context.temp_allocator)
	surface := sdl.LoadBMP(strings.clone_to_cstring(path, context.temp_allocator))
	if surface == nil {
		log.warnf("background not loaded (%s): %s", path, sdl.GetError())
		return nil
	}
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		log.warnf("CreateTextureFromSurface (background) failed: %s", sdl.GetError())
		return nil
	}
	sdl.SetTextureColorMod(texture, BACKGROUND_DIM, BACKGROUND_DIM, BACKGROUND_DIM)
	log.infof("loaded background %vx%v", surface.w, surface.h)
	return texture
}

background_destroy :: proc(texture: ^^sdl.Texture) {
	if texture^ != nil {
		sdl.DestroyTexture(texture^)
		texture^ = nil
		log.debug("destroyed background")
	}
}
