#!/usr/bin/env bash
# Builds the locked native dependencies into third_party/prefix/<os>-<arch>.
#
# Usage: scripts/bootstrap.sh [--with-odin] [--with-image] [--with-text] [--all-features] [--force]
#   --with-odin     download the locked Odin release into third_party/odin/<os>-<arch>
#   --with-image    also build SDL3_image (examples/images)
#   --with-text     also build FreeType + SDL3_ttf (examples/text)
#   --all-features  same as --with-image --with-text
#   --force         rebuild everything even if install stamps match the lock
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

with_odin=0
force=0
features=()
for arg in "$@"; do
	case "$arg" in
	--with-odin)    with_odin=1 ;;
	--with-image)   features+=(image) ;;
	--with-text)    features+=(text) ;;
	--all-features) features+=(image text) ;;
	--force)        force=1 ;;
	*)              die "unknown option: $arg" ;;
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

# --- Native packages ----------------------------------------------------------

# build_package <lock key>: download, verify, configure, build and install one
# CMake package from the lock. Returns 1 if it was already up to date.
build_package() {
	local key="$1" version stamp want url sum archive src build_dir opt
	version="$(lock_get "d['$key']['version']")"
	stamp="$PREFIX/.lock-$key"
	want="$(lock_get "json.dumps(d['$key'], sort_keys=True)")"
	if [[ $force -eq 0 && $chain_rebuild -eq 0 && -f "$stamp" && "$(cat "$stamp")" == "$want" ]]; then
		log "$key $version already installed"
		return 1
	fi

	url="$(lock_get "d['$key']['archive']['url']")"
	sum="$(lock_get "d['$key']['archive']['sha256']")"
	archive="$ROOT/third_party/src/$(basename "$url")"
	fetch_verified "$url" "$sum" "$archive"

	src="$ROOT/third_party/src/$(lock_get "d['$key']['dir']")"
	rm -rf "$src"
	tar -xzf "$archive" -C "$ROOT/third_party/src"

	build_dir="$ROOT/third_party/build/$key-$TARGET"
	rm -rf "$build_dir"
	local opts=()
	while read -r opt; do opts+=("$opt"); done < <(lock_get "d['$key']['cmake_options']['common'] + d['$key']['cmake_options']['$OS']")

	log "configuring $key $version"
	cmake -S "$src" -B "$build_dir" -G Ninja "${opts[@]}" \
		-DCMAKE_INSTALL_PREFIX="$PREFIX" \
		-DCMAKE_PREFIX_PATH="$PREFIX" \
		-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON \
		-DCMAKE_INSTALL_LIBDIR=lib
	log "building $key $version"
	cmake --build "$build_dir"
	BUILT_DIR="$build_dir"
	BUILT_SRC="$src"
	BUILT_STAMP="$stamp"
	BUILT_WANT="$want"
	return 0
}

finish_package() { # <lock key>
	local file
	cmake --install "$BUILT_DIR"
	# Packages that do not install their own license texts list them in the lock.
	while read -r file; do
		[[ -z "$file" ]] && continue
		mkdir -p "$PREFIX/share/licenses/$1"
		cp "$BUILT_SRC/$file" "$PREFIX/share/licenses/$1/"
	done < <(lock_get "d['$1'].get('license_files', [])")
	echo "$BUILT_WANT" > "$BUILT_STAMP"
	log "installed $1 $(lock_get "d['$1']['version']") to $PREFIX"
}

# Fails if an installed shared library links a dependency the lock forbids
# (e.g. a system FreeType or libpng picked up instead of the locked/built-in one).
check_links() { # <lock key> <library base name>
	local key="$1" name="$2" lib deps bad
	case "$OS" in
	linux) lib="$PREFIX/lib/lib$name.so";    deps="$(ldd "$lib")" ;;
	macos) lib="$PREFIX/lib/lib$name.dylib"; deps="$(otool -L "$lib")" ;;
	esac
	while read -r bad; do
		[[ -z "$bad" ]] && continue
		if grep -qi "lib$bad" <<< "$deps"; then
			echo "$deps" >&2
			die "$lib links forbidden dependency '$bad'"
		fi
	done < <(lock_get "d['$key']['must_not_link']")
	echo "    links ok: lib$name"
}

chain_rebuild=0

# SDL3. Rebuilding it wipes the prefix, so every dependent package rebuilds too.
if build_package sdl3; then
	rm -rf "$PREFIX"

	# Verify the backends the starter relies on were actually compiled in.
	config="$(find "$BUILT_DIR" -name SDL_build_config.h -print -quit)"
	[[ -n "$config" ]] || die "SDL_build_config.h not found in $BUILT_DIR"
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

	finish_package sdl3
fi

for feature in ${features[@]+"${features[@]}"}; do
	# Packages are listed in dependency order; once one rebuilds, the rest must too
	# (e.g. SDL3_ttf links FreeType statically).
	chain_rebuild=0
	while read -r key; do
		if build_package "$key"; then
			finish_package "$key"
			chain_rebuild=1
		fi
	done < <(lock_get "d['features']['$feature']['packages']")
	case "$feature" in
	image) check_links sdl3_image SDL3_image ;;
	text)  check_links sdl3_ttf SDL3_ttf ;;
	esac
done
