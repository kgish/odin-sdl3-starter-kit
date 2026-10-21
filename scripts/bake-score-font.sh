#!/usr/bin/env bash
# Regenerates src/score_font.odin from assets/fonts/Jersey10-Regular.ttf.
# Only needed after changing the font or the baked characters; the starter
# itself never links SDL_ttf.
#
# Usage: scripts/bake-score-font.sh   (needs scripts/bootstrap.sh --with-text)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_odin
require_sdl
require_feature text
mkdir -p "$BUILD"

tool="$BUILD/bake-score-font"
log "building $tool"
"$ODIN_BIN" build "$ROOT/tools/bake-score-font" -vet -strict-style "-extra-linker-flags:$(sdl_link_flags)" -out:"$tool"
"$tool" "$ROOT/assets/fonts/Jersey10-Regular.ttf" "$ROOT/src/score_font.odin"
