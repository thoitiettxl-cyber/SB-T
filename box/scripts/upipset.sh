#!/system/bin/sh
# Download and stage TanakaLun/IPSET_LKM. The GitHub Release digest and archive
# shape are verified before any module-owned file is replaced.

box_dir="${SB_BOX_DIR:-/data/adb/box}"
ipset_lkm_dir="${SB_IPSET_LKM_DIR:-${box_dir}/bin/IPSET-LKM}"
log_file="${SB_LOG_FILE:-${box_dir}/run/runs.log}"
gh_repo="TanakaLun/IPSET_LKM"
release_api="${SB_IPSET_RELEASE_API:-https://api.github.com/repos/${gh_repo}/releases/latest}"
kernel_release="${SB_KERNEL_RELEASE:-$(uname -r)}"
modinfo_bin="${SB_MODINFO_BIN:-modinfo}"

SCRIPTS_DIR="$(cd "${0%/*}" 2>/dev/null && pwd)" || SCRIPTS_DIR="/data/adb/box/scripts"
. "${SCRIPTS_DIR}/box.tool"

log() {
    local line
    line="$(date '+%Y-%m-%d %H:%M:%S') [upipset] $*"
    printf '%s\n' "$line"
    mkdir -p "${log_file%/*}" 2>/dev/null || true
    printf '%s\n' "$line" >> "$log_file" 2>/dev/null || true
}

tmp_json=""
tmp_zip=""
tmp_extract=""
stage_root=""
backup_root=""
lock_dir=""

cleanup() {
    [ -n "$tmp_json" ] && rm -f "$tmp_json" 2>/dev/null
    [ -n "$tmp_zip" ] && rm -f "$tmp_zip" 2>/dev/null
    [ -n "$tmp_extract" ] && rm -rf "$tmp_extract" 2>/dev/null
    [ -n "$stage_root" ] && rm -rf "$stage_root" 2>/dev/null
    [ -n "$backup_root" ] && rm -rf "$backup_root" 2>/dev/null
    [ -n "$lock_dir" ] && rmdir "$lock_dir" 2>/dev/null
}
trap cleanup EXIT
trap 'exit 130' INT TERM

temp_parent() {
    local directory
    for directory in "${box_dir}/run" /data/local/tmp /tmp; do
        if mkdir -p "$directory" 2>/dev/null && [ -d "$directory" ] && [ -w "$directory" ]; then
            printf '%s\n' "$directory"
            return 0
        fi
    done
    return 1
}

download() {
    local url="$1" destination="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -L --connect-timeout 20 --retry 2 "$url" -o "$destination"
    else
        "$busybox" wget -q -T 20 -t 2 -O "$destination" "$url"
    fi
}

sha256_file() {
    if [ -x "$busybox" ]; then
        "$busybox" sha256sum "$1" | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        return 1
    fi
}

module_release() {
    local module="$1" vermagic
    vermagic=$("$modinfo_bin" -F vermagic "$module" 2>/dev/null) || vermagic=""
    if [ -z "$vermagic" ] && [ -x /system/bin/modinfo ]; then
        vermagic=$(/system/bin/modinfo -F vermagic "$module" 2>/dev/null) || vermagic=""
    fi
    if [ -z "$vermagic" ] && [ -x "$busybox" ]; then
        vermagic=$("$busybox" modinfo -F vermagic "$module" 2>/dev/null) || vermagic=""
    fi
    [ -n "$vermagic" ] || return 1
    printf '%s\n' "${vermagic%% *}"
}

kernel_series=$(printf '%s\n' "$kernel_release" | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p')
case "$kernel_series" in
    5.10) asset_name="IPSET-LKM-android12-5.10.zip" ;;
    5.15) asset_name="IPSET-LKM-android13-5.15.zip" ;;
    6.1)  asset_name="IPSET-LKM-android14-6.1.zip" ;;
    6.6)  asset_name="IPSET-LKM-android15-6.6.zip" ;;
    6.12) asset_name="IPSET-LKM-android16-6.12-Mi.zip" ;;
    *)
        log "FAILED: unsupported kernel series '${kernel_series:-unknown}' (${kernel_release})"
        exit 1
        ;;
esac

case "${1:-}" in
    ""|--force) ;;
    *)
        log "FAILED: usage: upipset.sh [--force]"
        exit 1
        ;;
esac

dest_dir="${ipset_lkm_dir}/netfilter/${kernel_series}"
loader_path="${ipset_lkm_dir}/ko-loader"
manifest_path="${ipset_lkm_dir}/manifest-${kernel_series}.ini"

if [ "${1:-}" != "--force" ] && [ -d "$dest_dir" ] && [ -x "$loader_path" ]; then
    log "Bundle already installed at ${dest_dir}; use --force to refresh"
    "${SCRIPTS_DIR}/ipset.sh" status || true
    exit 0
fi

mkdir -p "$ipset_lkm_dir" "${ipset_lkm_dir}/netfilter" "${box_dir}/run" || {
    log "FAILED: cannot create module-owned directories"
    exit 1
}
lock_dir="${ipset_lkm_dir}/.update.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
    log "FAILED: another IPSET update is active (${lock_dir})"
    exit 1
fi

tmp_parent=$(temp_parent) || {
    log "FAILED: no writable temporary directory"
    exit 1
}
tmp_json=$("$busybox" mktemp "${tmp_parent}/upipset_json_XXXXXX") || {
    log "FAILED: cannot create release metadata file"
    exit 1
}

log "Fetching release metadata from github.com/${gh_repo}"
if ! download "$release_api" "$tmp_json"; then
    log "FAILED: GitHub Release API is unreachable"
    exit 1
fi

tag=$(awk -F'"' '/^[[:space:]]*"tag_name"[[:space:]]*:/ {print $4; exit}' "$tmp_json")
case "$tag" in
    ""|*[!A-Za-z0-9._-]*)
        log "FAILED: invalid release tag in GitHub response"
        exit 1
        ;;
esac

asset_record=$(awk -F'"' -v wanted="$asset_name" '
    /^[[:space:]]*"name"[[:space:]]*:/ { name=$4; digest="" }
    /^[[:space:]]*"digest"[[:space:]]*:/ { digest=$4 }
    /^[[:space:]]*"browser_download_url"[[:space:]]*:/ {
        if (name == wanted) {
            print $4 "|" digest
            exit
        }
    }
' "$tmp_json")
zip_url=$(printf '%s\n' "$asset_record" | awk -F'|' '{print $1}')
digest=$(printf '%s\n' "$asset_record" | awk -F'|' '{print $2}')
expected_url="https://github.com/${gh_repo}/releases/download/${tag}/${asset_name}"
if [ -z "$asset_record" ] || [ "$zip_url" != "$expected_url" ]; then
    log "FAILED: release ${tag} does not contain trusted asset ${asset_name}"
    exit 1
fi

case "$digest" in
    sha256:*) expected_sha=${digest#sha256:} ;;
    *)
        log "FAILED: GitHub did not publish a SHA-256 digest for ${asset_name}"
        exit 1
        ;;
esac
case "$expected_sha" in
    *[!0-9a-fA-F]*)
        log "FAILED: malformed SHA-256 digest for ${asset_name}"
        exit 1
        ;;
esac
if [ "${#expected_sha}" -ne 64 ]; then
    log "FAILED: malformed SHA-256 digest length for ${asset_name}"
    exit 1
fi

tmp_zip=$("$busybox" mktemp "${tmp_parent}/upipset_zip_XXXXXX") || {
    log "FAILED: cannot create archive file"
    exit 1
}
tmp_extract=$("$busybox" mktemp -d "${tmp_parent}/upipset_extract_XXXXXX") || {
    log "FAILED: cannot create extraction directory"
    exit 1
}

log "Release ${tag}: downloading ${asset_name}"
if ! download "$zip_url" "$tmp_zip"; then
    log "FAILED: cannot download ${zip_url}"
    exit 1
fi
actual_sha=$(sha256_file "$tmp_zip") || {
    log "FAILED: no SHA-256 implementation is available"
    exit 1
}
if [ "$actual_sha" != "$expected_sha" ]; then
    log "FAILED: SHA-256 mismatch for ${asset_name}"
    exit 1
fi
log "SHA-256 verified: ${actual_sha}"

if ! "$busybox" unzip -lq "$tmp_zip" 2>/dev/null \
    | awk 'NR > 2 { if ($0 ~ /^[[:space:]]*-+/) exit; print substr($0, 31) }' \
    > "$tmp_json"; then
    log "FAILED: cannot inspect archive paths"
    exit 1
fi
while IFS= read -r archive_path; do
    case "$archive_path" in
        ""|/*|*\\*|[A-Za-z]:*)
            log "FAILED: archive contains unsafe path '${archive_path}'"
            exit 1
            ;;
    esac
    case "/${archive_path}/" in
        */../*)
            log "FAILED: archive contains traversal path '${archive_path}'"
            exit 1
            ;;
    esac
done < "$tmp_json"
if ! "$busybox" unzip -qo "$tmp_zip" -d "$tmp_extract" 2>/dev/null; then
    log "FAILED: cannot extract ${asset_name}"
    exit 1
fi
if find "$tmp_extract" -type l 2>/dev/null | grep -q .; then
    log "FAILED: archive contains symlinks"
    exit 1
fi
if [ ! -d "${tmp_extract}/netfilter" ] \
    || [ ! -f "${tmp_extract}/bin/ko-loader" ] \
    || [ -L "${tmp_extract}/bin/ko-loader" ]; then
    log "FAILED: archive is missing netfilter/ or regular bin/ko-loader"
    exit 1
fi

stage_root="${ipset_lkm_dir}/.stage.$$"
if ! mkdir "$stage_root" || ! mkdir "${stage_root}/netfilter"; then
    log "FAILED: cannot create staging directory"
    exit 1
fi
if ! cp -R "${tmp_extract}/netfilter/." "${stage_root}/netfilter/" \
    || ! cp "${tmp_extract}/bin/ko-loader" "${stage_root}/ko-loader"; then
    log "FAILED: cannot stage release contents"
    exit 1
fi
find "${stage_root}/netfilter" -type f -exec chmod 0644 {} \;
find "${stage_root}/netfilter" -type d -exec chmod 0755 {} \;
chmod 0755 "${stage_root}/ko-loader"

compatible=1
vermagic_summary=""
for entry in \
    "ip_set:ipset/ip_set.ko" \
    "ip_set_hash_net:ipset/ip_set_hash_net.ko" \
    "xt_set:xt_set.ko"; do
    module_name=${entry%%:*}
    relative=${entry#*:}
    module="${stage_root}/netfilter/${relative}"
    if [ ! -f "$module" ] || [ -L "$module" ]; then
        log "FAILED: archive is missing regular ${relative}"
        exit 1
    fi
    release=$(module_release "$module") || release="unreadable"
    vermagic_summary="${vermagic_summary}${module_name}:${release} "
    if [ "$release" != "$kernel_release" ]; then
        compatible=0
    fi
done

if [ -f "${tmp_extract}/LICENSE" ] && [ ! -L "${tmp_extract}/LICENSE" ]; then
    cp "${tmp_extract}/LICENSE" "${stage_root}/UPSTREAM-LICENSE" || true
    chmod 0644 "${stage_root}/UPSTREAM-LICENSE" 2>/dev/null || true
fi

cat > "${stage_root}/manifest.ini" <<EOF
source_repo=${gh_repo}
release_tag=${tag}
asset_name=${asset_name}
sha256=${actual_sha}
kernel_release=${kernel_release}
kernel_series=${kernel_series}
exact_vermagic_compatible=${compatible}
vermagic=${vermagic_summary% }
EOF
chmod 0644 "${stage_root}/manifest.ini"

backup_root="${ipset_lkm_dir}/.backup.$$"
mkdir -p "$backup_root" || {
    log "FAILED: cannot create rollback directory"
    exit 1
}
if [ -e "$dest_dir" ] || [ -L "$dest_dir" ]; then
    mv "$dest_dir" "${backup_root}/netfilter" || {
        log "FAILED: cannot stage existing module bundle for rollback"
        exit 1
    }
fi
if [ -e "$loader_path" ] || [ -L "$loader_path" ]; then
    mv "$loader_path" "${backup_root}/ko-loader" || {
        [ -d "${backup_root}/netfilter" ] && mv "${backup_root}/netfilter" "$dest_dir"
        log "FAILED: cannot stage existing ko-loader for rollback"
        exit 1
    }
fi
if [ -e "$manifest_path" ] || [ -L "$manifest_path" ]; then
    mv "$manifest_path" "${backup_root}/manifest.ini" || {
        [ -d "${backup_root}/netfilter" ] && mv "${backup_root}/netfilter" "$dest_dir"
        [ -e "${backup_root}/ko-loader" ] && mv "${backup_root}/ko-loader" "$loader_path"
        log "FAILED: cannot stage existing manifest for rollback"
        exit 1
    }
fi

install_failed=0
mkdir -p "${ipset_lkm_dir}/netfilter" || install_failed=1
[ "$install_failed" -eq 0 ] && mv "${stage_root}/netfilter" "$dest_dir" || install_failed=1
[ "$install_failed" -eq 0 ] && mv "${stage_root}/ko-loader" "$loader_path" || install_failed=1
[ "$install_failed" -eq 0 ] && mv "${stage_root}/manifest.ini" "$manifest_path" || install_failed=1

if [ "$install_failed" -ne 0 ]; then
    rm -rf "$dest_dir" 2>/dev/null
    rm -f "$loader_path" "$manifest_path" 2>/dev/null
    [ -d "${backup_root}/netfilter" ] && mv "${backup_root}/netfilter" "$dest_dir"
    [ -f "${backup_root}/ko-loader" ] && mv "${backup_root}/ko-loader" "$loader_path"
    [ -f "${backup_root}/manifest.ini" ] && mv "${backup_root}/manifest.ini" "$manifest_path"
    log "FAILED: install was rolled back"
    exit 1
fi

rm -rf "$backup_root" "$stage_root" 2>/dev/null
backup_root=""
stage_root=""
chmod 0755 "$loader_path"

log "Installed ${tag} modules to ${dest_dir} and ko-loader to ${loader_path}"
if [ "$compatible" -eq 1 ]; then
    log "Exact vermagic match confirmed; loader remains gated by BYPASS_CN_IP"
else
    log "BLOCKED: installed bundle is inert because vermagic does not exactly match ${kernel_release}"
fi
log "Run 'sbctl ipset status' for the read-only compatibility report"
