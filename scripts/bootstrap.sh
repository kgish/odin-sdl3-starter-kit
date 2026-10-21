#!/usr/bin/env bash
# Builds the locked SDL3 release into third_party/prefix/<os>-<arch>.
#
# Usage: scripts/bootstrap.sh [--with-odin] [--force]
#   --with-odin  download the locked Odin release into third_party/odin/<os>-<arch>
#   --force      rebuild SDL3 even if the install stamp matches the lock
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

with_odin=0
force=0
for arg in "$@"; do
	case "$arg" in
	--with-odin) with_odin=1 ;;
	--force)     force=1 ;;
	*)           die "unknown option: $arg" ;;
	esac
done

log "host: $TARGET"
for tool in curl tar cmake ninja python3; do
	command -v "$tool" >/dev/null || die "missing required tool: $tool (see docs/dependencies.md)"
done
command -v cc >/dev/null || command -v clang >/dev/null || die "missing C compiler (see docs/dependencies.md)"

# --- Odin -------------------------------------------------------------------

if [[ $with_odin -eq 1 ]]; then
	url="$(lock_get "d['odin']['archives']['$TARGET']['url']")" || die "no locked Odin archive for $TARGET"
	sum="$(lock_get "d['odin']['archives']['$TARGET']['sha256']")"
	archive="$ROOT/third_party/src/$(basename "$url")"
	fetch_verified "$url" "$sum" "$archive"
	dest="$ROOT/third_party/odin/$TARGET"
	rm -rf "$dest"
	mkdir -p "$dest"
	tar -xzf "$archive" -C "$dest" --strip-components=1
fi

require_odin
log "odin: $ODIN_BIN ($("$ODIN_BIN" version))"

# --- SDL3 -------------------------------------------------------------------

version="$(lock_get "d['sdl3']['version']")"
stamp="$PREFIX/.sdl3-lock"
want_stamp="$(lock_get "json.dumps(d['sdl3'], sort_keys=True)")"

if [[ $force -eq 0 && -f "$stamp" && "$(cat "$stamp")" == "$want_stamp" ]]; then
	log "SDL3 $version already installed in $PREFIX"
else
	url="$(lock_get "d['sdl3']['archive']['url']")"
	sum="$(lock_get "d['sdl3']['archive']['sha256']")"
	archive="$ROOT/third_party/src/$(basename "$url")"
	fetch_verified "$url" "$sum" "$archive"

	src="$ROOT/third_party/src/SDL3-$version"
	rm -rf "$src"
	tar -xzf "$archive" -C "$ROOT/third_party/src"

	build_dir="$ROOT/third_party/build/sdl3-$TARGET"
	rm -rf "$build_dir" "$PREFIX"
	opts=()
	while read -r opt; do opts+=("$opt"); done < <(lock_get "d['sdl3']['cmake_options']['common'] + d['sdl3']['cmake_options']['$OS']")

	log "configuring SDL3 $version"
	cmake -S "$src" -B "$build_dir" -G Ninja "${opts[@]}" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_INSTALL_LIBDIR=lib
	log "building SDL3 $version"
	cmake --build "$build_dir"

	# Verify the backends the starter relies on were actually compiled in.
	config="$(find "$build_dir" -name SDL_build_config.h -print -quit)"
	[[ -n "$config" ]] || die "SDL_build_config.h not found in $build_dir"
	missing=0
	while read -r requirement; do
		found=0
		IFS='|' read -ra alternatives <<< "$requirement"
		for define in "${alternatives[@]}"; do
			if grep -Eq "^#define $define 1" "$config"; then found=1; fi
		done
		if [[ $found -eq 1 ]]; then
			echo "    backend ok: $requirement"
		else
			echo "    backend MISSING: $requirement" >&2
			missing=1
		fi
	done < <(lock_get "d['sdl3']['required_defines']['$OS']")
	[[ $missing -eq 0 ]] || die "required SDL backends missing; install their development packages (docs/dependencies.md) and rerun with --force"

	cmake --install "$build_dir"
	echo "$want_stamp" > "$stamp"
	log "installed SDL3 $version to $PREFIX"
fi
