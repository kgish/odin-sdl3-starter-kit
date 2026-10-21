#!/usr/bin/env bash
# Resolves the newest *stable* Odin, SDL3, SDL3_image, SDL3_ttf and FreeType
# releases and rewrites deps.lock.json with their tags, commits and archive
# checksums. Build options are left untouched.
# This is the only script that follows "latest"; review the diff, then run
# scripts/bootstrap.sh --force and the full test suite.
#
# Usage: scripts/update-deps.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

for tool in curl git python3; do
	command -v "$tool" >/dev/null || die "missing required tool: $tool"
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

latest_tag() { # GitHub's "latest" excludes drafts and prereleases
	curl -fsSL "https://api.github.com/repos/$1/releases/latest" | python3 -I -c "import json,sys; print(json.load(sys.stdin)['tag_name'])"
}
# Commit a tag points to: the peeled "^{}" entry for annotated tags, else the tag ref.
tag_commit() { # repo-url tag
	git ls-remote "$1" "refs/tags/$2" "refs/tags/$2^{}" |
		awk '$2 ~ /\^\{\}$/ { peeled = $1 } { any = $1 } END { print (peeled ? peeled : any) }'
}
archive_sum() {
	curl -fsSL -o "$work/archive" "$1"
	sha256_of "$work/archive"
}

# Prints "<tag> <version> <commit> <url> <sha256>" for an SDL-family release.
sdl_family() { # repo archive-prefix
	local tag version
	tag="$(latest_tag "libsdl-org/$1")"
	version="${tag#release-}"
	local url="https://github.com/libsdl-org/$1/releases/download/$tag/$2-$version.tar.gz"
	log "$1 $version: hashing $url" >&2
	echo "$tag $version $(tag_commit "https://github.com/libsdl-org/$1" "$tag") $url $(archive_sum "$url")"
}

# FreeType is not released on GitHub: take the newest x.y.z tarball from the
# savannah listing and its VER-x-y-z tag from the freedesktop repository.
freetype_release() {
	local version tag url commit
	version="$(curl -fsSL https://download.savannah.gnu.org/releases/freetype/ |
		grep -oE 'freetype-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz' | sed -E 's/^freetype-|\.tar\.gz$//g' |
		sort -u -V | tail -n1)"
	[[ -n "$version" ]] || die "could not find a FreeType release"
	tag="VER-${version//./-}"
	url="https://download.savannah.gnu.org/releases/freetype/freetype-$version.tar.gz"
	commit="$(tag_commit https://gitlab.freedesktop.org/freetype/freetype.git "$tag")"
	[[ -n "$commit" ]] || die "FreeType tag $tag not found"
	log "FreeType $version: hashing $url" >&2
	echo "$tag $version $commit $url $(archive_sum "$url")"
}

odin_tag="$(latest_tag odin-lang/Odin)"
odin_commit="$(tag_commit https://github.com/odin-lang/Odin "$odin_tag")"
log "Odin $odin_tag"

odin_archives="{}"
for target in linux-amd64 linux-arm64 macos-arm64 windows-amd64; do
	ext="tar.gz"; [[ "$target" == windows-* ]] && ext="zip"
	url="https://github.com/odin-lang/Odin/releases/download/$odin_tag/odin-$target-$odin_tag.$ext"
	log "hashing $url"
	sum="$(archive_sum "$url")"
	odin_archives="$(python3 -I -c "import json,sys; a=json.loads(sys.argv[1]); a[sys.argv[2]]={'url':sys.argv[3],'sha256':sys.argv[4]}; print(json.dumps(a))" "$odin_archives" "$target" "$url" "$sum")"
done

# Plain assignments, so a failed lookup stops the script (set -e).
sdl3="$(sdl_family SDL SDL3)"
sdl3_image="$(sdl_family SDL_image SDL3_image)"
sdl3_ttf="$(sdl_family SDL_ttf SDL3_ttf)"
freetype="$(freetype_release)"

python3 -I - "$LOCK" "$odin_tag" "$odin_commit" "$odin_archives" \
	"sdl3=$sdl3" "sdl3_image=$sdl3_image" "sdl3_ttf=$sdl3_ttf" "freetype=$freetype" <<'EOF'
import datetime, json, sys
path, odin_tag, odin_commit, odin_archives, *packages = sys.argv[1:]
d = json.load(open(path))
d["resolved_on"] = datetime.date.today().isoformat()
d["odin"].update(tag=odin_tag, commit=odin_commit, archives=json.loads(odin_archives))
for entry in packages:
    key, fields = entry.split("=", 1)
    tag, version, commit, url, sha = fields.split()
    prefix = url.rsplit("/", 1)[1].removesuffix(".tar.gz")
    d[key].update(tag=tag, version=version, commit=commit, dir=prefix, archive={"url": url, "sha256": sha})
with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
EOF
log "updated $LOCK; check odin.sdl3*_binding_headers against the new compiler's vendor/sdl3 sources"
