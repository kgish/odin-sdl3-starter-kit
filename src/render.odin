package main

import "core:fmt"
import "core:log"
import "core:strings"
import "../game"
import sdl "vendor:sdl3"

// Draws the current game state in world units (see SetRenderLogicalPresentation).
// Returns false if an SDL render call failed; SDL's error string has details.
render :: proc(state: ^App_State, alpha: f32) -> bool {
	r := state.renderer
	g := &state.game

	sdl.SetRenderDrawColor(r, 18, 20, 28, 255) or_return
	sdl.RenderClear(r) or_return
	if state.background != nil {
		background_draw(r, state.background, sdl.GetTicksNS()) or_return
	}

	sdl.SetRenderDrawColor(r, 90, 200, 140, 255) or_return
	draw_body(r, g.player, alpha) or_return
	sdl.SetRenderDrawColor(r, 240, 190, 80, 255) or_return
	draw_body(r, g.ball, alpha) or_return

	sdl.SetRenderDrawColor(r, 230, 230, 230, 255) or_return
	switch g.state {
	case .Menu:
		draw_centered(&state.menu_font, r, game.WORLD_HEIGHT / 2 - 16, "ODIN + SDL3 STARTER", 2) or_return
		draw_centered(&state.menu_font, r, game.WORLD_HEIGHT / 2 + 4, "ENTER: PLAY  ESC: QUIT") or_return
	case .Paused:
		draw_centered_text(r, game.WORLD_HEIGHT / 2 - 4, "PAUSED (P)") or_return
		draw_centered(&state.score_font, r, 4, fmt.tprintf("SCORE %d", g.score)) or_return
	case .Playing:
		draw_centered(&state.score_font, r, 4, fmt.tprintf("SCORE %d", g.score)) or_return
	}

	if state.ui.show_fps {
		draw_fps(r, state.ui.fps) or_return
	}

	ui_draw(&state.ui, r, state.window) or_return
	if state.cfg.screenshot != "" && state.frames == state.cfg.smoke_frames {
		save_screenshot(r, state.cfg.screenshot)
	}
	return sdl.RenderPresent(r)
}

@(private = "file")
draw_body :: proc(r: ^sdl.Renderer, body: game.Body, alpha: f32) -> bool {
	pos := game.body_render_pos(body, alpha)
	half := body.size / 2
	rect := sdl.FRect{pos.x - half, pos.y - half, body.size, body.size}
	return sdl.RenderFillRect(r, &rect)
}

@(private = "file")
draw_centered_text :: proc(r: ^sdl.Renderer, y: f32, text: cstring) -> bool {
	width := f32(len(text) * sdl.DEBUG_TEXT_FONT_CHARACTER_SIZE)
	return sdl.RenderDebugText(r, (game.WORLD_WIDTH - width) / 2, y, text)
}

// Draws `text` in a baked pixel font, horizontally centered, with its top at `y`.
@(private = "file")
draw_centered :: proc(f: ^Baked_Font, r: ^sdl.Renderer, y: f32, text: string, scale: f32 = 1) -> bool {
	// Whole world units, so every font pixel lands on the same screen-pixel grid.
	x := f32(int(game.WORLD_WIDTH - f32(baked_font_width(f, text)) * scale) / 2)
	return baked_font_draw(f, r, {x, y}, text, scale)
}

// Draws the measured frame rate in the top-right corner, in world units.
@(private = "file")
draw_fps :: proc(r: ^sdl.Renderer, fps: f32) -> bool {
	text := fmt.ctprintf("%.0f FPS", fps)
	width := f32(len(text) * sdl.DEBUG_TEXT_FONT_CHARACTER_SIZE)
	sdl.SetRenderDrawColor(r, 230, 230, 230, 255) or_return
	return sdl.RenderDebugText(r, game.WORLD_WIDTH - width - 4, 4, text)
}

// Saves the frame drawn so far (before present) as a BMP, for tests and docs.
// Failure is logged, not fatal.
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
