# Assets

The app resolves this directory relative to the executable (`<exe dir>/assets`),
never the working directory. `scripts/build.*` and `scripts/package.*` copy it
next to the built executable. Override during development with
`--assets=<dir>`.

The baseline starter loads only `backgrounds/blue-nebula.bmp` (BMP, so core
SDL can read it without SDL_image). It is optional: if the file is missing the
game logs a warning and draws the plain clear color. The fonts and `images/`
are used by the optional examples (`examples/images`, `examples/text`); delete
them along with the examples.

## Provenance and licenses

Record every file you add here: source URL, author, license, and any
modifications. Ship the license texts with the packaged game.

| File | Source | Author | License |
| --- | --- | --- | --- |
| `fonts/PressStart2P-Regular.ttf` | [google/fonts](https://github.com/google/fonts/tree/e06fe11c39051bddaef73ec338a9d1c8175723f1/ofl/pressstart2p) `ofl/pressstart2p`, commit `e06fe11`, unmodified (SHA-256 `034c77f1…017d`) | The Press Start 2P Project Authors (CodeMan38) | SIL OFL 1.1, text in `fonts/OFL.txt` |
| `fonts/OFL.txt` | same commit | — | License text for the font |
| `backgrounds/blue-nebula.bmp` | [Seamless Space Backgrounds](https://opengameart.org/content/seamless-space-backgrounds), small 512×512 pack (`sbs_-_seamless_space_backgrounds_-_small_512x512_0.zip`, SHA-256 `401a73e2…59e0ab`), file `Blue Nebula 4 - 512x512.png` (SHA-256 `006cc7c8…9bce21`). Cropped to the vertically centered 512×288 band (16:9) and converted to 24-bit BMP. Dimmed at runtime (`BACKGROUND_DIM` in `src/background.odin`) | Screaming Brain Studios | CC0 1.0 (public domain); no credit required |
| `images/slime.png` | Drawn for this project (16×16 RGBA) | Odin SDL3 Starter Kit contributors | MIT, same as the project |

`scripts/package.*` copies `fonts/OFL.txt` to `licenses/` when it packages the
text example.
