# Dependencies

Exact versions, commits, archive checksums and SDL build options live in
[`deps.lock.json`](../deps.lock.json). Ordinary builds use only those locked
inputs. `scripts/update-deps.sh` is the only script that resolves "latest".

| Component | Locked | Notes |
| --- | --- | --- |
| Odin | `dev-2026-10` (`84bc3fc`) | Its `vendor:sdl3` bindings declare SDL **3.4.2** headers |
| SDL3 | `3.4.18` (`829a65d`) | Built from the release tarball as a shared library with CMake + Ninja |

The bindings are older than the locked SDL. Within SDL 3.x the ABI is
backwards compatible, and the starter only calls functions present in both.
At startup the app logs both versions (`SDL runtime 3.4.18 …, bindings 3.4.2`).

## Prerequisites

All platforms: Git, CMake ≥ 3.16, Ninja, Python 3 (Unix scripts parse the lock
with it), curl or PowerShell 7.

### Linux

Clang (Odin's linker driver), a C toolchain, `pkg-config`, and SDL's backend
development packages. On Ubuntu 24.04:

```sh
sudo apt-get install build-essential clang cmake ninja-build pkg-config python3 \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev libxi-dev libxss-dev libxtst-dev \
  libxkbcommon-dev libwayland-dev libdecor-0-dev \
  libdrm-dev libgbm-dev libgl1-mesa-dev libgles2-mesa-dev libegl1-mesa-dev \
  libdbus-1-dev libibus-1.0-dev libudev-dev
```

For other distributions, see the
[SDL Linux package lists](https://wiki.libsdl.org/SDL3/README-linux).

### macOS

Xcode command-line tools and `brew install cmake ninja`. The locked Odin
archive is Apple Silicon (`macos-arm64`).

### Windows

Visual Studio 2022 or later with the C++ workload and a Windows SDK. Use a
**Developer PowerShell 7** so `cl.exe` is on `PATH`, plus CMake and Ninja.

## What bootstrap does

1. Downloads the SDL3 tarball into `third_party/src/` and verifies its SHA-256.
2. Configures with the lock's CMake options, builds into
   `third_party/build/sdl3-<os>-<arch>`, and installs to
   `third_party/prefix/<os>-<arch>`.
3. Reads the generated `SDL_build_config.h` and **fails** if any backend in
   `required_defines` is missing. SDL can build successfully while silently
   dropping a backend whose dev package is absent.
4. With `--with-odin` (always on Windows), downloads and verifies the locked
   Odin release into `third_party/odin/<os>-<arch>`.

Bootstrap writes a stamp, so rerunning it is a no-op until the lock changes.
Use `--force` / `-Force` to rebuild.

## Linking and loading

| OS | Link time | Run time (dev build) | Run time (`dist/`) |
| --- | --- | --- | --- |
| Linux | `system:SDL3` + `-L<prefix>/lib` | `RUNPATH` = absolute prefix | `RUNPATH` = `$ORIGIN`, `libSDL3.so.0` beside the exe |
| macOS | same | `LC_RPATH` = absolute prefix | `@executable_path`, `libSDL3.0.dylib` beside the exe |
| Windows | `vendor/sdl3/SDL3.lib` in the **project-local** Odin | `SDL3.dll` copied beside the exe | same |

On Windows, `vendor:sdl3` links `SDL3.lib` by path inside the Odin
distribution. That distribution also bundles its own `SDL3.dll`, which is not
the locked version. `bootstrap.ps1` therefore overwrites `vendor/sdl3/SDL3.lib`
and `SDL3.dll` **in the project-local Odin copy only** with the locked build,
so the import library and DLL always match. Your global Odin install is never
touched.

`scripts/package.*` checks the packaged app: it runs it from a temp directory
with loader overrides removed, and checks that it reports the locked SDL
version. On Linux it also checks that `ldd` resolves the bundled library.

## Updating

```sh
scripts/update-deps.sh          # resolves latest stable tags, rewrites the lock
git diff deps.lock.json         # review
scripts/bootstrap.sh --force --with-odin
scripts/test.sh && scripts/package.sh
```

Then compare `vendor/sdl3/sdl3_version.odin` in the new compiler with
`odin.sdl3_binding_headers` in the lock, and update the version table in
`CLAUDE.md`.

Optional libraries (SDL3_image, SDL3_ttf, GPU shader tools) are not part of
the baseline and are not in the lock.
