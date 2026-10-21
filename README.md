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
scripts/bootstrap.ps1
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
| `tests/integration/` | Runs the real executable headlessly through success, quit and failure paths |
| `scripts/` | Bootstrap, build, test, package and dependency-update scripts (`.sh` and `.ps1`) |
| `deps.lock.json` | Exact Odin and SDL3 versions, commits, checksums and build options |
| `docs/` | [Architecture](docs/architecture.md), [dependencies](docs/dependencies.md), [testing](docs/testing.md) |

## Starting a game

Replace `game/game.odin` (and its tests) with your own simulation. Keep it free
of SDL: feed it `Step_Input` and a fixed `dt`, render from its state in
`src/render.odin`, and add key bindings in `src/input.odin`.

## Command-line options

| Option | Effect |
| --- | --- |
| `--seed=N` | Seed for the deterministic simulation |
| `--sim-hz=N` | Fixed simulation rate (default 60) |
| `--no-vsync` | Disable vsync; SDL then paces callbacks at 120 Hz |
| `--assets=DIR` | Override the asset directory (default: `assets` next to the executable) |
| `--frames=N` | Exit successfully after N iterations (smoke tests) |
| `--push-quit-at=N` | Push a quit event on iteration N (tests) |
| `--fail-after=STAGE` | Fail init after `metadata`, `video`, `window`, `renderer` or `game` (tests) |

## License

MIT; see [LICENSE](LICENSE). SDL3 is under the zlib license; its license text is
shipped in `dist/*/licenses/`.
