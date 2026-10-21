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

	sdl.SetRenderDrawColor(r, 90, 200, 140, 255) or_return
	draw_body(r, g.player, alpha) or_return
	sdl.SetRenderDrawColor(r, 240, 190, 80, 255) or_return
	draw_body(r, g.ball, alpha) or_return

	sdl.SetRenderDrawColor(r, 230, 230, 230, 255) or_return
	switch g.state {
	case .Menu:
		draw_centered_text(r, game.WORLD_HEIGHT / 2 - 12, "ODIN + SDL3 STARTER") or_return
		draw_centered_text(r, game.WORLD_HEIGHT / 2 + 4, "ENTER: PLAY  ESC: QUIT") or_return
	case .Paused:
		draw_centered_text(r, game.WORLD_HEIGHT / 2 - 4, "PAUSED (P)") or_return
		draw_centered_text(r, 4, fmt.ctprintf("SCORE %d", g.score)) or_return
	case .Playing:
		draw_centered_text(r, 4, fmt.ctprintf("SCORE %d", g.score)) or_return
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
