package main

import "core:log"
import sdl "vendor:sdl3"

// One baked glyph: its left edge `x` in the atlas, and rows of '#' (ink) and
// '.' (empty), `advance` pixels wide.
Baked_Glyph :: struct {
	char:    rune,
	x:       i32,
	advance: i32,
	rows:    []string,
}

// A pixel font drawn from glyphs baked into src/*_font.odin by
// tools/bake-font, so the baseline needs neither SDL_ttf nor a font file at
// runtime. `atlas` holds the glyphs side by side; it is created in
// baked_font_init and destroyed only in baked_font_destroy, before the renderer.
Baked_Font :: struct {
	name:   string, // for diagnostics, e.g. "score"
	glyphs: []Baked_Glyph,
	height: i32,
	atlas:  ^sdl.Texture,
}

baked_font_init :: proc(f: ^Baked_Font, renderer: ^sdl.Renderer, name: string, glyphs: []Baked_Glyph) -> bool {
	f.name = name
	f.glyphs = glyphs
	f.height = i32(len(glyphs[0].rows))
	last := glyphs[len(glyphs) - 1]
	w, h := last.x + last.advance, f.height

	// White ink on transparent, so color mod tints it.
	pixels := make([][4]u8, int(w * h), context.temp_allocator)
	for g in glyphs {
		assert(i32(len(g.rows)) == h)
		for row, y in g.rows {
			assert(i32(len(row)) == g.advance)
			for c, x in transmute([]u8)row {
				if c == '#' do pixels[y * int(w) + int(g.x) + x] = {255, 255, 255, 255}
			}
		}
	}
	f.atlas = sdl.CreateTexture(renderer, .RGBA32, .STATIC, w, h)
	if f.atlas == nil {
		log.errorf("CreateTexture (%s atlas) failed: %s", name, sdl.GetError())
		return false
	}
	log.debugf("created %s atlas", name)
	if !sdl.UpdateTexture(f.atlas, nil, raw_data(pixels), w * 4) {
		log.errorf("UpdateTexture (%s atlas) failed: %s", name, sdl.GetError())
		return false
	}
	sdl.SetTextureBlendMode(f.atlas, {.BLEND})
	// Nearest keeps the pixel font sharp when it is scaled up.
	sdl.SetTextureScaleMode(f.atlas, .NEAREST)
	return true
}

baked_font_destroy :: proc(f: ^Baked_Font) {
	if f.atlas != nil {
		sdl.DestroyTexture(f.atlas)
		f.atlas = nil
		log.debugf("destroyed %s atlas", f.name)
	}
}

// Width of `text` in font pixels (multiply by the draw scale for world units).
baked_font_width :: proc(f: ^Baked_Font, text: string) -> i32 {
	w: i32
	for ch in text {
		w += baked_glyph(f, ch).advance
	}
	return w
}

// Draws `text` with its top-left corner at `pos`, each font pixel `scale`
// world units wide, tinted with the current draw color.
baked_font_draw :: proc(f: ^Baked_Font, r: ^sdl.Renderer, pos: [2]f32, text: string, scale: f32 = 1) -> bool {
	cr, cg, cb, ca: u8
	sdl.GetRenderDrawColor(r, &cr, &cg, &cb, &ca) or_return
	sdl.SetTextureColorMod(f.atlas, cr, cg, cb) or_return
	sdl.SetTextureAlphaMod(f.atlas, ca) or_return

	x := pos.x
	for ch in text {
		g := baked_glyph(f, ch)
		adv := f32(g.advance)
		src := sdl.FRect{f32(g.x), 0, adv, f32(f.height)}
		dst := sdl.FRect{x, pos.y, adv * scale, f32(f.height) * scale}
		sdl.RenderTexture(r, f.atlas, &src, &dst) or_return
		x += adv * scale
	}
	return true
}

// Text drawn with a baked font is a program constant or built from a fixed
// character set, so a missing glyph is a bug: rebake with that character.
@(private = "file")
baked_glyph :: proc(f: ^Baked_Font, ch: rune) -> Baked_Glyph {
	for g in f.glyphs {
		if g.char == ch do return g
	}
	log.panicf("%q is not baked into the %s font; add it in scripts/bake-fonts.sh", ch, f.name)
}
