# Architecture

## Startup adapter (`src/main.odin`)

Odin does not process C macros, so `SDL_MAIN_USE_CALLBACKS` + `SDL_main.h`
cannot be used directly. The adapter reproduces what that header generates in
the locked SDL release (`include/SDL3/SDL_main_impl.h`) for desktop platforms:

```text
Odin entry point (runtime initialized)
  main -> run
    set logger / debug tracking allocator, store g_context
    SDL_RunApp(argc, argv, sdl_main)          Windows: (0, NULL) like SDL's WinMain shim
      sdl_main -> SDL_EnterAppMainCallbacks(app_init_c, app_iterate_c, app_event_c, app_quit_c)
  report leaks (debug), exit with SDL's status
```

There is exactly one executable entry point (Odin's) and no C bridge. The
Odin runtime is initialized before SDL can call back.

## Callback boundary (`src/callbacks.odin`)

The four `proc "c"` callbacks set `context = g_context` and forward to plain
Odin procedures in `src/app.odin`. `g_context` is written once before
`SDL_RunApp` and never mutated, so every callback sees the same allocator and
logger. `AppResult` values in the pinned bindings are `.CONTINUE`, `.SUCCESS`
and `.FAILURE`.

## Lifecycle and ownership (`src/app.odin`)

| Resource | Created | Destroyed |
| --- | --- | --- |
| `App_State` (heap) | first line of `app_init`, published to `appstate` immediately | `app_quit` (`free`) |
| `asset_dir` string | `app_init` | `app_quit` |
| `^sdl.Window` | `app_init` (Window stage) | `app_quit`, after the renderer |
| `^sdl.Renderer` | `app_init` (Renderer stage) | `app_quit`, after the audio stream |
| `^sdl.AudioStream` + beep samples | `audio_open` (Audio stage); optional | `audio_close`, after the UI atlas |
| microui context + atlas `^sdl.Texture` | `ui_init` (Ui stage) | `ui_destroy`, first in `app_quit` |
| SDL subsystems | `sdl.Init` / `sdl.InitSubSystem` in `app_init` | SDL, after `app_quit` returns |

`app_quit` runs exactly once, also after a failed `app_init`, and checks each
handle before destroying it, so partial initialization is safe. The
`--fail-after=<stage>` option exercises every such path.

Temporary allocations use `context.temp_allocator`, freed at the end of each
`app_init` and `app_iterate` call. Nothing temp-allocated or borrowed from an
SDL event is kept across callbacks.

## Timing (`game/timestep.odin`, `src/app.odin`)

Each `app_iterate` call:

1. Reads `SDL_GetTicksNS` and feeds it to `timestep_advance`. That clamps
   elapsed time to 250 ms and returns how many fixed 1/60 s steps are owed. At
   most 5 steps run per iteration. Excess whole steps are dropped, so the game
   slows down instead of spiralling, and are counted.
2. Runs that many `game_update` calls. Each consumes one `Step_Input`, so a
   press is seen by exactly one step, even when 0 or several steps run.
3. Plays a sound for each of the game's hit counters (`bounces`,
   `paddle_hits`) that went up during those steps (at most one of each per
   iteration).
4. Renders, interpolating bodies between their previous and current position
   by the leftover fraction.

Pacing uses vsync when the renderer supports it. Otherwise
`SDL_HINT_MAIN_CALLBACK_RATE` caps callbacks at 120 Hz. Minimize/hide sets
`suspended`, which skips simulation and rendering and sleeps 10 ms per
iteration. Restoring the window, regaining the foreground, or minimizing all
reset the timestep, so there is no catch-up burst. Focus loss clears held
input.

## Input (`game/input.odin`, `src/input.odin`)

`src/input.odin` maps physical scancodes to `game.Action` and ignores key
repeat. The game sees `held`, `pressed` and `released` sets only. Text entry
is not used. If you add it, use SDL text input events, not scancodes.

## Game (`game/`)

The example has a `Menu` → `Playing` ⇄ `Paused` state machine, a player square
(the paddle) and a ball whose launch direction comes from a seeded RNG. The
ball reflects off the world edges and off the paddle; for the paddle it is
pushed out along the axis of least overlap, and only counts as a hit when it
was moving towards the paddle. Each paddle hit makes the ball 10 % faster, up
to a cap that keeps it from passing through the paddle in a single step, and a
new round resets its speed. The package has no
SDL import, so it can be unit-tested and replaced freely.

## Threads

The app uses no worker threads, and only SDL's main-thread event pump calls
`app_event`. If you add workers, send their owned results through a bounded,
synchronized queue and drain it in `app_iterate`. Do not push SDL events that
mutate `App_State` from other threads.

## Sound (`src/audio.odin`)

The game package knows nothing about sound: it only counts how often the ball
hits a world edge (`Game.bounces`) or the player's paddle
(`Game.paddle_hits`). After the simulation steps of an iteration,
`app_iterate` compares each counter with the last value it answered and
queues the matching sound on an SDL audio device stream: an 880 Hz beep for a
wall and an octave higher (1760 Hz) for the paddle. Both are 60 ms sine tones
with a short fade-in and fade-out, generated once at startup, and SDL copies
them on every put. If the stream already holds more than 100 ms of
sound, the beep is skipped, so beeps can't pile up. Sound is optional: if no
audio device opens, the app logs a warning and runs silently, and `--mute`
skips audio entirely.

## Tuning panel (`src/ui.odin`)

A debug panel built with `vendor:microui`, which ships with Odin and is pure
Odin, so it adds no native library. Its context lives in `App_State`. Its
font/icon atlas is uploaded once to an SDL texture.

- `app_event` forwards mouse events to microui while the panel is visible. F1
  toggles it and is handled before game key bindings.
- `app_iterate` builds the panel (`ui_update`) before the simulation steps.
  Slider changes go through `game.game_set_tuning`, which clamps them to safe
  ranges and applies them, so the game package still knows nothing about the
  UI.
- `render` draws the game in world units and then the panel (`ui_draw`). For
  the panel it turns off logical presentation for the rest of the frame, which
  SDL allows. It scales by the window's pixel density, so the panel is sharp
  and its coordinates match mouse event coordinates on high-DPI displays.

Delete `src/ui.odin` and its few call sites to drop the panel.

## Optional examples (`examples/`)

`examples/images` and `examples/text` are separate executable packages. Each
is a single file with its own copy of the startup adapter and callbacks, plus
a minimal `App` struct, so it can be copied or deleted without touching `src/`
or `game/`. The two are deliberately not factored into a shared package: a
shared "platform" layer would be an abstraction with only one real user.

They follow the same ownership rules as the starter. Resources created in
`app_init` (texture; or font, text engine and `TTF_Text` objects) are owned
by the `App` and destroyed in `app_quit` in reverse order: the text objects and
text engine before the font, all before `TTF_Quit`, and everything before the
renderer and window. A failed load returns `.FAILURE` and still goes through
the same partial cleanup.
