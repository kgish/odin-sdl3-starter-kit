#!/usr/bin/env bash
# Resolves the newest *stable* Odin and SDL3 releases and rewrites
# deps.lock.json with their tags, commits and archive checksums.
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
tag_commit() {
	git ls-remote "https://github.com/$1" "refs/tags/$2^{}" "refs/tags/$2" | head -n1 | cut -f1
}
archive_sum() {
	curl -fsSL -o "$work/archive" "$1"
	sha256_of "$work/archive"
}

odin_tag="$(latest_tag odin-lang/Odin)"
sdl_tag="$(latest_tag libsdl-org/SDL)"
sdl_version="${sdl_tag#release-}"
log "Odin $odin_tag, SDL3 $sdl_version"

odin_commit="$(tag_commit odin-lang/Odin "$odin_tag")"
sdl_commit="$(tag_commit libsdl-org/SDL "$sdl_tag")"
sdl_url="https://github.com/libsdl-org/SDL/releases/download/$sdl_tag/SDL3-$sdl_version.tar.gz"
sdl_sum="$(archive_sum "$sdl_url")"

odin_archives="{}"
for target in linux-amd64 linux-arm64 macos-arm64 windows-amd64; do
	ext="tar.gz"; [[ "$target" == windows-* ]] && ext="zip"
	url="https://github.com/odin-lang/Odin/releases/download/$odin_tag/odin-$target-$odin_tag.$ext"
	log "hashing $url"
	sum="$(archive_sum "$url")"
	odin_archives="$(python3 -I -c "import json,sys; a=json.loads(sys.argv[1]); a[sys.argv[2]]={'url':sys.argv[3],'sha256':sys.argv[4]}; print(json.dumps(a))" "$odin_archives" "$target" "$url" "$sum")"
done

python3 -I - "$LOCK" "$odin_tag" "$odin_commit" "$odin_archives" "$sdl_tag" "$sdl_version" "$sdl_commit" "$sdl_url" "$sdl_sum" <<'PY'
import datetime, json, sys
path, odin_tag, odin_commit, odin_archives, sdl_tag, sdl_version, sdl_commit, sdl_url, sdl_sum = sys.argv[1:]
d = json.load(open(path))
d["resolved_on"] = datetime.date.today().isoformat()
d["odin"].update(tag=odin_tag, commit=odin_commit, archives=json.loads(odin_archives))
d["sdl3"].update(tag=sdl_tag, version=sdl_version, commit=sdl_commit, archive={"url": sdl_url, "sha256": sdl_sum})
with open(path, "w") as f:
    json.dump(d, f, indent=2)
    f.write("\n")
PY
log "updated $LOCK; check odin.sdl3_binding_headers against the new compiler's vendor/sdl3/sdl3_version.odin"
