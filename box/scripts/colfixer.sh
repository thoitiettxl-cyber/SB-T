#!/system/bin/sh
# ColorOS 16 / RedMagic OS Google Services Firewall Fixer
# Removes REJECT/DROP rules injected by the OS into filter-table chains
# that block Google Play Store and Google Play Services.
#
# Called at boot from service.sh (with delay) and on manual toggle from action.sh.
#
# LAW-1 exception (documented): these chains — oplus_fw_INPUT, oplus_fw_OUTPUT,
# fw_INPUT, fw_OUTPUT, fw_OUTPUT_oplus_dns, zte_fw_gms — are OS-injected in the
# filter table,
# entirely separate from tproxy.sh's mangle/routing chains. No orphan-rule
# risk to tproxy state from cleaning them here.
#
# Reference: https://github.com/CHIZI-0618/ColorOS-Google-Firewall-Fixer

SCRIPTS_DIR="${0%/*}"
. "${SCRIPTS_DIR}/box.tool"

BOX_RUN="/data/adb/box/run"
LOG_FILE="${BOX_RUN}/colfixer.log"

# oplus_fw_INPUT/OUTPUT: HANS BPF filter (OPPO/OnePlus/ColorOS 14+)
# fw_INPUT/OUTPUT/oplus_dns: older ColorOS / generic OPPO variants
# zte_fw_gms: RedMagic OS — silently skipped if chain absent
CHAINS="oplus_fw_INPUT oplus_fw_OUTPUT fw_INPUT fw_OUTPUT fw_OUTPUT_oplus_dns zte_fw_gms"

_remove_block_rules() {
    local chain="$1" ipt="$2"

    command "$ipt" -t filter -nL "$chain" >/dev/null 2>&1 || return 0

    local nums
    nums=$(command "$ipt" -t filter -nvL "$chain" --line-numbers 2>/dev/null \
        | $busybox awk '/REJECT|DROP/ {print $1}' \
        | $busybox sort -rn)

    [ -z "$nums" ] && return 0

    local deleted=0
    for n in $nums; do
        if command "$ipt" -t filter -D "$chain" "$n" 2>/dev/null; then
            deleted=$((deleted + 1))
        fi
    done

    [ "$deleted" -gt 0 ] && log Info "colfixer: ${ipt} removed ${deleted} REJECT/DROP rule(s) from ${chain}"
}

main() {
    local mode="${1:-manual}"
    log Info "colfixer: start (mode=${mode})"

    for chain in $CHAINS; do
        _remove_block_rules "$chain" iptables
        _remove_block_rules "$chain" ip6tables
    done

    log Info "colfixer: done"
}

main "$@"
