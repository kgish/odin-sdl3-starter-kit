# Shared helpers for the Unix scripts. Source this file; do not execute it.
# Requires: python3 (lock parsing), uname.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$ROOT/deps.lock.json"

die() { echo "error: $*" >&2; exit 1; }
log() { echo "==> $*"; }

host_os() {
	case "$(uname -s)" in
	Linux)  echo linux ;;
	Darwin) echo macos ;;
	*)      die "unsupported host OS: $(uname -s) (use the .ps1 scripts on Windows)" ;;
	esac
}

host_arch() {
	case "$(uname -m)" in
	x86_64|amd64)  echo amd64 ;;
	arm64|aarch64) echo arm64 ;;
	*)             die "unsupported host architecture: $(uname -m)" ;;
	esac
}

OS="$(host_os)"
ARCH="$(host_arch)"
TARGET="$OS-$ARCH"
PREFIX="$ROOT/third_party/prefix/$TARGET"
BUILD="$ROOT/build"

# lock_get <python expression on `d`>, e.g. lock_get "d['sdl3']['version']"
lock_get() {
	python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); v=$1; print('\n'.join(v) if isinstance(v,list) else v)" "$LOCK"
}

# Resolve the locked Odin compiler: project-local download first, then $ODIN, then PATH.
# The candidate must report the locked commit.
resolve_odin() {
	local commit short candidate
	commit="$(lock_get "d['odin']['commit']")"
	short="${commit:0:7}"
	for candidate in "$ROOT/third_party/odin/$TARGET/odin" "${ODIN:-}" "$(command -v odin || true)"; do
		[[ -n "$candidate" && -x "$candidate" ]] || continue
		if "$candidate" version | grep -q ":$short"; then
			echo "$candidate"
			return 0
		fi
	done
	return 1
}

require_odin() {
	ODIN_BIN="$(resolve_odin)" || die "no Odin compiler at locked commit $(lock_get "d['odin']['commit']" | cut -c1-7); run scripts/bootstrap.sh --with-odin"
	export ODIN_BIN
}

require_sdl() {
	[[ -d "$PREFIX/lib" ]] || die "locked SDL3 not found in $PREFIX; run scripts/bootstrap.sh"
}

# Linker flags that point the Odin build at the project-local SDL3.
# Dev builds embed an absolute rpath; package.sh rewrites it to a relative one.
sdl_link_flags() {
	echo "-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"
}

sha256_of() {
	if command -v sha256sum >/dev/null; then sha256sum "$1" | cut -d' ' -f1
	else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# fetch_verified <url> <sha256> <dest-file>
fetch_verified() {
	local url="$1" want="$2" dest="$3" got
	if [[ ! -f "$dest" ]]; then
		log "downloading $url"
		mkdir -p "$(dirname "$dest")"
		curl -fsSL -o "$dest.part" "$url"
		mv "$dest.part" "$dest"
	fi
	got="$(sha256_of "$dest")"
	if [[ "$got" != "$want" ]]; then
		rm -f "$dest"
		die "checksum mismatch for $url: expected $want, got $got"
	fi
}
