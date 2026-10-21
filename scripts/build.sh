#!/usr/bin/env bash
# Builds the starter (or an optional example) against the locked native libraries.
#
# Usage: scripts/build.sh [debug|release] [starter|images|text]   (default: debug starter)
# Output: build/<target>-debug or build/<target>
#   images needs scripts/bootstrap.sh --with-image; text needs --with-text.
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

mode="${1:-debug}"
target="${2:-starter}"
require_odin
require_sdl
mkdir -p "$BUILD"

case "$target" in
starter) src="$ROOT/src" ;;
images)  src="$ROOT/examples/images"; require_feature image ;;
text)    src="$ROOT/examples/text";   require_feature text ;;
*)       die "unknown target: $target (expected starter, images or text)" ;;
esac

common=(-vet -strict-style "-extra-linker-flags:$(sdl_link_flags)")
case "$mode" in
debug)   out="$BUILD/$target-debug"; flags=(-debug) ;;
release) out="$BUILD/$target";       flags=(-o:speed) ;;
*)       die "unknown build mode: $mode (expected debug or release)" ;;
esac

log "building $target ($mode) -> $out"
"$ODIN_BIN" build "$src" "${common[@]}" "${flags[@]}" -out:"$out"

# Dev builds find assets next to the executable, exactly like packaged builds.
rm -rf "$BUILD/assets"
cp -R "$ROOT/assets" "$BUILD/assets"
