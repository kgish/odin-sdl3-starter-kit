package main

import "core:log"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

BALL_SPRITE_FILE :: "sprites/ball.bmp"

// Loads the ball image from `asset_dir`. A 32-bit BMP with alpha keeps this in
// core SDL, so the baseline does not link SDL_image. A missing or unreadable
// file is not fatal: it returns nil and render draws a plain square instead.
// The caller owns the texture and frees it with ball_sprite_destroy.
ball_sprite_load :: proc(renderer: ^sdl.Renderer, asset_dir: string) -> ^sdl.Texture {
	path, _ := filepath.join({asset_dir, BALL_SPRITE_FILE}, context.temp_allocator)
	surface := sdl.LoadBMP(strings.clone_to_cstring(path, context.temp_allocator))
	if surface == nil {
		log.warnf("ball sprite not loaded (%s): %s", path, sdl.GetError())
		return nil
	}
	defer sdl.DestroySurface(surface)

	texture := sdl.CreateTextureFromSurface(renderer, surface)
	if texture == nil {
		log.warnf("CreateTextureFromSurface (ball sprite) failed: %s", sdl.GetError())
		return nil
	}
	sdl.SetTextureBlendMode(texture, {.BLEND})
	// Smooth: the ball is drawn at any size from BALL_SIZE_MIN to BALL_SIZE_MAX.
	sdl.SetTextureScaleMode(texture, .LINEAR)
	log.infof("loaded ball sprite %vx%v", surface.w, surface.h)
	return texture
}

ball_sprite_destroy :: proc(texture: ^^sdl.Texture) {
	if texture^ != nil {
		sdl.DestroyTexture(texture^)
		texture^ = nil
		log.debug("destroyed ball sprite")
	}
}
