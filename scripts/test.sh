#!/usr/bin/env bash
# Runs unit tests and the headless lifecycle integration tests, including the
# optional examples whose libraries are installed.
#
# Usage: scripts/test.sh [--require-features]
#   --require-features  fail instead of skipping examples whose libraries are missing
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_all=0
[[ "${1:-}" == "--require-features" ]] && require_all=1

require_odin
require_sdl
mkdir -p "$BUILD"

log "unit tests: game"
"$ODIN_BIN" test "$ROOT/game" -vet -strict-style -out:"$BUILD/game-tests"

log "unit tests: src (pure procedures only)"
"$ODIN_BIN" test "$ROOT/src" -vet -strict-style -out:"$BUILD/src-tests" "-extra-linker-flags:$(sdl_link_flags)"

log "integration runner"
"$ODIN_BIN" build "$ROOT/tests/integration" -vet -strict-style -out:"$BUILD/integration"

for mode in debug release; do
	"$ROOT/scripts/build.sh" "$mode" starter
	exe="$BUILD/starter"; flag=(--release)
	[[ "$mode" == debug ]] && { exe="$BUILD/starter-debug"; flag=(); }
	log "lifecycle cases: starter ($mode)"
	"$BUILD/integration" "$exe" "$BUILD/integration-logs/starter-$mode" ${flag[@]+"${flag[@]}"}
done

# Feature isolation: the baseline must not link the optional libraries.
case "$OS" in
linux) deps="$(ldd "$BUILD/starter")" ;;
macos) deps="$(otool -L "$BUILD/starter")" ;;
esac
if grep -Eq "SDL3_(image|ttf)" <<< "$deps"; then
	echo "$deps" >&2
	die "baseline starter links an optional library"
fi
log "baseline links only SDL3"

for pair in images:image text:text; do
	target="${pair%%:*}" feature="${pair##*:}"
	if ! has_feature "$feature"; then
		[[ $require_all -eq 1 ]] && die "example '$target' requires: scripts/bootstrap.sh --with-$feature"
		log "skipping example '$target' (run scripts/bootstrap.sh --with-$feature)"
		continue
	fi
	"$ROOT/scripts/build.sh" debug "$target"
	log "lifecycle cases: $target (debug)"
	"$BUILD/integration" "$BUILD/$target-debug" "$BUILD/integration-logs/$target-debug" --suite="$target"
	"$ROOT/scripts/build.sh" release "$target"
	log "lifecycle cases: $target (release)"
	"$BUILD/integration" "$BUILD/$target" "$BUILD/integration-logs/$target-release" --suite="$target" --release
done
