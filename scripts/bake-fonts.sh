#!/usr/bin/env bash
# Regenerates the baked pixel fonts in src/ from assets/fonts/:
#   src/score_font.odin  Jersey 10, the score
#   src/menu_font.odin   Silkscreen, menu and tuning panel text (printable ASCII except `)
# Only needed after changing a font or a character set; the starter itself
# never links SDL_ttf.
#
# Usage: scripts/bake-fonts.sh   (needs scripts/bootstrap.sh --with-text)
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_odin
require_sdl
require_feature text
mkdir -p "$BUILD"

tool="$BUILD/bake-font"
log "building $tool"
"$ODIN_BIN" build "$ROOT/tools/bake-font" -vet -strict-style "-extra-linker-flags:$(sdl_link_flags)" -out:"$tool"

# Sizes are units per em / units per font pixel (from each font's design grid).
"$tool" "$ROOT/assets/fonts/Jersey10-Regular.ttf" 1400/75 "SCORE 0123456789" SCORE_FONT "$ROOT/src/score_font.odin"
"$tool" "$ROOT/assets/fonts/Silkscreen-Regular.ttf" 1000/125 \
	' !"#$%&'"'"'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\]^_abcdefghijklmnopqrstuvwxyz{|}~' MENU_FONT "$ROOT/src/menu_font.odin"
