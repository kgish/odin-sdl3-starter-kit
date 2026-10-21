package main

import "core:fmt"
import "core:log"
import "../game"
import mu "vendor:microui"
import sdl "vendor:sdl3"

UI_TOGGLE_KEY :: sdl.Scancode.F1

// Debug UI drawn with vendor:microui. The microui context lives inside
// App_State (it is large, and App_State is heap allocated). `atlas` holds
// microui's built-in font and icons; it is created in ui_init and destroyed
// only in ui_destroy, before the renderer.
Ui :: struct {
	ctx:     mu.Context,
	atlas:   ^sdl.Texture,
	visible: bool,
	// FPS overlay, toggled from the panel. `fps` is the rate measured over the
	// last FPS_WINDOW_NS; it keeps updating while the panel is hidden.
	show_fps:     bool,
	fps:          f32,
	fps_frames:   int,
	fps_start_ns: u64,
}

FPS_WINDOW_NS :: 500_000_000

ui_init :: proc(ui: ^Ui, renderer: ^sdl.Renderer) -> bool {
	mu.init(&ui.ctx)
	ui.ctx.text_width = mu.default_atlas_text_width
	ui.ctx.text_height = mu.default_atlas_text_height

	// The atlas is an alpha mask; expand it to white RGBA so color mod tints it.
	W :: mu.DEFAULT_ATLAS_WIDTH
	H :: mu.DEFAULT_ATLAS_HEIGHT
	pixels := make([][4]u8, W * H, context.temp_allocator)
	for alpha, i in mu.default_atlas_alpha {
		pixels[i] = {255, 255, 255, alpha}
	}
	ui.atlas = sdl.CreateTexture(renderer, .RGBA32, .STATIC, W, H)
	if ui.atlas == nil {
		log.errorf("CreateTexture (ui atlas) failed: %s", sdl.GetError())
		return false
	}
	log.debug("created ui atlas")
	if !sdl.UpdateTexture(ui.atlas, nil, raw_data(pixels), W * 4) {
		log.errorf("UpdateTexture (ui atlas) failed: %s", sdl.GetError())
		return false
	}
	sdl.SetTextureBlendMode(ui.atlas, {.BLEND})
	sdl.SetTextureScaleMode(ui.atlas, .NEAREST)
	return true
}

ui_destroy :: proc(ui: ^Ui) {
	if ui.atlas != nil {
		sdl.DestroyTexture(ui.atlas)
		ui.atlas = nil
		log.debug("destroyed ui atlas")
	}
}

ui_set_visible :: proc(ui: ^Ui, visible: bool) {
	ui.visible = visible
	log.infof("tuning panel %s (F1)", "shown" if visible else "hidden")
}

// Counts one rendered frame at `now_ns` (monotonic) and refreshes `fps` once
// per FPS_WINDOW_NS.
ui_count_frame :: proc(ui: ^Ui, now_ns: u64) {
	if ui.fps_start_ns == 0 {
		ui.fps_start_ns = now_ns
	}
	ui.fps_frames += 1
	if elapsed := now_ns - ui.fps_start_ns; elapsed >= FPS_WINDOW_NS {
		ui.fps = f32(ui.fps_frames) * 1e9 / f32(elapsed)
		ui.fps_frames = 0
		ui.fps_start_ns = now_ns
	}
}

// Forwards mouse input to microui while the panel is visible. Coordinates are
// window coordinates, which is also the space the panel is drawn in.
ui_handle_event :: proc(ui: ^Ui, event: ^sdl.Event) {
	if !ui.visible {
		return
	}
	#partial switch event.type {
	case .MOUSE_MOTION:
		mu.input_mouse_move(&ui.ctx, i32(event.motion.x), i32(event.motion.y))
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		b := event.button
		btn: mu.Mouse
		switch b.button {
		case sdl.BUTTON_LEFT:   btn = .LEFT
		case sdl.BUTTON_RIGHT:  btn = .RIGHT
		case sdl.BUTTON_MIDDLE: btn = .MIDDLE
		case: return
		}
		if b.down {
			mu.input_mouse_down(&ui.ctx, i32(b.x), i32(b.y), btn)
		} else {
			mu.input_mouse_up(&ui.ctx, i32(b.x), i32(b.y), btn)
		}
	case .MOUSE_WHEEL:
		mu.input_scroll(&ui.ctx, 0, i32(-event.wheel.y * 30))
	}
}

// Builds the tuning panel for this frame. Edits are applied to the game at
// once, between simulation steps.
ui_update :: proc(ui: ^Ui, g: ^game.Game) {
	if !ui.visible {
		return
	}
	ctx := &ui.ctx
	mu.begin(ctx)
	defer mu.end(ctx)

	if !mu.begin_window(ctx, "Tuning", {16, 16, 280, 196}, {.NO_CLOSE}) {
		return
	}
	defer mu.end_window(ctx)

	t := g.tuning
	changed := false
	mu.layout_row(ctx, {100, -1})
	mu.label(ctx, "Ball speed")
	if .CHANGE in mu.slider(ctx, &t.ball_speed, game.BALL_MIN_SPEED, game.BALL_MAX_SPEED, 1, "%.0f") do changed = true
	mu.label(ctx, "Ball size")
	if .CHANGE in mu.slider(ctx, &t.ball_size, game.BALL_SIZE_MIN, game.BALL_SIZE_MAX, 1, "%.0f") do changed = true
	mu.label(ctx, "Paddle size")
	if .CHANGE in mu.slider(ctx, &t.player_size, game.PLAYER_SIZE_MIN, game.PLAYER_SIZE_MAX, 1, "%.0f") do changed = true

	mu.label(ctx, "Current speed")
	mu.label(ctx, fmt.tprintf("%.0f (x%.2f per paddle hit)", game.game_ball_speed(g^), game.BALL_SPEEDUP))
	mu.layout_row(ctx, {-1})
	mu.checkbox(ctx, "Show FPS", &ui.show_fps)
	mu.layout_row(ctx, {100, -1})
	if .SUBMIT in mu.button(ctx, "Defaults") {
		t = game.TUNING_DEFAULT
		changed = true
	}
	mu.label(ctx, "F1: hide panel")

	if changed {
		game.game_set_tuning(g, t)
	}
}

// Draws the panel built by ui_update on top of the game, at window resolution.
ui_draw :: proc(ui: ^Ui, r: ^sdl.Renderer, window: ^sdl.Window) -> bool {
	if !ui.visible {
		return true
	}
	// Toggling logical presentation mid-frame is supported by SDL. Scaling by
	// the pixel density makes UI coordinates equal window (mouse) coordinates.
	lw, lh: i32
	mode: sdl.RendererLogicalPresentation
	sdl.GetRenderLogicalPresentation(r, &lw, &lh, &mode) or_return
	sdl.SetRenderLogicalPresentation(r, 0, 0, .DISABLED) or_return
	density := sdl.GetWindowPixelDensity(window)
	if density <= 0 do density = 1
	sdl.SetRenderScale(r, density, density) or_return
	sdl.SetRenderDrawBlendMode(r, {.BLEND}) or_return

	cmd: ^mu.Command
	for variant in mu.next_command_iterator(&ui.ctx, &cmd) {
		switch c in variant {
		case ^mu.Command_Rect:
			sdl.SetRenderDrawColor(r, c.color.r, c.color.g, c.color.b, c.color.a) or_return
			rect := sdl.FRect{f32(c.rect.x), f32(c.rect.y), f32(c.rect.w), f32(c.rect.h)}
			sdl.RenderFillRect(r, &rect) or_return
		case ^mu.Command_Text:
			pos := [2]f32{f32(c.pos.x), f32(c.pos.y)}
			for ch in c.str {
				if ch & 0xc0 == 0x80 do continue // UTF-8 continuation byte
				src := mu.default_atlas[mu.DEFAULT_ATLAS_FONT + min(int(ch), 127)]
				draw_atlas(ui.atlas, r, src, pos, c.color) or_return
				pos.x += f32(src.w)
			}
		case ^mu.Command_Icon:
			src := mu.default_atlas[c.id]
			pos := [2]f32{f32(c.rect.x + (c.rect.w - src.w) / 2), f32(c.rect.y + (c.rect.h - src.h) / 2)}
			draw_atlas(ui.atlas, r, src, pos, c.color) or_return
		case ^mu.Command_Clip:
			clip := sdl.Rect{c.rect.x, c.rect.y, c.rect.w, c.rect.h}
			sdl.SetRenderClipRect(r, &clip) or_return
		case ^mu.Command_Jump:
			unreachable() // consumed by the iterator
		}
	}

	sdl.SetRenderClipRect(r, nil) or_return
	sdl.SetRenderScale(r, 1, 1) or_return
	return sdl.SetRenderLogicalPresentation(r, lw, lh, mode)
}

@(private = "file")
draw_atlas :: proc(atlas: ^sdl.Texture, r: ^sdl.Renderer, src: mu.Rect, pos: [2]f32, color: mu.Color) -> bool {
	sdl.SetTextureColorMod(atlas, color.r, color.g, color.b) or_return
	sdl.SetTextureAlphaMod(atlas, color.a) or_return
	s := sdl.FRect{f32(src.x), f32(src.y), f32(src.w), f32(src.h)}
	d := sdl.FRect{pos.x, pos.y, f32(src.w), f32(src.h)}
	return sdl.RenderTexture(r, atlas, &s, &d)
}
