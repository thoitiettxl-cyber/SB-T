#!/system/bin/sh
# Safe, optional IPSET-LKM loader. Kernel mutation is blocked unless the CN-IP
# bypass feature requests it and every essential module matches uname -r.

SCRIPT_DIR="$(cd "${0%/*}" 2>/dev/null && pwd)" || SCRIPT_DIR="/data/adb/box/scripts"
. "${SCRIPT_DIR}/box.tool"

readonly BOX_DIR="${SB_BOX_DIR:-/data/adb/box}"
readonly IPSET_LKM_DIR="${SB_IPSET_LKM_DIR:-${BOX_DIR}/bin/IPSET-LKM}"
readonly TPROXY_CONFIG="${SB_TPROXY_CONFIG:-${BOX_DIR}/tproxy.conf}"
readonly SYS_MODULE_DIR="${SB_SYS_MODULE_DIR:-/sys/module}"
readonly PROC_IPTABLES_MATCHES="${SB_PROC_IPTABLES_MATCHES:-/proc/net/ip_tables_matches}"
readonly MODULES_DISABLED_FILE="${SB_MODULES_DISABLED_FILE:-/proc/sys/kernel/modules_disabled}"
readonly LOG_FILE="${SB_LOG_FILE:-${BOX_DIR}/run/runs.log}"
readonly IPSET_BIN="${SB_IPSET_BIN:-${BOX_DIR}/bin/ipset}"
readonly MODINFO_BIN="${SB_MODINFO_BIN:-modinfo}"
readonly KO_LOADER="${SB_KO_LOADER:-${IPSET_LKM_DIR}/ko-loader}"
readonly KERNEL_RELEASE="${SB_KERNEL_RELEASE:-$(uname -r)}"

WRITE_LOG=0

report() {
    local message timestamp
    message="$*"
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    printf '%s\n' "$message"
    if [ "$WRITE_LOG" -eq 1 ]; then
        mkdir -p "${LOG_FILE%/*}" 2>/dev/null || true
        printf '%s [ipset.sh] %s\n' "$timestamp" "$message" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

kernel_series() {
    printf '%s\n' "$KERNEL_RELEASE" | sed -n 's/^\([0-9][0-9]*\.[0-9][0-9]*\).*/\1/p'
}

ipset_required() {
    case "${SB_IPSET_REQUIRED:-}" in
        1) return 0 ;;
        0) return 1 ;;
    esac

    [ -r "$TPROXY_CONFIG" ] || return 1
    local value
    value=$(awk -F= '
        /^[[:space:]]*BYPASS_CN_IP[[:space:]]*=/ {
            value=$2
            gsub(/[[:space:]"\047]/, "", value)
            print value
            exit
        }
    ' "$TPROXY_CONFIG" 2>/dev/null)
    [ "$value" = "1" ]
}

xt_set_available() {
    case "${SB_XT_SET_AVAILABLE:-}" in
        1) return 0 ;;
        0) return 1 ;;
    esac
    [ -d "${SYS_MODULE_DIR}/xt_set" ] && return 0
    [ -r "$PROC_IPTABLES_MATCHES" ] && grep -qw set "$PROC_IPTABLES_MATCHES" 2>/dev/null
}

kernel_ipset_ready() {
    [ -x "$IPSET_BIN" ] || return 1
    "$IPSET_BIN" list -n >/dev/null 2>&1 || return 1
    xt_set_available
}

module_release() {
    local module="$1" vermagic
    vermagic=$("$MODINFO_BIN" -F vermagic "$module" 2>/dev/null) || vermagic=""
    if [ -z "$vermagic" ] && [ -x /system/bin/modinfo ]; then
        vermagic=$(/system/bin/modinfo -F vermagic "$module" 2>/dev/null) || vermagic=""
    fi
    if [ -z "$vermagic" ] && [ -x "$busybox" ]; then
        vermagic=$($busybox modinfo -F vermagic "$module" 2>/dev/null) || vermagic=""
    fi
    [ -n "$vermagic" ] || return 1
    printf '%s\n' "${vermagic%% *}"
}

bundle_dir() {
    local series
    series=$(kernel_series)
    [ -n "$series" ] || return 1
    printf '%s/netfilter/%s\n' "$IPSET_LKM_DIR" "$series"
}

bundle_preflight() {
    local lkm_dir series manifest entry relative module expected actual failed
    local manifest_source manifest_kernel manifest_compatible manifest_sha
    series=$(kernel_series)
    lkm_dir=$(bundle_dir) || {
        report "BLOCKED: cannot derive kernel series from ${KERNEL_RELEASE}"
        return 1
    }

    if [ "$(uname -m 2>/dev/null)" != "aarch64" ] && [ -z "${SB_ALLOW_TEST_ARCH:-}" ]; then
        report "BLOCKED: IPSET_LKM supports aarch64 only"
        return 1
    fi
    if [ -r "$MODULES_DISABLED_FILE" ] && [ "$(cat "$MODULES_DISABLED_FILE" 2>/dev/null)" = "1" ]; then
        report "BLOCKED: kernel module loading is disabled"
        return 1
    fi
    if [ ! -d "$lkm_dir" ] || [ -L "$lkm_dir" ]; then
        report "BLOCKED: no trusted LKM bundle at ${lkm_dir}"
        return 1
    fi

    failed=0
    for entry in \
        "ip_set:ipset/ip_set.ko" \
        "ip_set_hash_net:ipset/ip_set_hash_net.ko" \
        "xt_set:xt_set.ko"; do
        relative=${entry#*:}
        module="${lkm_dir}/${relative}"
        if [ ! -f "$module" ] || [ -L "$module" ]; then
            report "BLOCKED: missing regular module ${module}"
            failed=1
            continue
        fi
        actual=$(module_release "$module") || actual=""
        expected="$KERNEL_RELEASE"
        if [ -z "$actual" ]; then
            report "BLOCKED: cannot read vermagic from ${module}"
            failed=1
        elif [ "$actual" != "$expected" ]; then
            report "BLOCKED: ${relative} vermagic ${actual} != running kernel ${expected}"
            failed=1
        fi
    done
    [ "$failed" -eq 0 ] || return 1

    manifest="${IPSET_LKM_DIR}/manifest-${series}.ini"
    if [ ! -f "$manifest" ] || [ -L "$manifest" ]; then
        report "BLOCKED: verified release manifest not found at ${manifest}"
        return 1
    fi
    manifest_source=$(sed -n 's/^source_repo=//p' "$manifest" | head -1)
    manifest_kernel=$(sed -n 's/^kernel_release=//p' "$manifest" | head -1)
    manifest_compatible=$(sed -n 's/^exact_vermagic_compatible=//p' "$manifest" | head -1)
    manifest_sha=$(sed -n 's/^sha256=//p' "$manifest" | head -1)
    if [ "$manifest_source" != "TanakaLun/IPSET_LKM" ] \
        || [ "$manifest_kernel" != "$KERNEL_RELEASE" ] \
        || [ "$manifest_compatible" != "1" ]; then
        report "BLOCKED: release manifest does not authorize kernel ${KERNEL_RELEASE}"
        return 1
    fi
    case "$manifest_sha" in
        *[!0-9a-fA-F]*|"")
            report "BLOCKED: release manifest has no valid archive SHA-256"
            return 1
            ;;
    esac
    if [ "${#manifest_sha}" -ne 64 ]; then
        report "BLOCKED: release manifest has no valid archive SHA-256"
        return 1
    fi

    if [ ! -f "$KO_LOADER" ] || [ -L "$KO_LOADER" ] || [ ! -x "$KO_LOADER" ]; then
        report "BLOCKED: trusted executable ko-loader not found at ${KO_LOADER}"
        return 1
    fi

    report "Compatible LKM bundle: ${lkm_dir}"
    return 0
}

load_one() {
    local module_name="$1" module_path="$2" output status
    if [ -d "${SYS_MODULE_DIR}/${module_name}" ]; then
        report "Already loaded: ${module_name}"
        return 0
    fi

    output=$("$KO_LOADER" "$module_path" 2>&1)
    status=$?
    if [ "$status" -ne 0 ]; then
        output=$(printf '%s' "$output" | tr '\n' ' ')
        report "FAILED: ko-loader ${module_name} (${status}): ${output:-no error text}"
        return "$status"
    fi
    if [ ! -d "${SYS_MODULE_DIR}/${module_name}" ]; then
        report "FAILED: ${module_name} absent from sysfs after loader returned success"
        return 1
    fi
    report "Loaded: ${module_name}"
}

status_modules() {
    local required="no" lkm_dir
    ipset_required && required="yes"
    report "IPSET required by BYPASS_CN_IP: ${required}"
    report "Running kernel: ${KERNEL_RELEASE}"

    if kernel_ipset_ready; then
        report "Kernel IPSET status: ready"
        return 0
    fi
    report "Kernel IPSET status: unavailable"

    lkm_dir=$(bundle_dir 2>/dev/null) || lkm_dir="unresolved"
    report "LKM bundle: ${lkm_dir}"
    if bundle_preflight; then
        report "LKM compatibility: ready to load"
        return 0
    fi
    report "LKM compatibility: blocked"
    [ "$required" = "yes" ] && return 2
    return 0
}

load_modules() {
    local force="${1:-}" lkm_dir
    WRITE_LOG=1

    if [ "$force" != "--force" ] && ! ipset_required; then
        report "Skipped: BYPASS_CN_IP is disabled; DNS/ad blocking does not require IPSET"
        return 0
    fi
    if kernel_ipset_ready; then
        report "IPSET and xt_set are already available"
        return 0
    fi
    if ! bundle_preflight; then
        report "IPSET load was not attempted"
        return 2
    fi

    lkm_dir=$(bundle_dir) || return 2
    load_one ip_set "${lkm_dir}/ipset/ip_set.ko" || return $?
    load_one ip_set_hash_net "${lkm_dir}/ipset/ip_set_hash_net.ko" || return $?
    load_one xt_set "${lkm_dir}/xt_set.ko" || return $?

    if ! kernel_ipset_ready; then
        report "FAILED: kernel loaded modules but the ipset/xt_set readiness check failed"
        return 1
    fi
    report "IPSET is ready for CN-IP bypass"
}

case "${1:-}" in
    status|check)
        status_modules
        ;;
    load)
        load_modules "${2:-}"
        ;;
    *)
        printf 'Usage: %s {status|load [--force]}\n' "$0" >&2
        exit 1
        ;;
esac
