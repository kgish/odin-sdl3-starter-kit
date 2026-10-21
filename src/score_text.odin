package main

import "core:log"
import sdl "vendor:sdl3"

// One baked glyph: rows of '#' (ink) and '.' (empty), `advance` pixels wide.
Score_Glyph :: struct {
	char:    rune,
	advance: i32,
	rows:    [SCORE_FONT_HEIGHT]string,
}

// Score display in Jersey 10, drawn from the glyphs baked into score_font.odin,
// so the baseline needs neither SDL_ttf nor a font file at runtime. `atlas`
// holds the glyphs side by side; it is created in score_text_init and
// destroyed only in score_text_destroy, before the renderer.
Score_Text :: struct {
	atlas: ^sdl.Texture,
	x:     [len(SCORE_FONT_GLYPHS)]i32, // each glyph's left edge in the atlas
}

score_text_init :: proc(st: ^Score_Text, renderer: ^sdl.Renderer) -> bool {
	w: i32
	for g, i in SCORE_FONT_GLYPHS {
		st.x[i] = w
		w += g.advance
	}
	H :: SCORE_FONT_HEIGHT

	// White ink on transparent, so color mod tints it.
	pixels := make([][4]u8, int(w) * H, context.temp_allocator)
	for g, i in SCORE_FONT_GLYPHS {
		for row, y in g.rows {
			assert(i32(len(row)) == g.advance)
			for c, x in transmute([]u8)row {
				if c == '#' do pixels[y * int(w) + int(st.x[i]) + x] = {255, 255, 255, 255}
			}
		}
	}
	st.atlas = sdl.CreateTexture(renderer, .RGBA32, .STATIC, w, H)
	if st.atlas == nil {
		log.errorf("CreateTexture (score atlas) failed: %s", sdl.GetError())
		return false
	}
	log.debug("created score atlas")
	if !sdl.UpdateTexture(st.atlas, nil, raw_data(pixels), w * 4) {
		log.errorf("UpdateTexture (score atlas) failed: %s", sdl.GetError())
		return false
	}
	sdl.SetTextureBlendMode(st.atlas, {.BLEND})
	// Nearest keeps the pixel font sharp when logical presentation scales it up.
	sdl.SetTextureScaleMode(st.atlas, .NEAREST)
	return true
}

score_text_destroy :: proc(st: ^Score_Text) {
	if st.atlas != nil {
		sdl.DestroyTexture(st.atlas)
		st.atlas = nil
		log.debug("destroyed score atlas")
	}
}

// Width of `text` in pixels. Characters that were not baked count as nothing.
score_text_width :: proc(text: string) -> f32 {
	w: i32
	for ch in text {
		if i := score_glyph_index(ch); i >= 0 do w += SCORE_FONT_GLYPHS[i].advance
	}
	return f32(w)
}

// Draws `text` with its top-left corner at `pos`, tinted with the current
// draw color. Characters that were not baked are skipped.
score_text_draw :: proc(st: ^Score_Text, r: ^sdl.Renderer, pos: [2]f32, text: string) -> bool {
	cr, cg, cb, ca: u8
	sdl.GetRenderDrawColor(r, &cr, &cg, &cb, &ca) or_return
	sdl.SetTextureColorMod(st.atlas, cr, cg, cb) or_return
	sdl.SetTextureAlphaMod(st.atlas, ca) or_return

	x := pos.x
	for ch in text {
		i := score_glyph_index(ch)
		if i < 0 do continue
		adv := f32(SCORE_FONT_GLYPHS[i].advance)
		src := sdl.FRect{f32(st.x[i]), 0, adv, SCORE_FONT_HEIGHT}
		dst := sdl.FRect{x, pos.y, adv, SCORE_FONT_HEIGHT}
		sdl.RenderTexture(r, st.atlas, &src, &dst) or_return
		x += adv
	}
	return true
}

@(private = "file")
score_glyph_index :: proc(ch: rune) -> int {
	for g, i in SCORE_FONT_GLYPHS {
		if g.char == ch do return i
	}
	return -1
}
