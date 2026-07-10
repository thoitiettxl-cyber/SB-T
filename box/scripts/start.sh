#!/system/bin/sh
# sing-box control: start | stop | restart | status

export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin"

SCRIPTS_DIR="${0%/*}"
. "${SCRIPTS_DIR}/box.tool"
SETTINGS="/data/adb/box/settings.ini"

[ -f "$SETTINGS" ] && . "$SETTINGS"

BOX_DIR="${box_dir:-/data/adb/box}"
BOX_RUN="${box_run:-${BOX_DIR}/run}"
BOX_PID="${box_pid:-${BOX_RUN}/box.pid}"
BIN_PATH="${bin_path:-${BOX_DIR}/bin/sing-box}"
SB_CONFIG="${sing_config:-${BOX_DIR}/sing-box/config.json}"
SB_DIR="${BOX_DIR}/sing-box"
BIN_LOG="${bin_log:-${BOX_RUN}/sing-box.log}"
BOX_LOCK="${BOX_RUN}/box.lock"  # hardcoded — single-flight: serializes concurrent start.sh callers (LAW-6)
TPROXY_SH="${SCRIPTS_DIR}/tproxy.sh"
MODULE_PROP="/data/adb/modules/SB_Tproxy/module.prop"
USER_GROUP="${box_user_group:-root:net_admin}"
TPROXY_PORT="${tproxy_port:-1536}"
BOX_RUNS_LOG="${box_log:-${BOX_RUN}/runs.log}"

# ── Timing constants ─────────────────────────────────────────────────────────
WAIT_PORT_BIND=15       # max seconds waiting for tproxy port to bind
WAIT_PROCFS_GRACE=5     # extra grace iterations when procfs unreadable
WAIT_GRACEFUL_STOP=10   # SIGTERM iterations before SIGKILL

log() {
  local msg
  msg="$(date +%H:%M:%S) [$1] $2"
  echo "$msg"
  echo "$msg" >> "$BOX_RUNS_LOG" 2>/dev/null
}

# Update Magisk/KernelSU module description to reflect current service state.
_update_description() {
  [ -f "$MODULE_PROP" ] || return 0
  local status
  local _ver
  _ver=$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null)
  _ver="${_ver:-1.3.4}"
  _ver="${_ver#v}"
  if [ -f "$BOX_PID" ] && kill -0 "$(cat "$BOX_PID" 2>/dev/null)" 2>/dev/null; then
    status="🟢 Running | SB Tproxy v${_ver} | tproxy :${TPROXY_PORT} | tap Action to stop"
  else
    status="🔴 Stopped | SB Tproxy v${_ver} | tap Action to start"
  fi
  $busybox sed -i "s|^description=.*|description=${status}|" "$MODULE_PROP" 2>/dev/null || true
}

_check_config_consistency() {
  local tconf="${BOX_DIR}/tproxy.conf"
  [ -f "$tconf" ] || return 0
  local tconf_port tconf_ug
  tconf_port=$($busybox grep '^PROXY_TCP_PORT=' "$tconf" 2>/dev/null | cut -d= -f2 | tr -d '"')
  tconf_ug=$($busybox grep '^CORE_USER_GROUP=' "$tconf" 2>/dev/null | cut -d= -f2 | tr -d '"')
  [ -n "$tconf_port" ] && [ "$tconf_port" != "$TPROXY_PORT" ] && \
    log Warning "LAW-4 violation: tproxy_port=${TPROXY_PORT} in settings.ini != PROXY_TCP_PORT=${tconf_port} in tproxy.conf"
  [ -n "$tconf_ug" ] && [ "$tconf_ug" != "$USER_GROUP" ] && \
    log Warning "User/group mismatch: box_user_group=${USER_GROUP} != CORE_USER_GROUP=${tconf_ug}"
}

wait_singbox_ready() {
  # Returns: 0 = port confirmed listening; 1 = process died;
  #          2 = procfs unreadable (cannot probe) — caller applies a grace delay;
  #          3 = procfs readable but port never bound — caller MUST abort (blackhole).
  local pid="$1"
  local hex_port
  hex_port=$(printf '%04X' "$TPROXY_PORT")

  # If neither port table is readable (hardened/GKI kernels, restrictive
  # selinux domain), probing is impossible — wait a conservative fixed
  # delay and report unconfirmed instead of false-passing.
  if [ ! -r /proc/net/tcp ] && [ ! -r /proc/net/tcp6 ]; then
    local j=0
    while [ $j -lt $WAIT_PROCFS_GRACE ]; do
      kill -0 "$pid" 2>/dev/null || return 1
      sleep 1
      j=$((j+1))
    done
    kill -0 "$pid" 2>/dev/null || return 1
    return 2
  fi

  local i=0
  while [ $i -lt $WAIT_PORT_BIND ]; do
    kill -0 "$pid" 2>/dev/null || return 1
    if $busybox grep -qi ":${hex_port} " /proc/net/tcp6 2>/dev/null || \
       $busybox grep -qi ":${hex_port} " /proc/net/tcp 2>/dev/null; then
      return 0
    fi
    sleep 1
    i=$((i+1))
  done
  # Port never showed up but process still alive — genuine bind failure/stall.
  # Distinct from the procfs-unreadable case so the caller can abort instead of
  # applying TPROXY rules to a port nothing listens on (blackhole).
  kill -0 "$pid" 2>/dev/null || return 1
  return 3
}

do_start() {
  mkdir -p "$BOX_RUN"

  # Single-flight: serialize concurrent starts (rapid action.sh taps / net.inotify)
  # so two callers can't both pass the pid check and stack tproxy rules. The lock
  # is acquired at the very top, before the read-then-write pid window in _do_start.
  (
    if ! $busybox flock -n 9; then
      log Info "Another start is in progress — skipping"
      exit 0
    fi
    _do_start
  ) 9>"$BOX_LOCK"
}

_do_start() {
  if [ -f "$BOX_PID" ] && kill -0 "$(cat "$BOX_PID" 2>/dev/null)" 2>/dev/null; then
    log Info "sing-box already running (PID $(cat "$BOX_PID"))"
    return 0
  fi

  # Stale pid (crash/kill left it behind): flush any leftover tproxy rules so we
  # don't accumulate duplicate jumps/block rules, then drop the dead pid file.
  if [ -f "$BOX_PID" ]; then
    log Warning "Stale box.pid found — flushing leftover tproxy rules"
    "$TPROXY_SH" -d "$BOX_DIR" stop 2>/dev/null
    rm -f "$BOX_PID"
  fi

  if [ ! -x "$BIN_PATH" ]; then
    log Error "Binary not found or not executable: $BIN_PATH"
    return 1
  fi

  if [ ! -f "$SB_CONFIG" ]; then
    log Error "Config not found: $SB_CONFIG"
    return 1
  fi

  # Validate config before starting
  if ! "$BIN_PATH" check -c "$SB_CONFIG" -D "$SB_DIR" >"$BIN_LOG" 2>&1; then
    log Error "Config check failed — see $BIN_LOG"
    return 1
  fi

  chown root:net_admin "$BIN_PATH" 2>/dev/null
  chmod 6755 "$BIN_PATH" 2>/dev/null
  ulimit -SHn 1000000

  _check_config_consistency
  log Info "Starting sing-box..."
  nohup $busybox setuidgid "$USER_GROUP" \
    "$BIN_PATH" run -c "$SB_CONFIG" -D "$SB_DIR" \
    >>"$BIN_LOG" 2>&1 &
  local PID=$!

  wait_singbox_ready "$PID"
  local ready=$?
  if [ "$ready" -eq 1 ]; then
    log Error "sing-box failed to start — see $BIN_LOG"
    rm -f "$BOX_PID"
    return 1
  elif [ "$ready" -eq 3 ]; then
    log Error "sing-box alive but port $TPROXY_PORT never bound — aborting tproxy to avoid blackhole (see $BIN_LOG)"
    $busybox pkill -15 sing-box 2>/dev/null || true
    rm -f "$BOX_PID"
    return 1
  elif [ "$ready" -eq 2 ]; then
    log Warning "sing-box port unconfirmed (procfs unreadable) — applying extra grace delay before tproxy"
    sleep $WAIT_PROCFS_GRACE
  fi

  # Persist the PID only after readiness is confirmed. Prefer sing-box's own PID
  # (the launcher PID from $! may be busybox setuidgid, not the final process).
  local SB_PID
  SB_PID=$($busybox pidof sing-box 2>/dev/null | $busybox awk '{print $1}')
  [ -n "$SB_PID" ] && PID="$SB_PID"
  echo -n "$PID" >"$BOX_PID"

  log Info "sing-box started (PID $PID)"
  log Info "Applying tproxy rules..."
  "$TPROXY_SH" -d "$BOX_DIR" start
  local rv=$?
  [ $rv -eq 0 ] && log Info "tproxy rules applied" || log Error "tproxy.sh start failed (exit $rv)"
  return $rv
}

do_stop() {
  local PID=""
  [ -f "$BOX_PID" ] && PID="$(cat "$BOX_PID" 2>/dev/null)"
  # Remove the pid file first so the boot watchdog and action.sh observe a clean
  # stop and do not resurrect the core during the teardown window.
  rm -f "$BOX_PID"

  log Info "Removing tproxy rules..."
  "$TPROXY_SH" -d "$BOX_DIR" stop 2>/dev/null

  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    log Info "Stopping sing-box (PID $PID)..."
    kill -15 "$PID" 2>/dev/null
    local i=0
    while kill -0 "$PID" 2>/dev/null && [ $i -lt $WAIT_GRACEFUL_STOP ]; do
      sleep 1
      i=$((i+1))
    done
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
  else
    $busybox pkill -15 sing-box 2>/dev/null || true
  fi

  log Info "sing-box stopped"
}

do_status() {
  local PID=""
  [ -f "$BOX_PID" ] && PID="$(cat "$BOX_PID" 2>/dev/null)"

  if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
    log Info "sing-box running (PID $PID)"

    local hex_port
    hex_port=$(printf '%04X' "$TPROXY_PORT")
    local rule_count
    # Read-only status probe. -n avoids reverse-DNS lookups (can hang on a bad
    # resolver); -w waits for the xtables lock instead of failing if tproxy.sh
    # holds it. tproxy.sh remains the sole mutator of netfilter state.
    rule_count=$(iptables -w -t mangle -nL 2>/dev/null | $busybox grep -cE "TPROXY|tproxy" 2>/dev/null) || rule_count=0
    log Info "tproxy rules: $rule_count (port $TPROXY_PORT)"

    if [ -f "/proc/$PID/status" ]; then
      local rss
      rss=$($busybox awk '/VmRSS/{print $2}' "/proc/$PID/status" 2>/dev/null)
      [ -n "$rss" ] && log Info "Memory: $((rss/1024)) MB RSS"
    fi

    local uptime
    uptime=$($busybox ps -o etime -p "$PID" 2>/dev/null | tail -1 | tr -d ' ')
    [ -n "$uptime" ] && log Info "Uptime: $uptime"
  else
    log Warning "sing-box not running"
    return 1
  fi

  if [ -f "$BIN_LOG" ]; then
    echo "--- last 5 log lines ---"
    tail -5 "$BIN_LOG"
  fi
}

case "$1" in
  start)   do_start; _update_description ;;
  stop)    do_stop; _update_description ;;
  restart) do_stop; do_start; _update_description ;;
  status)  do_status ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}" >&2
    exit 1
    ;;
esac
