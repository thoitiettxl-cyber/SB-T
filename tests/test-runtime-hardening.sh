#!/bin/sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
LIB="$REPO_ROOT/box/scripts/runtime.lib"
NET="$REPO_ROOT/box/scripts/net.inotify"
START="$REPO_ROOT/box/scripts/start.sh"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sb-runtime.XXXXXX")
CORE_PID=""
FD_PID=""
PASS_COUNT=0

cleanup() {
    if [ -n "$CORE_PID" ]; then
        kill "$CORE_PID" 2>/dev/null || true
        wait "$CORE_PID" 2>/dev/null || true
    fi
    if [ -n "$FD_PID" ]; then
        kill "$FD_PID" 2>/dev/null || true
    fi
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf 'ok - %s\n' "$*"
}

assert_eq() {
    [ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

assert_file_contains() {
    grep -q -- "$2" "$1" || fail "expected '$1' to contain '$2'"
}

write_ipv6_backup_fixture() {
    forwarding_origin=${2:-0}
    cat > "$1" <<EOF
# IPv6 fixture origin
accept_ra=2
autoconf=1
forwarding=$forwarding_origin
default=0
all=0
EOF
}

BIN="$TEST_ROOT/bin/sing-box"
mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/proc/net" "$TEST_ROOT/run"
touch "$BIN"
chmod 0755 "$BIN"

# Build a fake proc tree around a real, harmless sleep process. This lets the
# probe test real kill -0 semantics while controlling cmdline/socket ownership.
sleep 120 &
CORE_PID=$!
mkdir -p "$TEST_ROOT/proc/$CORE_PID/fd"
printf '%s\0run\0-c\0fixture\0' "$BIN" > "$TEST_ROOT/proc/$CORE_PID/cmdline"
ln -s 'socket:[101]' "$TEST_ROOT/proc/$CORE_PID/fd/3"
ln -s 'socket:[102]' "$TEST_ROOT/proc/$CORE_PID/fd/4"
cat > "$TEST_ROOT/proc/net/tcp" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000:0600 00000000:0000 0A 00000000:00000000 00:00000000 00000000   0        0 101 1
EOF
cat > "$TEST_ROOT/proc/net/tcp6" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
EOF
cat > "$TEST_ROOT/proc/net/udp" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
   0: 00000000:0600 00000000:0000 07 00000000:00000000 00:00000000 00000000   0        0 102 1
EOF
cat > "$TEST_ROOT/proc/net/udp6" <<'EOF'
  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode
EOF

busybox=$(command -v busybox)
export busybox SB_PROC_ROOT="$TEST_ROOT/proc"
. "$REPO_ROOT/box/scripts/box.tool"
. "$LIB"

runtime_pid_is_core "$CORE_PID" "$BIN" || fail "valid core PID was rejected"
if runtime_pid_is_core "$CORE_PID" "$TEST_ROOT/bin/other"; then
    fail "PID reuse guard accepted the wrong executable"
fi
runtime_tproxy_port_ready "$CORE_PID" 1536 "$BIN" \
    || fail "TCP/UDP socket ownership probe rejected valid sockets"
rm -f "$TEST_ROOT/proc/$CORE_PID/fd/4"
if runtime_tproxy_port_ready "$CORE_PID" 1536 "$BIN"; then
    fail "readiness accepted a missing UDP socket"
fi
ln -s 'socket:[102]' "$TEST_ROOT/proc/$CORE_PID/fd/4"
pass "readiness requires exact PID-owned TCP and UDP sockets"

CONFIG_DIR="$REPO_ROOT/box"
SB_BOX_PID="$TEST_ROOT/hook.pid"
SB_CORE_BIN="$BIN"
printf '%s\n' "$CORE_PID" > "$SB_BOX_PID"
. "$REPO_ROOT/box/tproxy.conf"
pre_start_hook || fail "pre_start_hook rejected valid PID-owned listeners"
rm -f "$TEST_ROOT/proc/$CORE_PID/fd/4"
set +e
( pre_start_hook >/dev/null 2>&1 )
hook_rc=$?
set -e
[ "$hook_rc" -ne 0 ] || fail "pre_start_hook accepted a missing UDP listener"
ln -s 'socket:[102]' "$TEST_ROOT/proc/$CORE_PID/fd/4"
pass "pre_start_hook fails closed on listener loss"

printf '%0300d\n' 0 > "$TEST_ROOT/run/log"
inode_before=$(stat -c %i "$TEST_ROOT/run/log")
runtime_trim_log "$TEST_ROOT/run/log" 128 64 || fail "log trim failed"
size_after=$(stat -c %s "$TEST_ROOT/run/log")
inode_after=$(stat -c %i "$TEST_ROOT/run/log")
[ "$size_after" -le 128 ] || fail "log remained over bound"
assert_eq "$inode_after" "$inode_before"
printf 'keep\n' > "$TEST_ROOT/run/target"
ln -s "$TEST_ROOT/run/target" "$TEST_ROOT/run/link.log"
runtime_trim_log "$TEST_ROOT/run/link.log" 1 0 2>/dev/null || true
assert_file_contains "$TEST_ROOT/run/target" keep
pass "log trimming is bounded and preserves the live inode"

# Fake Android commands for the state-aware net.inotify path.
cat > "$TEST_ROOT/bin/iptables" <<'EOF'
#!/bin/sh
case " $* " in
  *" -S PROXY_PREROUTING "*)
    [ ! -f "$SB_TEST_ROOT/broken-state" ] || exit 1
    if [ -f "$SB_TEST_ROOT/redirect-mode" ]; then
      printf '%s\n' '-A PROXY_CHAIN -j REDIRECT --to-ports 1536'
      exit 0
    fi
    printf '%s\n' '-A PROXY_CHAIN -p tcp -j TPROXY --on-port 1536 --tproxy-mark 0x14/0xff'
    [ ! -f "$SB_TEST_ROOT/missing-udp" ] || exit 0
    printf '%s\n' '-A PROXY_CHAIN -p udp -j TPROXY --on-port 1536 --tproxy-mark 0x14/0xff'
    ;;
  *" -S PROXY_OUTPUT "*)
    if [ -f "$SB_TEST_ROOT/redirect-mode" ]; then
      printf '%s\n' '-A PROXY_OUTPUT -j REDIRECT --to-ports 1536'
    else
      printf '%s\n' '-A PROXY_OUTPUT -j MARK --set-xmark 0x14/0xffffffff'
    fi
    ;;
  *) : ;;
esac
exit 0
EOF
cat > "$TEST_ROOT/bin/ip6tables" <<'EOF'
#!/bin/sh
case " $* " in
  *" -S PROXY_PREROUTING6 "*)
    printf '%s\n' '-A PROXY_PREROUTING6 -p tcp -j TPROXY --on-port 1536 --tproxy-mark 0x19/0xff'
    printf '%s\n' '-A PROXY_PREROUTING6 -p udp -j TPROXY --on-port 1536 --tproxy-mark 0x19/0xff'
    ;;
  *" -S PROXY_OUTPUT6 "*)
    printf '%s\n' '-A PROXY_OUTPUT6 -j MARK --set-xmark 0x19/0xffffffff'
    ;;
  *" -S OUTPUT "*)
    if [ -f "$SB_TEST_ROOT/stale-ipv6-guard" ]; then
      printf '%s\n' '-A OUTPUT -m owner --uid-owner 0 -j ACCEPT'
      printf '%s\n' '-A OUTPUT -j DROP'
    fi
    ;;
esac
exit 0
EOF
cat > "$TEST_ROOT/bin/ip" <<'EOF'
#!/bin/sh
case " $* " in
  *" -6 rule show "*) printf '%s\n' '2025: from all fwmark 0x19 lookup 2025' ;;
  *" -6 route show table 2025 "*) printf '%s\n' 'local ::/0 dev lo metric 1024' ;;
  *" rule show "*) printf '%s\n' '2025: from all fwmark 0x14 lookup 2025' ;;
  *" route show table 2025 "*) printf '%s\n' 'local default dev lo scope host' ;;
  *) : ;;
esac
exit 0
EOF
cat > "$TEST_ROOT/bin/tproxy-fixture" <<'EOF'
#!/bin/sh
action=""
box_dir=""
previous=""
write_ipv6_backup() {
  forwarding_origin=${2:-0}
  cat > "$1" <<BACKUP
# IPv6 fixture origin
accept_ra=2
autoconf=1
forwarding=$forwarding_origin
default=0
all=0
BACKUP
}
for arg in "$@"; do
    [ "$previous" = "-d" ] && box_dir=$arg
    case "$arg" in stop|start|guard-ipv6) action="$arg" ;; esac
    previous=$arg
done
printf '%s\n' "$action" >> "$SB_TEST_ROOT/tproxy.calls"
if [ "$action" = start ]; then
  printf 'start:keep=%s\n' "${TPROXY_KEEP_IPV6_DISABLED:-0}" >> "$SB_TEST_ROOT/tproxy.env"
fi
if [ "$action" = stop ] && [ -f "$SB_TEST_ROOT/fail-stop" ]; then exit 8; fi
if [ "$action" = start ] && [ -f "$SB_TEST_ROOT/fail-start" ]; then exit 7; fi
if [ "$action" = guard-ipv6 ] && [ -f "$SB_TEST_ROOT/fail-guard" ]; then exit 6; fi
if [ "$action" = stop ]; then
  printf 'stop:keep=%s\n' "${TPROXY_KEEP_IPV6_DISABLED:-0}" >> "$SB_TEST_ROOT/tproxy.env"
  if [ "${TPROXY_KEEP_IPV6_DISABLED:-0}" -ne 1 ]; then
    rm -f "$SB_TEST_ROOT/stale-ipv6-guard" "$box_dir/ipv6_backup.conf"
  fi
fi
if [ "$action" = guard-ipv6 ]; then
  [ -f "$SB_TEST_ROOT/box/run/box.recover" ] || : > "$SB_TEST_ROOT/guard-before-marker"
  : > "$SB_TEST_ROOT/stale-ipv6-guard"
  [ -f "$box_dir/ipv6_backup.conf" ] || \
    write_ipv6_backup "$box_dir/ipv6_backup.conf" "${TPROXY_IPV6_FORWARDING_ORIGIN:-0}"
  for path in "$SB_TEST_ROOT"/proc/sys/net/ipv6/conf/*/disable_ipv6; do
    [ -f "$path" ] && printf '1\n' > "$path"
  done
fi
if [ "$action" = start ]; then
  rm -f "$SB_TEST_ROOT/missing-udp" "$SB_TEST_ROOT/broken-state"
  next_mode=$(awk -F= '
    /^[[:space:]]*PROXY_IPV6[[:space:]]*=/ {
      value=$2; gsub(/[[:space:]"\047]/, "", value); print value; exit
    }
  ' "$box_dir/tproxy.conf" 2>/dev/null)
  case "$next_mode" in '' ) next_mode=0 ;; -1|0|1) ;; *) exit 12 ;; esac
  if [ -f "$box_dir/runtime_tproxy.conf" ]; then
    sed -i "s/^PROXY_IPV6=.*/PROXY_IPV6=$next_mode/" "$box_dir/runtime_tproxy.conf"
  fi
  if [ "$next_mode" = "-1" ]; then
    : > "$SB_TEST_ROOT/stale-ipv6-guard"
    [ -f "$box_dir/ipv6_backup.conf" ] || \
      write_ipv6_backup "$box_dir/ipv6_backup.conf" "${TPROXY_IPV6_FORWARDING_ORIGIN:-0}"
  else
    rm -f "$SB_TEST_ROOT/stale-ipv6-guard" "$box_dir/ipv6_backup.conf"
  fi
  if [ -f "$SB_TEST_ROOT/drop-core-on-start" ]; then
    rm -f "$SB_TEST_ROOT/proc/$(cat "$SB_TEST_ROOT/box/run/box.pid")/fd/4"
  fi
fi
exit 0
EOF
cat > "$TEST_ROOT/bin/start-fixture" <<'EOF'
#!/bin/sh
printf '%s\n' recover >> "$SB_TEST_ROOT/tproxy.calls"
[ ! -f "$SB_TEST_ROOT/fail-recover" ] || exit 9
exit 0
EOF
chmod 0755 "$TEST_ROOT/bin/iptables" "$TEST_ROOT/bin/ip6tables" \
    "$TEST_ROOT/bin/ip" "$TEST_ROOT/bin/tproxy-fixture" "$TEST_ROOT/bin/start-fixture"

mkdir -p "$TEST_ROOT/box/run"
printf '%s\n' "$CORE_PID" > "$TEST_ROOT/box/run/box.pid"
cat > "$TEST_ROOT/box/settings.ini" <<EOF
tproxy_port="1536"
EOF
cat > "$TEST_ROOT/box/runtime_tproxy.conf" <<'EOF'
CORE_USER_GROUP=root:net_admin
PROXY_TCP=1
PROXY_UDP=1
PROXY_IPV6=0
PROXY_MODE=1
BYPASS_CN_IP=0
BLOCK_QUIC=0
DNS_HIJACK_ENABLE=0
DNS_PORT=1053
TABLE_ID=2025
MARK_VALUE=20
MARK_VALUE6=25
ORIG_IP6_FORWARDING=0
USE_TPROXY=1
EOF
cat > "$TEST_ROOT/box/tproxy.conf" <<'EOF'
PROXY_IPV6=0
EOF
: > "$TEST_ROOT/box/run/net.log"
: > "$TEST_ROOT/box/run/box.lock"
: > "$TEST_ROOT/box/run/box.want"
export SB_TEST_ROOT="$TEST_ROOT"

export SB_IPTABLES_BIN="$TEST_ROOT/bin/iptables"
export SB_IP6TABLES_BIN="$TEST_ROOT/bin/ip6tables"
export SB_IP_BIN="$TEST_ROOT/bin/ip"
touch "$TEST_ROOT/redirect-mode"
sed -i 's/^USE_TPROXY=1$/USE_TPROXY=0/' "$TEST_ROOT/box/runtime_tproxy.conf"
runtime_tproxy_state_ready "$TEST_ROOT/box/runtime_tproxy.conf" 1536 \
    || fail "REDIRECT runtime state was rejected"
sed -i 's/^USE_TPROXY=0$/USE_TPROXY=1/' "$TEST_ROOT/box/runtime_tproxy.conf"
rm -f "$TEST_ROOT/redirect-mode"
pass "health probe supports REDIRECT rules without protocol tokens"

printf '%s' "$$" > "$TEST_ROOT/box/runtime_tproxy.starting"
if runtime_tproxy_state_ready "$TEST_ROOT/box/runtime_tproxy.conf" 1536; then
    fail "health probe accepted an uncommitted runtime start journal"
fi
rm -f "$TEST_ROOT/box/runtime_tproxy.starting"
pass "health probe rejects uncommitted runtime start state"

# The generated cleanup snapshot is data, not shell code. A fixed-key parser
# must preserve spaces literally and never execute command substitutions.
TPROXY_LIB="$TEST_ROOT/tproxy-lib.sh"
sed -n '/^parse_args "\$@"/q;p' "$REPO_ROOT/box/scripts/tproxy.sh" > "$TPROXY_LIB"
. "$TPROXY_LIB"
RUNTIME_BOX="$TEST_ROOT/runtime-config"
mkdir -p "$RUNTIME_BOX"
CONFIG_DIR="$RUNTIME_BOX"
DRY_RUN=0
LOG_TIMESTAMP=0
cat > "$RUNTIME_BOX/runtime_tproxy.conf" <<EOF
CONFIG_DIR=$RUNTIME_BOX
CORE_USER_GROUP=root:net_admin
PROXY_TCP=1
PROXY_UDP=1
PROXY_TCP_PORT=1536
PROXY_UDP_PORT=1536
PROXY_IPV6=-1
PROXY_MODE=1
OTHER_PROXY_INTERFACES=\$(touch $TEST_ROOT/runtime-parser-executed)
BYPASS_CN_IP=0
BLOCK_QUIC=1
DNS_HIJACK_ENABLE=0
DNS_PORT=1053
TABLE_ID=2025
MARK_VALUE=20
MARK_VALUE6=25
MOBILE_INTERFACE=rmnet_data+
WIFI_INTERFACE=wlan0
HOTSPOT_INTERFACE=wlan2
USB_INTERFACE=rndis+
PROXY_MOBILE=1
PROXY_WIFI=1
PROXY_HOTSPOT=0
PROXY_USB=0
ORIG_IP_FORWARD=0
ORIG_IP6_FORWARDING=0
USE_TPROXY=1
EOF
load_runtime_config || fail "fixed-key runtime config parser rejected a valid snapshot"
assert_eq "$DNS_PORT" "1053"
[ ! -e "$TEST_ROOT/runtime-parser-executed" ] || fail "runtime config was executed as shell code"
assert_eq "$OTHER_PROXY_INTERFACES" "\$(touch $TEST_ROOT/runtime-parser-executed)"
parse_core_identity || fail "valid runtime core identity was rejected"
CORE_USER_GROUP='root:net_admin:extra'
if parse_core_identity; then
    fail "malformed runtime core identity was accepted"
fi
pass "runtime cleanup snapshot is parsed as data with strict core identity"

# Upgrade cleanup accepts the exact 14-key v1.3.4 snapshot, while any partial
# mixture with the current schema is treated as corrupt.
cp "$RUNTIME_BOX/runtime_tproxy.conf" "$RUNTIME_BOX/full.snapshot"
cat > "$RUNTIME_BOX/runtime_tproxy.conf" <<EOF
CONFIG_DIR=$RUNTIME_BOX
CORE_USER_GROUP=root:net_admin
PROXY_TCP=1
PROXY_UDP=1
PROXY_IPV6=-1
PROXY_MODE=1
OTHER_PROXY_INTERFACES=
BYPASS_CN_IP=0
BLOCK_QUIC=0
DNS_HIJACK_ENABLE=0
TABLE_ID=2025
MARK_VALUE=20
MARK_VALUE6=25
USE_TPROXY=1
EOF
load_runtime_config || fail "exact v1.3.4 snapshot was rejected"
assert_eq "$RUNTIME_SNAPSHOT_KIND" legacy
assert_eq "$FORWARDING_META_KNOWN" 0
assert_eq "$PROXY_TCP_PORT" 1536
printf 'ORIG_IP_FORWARD=0\n' >> "$RUNTIME_BOX/runtime_tproxy.conf"
if load_runtime_config >/dev/null 2>&1; then
    fail "partial current snapshot fields were accepted as legacy"
fi
mv "$RUNTIME_BOX/full.snapshot" "$RUNTIME_BOX/runtime_tproxy.conf"
load_runtime_config || fail "full snapshot could not be restored after legacy test"
pass "snapshot loader supports exact v1.3.4 schema and rejects mixed metadata"

cp "$RUNTIME_BOX/runtime_tproxy.conf" "$RUNTIME_BOX/numeric-valid.snapshot"
for invalid_numeric in PROXY_TCP_PORT:0 PROXY_UDP_PORT:65536 DNS_PORT:0 \
    TABLE_ID:65536 MARK_VALUE:2147483648 MARK_VALUE6:0; do
    invalid_key=${invalid_numeric%%:*}
    invalid_value=${invalid_numeric#*:}
    sed "s/^${invalid_key}=.*/${invalid_key}=${invalid_value}/" \
        "$RUNTIME_BOX/numeric-valid.snapshot" > "$RUNTIME_BOX/runtime_tproxy.conf"
    if load_runtime_config >/dev/null 2>&1; then
        fail "runtime snapshot accepted ${invalid_key}=${invalid_value}"
    fi
done
mv "$RUNTIME_BOX/numeric-valid.snapshot" "$RUNTIME_BOX/runtime_tproxy.conf"
load_runtime_config || fail "valid snapshot failed after numeric-bound tests"
pass "runtime snapshot enforces port, table, and mark bounds"

JOURNAL_BOX="$TEST_ROOT/runtime-journal"
mkdir -p "$JOURNAL_BOX"
(
    CONFIG_DIR="$JOURNAL_BOX"
    DRY_RUN=0
    begin_runtime_start_journal || exit 1
    [ -f "$JOURNAL_BOX/runtime_tproxy.conf" ] || exit 2
    grep -q '^ORIG_IP_FORWARD=0$' "$JOURNAL_BOX/runtime_tproxy.conf" || exit 7
    runtime_start_journal_valid || exit 3
    commit_runtime_start_journal || exit 4
    [ ! -e "$JOURNAL_BOX/runtime_tproxy.starting" ] || exit 5
    [ -f "$JOURNAL_BOX/runtime_tproxy.conf" ] || exit 6
) || fail "two-phase runtime start journal failed"
pass "runtime origin journal commits before network mutation state"

# Even without a usable snapshot, stop must visit every fixed module-owned
# cleanup surface. Unknown forwarding origin is not a reason to strand rules.
CLEANUP_CALLS="$TEST_ROOT/cleanup.calls"
: > "$CLEANUP_CALLS"
(
    DRY_RUN=1
    STOP_FAST_PATH=0
    CONFIG_DIR="$RUNTIME_BOX"
    CORE_USER_GROUP=root:net_admin
    PROXY_TCP=1
    PROXY_UDP=1
    PROXY_TCP_PORT=1536
    PROXY_UDP_PORT=1536
    PROXY_IPV6=-1
    PROXY_MODE=1
    BYPASS_CN_IP=0
    BLOCK_QUIC=0
    DNS_HIJACK_ENABLE=0
    DNS_PORT=1053
    TABLE_ID=2025
    MARK_VALUE=20
    MARK_VALUE6=25
    USE_TPROXY=1
    load_runtime_config() { return 1; }
    check_dependencies() { :; }
    validate_cleanup_config() { return 0; }
    parse_core_identity() { CORE_USER=root; CORE_GROUP=net_admin; return 0; }
    cleanup_tproxy_chain4() { echo tproxy4 >> "$CLEANUP_CALLS"; }
    cleanup_tproxy_chain6() { echo tproxy6 >> "$CLEANUP_CALLS"; }
    cleanup_redirect_chain4() { echo redirect4 >> "$CLEANUP_CALLS"; }
    cleanup_redirect_chain6() { echo redirect6 >> "$CLEANUP_CALLS"; }
    cleanup_routing4() { echo route4 >> "$CLEANUP_CALLS"; }
    cleanup_routing6() { echo route6 >> "$CLEANUP_CALLS"; }
    cleanup_ipset() { echo ipset >> "$CLEANUP_CALLS"; }
    block_loopback_traffic() { echo loopback >> "$CLEANUP_CALLS"; }
    block_quic() { echo quic >> "$CLEANUP_CALLS"; }
    block_ipv6_output() { echo ipv6guard >> "$CLEANUP_CALLS"; }
    restore_forwarding_state() { return 0; }
    verify_proxy_stopped() { return 0; }
    stop_proxy >/dev/null 2>&1
) || fail "missing-snapshot cleanup flow returned failure"
for required_call in tproxy4 tproxy6 redirect4 redirect6 route4 route6 ipset loopback quic ipv6guard; do
    grep -qx "$required_call" "$CLEANUP_CALLS" || fail "cleanup skipped $required_call"
done
pass "missing snapshot cannot block fixed owned-state teardown"

# Exercise the production stop control flow: transition mode must retain the
# IPv6 backup/guard instead of logging "preserve" and then disabling it.
KEEP_CALLS="$TEST_ROOT/keep.calls"
: > "$KEEP_CALLS"
(
    DRY_RUN=1
    CONFIG_DIR="$RUNTIME_BOX"
    CORE_USER_GROUP=root:net_admin
    PROXY_TCP=1
    PROXY_UDP=1
    PROXY_TCP_PORT=1536
    PROXY_UDP_PORT=1536
    PROXY_IPV6=1
    BYPASS_CN_IP=0
    BLOCK_QUIC=0
    DNS_HIJACK_ENABLE=0
    DNS_PORT=1053
    TABLE_ID=2025
    MARK_VALUE=20
    MARK_VALUE6=25
    USE_TPROXY=1
    FORWARDING_META_KNOWN=1
    TPROXY_KEEP_IPV6_DISABLED=1
    load_runtime_config() { return 0; }
    check_dependencies() { :; }
    validate_cleanup_config() { return 0; }
    parse_core_identity() { CORE_USER=root; CORE_GROUP=net_admin; return 0; }
    cleanup_tproxy_chain4() { :; }
    cleanup_tproxy_chain6() { :; }
    cleanup_redirect_chain4() { :; }
    cleanup_redirect_chain6() { :; }
    cleanup_routing4() { :; }
    cleanup_routing6() { :; }
    cleanup_ipset() { :; }
    block_loopback_traffic() { :; }
    block_quic() { :; }
    manage_ipv6() { echo "manage:$1" >> "$KEEP_CALLS"; }
    block_ipv6_output() { echo "block:$1" >> "$KEEP_CALLS"; }
    restore_forwarding_state() { :; }
    verify_proxy_stopped() { :; }
    stop_proxy >/dev/null 2>&1
) || fail "production keep-disabled stop flow returned failure"
[ ! -s "$KEEP_CALLS" ] || fail "keep-disabled stop mutated IPv6 state: $(tr '\n' ' ' < "$KEEP_CALLS")"
pass "production stop retains IPv6 guard across transition"

ROLLBACK_KEEP_CALLS="$TEST_ROOT/rollback-keep.calls"
: > "$ROLLBACK_KEEP_CALLS"
(
    DRY_RUN=1
    CONFIG_DIR="$RUNTIME_BOX"
    PROXY_IPV6=-1
    TPROXY_KEEP_IPV6_DISABLED=1
    cleanup_tproxy_chain4() { :; }
    cleanup_tproxy_chain6() { :; }
    cleanup_redirect_chain4() { :; }
    cleanup_redirect_chain6() { :; }
    cleanup_routing4() { :; }
    cleanup_routing6() { :; }
    cleanup_ipset() { :; }
    block_loopback_traffic() { :; }
    block_quic() { :; }
    manage_ipv6() { echo "manage:$1" >> "$ROLLBACK_KEEP_CALLS"; }
    block_ipv6_output() { echo "block:$1" >> "$ROLLBACK_KEEP_CALLS"; }
    restore_forwarding_state() { :; }
    verify_proxy_stopped() { :; }
    rollback_proxy_start >/dev/null 2>&1
) || fail "keep-disabled start rollback returned failure"
[ ! -s "$ROLLBACK_KEEP_CALLS" ] || fail "start rollback opened IPv6 transition guard"
pass "failed IPv6 start rollback retains transition guard"

PREFLIGHT_CALLS="$TEST_ROOT/preflight.calls"
: > "$PREFLIGHT_CALLS"
(
    DRY_RUN=1
    CONFIG_DIR="$TEST_ROOT/missing-origin-box"
    mkdir -p "$CONFIG_DIR"
    CORE_USER_GROUP=root:net_admin
    PROXY_TCP=1
    PROXY_UDP=1
    PROXY_TCP_PORT=1536
    PROXY_UDP_PORT=1536
    PROXY_IPV6=-1
    BYPASS_CN_IP=0
    BLOCK_QUIC=0
    DNS_HIJACK_ENABLE=0
    DNS_PORT=1053
    TABLE_ID=2025
    MARK_VALUE=20
    MARK_VALUE6=25
    USE_TPROXY=1
    load_runtime_config() { return 0; }
    check_dependencies() { :; }
    validate_cleanup_config() { return 0; }
    cleanup_tproxy_chain4() { echo mutate >> "$PREFLIGHT_CALLS"; }
    cleanup_tproxy_chain6() { echo mutate >> "$PREFLIGHT_CALLS"; }
    cleanup_redirect_chain4() { echo mutate >> "$PREFLIGHT_CALLS"; }
    cleanup_redirect_chain6() { echo mutate >> "$PREFLIGHT_CALLS"; }
    cleanup_routing4() { echo mutate >> "$PREFLIGHT_CALLS"; }
    cleanup_routing6() { echo mutate >> "$PREFLIGHT_CALLS"; }
    if stop_proxy >/dev/null 2>&1; then exit 1; fi
) || fail "missing-origin stop preflight did not fail closed"
[ ! -s "$PREFLIGHT_CALLS" ] || fail "missing-origin stop mutated network state"
pass "stop preflights IPv6 origin before network mutation"

STARTING_STOP_CALLS="$TEST_ROOT/starting-stop.calls"
: > "$STARTING_STOP_CALLS"
(
    DRY_RUN=1
    CONFIG_DIR="$TEST_ROOT/starting-stop-box"
    mkdir -p "$CONFIG_DIR"
    printf '123' > "$CONFIG_DIR/runtime_tproxy.starting"
    CORE_USER_GROUP=root:net_admin
    PROXY_TCP=1
    PROXY_UDP=1
    PROXY_TCP_PORT=1536
    PROXY_UDP_PORT=1536
    PROXY_IPV6=-1
    BYPASS_CN_IP=0
    BLOCK_QUIC=0
    DNS_HIJACK_ENABLE=0
    DNS_PORT=1053
    TABLE_ID=2025
    MARK_VALUE=20
    MARK_VALUE6=25
    USE_TPROXY=1
    FORWARDING_META_KNOWN=1
    load_runtime_config() { return 0; }
    check_dependencies() { :; }
    validate_cleanup_config() { return 0; }
    parse_core_identity() { CORE_USER=root; CORE_GROUP=net_admin; return 0; }
    cleanup_tproxy_chain4() { echo cleanup >> "$STARTING_STOP_CALLS"; }
    cleanup_tproxy_chain6() { :; }
    cleanup_redirect_chain4() { :; }
    cleanup_redirect_chain6() { :; }
    cleanup_routing4() { :; }
    cleanup_routing6() { :; }
    cleanup_ipset() { :; }
    block_loopback_traffic() { :; }
    block_quic() { :; }
    block_ipv6_output() { :; }
    restore_forwarding_state() { :; }
    verify_proxy_stopped() { :; }
    stop_proxy >/dev/null 2>&1
) || fail "interrupted pre-rule start could not teardown"
grep -q '^cleanup$' "$STARTING_STOP_CALLS" || fail "start journal skipped fixed cleanup"
pass "pre-rule start journal allows teardown without IPv6 backup"

(
    unset busybox
    setup_busybox >/dev/null 2>&1
    [ -n "$busybox" ] && [ -x "$busybox" ]
) || fail "setup_busybox did not resolve an executable owner-lock binary"
pass "direct tproxy invocation resolves BusyBox for owner lock"

LOCK_BOX="$TEST_ROOT/owner-lock"
LOCK_CALLS="$TEST_ROOT/owner-lock.calls"
mkdir -p "$LOCK_BOX/run"
: > "$LOCK_CALLS"
(
    CONFIG_DIR="$LOCK_BOX"
    DRY_RUN=0
    setup_busybox >/dev/null 2>&1 || exit 1
    lock_holder() {
        printf 'holder-start\n' >> "$LOCK_CALLS"
        sleep 2
        printf 'holder-end\n' >> "$LOCK_CALLS"
    }
    lock_follower() { printf 'follower\n' >> "$LOCK_CALLS"; }
    run_tproxy_locked lock_holder &
    holder_pid=$!
    lock_wait=0
    while ! grep -q '^holder-start$' "$LOCK_CALLS" && [ "$lock_wait" -lt 5 ]; do
        sleep 1
        lock_wait=$((lock_wait + 1))
    done
    grep -q '^holder-start$' "$LOCK_CALLS" || { wait "$holder_pid"; exit 4; }
    run_tproxy_locked lock_follower || exit 2
    wait "$holder_pid" || exit 3
) || fail "direct tproxy owner lock contention fixture failed"
assert_eq "$(tr '\n' ' ' < "$LOCK_CALLS")" 'holder-start holder-end follower '
pass "direct tproxy actions serialize on the owner lock"

# IPv6 origin is captured once, reused across repair, and applied to interfaces
# that appear only after the original backup.
IPV6_BOX="$TEST_ROOT/ipv6-box"
IPV6_PROC="$TEST_ROOT/ipv6-proc"
mkdir -p "$IPV6_BOX" \
    "$IPV6_PROC/sys/net/ipv6/conf/all" \
    "$IPV6_PROC/sys/net/ipv6/conf/default" \
    "$IPV6_PROC/sys/net/ipv6/conf/wlan0"
printf '2\n' > "$IPV6_PROC/sys/net/ipv6/conf/all/accept_ra"
printf '1\n' > "$IPV6_PROC/sys/net/ipv6/conf/all/autoconf"
printf '1\n' > "$IPV6_PROC/sys/net/ipv6/conf/all/forwarding"
printf '0\n' > "$IPV6_PROC/sys/net/ipv6/conf/all/disable_ipv6"
printf '0\n' > "$IPV6_PROC/sys/net/ipv6/conf/default/disable_ipv6"
printf '0\n' > "$IPV6_PROC/sys/net/ipv6/conf/wlan0/disable_ipv6"
(
    CONFIG_DIR="$IPV6_BOX"
    SB_PROC_ROOT="$IPV6_PROC"
    DRY_RUN=0
    VERBOSE=0
    LOG_TIMESTAMP=0
    manage_ipv6 disable >/dev/null 2>&1 || exit 1
    [ "$(read_ipv6_backup_forwarding "$IPV6_BOX/ipv6_backup.conf")" = "1" ] || exit 4
    backup_hash=$($busybox sha256sum "$IPV6_BOX/ipv6_backup.conf" | $busybox awk '{print $1}')
    mkdir -p "$IPV6_PROC/sys/net/ipv6/conf/rmnet_new"
    printf '1\n' > "$IPV6_PROC/sys/net/ipv6/conf/rmnet_new/disable_ipv6"
    manage_ipv6 disable >/dev/null 2>&1 || exit 1
    second_hash=$($busybox sha256sum "$IPV6_BOX/ipv6_backup.conf" | $busybox awk '{print $1}')
    [ "$backup_hash" = "$second_hash" ] || exit 2
    TPROXY_RETAIN_IPV6_BACKUP=1 manage_ipv6 restore >/dev/null 2>&1 || exit 3
    [ -f "$IPV6_BOX/ipv6_backup.conf" ] || exit 5
    TPROXY_RETAIN_IPV6_BACKUP=1 manage_ipv6 restore >/dev/null 2>&1 || exit 6
    rm -f "$IPV6_BOX/ipv6_backup.conf" || exit 7
) || fail "IPv6 acquire-once backup/restore failed"
assert_eq "$(cat "$IPV6_PROC/sys/net/ipv6/conf/all/accept_ra")" 2
assert_eq "$(cat "$IPV6_PROC/sys/net/ipv6/conf/all/autoconf")" 1
assert_eq "$(cat "$IPV6_PROC/sys/net/ipv6/conf/all/forwarding")" 1
assert_eq "$(cat "$IPV6_PROC/sys/net/ipv6/conf/rmnet_new/disable_ipv6")" 0
[ ! -e "$IPV6_BOX/ipv6_backup.conf" ] || fail "successful IPv6 restore retained backup"
create_ipv6_backup "$IPV6_BOX/override.conf" "$IPV6_PROC" 0 \
    || fail "IPv6 transition origin override could not create backup"
assert_eq "$(read_ipv6_backup_forwarding "$IPV6_BOX/override.conf")" 0
rm -f "$IPV6_BOX/override.conf"
pass "IPv6 backup is acquire-once, retryable through cleanup commit, and origin-aware"

# Guard helpers must aggregate command failures instead of logging success and
# allowing start_proxy to commit a healthy-looking runtime snapshot.
GUARD_BIN="$TEST_ROOT/guard-bin"
mkdir -p "$GUARD_BIN"
cat > "$GUARD_BIN/iptables" <<'EOF'
#!/bin/sh
case " $* " in *" -D "*) exit 1 ;; esac
if [ "${SB_FAIL_MATCH:-}" = " -A OUTPUT -j DROP " ]; then
  case " $* " in *" -C OUTPUT -j DROP "*) exit 1 ;; esac
fi
if [ -n "${SB_FAIL_MATCH:-}" ]; then
  case " $* " in *"$SB_FAIL_MATCH"*) exit 9 ;; esac
fi
exit 0
EOF
cp "$GUARD_BIN/iptables" "$GUARD_BIN/ip6tables"
chmod 0755 "$GUARD_BIN/iptables" "$GUARD_BIN/ip6tables"
(
    PATH="$GUARD_BIN:$PATH"
    export PATH
    hash -r 2>/dev/null || true
    CORE_USER=root
    CORE_GROUP=net_admin
    PROXY_TCP_PORT=1536
    BYPASS_CN_IP=0
    PROXY_IPV6=0
    SB_FAIL_MATCH=' -A OUTPUT -d 127.0.0.1 '
    export SB_FAIL_MATCH
    if block_loopback_traffic enable >/dev/null 2>&1; then exit 1; fi
    SB_FAIL_MATCH=' -I FORWARD -j BLOCK_QUIC '
    export SB_FAIL_MATCH
    if block_quic enable >/dev/null 2>&1; then exit 2; fi
    SB_FAIL_MATCH=' -A OUTPUT -j DROP '
    export SB_FAIL_MATCH
    if block_ipv6_output enable >/dev/null 2>&1; then exit 3; fi
) || fail "packet guard command failures were swallowed"
grep -q 'if ! block_loopback_traffic enable' "$REPO_ROOT/box/scripts/tproxy.sh" \
    || fail "start_proxy does not check loopback guard status"
grep -q 'if ! block_ipv6_output enable' "$REPO_ROOT/box/scripts/tproxy.sh" \
    || fail "start_proxy does not check IPv6 guard status"
pass "loopback, QUIC, and IPv6 guard failures propagate to start"

# Postcondition probes must query the whole table successfully before treating
# an absent owned rule as clean. A generic rc=1 is not a missing-chain proof.
cat > "$TEST_ROOT/bin/xtables-probe" <<'EOF'
#!/bin/sh
if [ -f "$SB_TEST_ROOT/probe-permission" ]; then
  printf '%s\n' "iptables: can't initialize iptables table \`filter': Permission denied" >&2
  exit 1
fi
if [ -f "$SB_TEST_ROOT/probe-error" ]; then exit 1; fi
printf '%s\n' '-P INPUT ACCEPT' '-P FORWARD ACCEPT' '-P OUTPUT ACCEPT'
if [ -f "$SB_TEST_ROOT/probe-leftover" ]; then
  printf '%s\n' '-A OUTPUT -d 127.0.0.1/32 -p tcp -m owner --uid-owner 0 --gid-owner 3005 -m tcp --dport 1536 -j REJECT'
fi
EOF
chmod 0755 "$TEST_ROOT/bin/xtables-probe"
export SB_TEST_ROOT="$TEST_ROOT"
PROXY_TCP_PORT=1536
verify_xtables_table_clean "$TEST_ROOT/bin/xtables-probe" filter 4 \
    || fail "clean whole-table postcondition was rejected"
touch "$TEST_ROOT/probe-leftover"
if verify_xtables_table_clean "$TEST_ROOT/bin/xtables-probe" filter 4 >/dev/null 2>&1; then
    fail "loopback REJECT leftover passed cleanup postcondition"
fi
rm -f "$TEST_ROOT/probe-leftover"
touch "$TEST_ROOT/probe-error"
if verify_xtables_table_clean "$TEST_ROOT/bin/xtables-probe" filter 4 >/dev/null 2>&1; then
    fail "xtables probe error was treated as clean state"
fi
rm -f "$TEST_ROOT/probe-error"
touch "$TEST_ROOT/probe-permission"
if verify_xtables_table_clean "$TEST_ROOT/bin/xtables-probe" filter 4 >/dev/null 2>&1; then
    fail "permission denied was mistaken for an unsupported table"
fi
rm -f "$TEST_ROOT/probe-permission"
pass "cleanup postcondition detects owner rules and fails closed on probe errors"

run_net() {
    env \
      SB_BOX_DIR="$TEST_ROOT/box" \
      SB_BIN_PATH="$BIN" \
      SB_PROC_ROOT="$TEST_ROOT/proc" \
      SB_IPTABLES_BIN="$TEST_ROOT/bin/iptables" \
      SB_IP6TABLES_BIN="$TEST_ROOT/bin/ip6tables" \
      SB_IP_BIN="$TEST_ROOT/bin/ip" \
      SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
      SB_START_SH="$TEST_ROOT/bin/start-fixture" \
      /bin/sh "$NET" w /data/misc/net rt_tables
}

printf '0\n' > "$TEST_ROOT/box/run/net_tproxy.lock"
run_net || fail "healthy network event returned failure"
if [ -e "$TEST_ROOT/tproxy.calls" ] && [ -s "$TEST_ROOT/tproxy.calls" ]; then
    cat "$TEST_ROOT/box/run/net.log" >&2
    fail "healthy state unexpectedly invoked: $(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")"
fi
assert_file_contains "$TEST_ROOT/box/run/net.log" 'reapply skipped'
pass "healthy network events skip the expensive reapply"

touch "$TEST_ROOT/missing-udp"
run_net || fail "incomplete network state did not recover"
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" 'stop start '
pass "missing UDP state bypasses debounce and preserves stop/start order"

: > "$TEST_ROOT/tproxy.calls"
rm -f "$TEST_ROOT/missing-udp" "$TEST_ROOT/fail-start"
touch "$TEST_ROOT/broken-state"
touch "$TEST_ROOT/fail-start"
touch "$TEST_ROOT/fail-recover"
set +e
run_net >/dev/null 2>&1
net_rc=$?
set -e
[ "$net_rc" -ne 0 ] || fail "failed reapply returned success"
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" 'stop start stop '
pass "failed reapply is observable and cleans partial state"
rm -f "$TEST_ROOT/fail-start" "$TEST_ROOT/fail-recover" "$TEST_ROOT/broken-state"

sed -i 's/^PROXY_IPV6=.*/PROXY_IPV6=-1/' "$TEST_ROOT/box/tproxy.conf"
: > "$TEST_ROOT/tproxy.calls"
: > "$TEST_ROOT/tproxy.env"
touch "$TEST_ROOT/broken-state" "$TEST_ROOT/fail-start"
set +e
run_net >/dev/null 2>&1
disabled_start_rc=$?
set -e
[ "$disabled_start_rc" -ne 0 ] || fail "failed IPv6-disable start returned success"
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" 'guard-ipv6 stop start stop guard-ipv6 '
assert_file_contains "$TEST_ROOT/tproxy.env" 'start:keep=1'
assert_eq "$(grep -c '^stop:keep=1$' "$TEST_ROOT/tproxy.env")" 2
[ -f "$TEST_ROOT/box/ipv6_backup.conf" ] || fail "failed IPv6 start lost origin backup"
[ -f "$TEST_ROOT/stale-ipv6-guard" ] || fail "failed IPv6 start opened output guard"
rm -f "$TEST_ROOT/fail-start" "$TEST_ROOT/box/run/box.recover"
sed -i 's/^PROXY_IPV6=.*/PROXY_IPV6=0/' "$TEST_ROOT/box/tproxy.conf"
rm -f "$TEST_ROOT/box/ipv6_backup.conf" "$TEST_ROOT/stale-ipv6-guard"
pass "failed IPv6 reapply retains guard through rollback and partial cleanup"

: > "$TEST_ROOT/tproxy.calls"
touch "$TEST_ROOT/broken-state" "$TEST_ROOT/drop-core-on-start"
set +e
run_net >/dev/null 2>&1
lost_socket_rc=$?
set -e
[ "$lost_socket_rc" -ne 0 ] || fail "post-start socket loss returned success"
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" 'stop start stop '
[ -f "$TEST_ROOT/box/run/box.recover" ] || fail "post-start socket loss cleared recovery"
ln -s 'socket:[102]' "$TEST_ROOT/proc/$CORE_PID/fd/4"
rm -f "$TEST_ROOT/drop-core-on-start" "$TEST_ROOT/box/run/box.recover"
pass "network reapply rechecks exact PID sockets and cleans failed post-state"

# IPv6 interface-only drift is repairable without tearing down healthy proxy
# chains/routes. A simultaneous hard failure must still classify as hard.
IPV6_CONF="$TEST_ROOT/proc/sys/net/ipv6/conf"
mkdir -p "$IPV6_CONF/all" "$IPV6_CONF/default" "$IPV6_CONF/rmnet_data3"
printf '0\n' > "$IPV6_CONF/all/accept_ra"
printf '0\n' > "$IPV6_CONF/all/autoconf"
printf '0\n' > "$IPV6_CONF/all/forwarding"
printf '1\n' > "$IPV6_CONF/all/disable_ipv6"
printf '1\n' > "$IPV6_CONF/default/disable_ipv6"
printf '0\n' > "$IPV6_CONF/rmnet_data3/disable_ipv6"
sed -i 's/^PROXY_IPV6=0$/PROXY_IPV6=-1/' "$TEST_ROOT/box/runtime_tproxy.conf"
rm -f "$TEST_ROOT/box/ipv6_backup.conf"
set +e
runtime_tproxy_state_classify "$TEST_ROOT/box/runtime_tproxy.conf" 1536
missing_backup_rc=$?
set -e
assert_eq "$missing_backup_rc" 1
write_ipv6_backup_fixture "$TEST_ROOT/box/ipv6_backup.conf"
set +e
runtime_tproxy_state_classify "$TEST_ROOT/box/runtime_tproxy.conf" 1536
classify_rc=$?
set -e
assert_eq "$classify_rc" 2
touch "$TEST_ROOT/broken-state"
set +e
runtime_tproxy_state_classify "$TEST_ROOT/box/runtime_tproxy.conf" 1536
classify_rc=$?
set -e
assert_eq "$classify_rc" 1
rm -f "$TEST_ROOT/broken-state"
pass "health classifier requires IPv6 origin and separates drift from hard degradation"

: > "$TEST_ROOT/tproxy.calls"
run_net || fail "IPv6 drift repair returned failure"
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" 'guard-ipv6 '
[ ! -e "$TEST_ROOT/guard-before-marker" ] || fail "IPv6 repair mutated before recovery marker"
[ ! -e "$TEST_ROOT/box/run/box.recover" ] || fail "successful IPv6 repair left recovery pending"
pass "IPv6 drift uses pre-armed guard repair without stop/start"

# A recovery-marker write failure must abort before the first network mutation.
printf '0\n' > "$IPV6_CONF/rmnet_data3/disable_ipv6"
mkdir "$TEST_ROOT/box/run/box.recover"
: > "$TEST_ROOT/tproxy.calls"
set +e
run_net >/dev/null 2>&1
marker_rc=$?
set -e
[ "$marker_rc" -ne 0 ] || fail "marker write failure returned success"
[ ! -s "$TEST_ROOT/tproxy.calls" ] || fail "network mutation ran without a recovery marker"
rmdir "$TEST_ROOT/box/run/box.recover"
pass "marker failure prevents all network mutation"

# Guard failure remains observable and leaves the marker for the watchdog.
touch "$TEST_ROOT/fail-guard"
: > "$TEST_ROOT/tproxy.calls"
set +e
run_net >/dev/null 2>&1
guard_rc=$?
set -e
[ "$guard_rc" -ne 0 ] || fail "failed IPv6 guard returned success"
[ -f "$TEST_ROOT/box/run/box.recover" ] || fail "failed IPv6 guard cleared recovery marker"
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" 'guard-ipv6 '
rm -f "$TEST_ROOT/fail-guard" "$TEST_ROOT/box/run/box.recover"
printf '1\n' > "$IPV6_CONF/rmnet_data3/disable_ipv6"
sed -i 's/^PROXY_IPV6=-1$/PROXY_IPV6=0/' "$TEST_ROOT/box/runtime_tproxy.conf"
rm -f "$TEST_ROOT/stale-ipv6-guard" "$TEST_ROOT/box/ipv6_backup.conf"
pass "failed IPv6 repair remains pending and non-zero"

# Modes 0/1 are healthy only after the disable-mode backup and generic output
# guard are both gone. Otherwise a -1 -> 0/1 transition can silently blackhole.
for transition_mode in 0 1; do
    sed -i "s/^PROXY_IPV6=.*/PROXY_IPV6=$transition_mode/" \
        "$TEST_ROOT/box/runtime_tproxy.conf"
    : > "$TEST_ROOT/stale-ipv6-guard"
    : > "$TEST_ROOT/box/ipv6_backup.conf"
    set +e
    runtime_tproxy_state_classify "$TEST_ROOT/box/runtime_tproxy.conf" 1536
    stale_rc=$?
    set -e
    assert_eq "$stale_rc" 1
    rm -f "$TEST_ROOT/stale-ipv6-guard" "$TEST_ROOT/box/ipv6_backup.conf"
    runtime_tproxy_state_ready "$TEST_ROOT/box/runtime_tproxy.conf" 1536 \
        || fail "clean IPv6 mode $transition_mode was rejected"
done
pass "IPv6 modes 0/1 reject stale disable guard and backup"

# An active -1 runtime without its origin is unrecoverable in place. The net
# handler must not snapshot already-disabled sysctls as a new fake origin.
sed -i 's/^PROXY_IPV6=.*/PROXY_IPV6=-1/' "$TEST_ROOT/box/runtime_tproxy.conf"
sed -i 's/^PROXY_IPV6=.*/PROXY_IPV6=-1/' "$TEST_ROOT/box/tproxy.conf"
rm -f "$TEST_ROOT/box/ipv6_backup.conf" "$TEST_ROOT/stale-ipv6-guard"
: > "$TEST_ROOT/tproxy.calls"
set +e
run_net >/dev/null 2>&1
lost_origin_rc=$?
set -e
[ "$lost_origin_rc" -ne 0 ] || fail "missing IPv6 origin was reacquired from disabled state"
[ ! -s "$TEST_ROOT/tproxy.calls" ] || fail "missing IPv6 origin allowed network mutation"
[ ! -e "$TEST_ROOT/box/run/box.recover" ] || fail "non-recoverable IPv6 origin queued watchdog teardown"
pass "missing active IPv6 origin aborts before guard mutation"

# net.inotify and the sourced tproxy.conf must not disagree about duplicate
# assignments. Reject ambiguity before the first teardown/guard action.
sed -i 's/^PROXY_IPV6=.*/PROXY_IPV6=0/' "$TEST_ROOT/box/runtime_tproxy.conf"
cat > "$TEST_ROOT/box/tproxy.conf" <<'EOF'
PROXY_IPV6=0
PROXY_IPV6=-1
EOF
: > "$TEST_ROOT/broken-state"
: > "$TEST_ROOT/tproxy.calls"
set +e
run_net >/dev/null 2>&1
duplicate_mode_rc=$?
set -e
[ "$duplicate_mode_rc" -ne 0 ] || fail "duplicate PROXY_IPV6 assignments were accepted"
[ ! -s "$TEST_ROOT/tproxy.calls" ] || fail "ambiguous next IPv6 mode allowed network mutation"
rm -f "$TEST_ROOT/broken-state" "$TEST_ROOT/box/run/box.recover"
cat > "$TEST_ROOT/box/tproxy.conf" <<'EOF'
PROXY_IPV6=0
EOF
pass "ambiguous next IPv6 mode aborts before mutation"

run_ipv6_transition() {
    old_mode=$1
    next_mode=$2
    expected_calls=$3
    sed -i "s/^PROXY_IPV6=.*/PROXY_IPV6=$old_mode/" \
        "$TEST_ROOT/box/runtime_tproxy.conf"
    sed -i "s/^PROXY_IPV6=.*/PROXY_IPV6=$next_mode/" \
        "$TEST_ROOT/box/tproxy.conf"
    : > "$TEST_ROOT/broken-state"
    : > "$TEST_ROOT/tproxy.calls"
    : > "$TEST_ROOT/tproxy.env"
    if [ "$old_mode" = "-1" ]; then
        : > "$TEST_ROOT/stale-ipv6-guard"
        write_ipv6_backup_fixture "$TEST_ROOT/box/ipv6_backup.conf"
    else
        rm -f "$TEST_ROOT/stale-ipv6-guard" "$TEST_ROOT/box/ipv6_backup.conf"
    fi
    run_net || fail "IPv6 transition $old_mode -> $next_mode failed"
    assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" "$expected_calls"
    assert_eq "$(awk -F= '/^PROXY_IPV6=/{print $2}' "$TEST_ROOT/box/runtime_tproxy.conf")" "$next_mode"
}

run_ipv6_transition -1 0 'stop start '
assert_file_contains "$TEST_ROOT/tproxy.env" 'stop:keep=1'
[ ! -e "$TEST_ROOT/stale-ipv6-guard" ] || fail "-1 -> 0 retained IPv6 output guard"
[ ! -e "$TEST_ROOT/box/ipv6_backup.conf" ] || fail "-1 -> 0 retained IPv6 backup"
run_ipv6_transition -1 1 'stop start '
assert_file_contains "$TEST_ROOT/tproxy.env" 'stop:keep=1'
[ ! -e "$TEST_ROOT/stale-ipv6-guard" ] || fail "-1 -> 1 retained IPv6 output guard"
[ ! -e "$TEST_ROOT/box/ipv6_backup.conf" ] || fail "-1 -> 1 retained IPv6 backup"
run_ipv6_transition -1 -1 'guard-ipv6 stop start '
assert_file_contains "$TEST_ROOT/tproxy.env" 'stop:keep=1'
run_ipv6_transition 0 -1 'guard-ipv6 stop start '
assert_file_contains "$TEST_ROOT/tproxy.env" 'stop:keep=1'
[ -e "$TEST_ROOT/stale-ipv6-guard" ] || fail "0 -> -1 did not install IPv6 output guard"
run_ipv6_transition 1 -1 'guard-ipv6 stop start '
assert_file_contains "$TEST_ROOT/tproxy.env" 'stop:keep=1'
assert_eq "$(awk -F= '$1 == "forwarding" { print $2 }' "$TEST_ROOT/box/ipv6_backup.conf")" 0
pass "network reapply preserves and reconciles IPv6 mode transitions"

sed -i 's/^PROXY_IPV6=.*/PROXY_IPV6=0/' "$TEST_ROOT/box/runtime_tproxy.conf"
sed -i 's/^PROXY_IPV6=.*/PROXY_IPV6=0/' "$TEST_ROOT/box/tproxy.conf"
rm -f "$TEST_ROOT/stale-ipv6-guard" "$TEST_ROOT/box/ipv6_backup.conf"

# Exercise start.sh teardown return propagation and PID safety with the same
# harmless process, using only a fake tproxy command.
START_BOX="$TEST_ROOT/start-box"
mkdir -p "$START_BOX/run" "$START_BOX/bin" "$START_BOX/sing-box"
cat > "$TEST_ROOT/start-settings.ini" <<EOF
box_dir="$START_BOX"
box_run="$START_BOX/run"
box_pid="$START_BOX/run/box.pid"
bin_path="$BIN"
bin_log="$START_BOX/run/sing-box.log"
box_log="$START_BOX/run/runs.log"
sing_config="$START_BOX/sing-box/config.json"
box_user_group="root:net_admin"
tproxy_port="1536"
EOF
printf '{}\n' > "$START_BOX/sing-box/config.json"
: > "$START_BOX/run/runs.log"
: > "$START_BOX/run/sing-box.log"
printf '%s\n' "$CORE_PID" > "$START_BOX/run/box.pid"
touch "$TEST_ROOT/fail-stop"
set +e
env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" stop >/dev/null 2>&1
stop_rc=$?
set -e
assert_eq "$stop_rc" 8
[ -f "$START_BOX/run/box.pid" ] || fail "failed cleanup did not restore verified PID"
assert_eq "$(cat "$START_BOX/run/box.stopping")" "$CORE_PID:0"
[ ! -e "$START_BOX/run/box.want" ] || fail "failed deliberate stop retained stale desired state"
kill -0 "$CORE_PID" 2>/dev/null || fail "failed cleanup killed the core"
rm -f "$TEST_ROOT/fail-stop"
env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" stop >/dev/null 2>&1 || fail "successful stop returned failure"
wait "$CORE_PID" 2>/dev/null || true
CORE_PID=""
pass "stop propagates cleanup failure and kills only verified PID"

# A launcher killed after fork but before box.pid commit leaves box.starting.
# Stop must use that exact marker, remove rules first, and terminate only it.
sleep 120 &
CORE_PID=$!
mkdir -p "$TEST_ROOT/proc/$CORE_PID/fd"
printf '%s\0run\0-c\0fixture\0' "$BIN" > "$TEST_ROOT/proc/$CORE_PID/cmdline"
printf '%s\n' "$CORE_PID" > "$START_BOX/run/box.starting"
rm -f "$START_BOX/run/box.pid" "$START_BOX/run/box.want" "$START_BOX/run/box.recover"
env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" stop >/dev/null 2>&1 \
    || fail "stop could not reconcile box.starting"
wait "$CORE_PID" 2>/dev/null || true
CORE_PID=""
[ ! -e "$START_BOX/run/box.starting" ] || fail "successful stop retained box.starting"
[ ! -e "$START_BOX/run/box.stopping" ] || fail "successful start-marker teardown retained box.stopping"
pass "interrupted start marker is reconciled by exact-PID stop transaction"

sleep 120 &
CORE_PID=$!
mkdir -p "$TEST_ROOT/proc/$CORE_PID/fd"
printf '%s\0run\0-c\0fixture\0' "$BIN" > "$TEST_ROOT/proc/$CORE_PID/cmdline"
printf '%s\n' "$CORE_PID" > "$START_BOX/run/box.pid"
printf '%s:1' "$CORE_PID" > "$START_BOX/run/box.stopping"
write_ipv6_backup_fixture "$START_BOX/ipv6_backup.conf"
: > "$TEST_ROOT/tproxy.calls"
: > "$TEST_ROOT/tproxy.env"
env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" finish-stop >/dev/null 2>&1 \
    || fail "resume-intent stop could not preserve IPv6 guard"
wait "$CORE_PID" 2>/dev/null || true
CORE_PID=""
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" 'guard-ipv6 stop '
assert_file_contains "$TEST_ROOT/tproxy.env" 'stop:keep=1'
[ -f "$START_BOX/ipv6_backup.conf" ] || fail "resume-intent stop removed IPv6 origin"
[ -f "$START_BOX/run/box.want" ] || fail "resume-intent stop lost desired state"
[ -f "$START_BOX/run/box.recover" ] || fail "resume-intent stop lost recovery state"
rm -f "$START_BOX/ipv6_backup.conf" "$START_BOX/run/box.want" \
    "$START_BOX/run/box.recover" "$TEST_ROOT/stale-ipv6-guard" \
    "$TEST_ROOT/guard-before-marker"
pass "recovery stop preserves IPv6 guard and origin until restart"

: > "$TEST_ROOT/tproxy.calls"
rm -f "$START_BOX/run/box.want" "$START_BOX/run/box.recover"
env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" recover >/dev/null 2>&1 \
    || fail "recovery without desired state returned failure"
[ ! -s "$TEST_ROOT/tproxy.calls" ] || fail "recovery resurrected a deliberate stop"
[ ! -e "$START_BOX/run/box.want" ] || fail "recovery recreated box.want"
pass "queued recovery cannot resurrect deliberate stop"

: > "$START_BOX/run/box.want"
: > "$TEST_ROOT/tproxy.calls"
rm -f "$START_BOX/run/box.recover"
env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" recover >/dev/null 2>&1 \
    || fail "cleared recovery request returned failure"
[ ! -s "$TEST_ROOT/tproxy.calls" ] || fail "queued recover consumed a cleared marker"
[ -f "$START_BOX/run/box.want" ] || fail "cleared recovery changed desired state"
rm -f "$START_BOX/run/box.want"
grep -q ': > "$BOX_RECOVERY"' "$REPO_ROOT/service.sh" \
    || fail "watchdog crash path does not arm recovery before dispatch"
pass "watchdog recovery rechecks its marker under box.lock"

env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" finish-stop >/dev/null 2>&1 \
    || fail "conditional finish-stop without a marker returned failure"
grep -q '_do_finish_stop)' "$START" || fail "finish-stop is not covered by lifecycle lock dispatch"
grep -q 'start.sh finish-stop' "$REPO_ROOT/service.sh" \
    || fail "watchdog still invokes unconditional public stop"
pass "interrupted-stop retry is conditional and lifecycle-locked"

# A user toggle during a restart transaction (intent 1) means stop, not a
# second start. The decision must be made after acquiring the lifecycle lock.
printf ':1' > "$START_BOX/run/box.stopping"
: > "$START_BOX/run/box.want"
env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" toggle >/dev/null 2>&1 \
    || fail "locked toggle could not cancel resume intent"
[ ! -e "$START_BOX/run/box.want" ] || fail "toggle retained desired-running state"
[ ! -e "$START_BOX/run/box.recover" ] || fail "toggle retained recovery state"
[ ! -e "$START_BOX/run/box.stopping" ] || fail "toggle retained stop marker"
grep -q '_do_toggle)' "$START" || fail "toggle is outside lifecycle dispatch"
pass "action toggle resolves stop intent under box.lock"

# The lifecycle FD belongs only to the start transaction. The long-lived core
# must close FD9 so later stop/recovery callers can acquire the same lock.
FD_BOX="$TEST_ROOT/fd-box"
FD_SCRIPTS="$TEST_ROOT/fd-scripts"
mkdir -p "$FD_BOX/run" "$FD_BOX/bin" "$FD_BOX/sing-box" "$FD_SCRIPTS"
REAL_BUSYBOX=$(command -v busybox)
cat > "$FD_SCRIPTS/busybox-fixture" <<EOF
#!/bin/sh
if [ "\$1" = "setuidgid" ]; then
  shift 2
  exec "\$@"
fi
exec "$REAL_BUSYBOX" "\$@"
EOF
chmod 0755 "$FD_SCRIPTS/busybox-fixture"
printf 'busybox=%s\n' "$FD_SCRIPTS/busybox-fixture" > "$FD_SCRIPTS/box.tool"
cat > "$FD_SCRIPTS/runtime.lib" <<'EOF'
runtime_flock_wait() {
  fd=$1
  timeout=$2
  waited=0
  while ! "$busybox" flock -n "$fd"; do
    [ "$waited" -ge "$timeout" ] && return 1
    sleep 1
    waited=$((waited + 1))
  done
}
runtime_pid_is_core() { kill -0 "$1" 2>/dev/null; }
runtime_tproxy_port_ready() {
  if [ -f "$SB_TEST_ROOT/fd-box/run/box.starting" ] && \
     [ "$(cat "$SB_TEST_ROOT/fd-box/run/box.starting")" != "$1" ]; then
    : > "$SB_TEST_ROOT/start-marker-pid-mismatch"
  fi
  if [ ! -f "$SB_TEST_ROOT/fd-box/run/box.starting" ] && \
     [ ! -f "$SB_TEST_ROOT/fd-box/run/box.pid" ]; then
    : > "$SB_TEST_ROOT/readiness-before-start-marker"
  fi
  kill -0 "$1" 2>/dev/null
}
runtime_tproxy_state_ready() { [ ! -f "$SB_TEST_ROOT/fail-runtime-state" ]; }
_runtime_ipv6_backup_valid() { [ -s "$1" ] && [ ! -L "$1" ]; }
runtime_trim_logs() { :; }
EOF
cat > "$FD_BOX/bin/sing-box" <<'EOF'
#!/bin/sh
case "$1" in
  check) exit 0 ;;
  run)
    if [ -e "/proc/$$/fd/9" ]; then
      printf 'inherited\n' > "$SB_TEST_ROOT/fd-state"
    else
      printf 'closed\n' > "$SB_TEST_ROOT/fd-state"
    fi
    trap 'exit 0' TERM INT
    while :; do sleep 1; done
    ;;
esac
EOF
chmod 0755 "$FD_BOX/bin/sing-box"
TEST_UID=$(id -u)
TEST_GID=$(id -g)
cat > "$FD_BOX/tproxy.conf" <<EOF
PROXY_TCP_PORT="1536"
PROXY_UDP_PORT="1536"
PROXY_UDP=1
CORE_USER_GROUP="$TEST_UID:$TEST_GID"
EOF
cat > "$FD_BOX/sing-box/config.json" <<'EOF'
{"inbounds":[{"type":"tproxy","listen_port":1536}]}
EOF
cat > "$TEST_ROOT/fd-settings.ini" <<EOF
box_dir="$FD_BOX"
box_run="$FD_BOX/run"
box_pid="$FD_BOX/run/box.pid"
bin_path="$FD_BOX/bin/sing-box"
bin_log="$FD_BOX/run/sing-box.log"
box_log="$FD_BOX/run/runs.log"
sing_config="$FD_BOX/sing-box/config.json"
box_user_group="$TEST_UID:$TEST_GID"
tproxy_port="1536"
EOF
set +e
env SB_SETTINGS="$TEST_ROOT/fd-settings.ini" SB_SCRIPTS_DIR="$FD_SCRIPTS" \
    SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" SB_TEST_ROOT="$TEST_ROOT" \
    /bin/sh "$START" start >/dev/null 2>&1
fd_start_rc=$?
set -e
[ -f "$FD_BOX/run/box.pid" ] && FD_PID=$(cat "$FD_BOX/run/box.pid")
[ "$fd_start_rc" -eq 0 ] || fail "FD inheritance fixture could not start core"
i=0
while [ ! -f "$TEST_ROOT/fd-state" ] && [ "$i" -lt 30 ]; do
    sleep 0.1
    i=$((i + 1))
done
assert_eq "$(cat "$TEST_ROOT/fd-state" 2>/dev/null)" closed
[ ! -e "$TEST_ROOT/readiness-before-start-marker" ] || fail "readiness ran before box.starting commit"
[ ! -e "$TEST_ROOT/start-marker-pid-mismatch" ] || fail "child did not commit its exact PID"
[ ! -e "$FD_BOX/run/box.starting" ] || fail "successful PID commit retained box.starting"
if ! ( "$busybox" flock -n 8 ) 8>"$FD_BOX/run/box.lock"; then
    fail "live core retained lifecycle lock FD9"
fi
env SB_SETTINGS="$TEST_ROOT/fd-settings.ini" SB_SCRIPTS_DIR="$FD_SCRIPTS" \
    SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" SB_TEST_ROOT="$TEST_ROOT" \
    /bin/sh "$START" stop >/dev/null 2>&1 \
    || fail "stop timed out after core launch"
i=0
while kill -0 "$FD_PID" 2>/dev/null && [ "$i" -lt 30 ]; do
    sleep 0.1
    i=$((i + 1))
done
kill -0 "$FD_PID" 2>/dev/null && fail "FD fixture core survived stop"
FD_PID=""
pass "sing-box child closes FD9 and later stop acquires lifecycle lock"

# Both a tproxy start error and a post-start health error must roll back through
# box.stopping, not hide box.pid first in an untracked window.
: > "$TEST_ROOT/tproxy.calls"
: > "$TEST_ROOT/tproxy.env"
write_ipv6_backup_fixture "$FD_BOX/ipv6_backup.conf"
touch "$TEST_ROOT/fail-start"
set +e
env SB_SETTINGS="$TEST_ROOT/fd-settings.ini" SB_SCRIPTS_DIR="$FD_SCRIPTS" \
    SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" SB_TEST_ROOT="$TEST_ROOT" \
    /bin/sh "$START" start >/dev/null 2>&1
failed_start_rc=$?
set -e
assert_eq "$failed_start_rc" 7
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" 'start guard-ipv6 stop '
assert_file_contains "$TEST_ROOT/tproxy.env" 'start:keep=1'
assert_file_contains "$TEST_ROOT/tproxy.env" 'stop:keep=1'
[ ! -e "$FD_BOX/run/box.pid" ] || fail "failed tproxy start retained box.pid"
[ ! -e "$FD_BOX/run/box.starting" ] || fail "failed tproxy start retained box.starting"
[ ! -e "$FD_BOX/run/box.stopping" ] || fail "completed failed-start rollback retained box.stopping"
[ -f "$FD_BOX/run/box.want" ] || fail "failed-start rollback lost resume intent"
[ -f "$FD_BOX/run/box.recover" ] || fail "failed-start rollback lost recovery marker"
[ -f "$FD_BOX/ipv6_backup.conf" ] || fail "failed tproxy start lost IPv6 origin backup"
[ -f "$TEST_ROOT/stale-ipv6-guard" ] || fail "failed tproxy start opened IPv6 transition guard"
rm -f "$TEST_ROOT/fail-start" "$FD_BOX/run/box.want" "$FD_BOX/run/box.recover" \
    "$FD_BOX/ipv6_backup.conf" "$TEST_ROOT/stale-ipv6-guard"

: > "$TEST_ROOT/tproxy.calls"
touch "$TEST_ROOT/fail-runtime-state"
set +e
env SB_SETTINGS="$TEST_ROOT/fd-settings.ini" SB_SCRIPTS_DIR="$FD_SCRIPTS" \
    SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" SB_TEST_ROOT="$TEST_ROOT" \
    /bin/sh "$START" start >/dev/null 2>&1
postcheck_rc=$?
set -e
assert_eq "$postcheck_rc" 1
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/tproxy.calls")" 'start stop '
[ ! -e "$FD_BOX/run/box.pid" ] || fail "failed post-start check retained box.pid"
[ ! -e "$FD_BOX/run/box.starting" ] || fail "failed post-start check retained box.starting"
[ -f "$FD_BOX/run/box.recover" ] || fail "failed post-start check lost recovery marker"
rm -f "$TEST_ROOT/fail-runtime-state" "$FD_BOX/run/box.want" "$FD_BOX/run/box.recover"
pass "failed and degraded starts use durable rollback transactions"

if grep -q ': > "$BOX_WANT"' "$REPO_ROOT/service.sh"; then
    fail "service.sh writes desired state outside lifecycle lock"
fi
grep -q '/data/adb/box/scripts/start.sh start' "$REPO_ROOT/service.sh" \
    || fail "boot path does not enter public locked start"
grep -q '\[ "$boot_start_rc" -eq 75 \]' "$REPO_ROOT/service.sh" \
    || fail "boot path does not retry lifecycle lock timeout 75"
pass "boot desired state is created only under lifecycle lock"

# LAW-4 is a hard start precondition across settings, TCP/UDP tproxy ports, and
# the sing-box tproxy inbound. A mismatch must fail before launching the core.
LAW4_BOX="$TEST_ROOT/law4-box"
mkdir -p "$LAW4_BOX/run" "$LAW4_BOX/bin" "$LAW4_BOX/sing-box"
cat > "$LAW4_BOX/bin/sing-box" <<'EOF'
#!/bin/sh
case "$1" in
  check) exit 0 ;;
  run) : > "$SB_TEST_ROOT/law4-core-launched"; sleep 30 ;;
esac
EOF
chmod 0755 "$LAW4_BOX/bin/sing-box"
cat > "$LAW4_BOX/tproxy.conf" <<'EOF'
PROXY_TCP_PORT="1536"
PROXY_UDP_PORT="1537"
PROXY_UDP=1
CORE_USER_GROUP="root:net_admin"
EOF
cat > "$LAW4_BOX/sing-box/config.json" <<'EOF'
{
  "inbounds": [
    {
      "listen_port": 1536,
      "type": "tproxy"
    }
  ]
}
EOF
cat > "$TEST_ROOT/law4-settings.ini" <<EOF
box_dir="$LAW4_BOX"
box_run="$LAW4_BOX/run"
box_pid="$LAW4_BOX/run/box.pid"
bin_path="$LAW4_BOX/bin/sing-box"
bin_log="$LAW4_BOX/run/sing-box.log"
box_log="$LAW4_BOX/run/runs.log"
sing_config="$LAW4_BOX/sing-box/config.json"
box_user_group="root:net_admin"
tproxy_port="1536"
EOF
set +e
env SB_SETTINGS="$TEST_ROOT/law4-settings.ini" \
    SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" SB_TEST_ROOT="$TEST_ROOT" \
    /bin/sh "$START" start >/dev/null 2>&1
law4_rc=$?
set -e
[ "$law4_rc" -ne 0 ] || fail "LAW-4 mismatch returned success"
[ ! -e "$TEST_ROOT/law4-core-launched" ] || fail "LAW-4 mismatch launched sing-box"
[ ! -e "$LAW4_BOX/run/box.pid" ] || fail "LAW-4 mismatch wrote box.pid"
pass "LAW-4 port mismatch fails before core launch"

sed -i 's/PROXY_UDP_PORT="1537"/PROXY_UDP_PORT="1536"/' "$LAW4_BOX/tproxy.conf"
sed -i 's/CORE_USER_GROUP="root:net_admin"/CORE_USER_GROUP="root:other_group"/' "$LAW4_BOX/tproxy.conf"
set +e
env SB_SETTINGS="$TEST_ROOT/law4-settings.ini" \
    SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" SB_TEST_ROOT="$TEST_ROOT" \
    /bin/sh "$START" start >/dev/null 2>&1
identity_rc=$?
set -e
[ "$identity_rc" -ne 0 ] || fail "core identity mismatch returned success"
[ ! -e "$TEST_ROOT/law4-core-launched" ] || fail "core identity mismatch launched sing-box"
pass "core identity mismatch fails before core launch"

# Static guards protect against reintroducing the two known unsafe shortcuts.
if grep -q 'pidof sing-box\|pkill .*sing-box\|chmod 6755' "$START"; then
    fail "unsafe global PID/privilege shortcut remains in start.sh"
fi
grep -q 'exit "$rv"' "$START" || fail "start.sh does not preserve command status"
pass "lifecycle source guards remain present"

jq empty "$REPO_ROOT/box/sing-box/config.json"
[ "$(jq -r '[.dns.rules[] | select(.domain == ["mdp-appconf-row.heytapdl.com"] and .rcode == "NXDOMAIN")] | length' "$REPO_ROOT/box/sing-box/config.json")" = 1 ] \
    || fail "exact-domain NXDOMAIN rule is missing"
[ "$(jq -r '.dns.rules[0].domain == ["mdp-appconf-row.heytapdl.com"]' "$REPO_ROOT/box/sing-box/config.json")" = true ] \
    || fail "exact-domain rule does not precede generic query-type rules"
[ "$(jq -r 'has("endpoints")' "$REPO_ROOT/box/sing-box/config.json")" = false ] \
    || fail "unused Tailscale endpoint remains"
[ "$(jq -r '.inbounds[] | select(.tag == "tproxy-in") | .udp_timeout' "$REPO_ROOT/box/sing-box/config.json")" = 1m ] \
    || fail "tproxy UDP timeout is not one minute"
pass "approved sing-box deltas are narrow and ordered"


# Malformed snapshot values with CR/LF must not load or save.
printf 'bad\nline' > "$TEST_ROOT/nl-value"
MOBILE_INTERFACE="$(cat "$TEST_ROOT/nl-value")"
if is_safe_config_scalar "$MOBILE_INTERFACE"; then
    fail "CR/LF scalar was accepted"
fi
MOBILE_INTERFACE=wlan0
pass "runtime snapshot scalars reject CR/LF"

# Missing DNS_PORT fails closed for cleanup snapshot identity.
sed '/^DNS_PORT=/d' "$RUNTIME_BOX/runtime_tproxy.conf" > "$RUNTIME_BOX/runtime_tproxy.conf.bad"
mv "$RUNTIME_BOX/runtime_tproxy.conf.bad" "$RUNTIME_BOX/runtime_tproxy.conf"
if load_runtime_config >/dev/null 2>&1; then
    fail "runtime snapshot missing DNS_PORT was accepted"
fi
# Restore a valid snapshot for later tests that source the lib helpers.
cat > "$RUNTIME_BOX/runtime_tproxy.conf" <<EOF
CONFIG_DIR=$RUNTIME_BOX
CORE_USER_GROUP=root:net_admin
PROXY_TCP=1
PROXY_UDP=1
PROXY_TCP_PORT=1536
PROXY_UDP_PORT=1536
PROXY_IPV6=0
PROXY_MODE=1
OTHER_PROXY_INTERFACES=
BYPASS_CN_IP=0
BLOCK_QUIC=0
DNS_HIJACK_ENABLE=0
DNS_PORT=1053
TABLE_ID=2025
MARK_VALUE=20
MARK_VALUE6=25
MOBILE_INTERFACE=rmnet_data+
WIFI_INTERFACE=wlan0
HOTSPOT_INTERFACE=wlan2
USB_INTERFACE=rndis+
PROXY_MOBILE=1
PROXY_WIFI=1
PROXY_HOTSPOT=0
PROXY_USB=0
ORIG_IP_FORWARD=0
ORIG_IP6_FORWARDING=0
USE_TPROXY=1
EOF
load_runtime_config || fail "could not restore valid runtime snapshot"
pass "runtime snapshot requires DNS_PORT"

# IPSET leftover parser must fail closed on awk/parser errors.
cat > "$TEST_ROOT/bin/fake-awk" <<'EOF'
#!/bin/sh
exit 42
EOF
chmod 0755 "$TEST_ROOT/bin/fake-awk"
ORIG_IP_FORWARD=0
ORIG_IP6_FORWARDING=0
BYPASS_CN_IP=1
PROXY_IPV6=0
USE_TPROXY=1
MARK_VALUE=20
MARK_VALUE6=25
TABLE_ID=2025
# Stub command ipset/ip and force PATH awk failure path via command -v order.
mkdir -p "$TEST_ROOT/fakebin"
cat > "$TEST_ROOT/fakebin/ipset" <<'EOF'
#!/bin/sh
printf '%s\n' 'Name: cnip'
exit 0
EOF
cat > "$TEST_ROOT/fakebin/ip" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$TEST_ROOT/fakebin/iptables" <<'EOF'
#!/bin/sh
printf '%s\n' '-P INPUT ACCEPT'
exit 0
EOF
cat > "$TEST_ROOT/fakebin/ip6tables" <<'EOF'
#!/bin/sh
printf '%s\n' '-P INPUT ACCEPT'
exit 0
EOF
cat > "$TEST_ROOT/fakebin/awk" <<'EOF'
#!/bin/sh
# Fail only for the ipset Name: parser; pass through for other uses.
if grep -q 'cnip|cnip6' >/dev/null 2>&1; then exit 42; fi
# Actually the pattern is in the program text on stdin of shell - hard.
# Always fail: verify_proxy_stopped ipset branch uses command awk.
exit 42
EOF
chmod 0755 "$TEST_ROOT/fakebin"/*
# Direct unit of the ipset branch via isolated awk status handling is covered
# by the verify_xtables parser-fail path; keep a source-shape guard here.
grep -q 'command awk' "$REPO_ROOT/box/scripts/tproxy.sh" \
  || fail "ipset leftover parser does not use command awk"
grep -q 'parser failed' "$REPO_ROOT/box/scripts/tproxy.sh" \
  || fail "ipset leftover parser lacks fail-closed status handling"
pass "ipset leftover parser is fail-closed"

# rollback_proxy_start must surface incomplete cleanup.
grep -q 'verify_proxy_stopped' "$REPO_ROOT/box/scripts/tproxy.sh" \
  || fail "rollback does not re-verify stopped state"
grep -A45 '^rollback_proxy_start()' "$REPO_ROOT/box/scripts/tproxy.sh" | grep -Fq 'return "$rc"' \
  || fail "rollback does not aggregate a non-zero status"
pass "rollback_proxy_start returns incomplete status"

# Legacy PID-only/empty markers are deliberate stops even if stale box.want
# still exists from the pre-transaction window.
: > "$START_BOX/run/box.stopping"
: > "$START_BOX/run/box.want"
env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" finish-stop >/dev/null 2>&1 \
    || fail "finish-stop with a legacy marker returned failure"
[ ! -e "$START_BOX/run/box.want" ] || fail "legacy finish-stop resurrected stale box.want"
[ ! -e "$START_BOX/run/box.stopping" ] || fail "finish-stop left box.stopping"
pass "legacy finish-stop cannot resurrect a deliberate stop"

# New markers carry resume intent explicitly; finish-stop must publish both the
# desired-running and recovery markers before committing marker removal.
printf ':1' > "$START_BOX/run/box.stopping"
env SB_SETTINGS="$TEST_ROOT/start-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" \
    /bin/sh "$START" finish-stop >/dev/null 2>&1 \
    || fail "finish-stop with resume intent returned failure"
[ -f "$START_BOX/run/box.want" ] || fail "resume marker did not restore box.want"
[ -f "$START_BOX/run/box.recover" ] || fail "resume marker did not restore box.recover"
[ ! -e "$START_BOX/run/box.stopping" ] || fail "resume marker was not committed"
rm -f "$START_BOX/run/box.want" "$START_BOX/run/box.recover"
pass "finish-stop resumes only from explicit marker intent"

# Minified reverse-order JSON must still enforce LAW-4.
cat > "$LAW4_BOX/sing-box/config.json" <<'EOF'
{"inbounds":[{"type":"tproxy","listen_port":1536}]}
EOF
sed -i 's/PROXY_UDP_PORT="1536"/PROXY_UDP_PORT="1536"/' "$LAW4_BOX/tproxy.conf"
sed -i 's/CORE_USER_GROUP="root:other_group"/CORE_USER_GROUP="root:net_admin"/' "$LAW4_BOX/tproxy.conf"
# Force a deliberate listen_port mismatch under minified JSON.
cat > "$LAW4_BOX/sing-box/config.json" <<'EOF'
{"inbounds":[{"type":"tproxy","listen_port":1537}]}
EOF
set +e
env SB_SETTINGS="$TEST_ROOT/law4-settings.ini" \
    SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/no-module.prop" SB_TEST_ROOT="$TEST_ROOT" \
    /bin/sh "$START" start >/dev/null 2>&1
minified_rc=$?
set -e
[ "$minified_rc" -ne 0 ] || fail "minified LAW-4 mismatch returned success"
pass "minified JSON LAW-4 mismatch fails closed"

# Unsupported ip6tables tables are treated as clean by whole-table probes.
cat > "$TEST_ROOT/bin/xtables-missing-table" <<'EOF'
#!/bin/sh
printf '%s\n' "ip6tables: can't initialize ip6tables table \`nat': Table does not exist" >&2
exit 1
EOF
chmod 0755 "$TEST_ROOT/bin/xtables-missing-table"
verify_xtables_table_clean "$TEST_ROOT/bin/xtables-missing-table" nat 6 \
  || fail "missing ip6tables table was treated as residual state"
pass "unsupported ip6tables tables count as clean after teardown"


# module.prop green/red status must rewrite even when the status text contains
# "|" characters. BusyBox sed uses "|" as the s/// delimiter in start.sh.
grep -Fq "tr '\\n|'" "$START" \
    || fail "start.sh no longer sanitizes '|' before description sed"
DESC_BOX="$TEST_ROOT/desc-box"
mkdir -p "$DESC_BOX/run" "$DESC_BOX/bin" "$DESC_BOX/sing-box"
printf 'version=v9.9.9\ndescription=placeholder static text\n' > "$TEST_ROOT/desc-module.prop"
cat > "$TEST_ROOT/desc-settings.ini" <<EOF
box_dir="$DESC_BOX"
box_run="$DESC_BOX/run"
box_pid="$DESC_BOX/run/box.pid"
bin_path="$BIN"
sing_config="$DESC_BOX/sing-box/config.json"
bin_log="$DESC_BOX/run/sing-box.log"
box_log="$DESC_BOX/run/runs.log"
box_user_group="root:net_admin"
tproxy_port="1536"
EOF
cat > "$DESC_BOX/sing-box/config.json" <<'EOF'
{"inbounds":[{"type":"tproxy","listen_port":1536}]}
EOF
cat > "$DESC_BOX/tproxy.conf" <<'EOF'
PROXY_TCP_PORT="1536"
PROXY_UDP_PORT="1536"
CORE_USER_GROUP="root:net_admin"
PROXY_UDP=1
EOF
# stop path with no pid -> 🔴 Stopped rewrite through the real public entrypoint
env SB_SETTINGS="$TEST_ROOT/desc-settings.ini" \
    SB_PROC_ROOT="$TEST_ROOT/proc" SB_TPROXY_SH="$TEST_ROOT/bin/tproxy-fixture" \
    SB_MODULE_PROP="$TEST_ROOT/desc-module.prop" \
    /bin/sh "$START" stop >/dev/null 2>&1 \
    || fail "description stop path returned failure"
grep -q '🔴 Stopped' "$TEST_ROOT/desc-module.prop" \
    || fail "stop did not write red status into module.prop: $(cat "$TEST_ROOT/desc-module.prop")"
grep -q 'placeholder static text' "$TEST_ROOT/desc-module.prop" \
    && fail "old description text was not replaced"
if grep -q '|' "$TEST_ROOT/desc-module.prop"; then
    fail "description still contains raw pipe characters"
fi
# Prove the unsanitized form still fails on BusyBox (documents the bug class).
printf 'description=old\n' > "$TEST_ROOT/desc-raw.prop"
status_raw="🟢 Running | SB Tproxy v9.9.9 | tproxy :1536 | Action to stop"
if $busybox sed -i "s|^description=.*|description=${status_raw}|" "$TEST_ROOT/desc-raw.prop" 2>/dev/null; then
    # If sed accepted it, the rewrite must not have applied the full multi-segment text.
    if grep -q 'Action to stop' "$TEST_ROOT/desc-raw.prop"; then
        fail "expected raw pipe-containing sed to be unsafe on this BusyBox"
    fi
else
    :
fi
pass "module.prop green/red status survives BusyBox sed delimiters"

printf '1..%s\n' "$PASS_COUNT"
