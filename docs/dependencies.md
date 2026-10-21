# Dependencies

Exact versions, commits, archive checksums and SDL build options live in
[`deps.lock.json`](../deps.lock.json). Ordinary builds use only those locked
inputs. `scripts/update-deps.sh` is the only script that resolves "latest".

| Component | Locked | Notes |
| --- | --- | --- |
| Odin | `dev-2026-10` (`84bc3fc`) | Its `vendor:sdl3` bindings declare SDL **3.4.2** headers |
| SDL3 | `3.4.18` (`829a65d`) | Built from the release tarball as a shared library with CMake + Ninja |
| SDL3_image | `3.4.8` (`0891fc3`) | Optional (`image` feature). Bindings declare **3.4.0** headers |
| SDL3_ttf | `3.2.2` (`a1ce367`) | Optional (`text` feature). Bindings declare 3.2.2 headers |
| FreeType | `2.15.0` (`37515cf`) | Optional (`text` feature). Static library linked into SDL3_ttf |

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
5. With `--with-image`, `--with-text` or `--all-features` (`-WithImage`,
   `-WithText`, `-AllFeatures`), builds the optional packages the same way into
   the same prefix. It then checks each library's dependencies (`ldd`, `otool -L`
   or `dumpbin /dependents`) against the lock's `must_not_link` list, so a
   system libpng or FreeType cannot be picked up by accident.

Each package writes a stamp (`<prefix>/.lock-<key>`), so rerunning bootstrap is
a no-op until its lock entry changes. A changed package also rebuilds the
packages after it in the same feature. Rebuilding SDL3 clears the whole prefix.
Use `--force` / `-Force` to rebuild everything that is selected.

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

`update-deps.sh` also resolves SDL3_image, SDL3_ttf and FreeType. FreeType does
not publish GitHub releases, so its version comes from the
[savannah listing](https://download.savannah.gnu.org/releases/freetype/) and its
commit from the `VER-x-y-z` tag in the
[freedesktop repository](https://gitlab.freedesktop.org/freetype/freetype).
Compare `odin.sdl3_image_binding_headers` and `odin.sdl3_ttf_binding_headers`
with `vendor/sdl3/image` and `vendor/sdl3/ttf` in the new compiler too.

## Optional libraries

The examples' native libraries are opt-in **features** (`features` in the
lock). Nothing in `src/` imports them, and a bootstrap without feature flags
does not build them.

| Feature | Packages | Used by |
| --- | --- | --- |
| `image` | SDL3_image | `examples/images` |
| `text` | FreeType, SDL3_ttf | `examples/text` |

### SDL3_image codecs

SDL3_image is built with its bundled **stb_image** backend for BMP, JPEG, PNG
and QOI, and every other format is off. This needs no external codec libraries,
so there are none to lock or license. The platform backends (ImageIO on
macOS, WIC on Windows) are also off, so all three OSes decode the same way. If
you need another format, enable it in the lock. If it needs an external
library (AVIF, JPEG XL, TIFF, WebP), add that library to the lock as its own
package, with its version, checksum and license, and remove it from
`must_not_link`.

### SDL3_ttf and FreeType

SDL3_ttf needs FreeType. Bootstrap builds FreeType 2.15.0 from source as a
static, position-independent library with zlib, bzip2, PNG, Brotli and HarfBuzz
support off, and SDL3_ttf links it in. Only `SDL3_ttf` ships as a shared
library. SDL3_ttf is built with `SDLTTF_HARFBUZZ=OFF` and `SDLTTF_PLUTOSVG=OFF`.
Text is therefore laid out without complex shaping (fine for Latin, Greek and
Cyrillic, but not for Arabic, Indic scripts and so on), and SVG/colour emoji
glyphs are not rendered. To enable shaping, add HarfBuzz to the lock as its own
package and turn on `SDLTTF_HARFBUZZ`.

FreeType is used under the FreeType License (`docs/FTL.TXT`). Bootstrap
installs each package's license files into `<prefix>/share/licenses/<key>`
(`<prefix>/licenses/<key>` on Windows), and packaging copies them to
`dist/*/licenses/`.

### Windows

The Odin distribution also bundles `SDL3_image` and `SDL3_ttf` import
libraries and DLLs under `vendor/sdl3/image` and `vendor/sdl3/ttf`, and
`vendor:sdl3/image` and `vendor:sdl3/ttf` link them by path. As with SDL3,
`bootstrap.ps1` replaces them **in the project-local Odin only** with the
locked builds when the matching feature is selected.

GPU shader tools are not part of the lock; they will be chosen if a GPU example
is added.
