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
| `^sdl.AudioStream` + beep samples | `audio_open` (Audio stage); optional | `audio_close`, first in `app_quit` |
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
3. Plays a beep if the game's `bounces` counter went up during those steps
   (at most one beep per iteration).
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
and a ball whose launch direction comes from a seeded RNG. The package has no
SDL import, so it can be unit-tested and replaced freely.

## Threads

The app uses no worker threads, and only SDL's main-thread event pump calls
`app_event`. If you add workers, send their owned results through a bounded,
synchronized queue and drain it in `app_iterate`. Do not push SDL events that
mutate `App_State` from other threads.

## Sound (`src/audio.odin`)

The game package knows nothing about sound: it only counts how often the ball
hits a world edge (`Game.bounces`). After the simulation steps of an
iteration, `app_iterate` compares that counter with the last value it answered
and queues a beep on an SDL audio device stream. The beep is a 60 ms, 880 Hz
sine tone with a short fade-in and fade-out, generated once at startup, and
SDL copies it on every put. If the stream already holds more than 100 ms of
sound, the beep is skipped, so beeps can't pile up. Sound is optional: if no
audio device opens, the app logs a warning and runs silently, and `--mute`
skips audio entirely.

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
