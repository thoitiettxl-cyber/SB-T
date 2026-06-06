#!/system/bin/sh
# Downloads IPSET kernel modules from TanakaLun/IPSET_LKM GitHub releases.
# Usage: upipset.sh [--force]
#
# Source: https://github.com/TanakaLun/IPSET_LKM
# Supported kernels: 5.10 / 5.15 / 6.1 / 6.6 / 6.12
# NOTE: Download is TLS-only; upstream publishes no checksums. Run over trusted network only.

box_dir="/data/adb/box"
ipset_lkm_dir="${box_dir}/bin/IPSET-LKM"
log_file="${box_dir}/run/runs.log"
gh_repo="TanakaLun/IPSET_LKM"

# M-1: resolve absolute path so box.tool is never sourced from an attacker-controlled CWD
SCRIPTS_DIR="$(cd "${0%/*}" 2>/dev/null && pwd)" || SCRIPTS_DIR="/data/adb/box/scripts"
. "${SCRIPTS_DIR}/box.tool"

log() { printf '%s [upipset] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" | tee -a "$log_file"; }

# L-3: initialize before trap so _cleanup is always safe even if mktemp never ran
tmp_json="" tmp_zip="" tmp_extract=""
_cleanup() { rm -f "$tmp_json" "$tmp_zip" 2>/dev/null; rm -rf "$tmp_extract" 2>/dev/null; }
trap _cleanup EXIT INT TERM

# M-3: prefer box_dir/run (root-owned) to eliminate TOCTOU symlink race in world-writable dirs
_tmpdir() {
    for d in "${box_dir}/run" /data/local/tmp /tmp; do
        mkdir -p "$d" 2>/dev/null && echo "$d" && return 0
    done
    return 1
}

_download() {
    local url="$1" dest="$2"
    if command -v curl > /dev/null 2>&1; then
        curl -fsSL -L --connect-timeout 20 --retry 2 "$url" -o "$dest"
    else
        $busybox wget -q -T 20 -t 2 -O "$dest" "$url"
    fi
}

kver=$(uname -r | command grep -oE '^[0-9]+\.[0-9]+')
# B-1: validate kver — empty kver would make zip_url grep match any .zip in the release
[ -n "$kver" ] || { log "FAILED: Cannot determine kernel version from uname -r"; exit 1; }
dest_dir="${ipset_lkm_dir}/netfilter/${kver}"

if [ -d "$dest_dir" ] && [ "${1:-}" != "--force" ]; then
    log "LKMs for kernel ${kver} already at ${dest_dir} (--force to re-download)"
    exit 0
fi

log "Fetching latest release from github.com/${gh_repo}..."
_td=$(_tmpdir) || { log "FAILED: no writable temp directory"; exit 1; }
tmp_json=$($busybox mktemp "${_td}/upipset_XXXXXX") || { log "FAILED: mktemp"; exit 1; }
if ! _download "https://api.github.com/repos/${gh_repo}/releases/latest" "$tmp_json" 2>/dev/null; then
    log "FAILED: GitHub API unreachable"
    exit 1
fi

tag=$(sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' "$tmp_json" | head -1)
# Require kver to be followed by a non-digit to avoid 6.1 matching 6.12 (substring collision)
zip_url=$(command grep -oE '"browser_download_url": *"[^"]*'"${kver}"'[^0-9][^"]*\.zip"' "$tmp_json" \
          | command grep -oE '"https://[^"]*"' | tr -d '"' | head -1)
rm -f "$tmp_json"; tmp_json=""

if [ -z "$tag" ]; then
    log "FAILED: Could not parse release tag from GitHub API"
    exit 1
fi
if [ -z "$zip_url" ]; then
    log "Kernel ${kver} not found in release ${tag}. Supported: 5.10 5.15 6.1 6.6 6.12"
    exit 1
fi

log "Release ${tag}: downloading LKMs for kernel ${kver}..."
tmp_zip=$($busybox mktemp "${_td}/upipset_XXXXXX") || { log "FAILED: mktemp"; exit 1; }
tmp_extract=$($busybox mktemp -d "${_td}/upipset_XXXXXX") || { log "FAILED: mktemp -d"; exit 1; }
if ! _download "$zip_url" "$tmp_zip"; then
    log "FAILED: Download ${zip_url}"
    exit 1
fi

# M-2: scan for path traversal AND absolute-path entries (busybox unzip behavior is version-dependent)
# Filter 'Archive:' header line first — it contains the tmp zip path which would false-positive the / check
if $busybox unzip -l "$tmp_zip" 2>/dev/null | command grep -v '^Archive:' | command grep -qE '(\.\.(/|$)|[[:space:]]/[^[:space:]])'; then
    log "FAILED: zip contains path traversal or absolute-path entries"
    exit 1
fi

if ! $busybox unzip -qo "$tmp_zip" -d "$tmp_extract" 2>/dev/null; then
    log "FAILED: Cannot extract zip"
    exit 1
fi
rm -f "$tmp_zip"; tmp_zip=""

if [ ! -d "${tmp_extract}/netfilter" ]; then
    log "FAILED: zip does not contain netfilter/ directory"
    exit 1
fi

# No symlinks in extracted content (defense against symlink Zip Slip variants)
if command find "$tmp_extract" -type l 2>/dev/null | command grep -q .; then
    log "FAILED: zip contains symlinks"
    exit 1
fi

mkdir -p "${dest_dir}"
# H-2: use cp -rf (not -af) then explicit chmod to strip any setuid/setgid bits from zip contents
if ! cp -rf "${tmp_extract}/netfilter/." "${dest_dir}/"; then
    log "FAILED: Could not install LKMs to ${dest_dir}"
    exit 1
fi
command find "${dest_dir}" -type f -exec chmod 644 {} \;
command find "${dest_dir}" -type d -exec chmod 755 {} \;
rm -rf "$tmp_extract"; tmp_extract=""

log "All LKMs for kernel ${kver} installed to ${dest_dir}"
log "On next reboot, ipset.sh will load them automatically."
log "To load now without reboot: /data/adb/box/scripts/ipset.sh load"
