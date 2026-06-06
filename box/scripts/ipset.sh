#!/system/bin/sh
# Loads IPSET kernel modules before tproxy.sh start.
# No-op if kernel already has ip_set loaded or LKM bundle not present.

readonly IPSET_LKM_DIR="/data/adb/box/bin/IPSET-LKM"
readonly LOG_FILE="/data/adb/box/run/runs.log"

_log() { printf '%s [ipset.sh] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE" 2>&1; }

load_modules() {
    if [ -d /sys/module/ip_set ]; then
        _log "ip_set already loaded, skipping"
        return 0
    fi

    local kver
    kver=$(uname -r | command grep -oE '^[0-9]+\.[0-9]+')
    local lkm_dir="${IPSET_LKM_DIR}/netfilter/${kver}"

    if [ ! -d "$lkm_dir" ]; then
        _log "No LKM bundle for kernel ${kver}; run upipset.sh to download"
        return 0
    fi

    _log "Loading IPSET modules for kernel ${kver}..."

    # Use insmod (always available as root on Android); ignore already-loaded errors
    _insmod() { command insmod "$1" 2>/dev/null || true; }

    _insmod "${lkm_dir}/ipset/ip_set.ko"

    for m in bitmap_ip bitmap_ipmac bitmap_port; do
        _insmod "${lkm_dir}/ipset/ip_set_${m}.ko"
    done
    for m in ip ipmac ipmark ipport ipportip ipportnet mac net netiface netnet netport netportnet; do
        _insmod "${lkm_dir}/ipset/ip_set_hash_${m}.ko"
    done
    _insmod "${lkm_dir}/ipset/ip_set_list_set.ko"
    _insmod "${lkm_dir}/xt_set.ko"
    _insmod "${lkm_dir}/xt_addrtype.ko"

    if [ -d /sys/module/ip_set ]; then
        _log "ip_set loaded successfully"
    else
        _log "WARN: ip_set still not in /sys/module after load attempt"
    fi
}

case "${1:-}" in
    load) load_modules ;;
    *) printf 'Usage: %s load\n' "$0" >&2; exit 1 ;;
esac
