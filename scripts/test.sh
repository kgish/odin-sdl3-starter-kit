#!/usr/bin/env bash
# Runs unit tests and the headless lifecycle integration tests.
#
# Usage: scripts/test.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_odin
require_sdl
mkdir -p "$BUILD"

log "unit tests: game"
"$ODIN_BIN" test "$ROOT/game" -vet -strict-style -out:"$BUILD/game-tests"

log "unit tests: src (pure procedures only)"
"$ODIN_BIN" test "$ROOT/src" -vet -strict-style -out:"$BUILD/src-tests" "-extra-linker-flags:$(sdl_link_flags)"

log "integration runner"
"$ODIN_BIN" build "$ROOT/tests/integration" -vet -strict-style -out:"$BUILD/integration"

"$ROOT/scripts/build.sh" debug
log "lifecycle cases: debug"
"$BUILD/integration" "$BUILD/starter-debug" "$BUILD/integration-logs/debug"

"$ROOT/scripts/build.sh" release
log "lifecycle cases: release"
"$BUILD/integration" "$BUILD/starter" "$BUILD/integration-logs/release" --release
