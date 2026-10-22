package main

import "core:log"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

BALL_SPRITE_FILE   :: "sprites/ball.bmp"
PADDLE_SPRITE_FILE :: "sprites/paddle.bmp"

// Loads the image `file` from `asset_dir`; `name` labels the log lines. A
// 32-bit BMP with alpha keeps this in core SDL, so the baseline does not link
// SDL_image. A missing or unreadable file is not fatal: it returns nil and
// render draws a plain square instead. The caller owns the texture and frees
// it with sprite_destroy.
sprite_load :: proc(renderer: ^sdl.Renderer, asset_dir, file, name: string) -> ^sdl.Texture {
	path, _ := filepath.join({asset_dir, file}, context.temp_allocator)
	surface := sdl.LoadBMP(strings.clone_to_cstring(path, context.temp_allocator))
	if surface == nil {
		log.warnf("%s sprite not loaded (%s): %s", name, path, sdl.GetError())
		return nil
	}
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		log.warnf("CreateTextureFromSurface (%s sprite) failed: %s", name, sdl.GetError())
		return nil
	}
	sdl.SetTextureBlendMode(texture, {.BLEND})
	// Smooth: bodies are drawn at any size the tuning panel allows.
	sdl.SetTextureScaleMode(texture, .LINEAR)
	log.infof("loaded %s sprite %vx%v", name, surface.w, surface.h)
	return texture
}

sprite_destroy :: proc(texture: ^^sdl.Texture, name: string) {
	if texture^ != nil {
		sdl.DestroyTexture(texture^)
		texture^ = nil
		log.debugf("destroyed %s sprite", name)
	}
}
