#!/bin/sh
# Verify one private/public GitHub release and its Magisk ZIP without printing
# credentials. Usage: check-github-release.sh v1.3.4
set -eu

tag="${1:-}"
printf '%s\n' "$tag" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' || {
    printf 'Usage: %s vMAJOR.MINOR.PATCH\n' "$0" >&2
    exit 2
}

remote=$(git config --get remote.origin.url)
repo=$(printf '%s\n' "$remote" | sed -n 's#^https://github.com/\([^/]*\/[^/]*\)\(.git\)\{0,1\}$#\1#p')
[ -n "$repo" ] || {
    printf 'Cannot derive GitHub repository from origin: %s\n' "$remote" >&2
    exit 2
}
repo=${repo%.git}

token="${GITHUB_TOKEN:-}"
username="x-access-token"
if [ -z "$token" ]; then
    credentials=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill 2>/dev/null || true)
    token=$(printf '%s\n' "$credentials" | sed -n 's/^password=//p' | head -1)
    username=$(printf '%s\n' "$credentials" | sed -n 's/^username=//p' | head -1)
    [ -n "$username" ] || username="x-access-token"
    credentials=""
fi

tmp_json=$(mktemp)
tmp_zip=$(mktemp)
tmp_netrc=$(mktemp)
trap 'rm -f "$tmp_json" "$tmp_zip" "$tmp_netrc"' EXIT INT TERM
chmod 0600 "$tmp_json" "$tmp_zip" "$tmp_netrc"
if [ -n "$token" ]; then
    printf 'machine api.github.com login %s password %s\n' "$username" "$token" > "$tmp_netrc"
fi

download() {
    local url="$1" destination="$2" accept="${3:-application/vnd.github+json}"
    if [ -n "$token" ]; then
        curl -fsSL --netrc-file "$tmp_netrc" -H "Accept: ${accept}" \
            -H "X-GitHub-Api-Version: 2022-11-28" "$url" -o "$destination"
    else
        curl -fsSL -H "Accept: ${accept}" -H "X-GitHub-Api-Version: 2022-11-28" \
            "$url" -o "$destination"
    fi
}

api="https://api.github.com/repos/${repo}/releases/tags/${tag}"
download "$api" "$tmp_json"

[ "$(jq -r '.tag_name' "$tmp_json")" = "$tag" ] || {
    printf 'Release tag mismatch\n' >&2
    exit 1
}
[ "$(jq -r '.draft' "$tmp_json")" = "false" ] || {
    printf 'Release is still a draft\n' >&2
    exit 1
}
[ "$(jq -r '.prerelease' "$tmp_json")" = "false" ] || {
    printf 'Release is marked prerelease\n' >&2
    exit 1
}

asset_name="SB_Tproxy_${tag}.zip"
asset_url=$(jq -r --arg name "$asset_name" '.assets[] | select(.name == $name) | .url' "$tmp_json" | head -1)
[ -n "$asset_url" ] && [ "$asset_url" != "null" ] || {
    printf 'Release asset missing: %s\n' "$asset_name" >&2
    exit 1
}
download "$asset_url" "$tmp_zip" application/octet-stream
unzip -tq "$tmp_zip" >/dev/null
unzip -Z1 "$tmp_zip" | grep -qx 'box/scripts/ipset.sh'
unzip -Z1 "$tmp_zip" | grep -qx 'box/scripts/upipset.sh'
unzip -p "$tmp_zip" module.prop | tr -d '\r' | grep -qx "version=${tag}"

sha=$(sha256sum "$tmp_zip" | awk '{print $1}')
size=$(wc -c < "$tmp_zip" | tr -d ' ')
printf 'release=%s\nasset=%s\nsize=%s\nsha256=%s\nstatus=PASS\n' \
    "$tag" "$asset_name" "$size" "$sha"
token=""
username=""
