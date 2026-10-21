# Odin SDL3 Starter Kit

A small, reusable game starter in [Odin](https://odin-lang.org) using
[SDL3](https://wiki.libsdl.org/SDL3/FrontPage)'s application callback
architecture: SDL owns the main loop, the app supplies init / event / iterate /
quit callbacks. It has a fixed-step simulation, an SDL-independent game
package, unit tests, headless lifecycle tests, and locked, reproducible native
dependencies.

## Quick start (Linux / macOS)

```sh
scripts/bootstrap.sh --with-odin   # locked Odin + SDL3 into third_party/
                                   #   add --with-image, --with-text or --all-features for the examples
scripts/build.sh debug             # build/starter-debug
build/starter-debug                # Enter: play, P: pause, arrows/WASD: move, Esc: quit
scripts/test.sh                    # unit + headless lifecycle tests
scripts/package.sh                 # relocatable dist/<os>-<arch>/
```

Omit `--with-odin` if `odin` on your `PATH` (or `$ODIN`) is already the locked
commit; the scripts check.

## Quick start (Windows)

From a Visual Studio **developer PowerShell 7** prompt:

```powershell
scripts/bootstrap.ps1              # -WithImage, -WithText or -AllFeatures for the examples
scripts/build.ps1 debug
build/starter-debug.exe
scripts/test.ps1
scripts/package.ps1
```

## Layout

| Path | Contents |
| --- | --- |
| `src/` | Executable: startup adapter, SDL callbacks, app lifecycle, input mapping, rendering, config |
| `game/` | SDL-independent simulation: input transitions, fixed timestep, state machine, example game |
| `examples/images/` | Optional: PNG loading with SDL3_image ([below](#optional-examples)) |
| `examples/text/` | Optional: TrueType text with SDL3_ttf |
| `assets/` | Example font and sprite, with [provenance and licenses](assets/README.md) |
| `tests/integration/` | Runs the real executable headlessly through success, quit and failure paths |
| `scripts/` | Bootstrap, build, test, package and dependency-update scripts (`.sh` and `.ps1`) |
| `deps.lock.json` | Exact Odin, SDL3 and optional-library versions, commits, checksums and build options |
| `docs/` | [Architecture](docs/architecture.md), [dependencies](docs/dependencies.md), [testing](docs/testing.md) |

## The example game

A small paddle-and-ball toy that exercises input, fixed-step simulation,
rendering and sound:

| Key | Action |
| --- | --- |
| Enter / Space | Start a round (from the menu), or resume |
| Arrows / WASD | Move the paddle left, right, up and down |
| P | Pause / resume |
| F1 | Show / hide the tuning panel |
| Esc | Quit (as does closing the window) |

- The ball bounces off the edges of the screen with an 880 Hz beep.
- It also bounces off the paddle, with a higher 1760 Hz beep. Each paddle hit
  makes the ball 10 % faster, up to 240 units/s (from 90 at the start of a
  round).
- The play field is 320×180 world units, letterboxed and scaled to the window.
- The **tuning panel** (F1, or start with `--tuning`) has sliders for the
  ball's launch speed, the ball size and the paddle size. Changes apply
  immediately and carry over to new rounds. It is drawn with Odin's built-in
  [`vendor:microui`](https://pkg.odin-lang.org/vendor/microui/), so it adds no
  native dependency; see `src/ui.odin`.
- Sound is optional. If no audio device opens, the game runs silently;
  `--mute` turns it off.

The rules live in `game/game.odin` (no SDL), the beeps in `src/audio.odin`.
See [architecture](docs/architecture.md#sound-srcaudioodin) for how the two
are connected.

## Starting a game

Replace `game/game.odin` (and its tests) with your own simulation. Keep it free
of SDL: feed it `Step_Input` and a fixed `dt`, render from its state in
`src/render.odin`, and add key bindings in `src/input.odin`. To trigger sounds,
expose counters or events from the game and play them in `app_iterate`, as the
bounce counters do; delete `src/audio.odin` if you don't need sound.

## Optional examples

Two independent executables show the optional libraries. Each is a single
self-contained file with its own copy of the startup adapter, so you can copy
one into your game or delete it without touching `src/`. The baseline starter
never links SDL3_image or SDL3_ttf; `scripts/test.*` checks this.

| Example | Needs | Build | Shows |
| --- | --- | --- | --- |
| `examples/images` | `bootstrap --with-image` | `scripts/build.sh debug images` | `IMG_LoadTexture`, pixel-art scaling, rotation |
| `examples/text` | `bootstrap --with-text` | `scripts/build.sh debug text` | `TTF_OpenFont`, the renderer text engine, updating text each frame |

Both accept `--frames=N`, `--assets=DIR` and `--screenshot=FILE.bmp`. The last
one saves the final frame of a `--frames` run. SDL3_image is built with only
BMP, JPEG, PNG and QOI support. SDL3_ttf is built with FreeType but without
HarfBuzz, so complex scripts are not shaped. See
[dependencies](docs/dependencies.md#optional-libraries).

## Command-line options

| Option | Effect |
| --- | --- |
| `--seed=N` | Seed for the deterministic simulation |
| `--sim-hz=N` | Fixed simulation rate (default 60) |
| `--no-vsync` | Disable vsync; SDL then paces callbacks at 120 Hz |
| `--assets=DIR` | Override the asset directory (default: `assets` next to the executable) |
| `--frames=N` | Exit successfully after N iterations (smoke tests) |
| `--push-quit-at=N` | Push a quit event on iteration N (tests) |
| `--mute` | Don't open an audio device (no bounce beep) |
| `--tuning` | Show the tuning panel at startup |
| `--screenshot=FILE.bmp` | With `--frames`, save the last frame (tests, docs) |
| `--fail-after=STAGE` | Fail init after `metadata`, `video`, `window`, `renderer`, `audio`, `ui` or `game` (tests) |

## License

MIT; see [LICENSE](LICENSE). SDL3, SDL3_image and SDL3_ttf are under the zlib
license, FreeType under the FreeType License, and the example font under the
SIL OFL 1.1. Their license texts are shipped in `dist/*/licenses/`.
