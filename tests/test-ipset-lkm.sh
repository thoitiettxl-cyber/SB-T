#!/bin/sh
set -eu

REPO_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SCRIPT="${REPO_ROOT}/box/scripts/ipset.sh"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

fail() {
    printf 'not ok - %s\n' "$*" >&2
    exit 1
}

assert_contains() {
    case "$1" in
        *"$2"*) ;;
        *) fail "expected output to contain: $2" ;;
    esac
}

assert_eq() {
    [ "$1" = "$2" ] || fail "expected '$2', got '$1'"
}

mkdir -p "$TEST_ROOT/bin" "$TEST_ROOT/box/bin/IPSET-LKM/netfilter/6.12" "$TEST_ROOT/sys"
printf '0\n' > "$TEST_ROOT/modules_disabled"
printf 'BYPASS_CN_IP=0\n' > "$TEST_ROOT/box/tproxy.conf"
: > "$TEST_ROOT/ip_tables_matches"

cat > "$TEST_ROOT/bin/modinfo" <<'EOF'
#!/bin/sh
[ "$1" = "-F" ] && [ "$2" = "vermagic" ] || exit 1
cat "$3"
EOF

cat > "$TEST_ROOT/bin/ipset" <<'EOF'
#!/bin/sh
[ -f "${SB_TEST_ROOT}/ipset-ready" ]
EOF

cat > "$TEST_ROOT/bin/ko-loader" <<'EOF'
#!/bin/sh
case "${1##*/}" in
    ip_set.ko) module=ip_set ;;
    ip_set_hash_net.ko) module=ip_set_hash_net ;;
    xt_set.ko) module=xt_set ;;
    *) exit 9 ;;
esac
mkdir -p "${SB_SYS_MODULE_DIR}/${module}"
printf '%s\n' "$module" >> "${SB_TEST_ROOT}/loader.calls"
if [ "$module" = "xt_set" ]; then
    : > "${SB_TEST_ROOT}/ipset-ready"
fi
exit 0
EOF

cat > "$TEST_ROOT/bin/failing-loader" <<'EOF'
#!/bin/sh
printf 'fixture loader refused %s\n' "${1##*/}" >&2
exit 7
EOF
chmod 0755 "$TEST_ROOT/bin/modinfo" "$TEST_ROOT/bin/ipset" \
    "$TEST_ROOT/bin/ko-loader" "$TEST_ROOT/bin/failing-loader"

write_modules() {
    local release="$1" directory compatible=0
    directory="$TEST_ROOT/box/bin/IPSET-LKM/netfilter/6.12"
    mkdir -p "$directory/ipset"
    printf '%s flags\n' "$release" > "$directory/ipset/ip_set.ko"
    printf '%s flags\n' "$release" > "$directory/ipset/ip_set_hash_net.ko"
    printf '%s flags\n' "$release" > "$directory/xt_set.ko"
    cp "$TEST_ROOT/bin/ko-loader" "$TEST_ROOT/box/bin/IPSET-LKM/ko-loader"
    chmod 0755 "$TEST_ROOT/box/bin/IPSET-LKM/ko-loader"
    if [ "$release" = "6.12.76-4k" ]; then
        compatible=1
    fi
    cat > "$TEST_ROOT/box/bin/IPSET-LKM/manifest-6.12.ini" <<EOF
source_repo=TanakaLun/IPSET_LKM
sha256=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
kernel_release=6.12.76-4k
exact_vermagic_compatible=${compatible}
EOF
}

reset_runtime() {
    rm -rf "$TEST_ROOT/sys"
    mkdir -p "$TEST_ROOT/sys"
    rm -f "$TEST_ROOT/ipset-ready" "$TEST_ROOT/loader.calls" "$TEST_ROOT/run.log"
}

run_ipset() {
    env \
        SB_BOX_DIR="$TEST_ROOT/box" \
        SB_SYS_MODULE_DIR="$TEST_ROOT/sys" \
        SB_PROC_IPTABLES_MATCHES="$TEST_ROOT/ip_tables_matches" \
        SB_MODULES_DISABLED_FILE="$TEST_ROOT/modules_disabled" \
        SB_LOG_FILE="$TEST_ROOT/run.log" \
        SB_IPSET_BIN="$TEST_ROOT/bin/ipset" \
        SB_MODINFO_BIN="$TEST_ROOT/bin/modinfo" \
        SB_KO_LOADER="${SB_KO_LOADER:-$TEST_ROOT/box/bin/IPSET-LKM/ko-loader}" \
        SB_KERNEL_RELEASE="${SB_TEST_KERNEL_RELEASE:-6.12.76-4k}" \
        SB_ALLOW_TEST_ARCH=1 \
        SB_TEST_ROOT="$TEST_ROOT" \
        /bin/sh "$SCRIPT" "$@"
}

# Disabled feature: no bundle or loader is touched.
reset_runtime
output=$(run_ipset load)
assert_contains "$output" "Skipped: BYPASS_CN_IP is disabled"
[ ! -e "$TEST_ROOT/loader.calls" ] || fail "loader ran while feature was disabled"
printf 'ok - disabled feature skips kernel mutation\n'

# Read-only status does not append to the runtime log.
rm -f "$TEST_ROOT/run.log"
output=$(run_ipset status)
assert_contains "$output" "IPSET required by BYPASS_CN_IP: no"
[ ! -e "$TEST_ROOT/run.log" ] || fail "status command wrote to the runtime log"
printf 'ok - status is read-only\n'

# Mismatched vermagic blocks before ko-loader executes.
printf 'BYPASS_CN_IP=1\n' > "$TEST_ROOT/box/tproxy.conf"
write_modules "6.12.99-other"
reset_runtime
set +e
output=$(run_ipset load 2>&1)
status=$?
set -e
assert_eq "$status" "2"
assert_contains "$output" "vermagic 6.12.99-other != running kernel 6.12.76-4k"
[ ! -e "$TEST_ROOT/loader.calls" ] || fail "loader ran with mismatched vermagic"
printf 'ok - mismatched vermagic is fail-closed\n'

# Exact modules load in the minimal dependency order and pass readiness.
write_modules "6.12.76-4k"
reset_runtime
output=$(run_ipset load)
assert_contains "$output" "IPSET is ready for CN-IP bypass"
assert_eq "$(tr '\n' ' ' < "$TEST_ROOT/loader.calls")" "ip_set ip_set_hash_net xt_set "
printf 'ok - exact bundle loads minimal module set\n'

# --force bypasses only the feature gate, not compatibility checks.
printf 'BYPASS_CN_IP=0\n' > "$TEST_ROOT/box/tproxy.conf"
reset_runtime
output=$(run_ipset load --force)
assert_contains "$output" "IPSET is ready for CN-IP bypass"
write_modules "6.12.99-other"
reset_runtime
set +e
output=$(run_ipset load --force 2>&1)
status=$?
set -e
assert_eq "$status" "2"
[ ! -e "$TEST_ROOT/loader.calls" ] || fail "--force bypassed vermagic validation"
printf 'ok - force cannot bypass compatibility\n'

# Loader errors are returned and retained in the run log.
write_modules "6.12.76-4k"
reset_runtime
set +e
output=$(SB_KO_LOADER="$TEST_ROOT/bin/failing-loader" run_ipset load --force 2>&1)
status=$?
set -e
assert_eq "$status" "7"
assert_contains "$output" "fixture loader refused ip_set.ko"
grep -q "fixture loader refused ip_set.ko" "$TEST_ROOT/run.log" \
    || fail "loader error was not written to the run log"
printf 'ok - loader failure is observable\n'

printf '1..6\n'
