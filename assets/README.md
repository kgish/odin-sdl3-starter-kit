# Assets

The app resolves this directory relative to the executable (`<exe dir>/assets`),
never the working directory. `scripts/build.*` and `scripts/package.*` copy it
next to the built executable. Override during development with
`--assets=<dir>`.

The baseline starter draws only rectangles and SDL's built-in debug text and
needs no asset files. The files below are used by the optional examples
(`examples/images`, `examples/text`); delete them along with the examples.

## Provenance and licenses

Record every file you add here: source URL, author, license, and any
modifications. Ship the license texts with the packaged game.

| File | Source | Author | License |
| --- | --- | --- | --- |
| `fonts/PressStart2P-Regular.ttf` | [google/fonts](https://github.com/google/fonts/tree/e06fe11c39051bddaef73ec338a9d1c8175723f1/ofl/pressstart2p) `ofl/pressstart2p`, commit `e06fe11`, unmodified (SHA-256 `034c77f1…017d`) | The Press Start 2P Project Authors (CodeMan38) | SIL OFL 1.1, text in `fonts/OFL.txt` |
| `fonts/OFL.txt` | same commit | — | License text for the font |
| `images/slime.png` | Drawn for this project (16×16 RGBA) | Odin SDL3 Starter Kit contributors | MIT, same as the project |

`scripts/package.*` copies `fonts/OFL.txt` to `licenses/` when it packages the
text example.
