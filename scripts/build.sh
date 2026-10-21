#!/usr/bin/env bash
# Builds the starter against the locked SDL3.
#
# Usage: scripts/build.sh [debug|release]   (default: debug)
# Output: build/starter-debug or build/starter
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mode="${1:-debug}"
require_odin
require_sdl
mkdir -p "$BUILD"

common=(-vet -strict-style "-extra-linker-flags:$(sdl_link_flags)")
case "$mode" in
debug)   out="$BUILD/starter-debug"; flags=(-debug) ;;
release) out="$BUILD/starter";       flags=(-o:speed) ;;
*)       die "unknown build mode: $mode (expected debug or release)" ;;
esac

log "building $mode -> $out"
"$ODIN_BIN" build "$ROOT/src" "${common[@]}" "${flags[@]}" -out:"$out"

# Dev builds find assets next to the executable, exactly like packaged builds.
rm -rf "$BUILD/assets"
cp -R "$ROOT/assets" "$BUILD/assets"
