#!/usr/bin/env bash
# Builds relocatable releases into dist/<os>-<arch>/ (the starter, plus each
# optional example whose libraries are installed) and checks that they launch
# from another directory using only the bundled libraries.
#
# Usage: scripts/package.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require_odin
require_sdl

dist="$ROOT/dist/$TARGET"
rm -rf "$dist"
mkdir -p "$dist/licenses"

case "$OS" in
linux) rpath='$ORIGIN';          libname() { echo "lib$1.so.0"; } ;;
macos) rpath='@executable_path'; libname() { echo "lib$1.0.dylib"; } ;;
esac

# bundle <library base name> <license dir name>...
bundle() {
	local lib="$1" dir
	shift
	cp -L "$PREFIX/lib/$(libname "$lib")" "$dist/"
	for dir in "$@"; do
		for file in "$PREFIX/share/licenses/$dir"/*; do
			cp "$file" "$dist/licenses/$dir-$(basename "$file")"
		done
	done
}

# build_target <name> <source dir>
build_target() {
	log "building $1 (relocatable release)"
	"$ODIN_BIN" build "$2" -vet -strict-style -o:speed -out:"$dist/$1" \
		"-extra-linker-flags:-L$PREFIX/lib -Wl,-rpath,$rpath"
}

targets=(starter)
build_target starter "$ROOT/src"
bundle SDL3 SDL3
# The starter embeds glyphs baked from Jersey 10 and Silkscreen (src/*_font.odin).
cp "$ROOT/assets/fonts/Jersey10-OFL.txt" "$ROOT/assets/fonts/Silkscreen-OFL.txt" "$dist/licenses/"
if has_feature image; then
	targets+=(images)
	build_target images "$ROOT/examples/images"
	bundle SDL3_image SDL3_image
fi
if has_feature text; then
	targets+=(text)
	build_target text "$ROOT/examples/text"
	bundle SDL3_ttf SDL3_ttf freetype
	cp "$ROOT/assets/fonts/OFL.txt" "$dist/licenses/PressStart2P-OFL.txt"
fi
cp -R "$ROOT/assets" "$dist/assets"
cp "$ROOT/LICENSE" "$dist/licenses/starter-LICENSE.txt"

# Launch check: different working directory, no custom loader paths.
check_dir="$(mktemp -d)"
trap 'rm -rf "$check_dir"' EXIT
sdl_version="$(lock_get "d['sdl3']['version']")"
for target in "${targets[@]}"; do
	log "launch check: $target"
	(
		cd "$check_dir"
		env -u LD_LIBRARY_PATH -u DYLD_LIBRARY_PATH -u DYLD_FALLBACK_LIBRARY_PATH \
			SDL_VIDEO_DRIVER=dummy SDL_RENDER_DRIVER=software SDL_AUDIO_DRIVER=dummy \
			"$dist/$target" --frames=10 > launch.log 2>&1 || { cat launch.log; die "packaged $target failed to run"; }
		grep -q "SDL.* $sdl_version" launch.log || { cat launch.log; die "packaged $target did not load the locked SDL3"; }
	)
	if [[ "$OS" == linux ]]; then
		# Every SDL library must resolve to the bundled copy.
		while read -r name path; do
			[[ "$path" == "$dist/$name" ]] || die "$target: $name resolved to $path, expected the bundled copy"
		done < <(ldd "$dist/$target" | awk '/libSDL3/ {print $1, $3}')
	fi
done
log "packaged ${targets[*]} in $dist"
