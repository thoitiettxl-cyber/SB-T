#!/bin/sh
# Read-only rooted Android smoke check. This script never calls start/stop,
# iptables mutation, sysctl writes, insmod, or ko-loader.
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ROOT_BIN="${SB_ROOT_BIN:-su}"

pass() {
    printf 'ok - %s\n' "$*"
}

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

root() {
    "$ROOT_BIN" -c "$1"
}

[ "$(root 'id -u')" = "0" ] || fail "root shell unavailable"
pass "root shell available"

jq empty "$REPO_ROOT/box/sing-box/config.json"
[ "$(jq -r '.route.find_process' "$REPO_ROOT/box/sing-box/config.json")" = "false" ] \
    || fail "repo config enables process lookup"
[ "$(jq -r '.experimental.clash_api.external_controller' "$REPO_ROOT/box/sing-box/config.json")" = "127.0.0.1:9090" ] \
    || fail "Clash API is not loopback-only"
root "/data/adb/box/bin/sing-box check -c '${REPO_ROOT}/box/sing-box/config.json' -D /data/adb/box/sing-box"
pass "sing-box config passes 1.13.x validation"

modules_before=$(root 'for m in ip_set ip_set_hash_net xt_set; do [ -d /sys/module/$m ] && echo $m; done; true')
log_before=$(root 'stat -c %Y /data/adb/box/run/runs.log 2>/dev/null || echo missing')
set +e
ipset_status=$(root "/system/bin/sh '${REPO_ROOT}/box/scripts/ipset.sh' status" 2>&1)
ipset_rc=$?
set -e
modules_after=$(root 'for m in ip_set ip_set_hash_net xt_set; do [ -d /sys/module/$m ] && echo $m; done; true')
log_after=$(root 'stat -c %Y /data/adb/box/run/runs.log 2>/dev/null || echo missing')
[ "$modules_before" = "$modules_after" ] || fail "IPSET status changed loaded modules"
[ "$log_before" = "$log_after" ] || fail "IPSET status changed runtime logs"
printf '%s\n' "$ipset_status" | grep -q 'IPSET required by BYPASS_CN_IP:' \
    || fail "IPSET status report is incomplete"
if printf '%s\n' "$ipset_status" | grep -q 'IPSET required by BYPASS_CN_IP: no'; then
    [ "$ipset_rc" -eq 0 ] || fail "optional IPSET status returned failure"
fi
if printf '%s\n' "$ipset_status" | grep -q 'vermagic .* != running kernel'; then
    printf '%s\n' "$ipset_status" | grep -q 'LKM compatibility: blocked' \
        || fail "mismatched LKM was not marked blocked"
fi
pass "IPSET preflight is read-only and fail-closed"

pid=$(root 'cat /data/adb/box/run/box.pid 2>/dev/null')
case "$pid" in
    ""|*[!0-9]*) fail "sing-box PID file is invalid" ;;
esac
root "kill -0 '$pid'" || fail "sing-box PID is not alive"
listeners=$(root 'ss -lnptu 2>/dev/null')
printf '%s\n' "$listeners" | grep -q ':1536' || fail "TPROXY listener 1536 is absent"
printf '%s\n' "$listeners" | grep -q '127.0.0.1:7080' || fail "mixed listener is not on loopback"
printf '%s\n' "$listeners" | grep -q '127.0.0.1:9090' || fail "Clash API listener is not on loopback"
pass "sing-box process and loopback listeners are healthy"

rule_count=$(root "ip rule show | grep -c 'fwmark 0x14.*lookup 2025'")
[ "$rule_count" = "1" ] || fail "expected one fwmark rule for table 2025, got ${rule_count}"
root 'ip route show table 2025 | grep -q "local default dev lo"' \
    || fail "table 2025 has no local default route"
pass "TPROXY policy routing is singular"

if command -v drill >/dev/null 2>&1; then
    normal=$(drill example.com 2>&1)
    ad=$(drill doubleclick.net 2>&1)
    direct_ad=$(drill @1.1.1.1 pagead2.googlesyndication.com 2>&1)
    printf '%s\n' "$normal" | grep -q 'rcode: NOERROR' || fail "normal DNS query failed"
    printf '%s\n' "$normal" | grep -q '198\.18\.' || fail "normal DNS query did not use FakeIP"
    printf '%s\n' "$ad" | grep -q 'rcode: NXDOMAIN' || fail "ad domain was not blocked"
    printf '%s\n' "$direct_ad" | grep -q 'rcode: NXDOMAIN' \
        || fail "direct port-53 query escaped DNS hijack"
    pass "DNS ad blocking and port-53 leak interception work"
else
    printf 'skip - drill is unavailable; DNS proof not run\n'
fi

printf 'android runtime check: PASS\n'
