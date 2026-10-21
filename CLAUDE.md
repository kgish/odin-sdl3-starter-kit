# Odin + SDL3 starter kit: instructions for Claude Code

## Project intent

Build a small, understandable, reusable game starter template in Odin using SDL3's application callback architecture. Target Windows, Linux, and macOS desktop first. Use current stable libraries, explicit resource ownership, reproducible builds, and meaningful automated tests. Keep the example easy to delete or replace when starting a game.

This document is an implementation specification and contributor guide. At its creation, the workspace contained no starter implementation. Commands and layouts below describe the intended project; they are not evidence that builds or tests have passed.

## Required decisions

- SDL owns the application loop through initialization, event, iteration, and quit callbacks.
- Do not introduce a traditional application-owned `while running` / `PollEvent` loop.
- Start with SDL's 2D renderer. Add SDL GPU rendering as an independent optional example if needed.
- Make SDL_image and SDL_ttf optional features with separate examples and dependency declarations.
- Use native builds and tests for each supported OS. Do not assume cross-compilation proves runtime compatibility.
- Prefer ordinary Odin packages, explicit structs, procedures, and composition. Add abstractions only for demonstrated needs.
- Keep gameplay logic independent of SDL wherever practical.

## Library versions and update policy

The following latest stable releases were checked on **2026-10-21**:

| Component | Verified release | Purpose |
| --- | --- | --- |
| Odin | `dev-2026-10` | Compiler, base/core libraries, vendor bindings |
| SDL3 | `3.4.18` | Required windowing, events, rendering, timing, audio/input APIs |
| SDL3_image | `3.4.8` | Optional image decoding |
| SDL3_ttf | `3.2.2` | Optional font rendering |

Official release sources:

- [Odin](https://github.com/odin-lang/Odin/releases/latest)
- [SDL3](https://github.com/libsdl-org/SDL/releases/latest)
- [SDL3_image](https://github.com/libsdl-org/SDL_image/releases/latest)
- [SDL3_ttf](https://github.com/libsdl-org/SDL_ttf/releases/latest)

These values are a dated research baseline. On implementation or an explicit dependency update, check official release sources again and select the newest stable releases. Do not silently substitute nightly builds, prereleases, or branch heads. If experimental development versions are requested, record exact commits and test them separately.

Keep a dependency lock manifest containing release tag, resolved commit, source URL, archive SHA-256, target architecture, build options, enabled codecs/backends, and relevant transitive dependency versions. Resolve “latest” during dependency updates, then build exact locked inputs. Ordinary builds must not fetch moving branch heads or unexpectedly upgrade dependencies.

Odin vendor bindings ship with the compiler; they do not necessarily expose every API in a newly released native library. Verify the actual pinned binding declarations against the selected SDL release. If an API is missing, prefer a compatible newer Odin release or a small documented local binding extension. Do not modify the user's global Odin installation. Never assume the Windows native binaries shipped with Odin are the newest SDL release.

## Dependency inventory

### Required for the baseline

| Dependency | Requirement |
| --- | --- |
| Odin distribution | Keep compiler and its matching `base`, `core`, and `vendor` directories together |
| `vendor:sdl3` | Bindings supplied with Odin; no separate binding package manager required |
| Native SDL3 | Build/link library plus runtime library for the target OS and architecture |
| Platform linker/SDK | MSVC tools and Windows SDK on Windows; Clang and development tools on Linux; Xcode command-line tools on macOS |
| Git | Versioned dependency source and project development |
| C compiler + CMake | Required when building SDL from source or compiling a C startup bridge |
| Ninja or Make | Native dependency build backend; select one and document it |
| `pkg-config` | Useful Unix dependency diagnostics/discovery; required where the selected native configuration needs it |

Use a prebuilt Odin release by default. Building Odin itself introduces its own compiler/LLVM requirements; consult the selected release's documentation rather than adding these to every user's prerequisites.

Odin's current SDL3 foreign imports use `SDL3.lib` on Windows and `system:SDL3` on Unix-like desktop platforms. Verify these declarations in the pinned compiler. Configure both link-time search paths and runtime loading; solving one does not solve the other.

### Linux native SDL build dependencies

The complete set depends on enabled features and the distribution. Do not present every backend as universally mandatory.

| Feature | Dependency families |
| --- | --- |
| Wayland | Wayland development files, wayland-protocols, xkbcommon, optional libdecor |
| X11 | X11/Xext and selected Xrandr, Xcursor, Xfixes, Xi, Xss, Xtst extensions |
| Audio | ALSA, PipeWire, PulseAudio; optionally JACK/sndio |
| Graphics | OpenGL/EGL/GLES development files; Vulkan headers/loader where the chosen backend requires them |
| Direct display | DRM and GBM where enabled |
| Controllers/devices | udev and libusb where enabled |
| Desktop/text integration | D-Bus, IBus, optional FriBidi/libthai |
| Other optional facilities | liburing and other packages selected by the pinned SDL configuration |

Use the [official SDL Linux package lists](https://wiki.libsdl.org/SDL3/README-linux) for concrete distribution commands. Review CMake's feature summary: SDL can compile successfully while omitting the desktop/audio backend the application needs. Keep a supported backend checklist in CI.

### Optional features

- **Images:** `vendor:sdl3/image` and native SDL3_image. Select supported formats explicitly. External dependencies for AVIF, JPEG-XL, TIFF, WebP, and other codecs depend on build options. Record the actual resolved dependency graph instead of claiming every codec is mandatory.
- **Fonts:** `vendor:sdl3/ttf` and native SDL3_ttf. Account for FreeType, HarfBuzz, and optional PlutoSVG/PlutoVG support according to the selected release/configuration. Include font licenses.
- **Audio:** SDL3 already provides audio APIs and WAV loading. Add a mixer/codec library only when the example requires it; separately research its latest release, bindings, codecs, and licenses before adoption.
- **GPU:** SDL GPU requires suitable hardware/drivers and shaders in formats supported by the selected backend. Choose and pin shader compilation tools only when implementing this profile.
- **Developer tooling:** Odin language server/editor integration, debugger, formatting tools, and native memory tools are useful but are not runtime dependencies.
- **CI:** A virtual display such as Xvfb may be useful for X11 integration tests. Dummy-driver smoke tests do not need a real display.

## Callback entry-point architecture

SDL's C callback model uses `SDL_MAIN_USE_CALLBACKS` and `SDL_main.h`. Odin does not process C preprocessor macros. Merely declaring or exporting four callback symbols is insufficient to install platform startup behavior.

Implement and validate one explicit adapter:

1. A platform-aware Odin entry adapter using the supported SDL entry functions, with correct arguments, exit status, and startup handling; or
2. A small C bridge using SDL's documented callback header machinery and forwarding into exported Odin procedures, with the executable entry point and Odin runtime initialization deliberately arranged.

Do not accidentally define two executable entry points. Do not call exported Odin code before its required runtime initialization. Keep the bridge limited to startup/ABI concerns. Prefer a proven pure-Odin adapter when supported and validated on all target platforms.

Odin exposes `RunApp` and `EnterAppMainCallbacks`; their existence alone does not establish that any arbitrary call sequence is supported. SDL documents `EnterAppMainCallbacks` as a low-level entry function with restrictions. Validate the adapter against the pinned SDL implementation and official startup documentation before adopting it.

| Callback | Responsibilities |
| --- | --- |
| `AppInit` | Establish state, application metadata, SDL subsystems, window, renderer, and resources; publish state early enough for failure cleanup |
| `AppEvent` | Handle one supplied event, translate it into application input/actions, then return promptly |
| `AppIterate` | Perform one bounded update/render iteration and return control to SDL |
| `AppQuit` | Destroy owned resources in reverse dependency order; tolerate nil state and partial initialization |

Use C calling conventions for all procedures called by SDL. Explicitly establish a valid Odin `context` at each foreign callback boundary; preserve persistent application allocator/logger configuration through a clear adapter strategy. Do not assume a foreign caller provides Odin's implicit context.

Allocate persistent `App_State` in memory that outlives `AppInit` and pass it through `appstate`. Never pass the address of a returning stack local. Return `.Continue`, `.Success`, or `.Failure` using the actual pinned Odin enum names. Preserve useful diagnostics and propagate process exit status.

SDL pumps events. Do not call `PollEvent`, `PumpEvents`, or build a blocking loop inside callbacks. SDL event pointers are borrowed; copy required data, including pointed-to payload data according to its ownership rules, before retaining it.

Events normally arrive serially through SDL's main-thread event pumping, but events explicitly pushed by worker threads can invoke the event callback from those threads. Use a synchronized handoff for worker results. Keep rendering/window operations and main application state mutation on their required thread; do not casually mutate shared state in `AppEvent` from an arbitrary thread.

## Game timing and frame behavior

Callback architecture is event-driven, but `AppIterate` is still called repeatedly. It does not automatically make the app sleep until input arrives.

For a game, use a fixed simulation step with a variable render cadence:

```text
AppIterate:
    measure elapsed time with a monotonic clock
    clamp unusually large elapsed time after pauses/debugging
    add elapsed time to the simulation accumulator
    latch pending input actions for simulation
    while accumulator >= fixed_step and update_count < update_limit:
        update simulation by fixed_step
        consume one-shot actions exactly once
        accumulator -= fixed_step
    apply documented overload policy if still behind
    render, optionally interpolating previous/current simulation state
    return Continue
```

This bounded simulation loop is allowed; it is not an event-polling or application lifetime loop. A reasonable configurable starting point is a 60 Hz simulation, a 250 ms elapsed-time clamp, and a small per-iteration update limit. Tune these as policy, not assumptions about SDL's callback rate.

- Measure time; do not assume callbacks run at monitor refresh rate.
- Separate held input from pressed/released transitions. Keep transient actions until a simulation step consumes them; do not drop them on render-only iterations or repeat them across catch-up steps.
- Treat keyboard text input separately from physical key bindings; support SDL text/IME events if the example accepts text.
- Reset held input on focus loss to avoid stuck controls.
- Use vsync when available, document fallback pacing, and avoid unnecessary blocking in callbacks.
- For tool-like examples, allow a dirty flag to skip rendering until something changes; separately choose an appropriate SDL-supported pacing policy.
- On minimize/suspend/resume, use an explicit pause/timing-reset policy to avoid a huge catch-up burst.

## Recommended design patterns

### Explicit ownership and composition

Use an `App_State` that composes configuration, platform resources, input state, simulation state, timing, and optional asset ownership. Document who creates and destroys each native resource. Keep handles/pointers with their owner and avoid multiple destruction paths.

Use `defer` for temporary resources scoped to a procedure. Persistent resources must survive initialization and be cleaned up by the lifecycle owner. Do not defer successful persistent-resource destruction inside `AppInit`.

### Thin platform adapter, independent simulation

Translate SDL events into small application actions. Run game rules on plain Odin values and render from simulation state. Avoid routing SDL calls through every gameplay package. Introduce small interfaces or procedure tables only where a second implementation or a real testing seam exists.

### State machines

Use an enum and explicit transitions for a few states such as menu, playing, paused, and shutdown. Add a scene abstraction only when multiple scenes need independent ownership/lifecycle. Avoid a generic engine framework in the starter.

### Data-oriented updates

Prefer arrays and clear iteration for collections of similar objects. Use stable IDs or validated handles if references must survive container movement. Introduce ECS only after the game has a concrete need; do not make it a baseline dependency.

### Commands at asynchronous boundaries

Worker threads produce owned results or commands through a synchronized queue. Apply them on the main thread at a defined point. Do not add a global event bus for simple direct interactions. Bound queues and define overflow/shutdown behavior.

### Configuration and feature isolation

Use sensible defaults and a small typed configuration structure. Keep optional libraries in separate packages/examples or compile-time-selected files so a minimal build does not accidentally link them. Avoid runtime toggles for dependencies that are absent at link time.

## Coding practices

- Follow the conventions of the pinned Odin release and its core/vendor examples.
- Prefer clear names, small cohesive procedures, explicit imports, and narrow package responsibilities.
- Use assertions for internal invariants; handle missing files, SDL failures, and unsupported devices as recoverable or reported errors.
- Check each SDL result according to that API's actual contract. SDL3 APIs often differ from SDL2; do not copy SDL2 return-value checks.
- Read `GetError` when an SDL operation reports failure, not as a universal success/failure test.
- Keep allocator choices explicit. Use a frame scratch allocator only for data that cannot escape the frame, then reset it at a well-defined boundary.
- Never retain scratch slices, temporary C strings, or callback event pointers in persistent state.
- Keep foreign strings null-terminated where required; make conversion lifetimes obvious.
- Handle logical window coordinates versus pixel dimensions deliberately for high-DPI rendering and input mapping.
- Resolve application assets independently of the process working directory; use an explicit development override if useful.
- Log version, selected video/render/audio backends, and initialization failures without producing per-frame noise.
- Keep debug checks enabled during development. Apply optimization only where measured or required.
- Avoid broad global mutable state, speculative abstraction layers, dependency injection frameworks, and unrelated utility packages.

## Intended directory structure

```text
CLAUDE.md
README.md
LICENSE
deps.lock.json
src/                         # executable package; keep initial version small
  main.odin                  # validated startup adapter
  callbacks.odin             # foreign callback/context boundaries
  app.odin                   # App_State and lifecycle ownership
  input.odin                 # SDL-to-action translation
  render.odin                # baseline SDL renderer
  config.odin
game/                        # SDL-independent simulation package
  game.odin
  game_test.odin
tests/
  integration/               # dedicated main-thread executable
assets/
  README.md                  # provenance and licenses
examples/
  images/                    # optional SDL_image executable
  text/                      # optional SDL_ttf executable
  gpu/                       # optional; create only when implemented
native/                      # startup bridge only if required
scripts/
  bootstrap.sh
  bootstrap.ps1
  build.sh
  build.ps1
  test.sh
  test.ps1
  package.sh
  package.ps1
  update-deps.*
docs/
  dependencies.md
  architecture.md
  testing.md
third_party/                 # fetched/locked dependency inputs
build/                       # ignored intermediate native/compiler outputs
dist/                        # ignored packaged runnable applications
.github/workflows/           # if GitHub Actions is selected
```

Files within an Odin directory form a package. Keep executable examples and integration runners in separate directories to avoid duplicate `main` procedures or conflicting package declarations. Start with fewer files if that is clearer, and split packages when responsibilities justify it.

## Build and packaging plan

1. Implement bootstrap/update scripts that validate toolchains, resolve locked dependencies, verify checksums, and build/install native libraries to a project-local prefix.
2. Explicitly configure shared/static mode and the required SDL backends. Start with shared SDL to keep native linking manageable.
3. Compile the startup adapter if required, then build Odin using the selected native search paths.
4. Provide equivalent debug, release, run, test, and package commands on supported hosts. Keep script prerequisites documented.
5. Include the required DLL/shared libraries, assets, and license notices in `dist`. Configure Linux/macOS loader paths appropriately; do not assume the executable directory is searched automatically.
6. On Windows, ensure the exact import library and runtime DLL form a matching pair. Confirm the application is actually loading the locked version.
7. Validate packaged output on a clean environment without the developer's SDL installation or custom library search environment.

Illustrative Odin commands after the implementation exists:

```sh
odin check src
odin build src -debug -out:build/starter-debug
odin build src -o:speed -out:build/starter
odin test game
```

Platform scripts must create output directories, choose platform-specific executable names, and add the native link options required by the pinned toolchain. These examples do not include that configuration.

Use SDL's CMake build documentation for native library setup. If debugging SDL itself, its native test programs can be enabled with `-DSDL_TESTS=ON`; these complement, rather than replace, application tests.

## Test strategy

### Dependency and compile checks

- Record `odin version`, dependency lock values, native runtime versions, and target architecture.
- Check baseline debug/release compilation on each supported platform.
- Build each optional example independently and verify that disabling it removes the native dependency.
- Verify native backend availability, rather than accepting only a successful SDL build.

### Unit tests

Use Odin's `core:testing` and `odin test` for meaningful pure-logic tests:

- Key press/release/held transitions, focus loss, and transient input across zero/multiple simulation updates.
- Fixed-step accumulation, time clamping, pause/resume, and overload policy.
- State transitions and configuration validation.
- Asset path resolution independent of the working directory.

Keep simulation deterministic by passing time/input and seeded randomness explicitly. Test observable behavior, not implementation details.

### Lifecycle integration executable

SDL window/render lifecycle tests must run on the required main thread. Do not assume `odin test` worker callbacks satisfy that requirement, even with a single test worker. Use a dedicated executable that exercises the real startup adapter and callbacks.

Add a smoke mode with a bounded number of iterations, explicit result reporting, a process timeout, and meaningful exit status. Test:

- Successful initialization, event delivery, one or more renders, and clean quit.
- Quit requested through an event.
- Failure after each significant initialization stage and safe partial cleanup.
- Missing/corrupt assets with useful diagnostics.
- Correct application exit code and resource destruction exactly once.

For supported builds, use `SDL_VIDEO_DRIVER=dummy`, `SDL_RENDER_DRIVER=software`, and optional `SDL_AUDIO_DRIVER=dummy` for headless smoke tests. Verify that these drivers are built in. Dummy drivers prove lifecycle behavior, not hardware acceleration, visible output, or physical-device correctness.

### Real desktop and release tests

Test Windows, Linux, and macOS on their native environments; include Linux Wayland and X11 where supported. Cover resize, high DPI, minimize/restore, focus changes, keyboard/mouse, vsync fallback, and quitting. Exercise controller hotplug/audio devices only if those features are included.

Inspect Odin allocation tracking where applicable, and separately audit native SDL ownership: Odin's allocator tracker does not automatically account for every C allocation. Use native memory diagnostics when investigating leaks or corruption.

Launch packaged output from another working directory and a clean machine/container/VM as appropriate. Confirm no dependency is accidentally resolved from the developer environment. A headless container does not replace a real desktop test.

## Implementation milestones and completion criteria

1. **Dependency foundation:** newest stable versions rechecked, locked inputs, working native bootstrap, backend diagnostics.
2. **Callback skeleton:** supported startup adapter, correct C ABI/Odin context, safe state lifetime, window and clear frame, event-driven exit.
3. **Game foundation:** input translation, fixed-step timing, small deterministic example, ownership and failure cleanup.
4. **Validation:** pure unit tests, headless lifecycle runner, native desktop CI/build checks, packaged launch verification.
5. **Optional features:** independent image/text examples, exact transitive dependency/license records; GPU only when requested or justified.

Before declaring completion, state what was implemented, which commands passed, which platforms were actually exercised, and any unresolved limitation. Do not claim tests or compatibility that were not verified.

## Official references

- [Odin installation and platform toolchains](https://odin-lang.org/docs/install/)
- [Odin SDL3 bindings](https://pkg.odin-lang.org/vendor/sdl3/)
- [Odin SDL3 linker declarations](https://github.com/odin-lang/Odin/blob/master/vendor/sdl3/sdl3__foreign.odin)
- [Odin SDL3 startup declarations](https://github.com/odin-lang/Odin/blob/master/vendor/sdl3/sdl3_main.odin)
- [Odin testing](https://odin-lang.org/docs/testing/)
- [SDL application entry points and callback architecture](https://wiki.libsdl.org/SDL3/README-main-functions)
- [SDL EnterAppMainCallbacks restrictions](https://wiki.libsdl.org/SDL3/SDL_EnterAppMainCallbacks)
- [SDL AppEvent: ownership and thread behavior](https://wiki.libsdl.org/SDL3/SDL_AppEvent)
- [SDL AppIterate: timing and iteration behavior](https://wiki.libsdl.org/SDL3/SDL_AppIterate)
- [SDL CMake builds](https://wiki.libsdl.org/SDL3/README-cmake)
- [SDL Linux dependencies](https://wiki.libsdl.org/SDL3/README-linux)
- [SDL video driver selection](https://wiki.libsdl.org/SDL3/SDL_HINT_VIDEO_DRIVER)
- [SDL renderer selection](https://wiki.libsdl.org/SDL3/SDL_HINT_RENDER_DRIVER)
- [SDL GPU API](https://wiki.libsdl.org/SDL3/CategoryGPU)
- [SDL_image source and build documentation](https://github.com/libsdl-org/SDL_image)
- [SDL_ttf source and build documentation](https://github.com/libsdl-org/SDL_ttf)

When implementing, read documentation and source for the locked releases. Links to moving branches describe the research source, not a substitute for version pinning.