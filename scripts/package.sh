#!/usr/bin/env bash
# Builds a relocatable release into dist/<os>-<arch>/ and checks that it
# launches from another directory using only the bundled SDL3.
#
# Usage: scripts/package.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_odin
require_sdl

dist="$ROOT/dist/$TARGET"
rm -rf "$dist"
mkdir -p "$dist"

case "$OS" in
linux) rpath='$ORIGIN';           lib="libSDL3.so.0" ;;
macos) rpath='@executable_path';  lib="libSDL3.0.dylib" ;;
esac

log "building relocatable release"
"$ODIN_BIN" build "$ROOT/src" -vet -strict-style -o:speed -out:"$dist/starter" \
	"-extra-linker-flags:-L$PREFIX/lib -Wl,-rpath,$rpath"

cp -L "$PREFIX/lib/$lib" "$dist/$lib"
cp -R "$ROOT/assets" "$dist/assets"
mkdir -p "$dist/licenses"
cp "$ROOT/LICENSE" "$dist/licenses/LICENSE.starter.txt"
cp "$PREFIX/share/licenses/SDL3/LICENSE.txt" "$dist/licenses/LICENSE.SDL3.txt"

# Launch check: different working directory, no custom loader paths.
log "launch check"
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
(
	cd "$check_dir"
	env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH \
		SDL_VIDEO_DRIVER=dummy SDL_RENDER_DRIVER=software SDL_AUDIO_DRIVER=dummy \
		"$dist/starter" --frames=10 > launch.log 2>&1 || { cat launch.log; die "packaged app failed to run"; }
	grep -q "SDL runtime $(lock_get "d['sdl3']['version']")" launch.log || { cat launch.log; die "packaged app did not load the locked SDL3"; }
)
if [[ "$OS" == linux ]]; then
	resolved="$(ldd "$dist/starter" | awk '/libSDL3/ {print $3}')"
	[[ "$resolved" == "$dist/$lib" ]] || die "libSDL3 resolved to $resolved, expected the bundled copy"
fi
log "packaged $dist"
