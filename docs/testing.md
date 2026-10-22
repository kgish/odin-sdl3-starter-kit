# Testing

`scripts/test.sh` (or `test.ps1`) runs everything below.

## Unit tests

```sh
odin test game          # SDL-independent simulation
odin test src ...       # pure procedures in the executable package (needs SDL link flags; use the script)
```

| Area | Covered |
| --- | --- |
| Input | press/held/release transitions, key repeat, taps between steps, no repeat across catch-up steps, focus-loss reset |
| Timestep | baseline, partial accumulation, 250 ms clamp, update limit and dropped-step accounting, pause/resume reset, non-monotonic time |
| Game | state-machine transitions, determinism for a seed, paused game does not advance, bodies stay in bounds, interpolation, wall and paddle hits, speed-up and its cap, tuning clamping and persistence |
| Config | defaults valid, option parsing, unknown/bad/out-of-range options, asset dir relative to the executable, override |

The simulation is deterministic: time, input and the RNG seed are passed in
explicitly.

## Lifecycle integration tests

`tests/integration` is a separate executable. It launches the real starter,
using the real startup adapter and callbacks, as a child process per case. The
child runs with `SDL_VIDEO_DRIVER=dummy`, `SDL_RENDER_DRIVER=software`,
`SDL_AUDIO_DRIVER=dummy`, uses the log directory as its working directory, and
has a 30 s timeout. Running in a child process means SDL's main-thread rules
hold, which `odin test` worker threads would not guarantee.

| Case | Expectation |
| --- | --- |
| `smoke` | 60 iterations, exit 0, renderer and window each destroyed exactly once |
| `smoke-no-vsync` | Fallback pacing path |
| `smoke-mute` | `--mute`: no audio stream is opened or destroyed |
| `smoke-tuning` | Tuning panel drawn every frame; `--screenshot` saves the last one |
| `quit-event` | A pushed `SDL_EVENT_QUIT` ends the app with exit 0 |
| `missing-assets` | Clear diagnostic (asset directory, background and sprites not found), still runs with the plain clear color and plain squares |
| `bad-option` | Exit 1, nothing created |
| `fail-after-<stage>` | Exit 1, only resources created before the failure are destroyed, each once |

Every case also checks that `app_quit` ran once. Debug builds also fail the
case if Odin's tracking allocator reports a leak or bad free; the app exits
with code 3 when that happens.

Logs are kept in `build/integration-logs/<app>-<debug|release>/<case>.log`.

## Optional examples

`test.*` also runs a suite (`--suite=images` or `--suite=text`) against each
example whose feature is installed, in debug and release. Examples whose
feature is missing are skipped with a hint. `--require-features` /
`-RequireFeatures` turns a skip into a failure; CI uses it.

| Case | Expectation |
| --- | --- |
| `smoke` | 30 frames, exit 0. The image or font loads, and every owned resource (texture, or text engine and font, then renderer and window) is destroyed exactly once |
| `screenshot` | `--screenshot=FILE.bmp` saves the final frame |
| `missing-assets` | Exit 1 with a "failed to load" diagnostic. The renderer and window are still cleaned up; nothing that was never created is destroyed |
| `bad-option` | Exit 1, nothing created |

The screenshots (`build/integration-logs/<app>-<mode>/<app>.bmp`) are rendered
by the software renderer and kept for inspection; they are not compared
against reference images.

## Feature isolation

After building the baseline starter, `test.*` checks its dynamic dependencies
(`ldd`, `otool -L` or `dumpbin /dependents`) and fails if it links SDL3_image
or SDL3_ttf. Bootstrap separately checks that each optional library links none
of the codec or shaping libraries the lock excludes (`must_not_link`).

Dummy drivers prove lifecycle behaviour only. They prove nothing about
hardware acceleration, visible output, or real devices.

## Manual desktop checklist

Run `build/starter-debug` on each OS. On Linux, run it under both X11
(`SDL_VIDEO_DRIVER=x11`) and Wayland (`SDL_VIDEO_DRIVER=wayland`). Check each
of these:

- resize, and moving between monitors with different scale (letterboxed and sharp)
- minimize/restore: no burst of movement after restore
- holding an arrow key and alt-tabbing away: the player does not keep moving
- `--no-vsync`: logs the fallback rate, motion stays smooth
- Enter, P and Esc work; the window close button exits with code 0

## Native memory

Odin's tracking allocator does not see allocations made by SDL. When
investigating native leaks or corruption, use Valgrind or ASan on Linux,
Instruments on macOS, or Application Verifier on Windows.
