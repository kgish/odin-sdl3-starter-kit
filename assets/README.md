# Assets

The app resolves this directory relative to the executable (`<exe dir>/assets`),
never the working directory. `scripts/build.*` and `scripts/package.*` copy it
next to the built executable. Override during development with
`--assets=<dir>`.

The baseline starter loads only `backgrounds/blue-nebula.bmp` (BMP, so core
SDL can read it without SDL_image). It is optional: if the file is missing the
game logs a warning and draws the plain clear color. The score is drawn in
Jersey 10 and the menu and tuning panel in Silkscreen, but the starter reads neither `.ttf` at
run time: `scripts/bake-fonts.sh` bakes their glyphs into `src/score_font.odin`
and `src/menu_font.odin`. Press Start 2P and `images/` are used by the
optional examples (`examples/images`, `examples/text`); delete them along with
the examples.

## Provenance and licenses

Record every file you add here: source URL, author, license, and any
modifications. Ship the license texts with the packaged game.

| File | Source | Author | License |
| --- | --- | --- | --- |
| `fonts/PressStart2P-Regular.ttf` | [google/fonts](https://github.com/google/fonts/tree/e06fe11c39051bddaef73ec338a9d1c8175723f1/ofl/pressstart2p) `ofl/pressstart2p`, commit `e06fe11`, unmodified (SHA-256 `034c77f1…017d`) | The Press Start 2P Project Authors (CodeMan38) | SIL OFL 1.1, text in `fonts/OFL.txt` |
| `fonts/OFL.txt` | same commit | — | License text for the font |
| `fonts/Jersey10-Regular.ttf` | [google/fonts](https://github.com/google/fonts/tree/45e3d5269e4a17d823f6d84470bc084dc5ae46f6/ofl/jersey10) `ofl/jersey10`, commit `45e3d52`, unmodified (SHA-256 `db9cbd09…3e82`); upstream [scfried/soft-type-jersey](https://github.com/scfried/soft-type-jersey) commit `d8446c4`. Glyphs `SCORE 0-9` baked into `src/score_font.odin` | The Soft Type Project Authors (Sarah Cadigan-Fried) | SIL OFL 1.1, text in `fonts/Jersey10-OFL.txt` |
| `fonts/Jersey10-OFL.txt` | same commit (`OFL.txt`, SHA-256 `436d5836…f2f4`) | — | License text for Jersey 10 |
| `fonts/Silkscreen-Regular.ttf` | [google/fonts](https://github.com/google/fonts/tree/45e3d5269e4a17d823f6d84470bc084dc5ae46f6/ofl/silkscreen) `ofl/silkscreen`, commit `45e3d52`, unmodified (SHA-256 `c8454733…ebd8`); upstream [googlefonts/silkscreen](https://github.com/googlefonts/silkscreen) commit `206ccf3`. Printable ASCII except the backtick baked into `src/menu_font.odin` | The Silkscreen Project Authors (Jason Kottke) | SIL OFL 1.1, text in `fonts/Silkscreen-OFL.txt` |
| `fonts/Silkscreen-OFL.txt` | same commit (`OFL.txt`, SHA-256 `86c5e9c9…fbd3`) | — | License text for Silkscreen |
| `backgrounds/blue-nebula.bmp` | [Seamless Space Backgrounds](https://opengameart.org/content/seamless-space-backgrounds), small 512×512 pack (`sbs_-_seamless_space_backgrounds_-_small_512x512_0.zip`, SHA-256 `401a73e2…59e0ab`), file `Blue Nebula 4 - 512x512.png` (SHA-256 `006cc7c8…9bce21`). Cropped to the vertically centered 512×288 band (16:9) and converted to 24-bit BMP. Brightness adjustable at runtime (`BACKGROUND_BRIGHTNESS` in `src/background.odin`, default 100 %, and the tuning panel) | Screaming Brain Studios | CC0 1.0 (public domain); no credit required |
| `images/slime.png` | Drawn for this project (16×16 RGBA) | Odin SDL3 Starter Kit contributors | MIT, same as the project |

`scripts/package.*` always copies `fonts/Jersey10-OFL.txt` and
`fonts/Silkscreen-OFL.txt` to `licenses/` (the starter embeds their glyphs), and copies `fonts/OFL.txt` when it packages the
text example.
