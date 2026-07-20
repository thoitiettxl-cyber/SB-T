#!/system/bin/sh
# sing-box control: start | stop | restart | status

export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin"

SCRIPTS_DIR="${SB_SCRIPTS_DIR:-${0%/*}}"
. "${SCRIPTS_DIR}/box.tool"
. "${SCRIPTS_DIR}/runtime.lib"
SETTINGS="${SB_SETTINGS:-/data/adb/box/settings.ini}"

[ -f "$SETTINGS" ] && . "$SETTINGS"

BOX_DIR="${box_dir:-/data/adb/box}"
SB_IPSET_BIN="${SB_IPSET_BIN:-${BOX_DIR}/bin/ipset}"
BOX_RUN="${box_run:-${BOX_DIR}/run}"
BOX_PID="${box_pid:-${BOX_RUN}/box.pid}"
BIN_PATH="${bin_path:-${BOX_DIR}/bin/sing-box}"
SB_CONFIG="${sing_config:-${BOX_DIR}/sing-box/config.json}"
SB_DIR="${BOX_DIR}/sing-box"
BIN_LOG="${bin_log:-${BOX_RUN}/sing-box.log}"
BOX_LOCK="${BOX_RUN}/box.lock"  # hardcoded — single-flight: serializes concurrent start.sh callers (LAW-6)
BOX_WANT="${BOX_RUN}/box.want"
BOX_RECOVERY="${BOX_RUN}/box.recover"
BOX_STOPPING="${BOX_RUN}/box.stopping"
BOX_STARTING="${BOX_RUN}/box.starting"
TPROXY_SH="${SB_TPROXY_SH:-${SCRIPTS_DIR}/tproxy.sh}"
MODULE_PROP="${SB_MODULE_PROP:-/data/adb/modules/SB_Tproxy/module.prop}"
USER_GROUP="${box_user_group:-root:net_admin}"
TPROXY_PORT="${tproxy_port:-1536}"
BOX_RUNS_LOG="${box_log:-${BOX_RUN}/runs.log}"

# ── Timing constants ─────────────────────────────────────────────────────────
WAIT_PORT_BIND=15       # max seconds waiting for tproxy port to bind
WAIT_GRACEFUL_STOP=10   # SIGTERM iterations before SIGKILL

PROXY_UDP_REQUIRED=1
if [ -f "${BOX_DIR}/tproxy.conf" ]; then
  PROXY_UDP_REQUIRED=$($busybox awk -F= '
    /^[[:space:]]*PROXY_UDP[[:space:]]*=/ {
      value=$2
      gsub(/[[:space:]"\047]/, "", value)
      print value
      exit
    }
  ' "${BOX_DIR}/tproxy.conf" 2>/dev/null)
fi
case "$PROXY_UDP_REQUIRED" in 0|1) ;; *) PROXY_UDP_REQUIRED=1 ;; esac

log() {
  local msg
  msg="$(date +%H:%M:%S) [$1] $2"
  echo "$msg"
  echo "$msg" >> "$BOX_RUNS_LOG" 2>/dev/null
}

_write_state_file() {
  local path="$1"
  local value="${2:-}"
  local tmp="${path}.tmp.$$"

  printf '%s' "$value" > "$tmp" 2>/dev/null && \
    mv -f "$tmp" "$path" 2>/dev/null || {
      rm -f "$tmp" 2>/dev/null
      log Error "Cannot write lifecycle state: $path"
      return 1
    }
  return 0
}

_remove_state_files() {
  rm -f "$@" 2>/dev/null || {
    log Error "Cannot remove lifecycle state: $*"
    return 1
  }
}

_read_stop_marker() {
  local marker pid intent

  STOP_MARKER_PID=""
  STOP_MARKER_INTENT=0
  [ -f "$BOX_STOPPING" ] || return 1
  marker="$(cat "$BOX_STOPPING" 2>/dev/null)" || return 1

  case "$marker" in
    *:*:*) return 1 ;;
    *:*)
      pid=${marker%%:*}
      intent=${marker#*:}
      case "$pid" in ''|*[!0-9]*) [ -z "$pid" ] || return 1 ;; esac
      case "$intent" in 0|1) ;; *) return 1 ;; esac
      STOP_MARKER_PID=$pid
      STOP_MARKER_INTENT=$intent
      ;;
    '')
      # v1.3.4 could leave an empty marker. It always means stay stopped.
      ;;
    *)
      case "$marker" in *[!0-9]*) return 1 ;; esac
      # A legacy PID-only marker came from a deliberate stop.
      STOP_MARKER_PID=$marker
      ;;
  esac
  return 0
}

_write_stop_marker() {
  local pid="$1"
  local intent="$2"

  case "$pid" in ''|*[!0-9]*) [ -z "$pid" ] || return 1 ;; esac
  case "$intent" in 0|1) ;; *) return 1 ;; esac
  _write_state_file "$BOX_STOPPING" "${pid}:${intent}"
}

_read_start_marker() {
  local marker

  START_MARKER_PID=""
  [ -f "$BOX_STARTING" ] || return 1
  marker="$(cat "$BOX_STARTING" 2>/dev/null)" || return 1
  case "$marker" in ''|*[!0-9]*) return 1 ;; esac
  START_MARKER_PID=$marker
  return 0
}

# Update Magisk/KernelSU module description to reflect current service state.
_update_description() {
  [ -f "$MODULE_PROP" ] || return 0
  local status
  local _ver
  _ver=$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null)
  _ver="${_ver:-1.3.5}"
  _ver="${_ver#v}"
  if [ -f "$BOX_PID" ] && runtime_pid_is_core "$(cat "$BOX_PID" 2>/dev/null)" "$BIN_PATH"; then
    status="🟢 Running | SB Tproxy v${_ver} | tproxy :${TPROXY_PORT} | tap Action to stop"
  else
    status="🔴 Stopped | SB Tproxy v${_ver} | tap Action to start"
  fi
  $busybox sed -i "s|^description=.*|description=${status}|" "$MODULE_PROP" 2>/dev/null || true
}

_check_config_consistency() {
  local tconf="${BOX_DIR}/tproxy.conf"
  [ -f "$tconf" ] || return 0
  local tconf_port tconf_udp tconf_ug config_port config_compact
  local failed=0
  tconf_port=$($busybox grep '^PROXY_TCP_PORT=' "$tconf" 2>/dev/null | cut -d= -f2 | tr -d '"')
  tconf_udp=$($busybox grep '^PROXY_UDP_PORT=' "$tconf" 2>/dev/null | cut -d= -f2 | tr -d '"')
  tconf_ug=$($busybox grep '^CORE_USER_GROUP=' "$tconf" 2>/dev/null | cut -d= -f2 | tr -d '"')
  # sing-box has already validated the JSON. Compact whitespace and match the
  # tproxy inbound object in either key order so formatting/minification cannot
  # turn a valid synchronized config into a false mismatch.
  config_compact=$($busybox tr -d '\r\n\t ' < "$SB_CONFIG" 2>/dev/null)
  config_port=$(printf '%s\n' "$config_compact" | $busybox sed -n \
    's/.*"type":"tproxy"[^}]*"listen_port":\([0-9][0-9]*\).*/\1/p')
  if [ -z "$config_port" ]; then
    config_port=$(printf '%s\n' "$config_compact" | $busybox sed -n \
      's/.*"listen_port":\([0-9][0-9]*\)[^}]*"type":"tproxy".*/\1/p')
  fi

  if [ -z "$tconf_port" ] || [ "$tconf_port" != "$TPROXY_PORT" ]; then
    log Error "LAW-4 violation: settings tproxy_port=${TPROXY_PORT}, tproxy TCP=${tconf_port:-missing}"
    failed=1
  fi
  if [ -z "$tconf_udp" ] || [ "$tconf_udp" != "$TPROXY_PORT" ]; then
    log Error "LAW-4 violation: settings tproxy_port=${TPROXY_PORT}, tproxy UDP=${tconf_udp:-missing}"
    failed=1
  fi
  if [ -z "$config_port" ] || [ "$config_port" != "$TPROXY_PORT" ]; then
    log Error "LAW-4 violation: settings tproxy_port=${TPROXY_PORT}, sing-box tproxy inbound=${config_port:-missing}"
    failed=1
  fi
  if [ -z "$tconf_ug" ] || [ "$tconf_ug" != "$USER_GROUP" ]; then
    log Error "Core identity mismatch: settings box_user_group=${USER_GROUP}, tproxy CORE_USER_GROUP=${tconf_ug:-missing}"
    failed=1
  fi
  [ "$failed" -eq 0 ]
}

wait_singbox_ready() {
  # Return only after both TCP and UDP sockets on the configured port are owned
  # by this exact sing-box PID. Inability to inspect procfs is fail-closed.
  local pid="$1"
  local i=0
  while [ $i -lt $WAIT_PORT_BIND ]; do
    kill -0 "$pid" 2>/dev/null || return 1
    if runtime_tproxy_port_ready "$pid" "$TPROXY_PORT" "$BIN_PATH" "$PROXY_UDP_REQUIRED"; then
      return 0
    fi
    sleep 1
    i=$((i+1))
  done
  runtime_pid_is_core "$pid" "$BIN_PATH" || return 1
  return 3
}

wait_start_marker() {
  local pid="$1"
  local i=0

  while [ "$i" -lt 5 ]; do
    if _read_start_marker; then
      [ "$START_MARKER_PID" = "$pid" ] && return 0
      return 2
    fi
    kill -0 "$pid" 2>/dev/null || return 1
    sleep 1
    i=$((i+1))
  done
  return 3
}

terminate_spawned_pid() {
  local pid="$1"
  local i=0

  # This PID is the direct child returned by $!, so it is safe to terminate
  # before box.pid commit even when procfs identity cannot yet be inspected.
  kill -15 "$pid" 2>/dev/null || true
  while kill -0 "$pid" 2>/dev/null && [ "$i" -lt 2 ]; do
    sleep 1
    i=$((i+1))
  done
  kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  ! kill -0 "$pid" 2>/dev/null
}

runtime_service_ready() {
  local pid="$1"

  runtime_pid_is_core "$pid" "$BIN_PATH" &&
    runtime_tproxy_port_ready "$pid" "$TPROXY_PORT" "$BIN_PATH" "$PROXY_UDP_REQUIRED" &&
    runtime_tproxy_state_ready "${BOX_DIR}/runtime_tproxy.conf" "$TPROXY_PORT"
}

do_start() {
  mkdir -p "$BOX_RUN" || return 1
  _run_lifecycle _do_start
}

do_stop() {
  _run_lifecycle _do_stop
}

do_restart() {
  mkdir -p "$BOX_RUN" || return 1
  _run_lifecycle _do_restart
}

do_recover() {
  _run_lifecycle _do_recover
}

do_finish_stop() {
  _run_lifecycle _do_finish_stop
}

do_toggle() {
  mkdir -p "$BOX_RUN" || return 1
  _run_lifecycle _do_toggle
}

_run_lifecycle() {
  local action="$1"
  mkdir -p "$BOX_RUN" || return 1

  # One lock covers start, stop, restart, watchdog recovery, and network
  # reapply. This prevents a stop from racing the start read/write PID window.
  (
    if ! runtime_flock_wait 9 15; then
      log Warning "Lifecycle lock timed out after 15 seconds"
      exit 75
    fi
    case "$action" in
      _do_start)   _do_start ;;
      _do_stop)    _do_stop 0 ;;
      _do_restart) _do_restart ;;
      _do_recover) _do_recover ;;
      _do_finish_stop) _do_finish_stop ;;
      _do_toggle)  _do_toggle ;;
      *)           log Error "Unknown lifecycle action: $action"; exit 2 ;;
    esac
  ) 9>"$BOX_LOCK"
}

_do_start() {
  local existing_pid=""
  local recovery_requested=0

  # A killed stop caller can leave rules/core mid-teardown. Finish that
  # transaction under the same lifecycle lock before accepting a new start.
  if [ -f "$BOX_STOPPING" ]; then
    log Warning "Completing interrupted stop transaction"
    _do_stop 1 || return 1
  fi

  # A killed launcher can leave a verified child between fork and box.pid
  # commit. Teardown that exact PID transactionally before launching another.
  if [ -f "$BOX_STARTING" ]; then
    if ! _read_start_marker; then
      log Error "Invalid start transaction marker: $BOX_STARTING"
      return 1
    fi
    log Warning "Recovering interrupted start transaction (PID $START_MARKER_PID)"
    _do_stop 1 || return 1
  fi

  [ -f "$BOX_RECOVERY" ] && recovery_requested=1
  _write_state_file "$BOX_WANT" || return 1
  runtime_trim_logs "$BOX_RUN"
  [ -f "$BOX_PID" ] && existing_pid="$(cat "$BOX_PID" 2>/dev/null)"
  if [ -n "$existing_pid" ] && runtime_pid_is_core "$existing_pid" "$BIN_PATH"; then
    if [ "$recovery_requested" -eq 0 ] && runtime_service_ready "$existing_pid"; then
      _remove_state_files "$BOX_RECOVERY" || return 1
      log Info "sing-box already running (PID $existing_pid)"
      return 0
    fi

    _write_state_file "$BOX_RECOVERY" || return 1
    log Warning "Recovering degraded sing-box lifecycle state (PID $existing_pid)"
    if ! _do_stop 1; then
      log Error "Cannot complete degraded lifecycle recovery for PID $existing_pid"
      return 1
    fi
  fi

  _write_state_file "$BOX_RECOVERY" || return 1

  # Stale pid (crash/kill left it behind): use the same resume transaction as
  # every other recovery so IPv6 guard state remains closed across teardown.
  if [ -f "$BOX_PID" ]; then
    log Warning "Stale box.pid found — flushing leftover tproxy rules"
    _do_stop 1 || {
      log Error "Cannot clear stale tproxy state; refusing to launch sing-box"
      return 1
    }
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

  _check_config_consistency || return 1

  chown root:net_admin "$BIN_PATH" 2>/dev/null
  # setuid/setgid bits are unnecessary: setuidgid already selects the runtime
  # identity. Keeping the binary non-setuid reduces the privilege surface.
  chmod 0755 "$BIN_PATH" 2>/dev/null
  ulimit -SHn 1000000

  log Info "Starting sing-box..."
  # The child commits its own PID while it still holds FD9, then closes the
  # lifecycle lock immediately before exec. If the parent dies after fork,
  # another lifecycle owner cannot enter before box.starting is durable.
  nohup /system/bin/sh -c '
    marker=$1
    bb=$2
    user_group=$3
    shift 3
    tmp="${marker}.tmp.$$"
    umask 077
    if ! printf "%s" "$$" > "$tmp" 2>/dev/null || \
       ! "$bb" mv -f "$tmp" "$marker" 2>/dev/null; then
      "$bb" rm -f "$tmp" 2>/dev/null
      printf "%s\n" "Cannot commit start transaction marker: $marker" >&2
      exit 125
    fi
    exec 9>&-
    exec "$bb" setuidgid "$user_group" "$@"
  ' sb-start "$BOX_STARTING" "$busybox" "$USER_GROUP" \
    "$BIN_PATH" run -c "$SB_CONFIG" -D "$SB_DIR" \
    >>"$BIN_LOG" 2>&1 &
  local PID=$!

  wait_start_marker "$PID"
  local marker_rc=$?
  if [ "$marker_rc" -ne 0 ]; then
    log Error "Child failed to commit box.starting for PID $PID (state $marker_rc)"
    if terminate_spawned_pid "$PID"; then
      if _read_start_marker && [ "$START_MARKER_PID" = "$PID" ]; then
        _remove_state_files "$BOX_STARTING" || true
      fi
    fi
    return 1
  fi

  wait_singbox_ready "$PID"
  local ready=$?
  if [ "$ready" -eq 1 ]; then
    log Error "sing-box failed to start — see $BIN_LOG"
    if kill -0 "$PID" 2>/dev/null; then
      if terminate_spawned_pid "$PID"; then
        _remove_state_files "$BOX_STARTING" || true
      else
        log Error "Unverified start PID $PID is still alive; retaining box.starting"
      fi
    else
      _remove_state_files "$BOX_STARTING" || true
    fi
    return 1
  elif [ "$ready" -eq 3 ]; then
    log Error "sing-box readiness failed for PID $PID and port $TPROXY_PORT — aborting tproxy (see $BIN_LOG)"
    if _terminate_core "$PID"; then
      _remove_state_files "$BOX_STARTING" || true
    fi
    return 1
  fi

  # Persist the launcher PID only after readiness is confirmed. setuidgid
  # execs sing-box, so this PID is also the exact process validated above;
  # never substitute a global pidof result from another instance.
  if ! _write_state_file "$BOX_PID" "$PID"; then
    if _terminate_core "$PID"; then
      _remove_state_files "$BOX_STARTING" || true
    fi
    return 1
  fi
  _remove_state_files "$BOX_STARTING" || return 1

  log Info "sing-box started (PID $PID)"
  log Info "Applying tproxy rules..."
  _start_tproxy_with_transition_guard
  local rv=$?
  if [ "$rv" -eq 0 ] && runtime_service_ready "$PID"; then
    _remove_state_files "$BOX_RECOVERY" || return 1
    log Info "tproxy rules applied"
    return 0
  fi

  if [ "$rv" -eq 0 ]; then
    rv=1
    log Error "Post-start PID/socket/tproxy verification failed"
  else
    log Error "tproxy.sh start failed (exit $rv)"
  fi

  # Use the same durable stop transaction as every other teardown. It writes
  # box.stopping before hiding box.pid, so interruption cannot orphan this core.
  if ! _do_stop 1; then
    log Error "Failed-start rollback is incomplete; recovery markers retained"
  fi
  return "$rv"
}

_terminate_core() {
  local PID="$1"
  local i=0

  runtime_pid_is_core "$PID" "$BIN_PATH" || return 0
  log Info "Stopping sing-box (PID $PID)..."
  kill -15 "$PID" 2>/dev/null || true
  while runtime_pid_is_core "$PID" "$BIN_PATH" && [ "$i" -lt "$WAIT_GRACEFUL_STOP" ]; do
    sleep 1
    i=$((i+1))
  done
  if runtime_pid_is_core "$PID" "$BIN_PATH"; then
    kill -9 "$PID" 2>/dev/null || true
    sleep 1
  fi
  if runtime_pid_is_core "$PID" "$BIN_PATH"; then
    log Error "sing-box PID $PID survived SIGKILL"
    return 1
  fi
  return 0
}

_stop_tproxy_for_intent() {
  local stop_intent="$1"

  if [ "$stop_intent" -eq 1 ] && \
     _runtime_ipv6_backup_valid "${BOX_DIR}/ipv6_backup.conf"; then
    if ! "$TPROXY_SH" -d "$BOX_DIR" guard-ipv6; then
      log Error "Cannot arm IPv6 transition guard before recovery teardown"
      return 1
    fi
    TPROXY_KEEP_IPV6_DISABLED=1 "$TPROXY_SH" -d "$BOX_DIR" stop
  else
    "$TPROXY_SH" -d "$BOX_DIR" stop
  fi
}

_start_tproxy_with_transition_guard() {
  if _runtime_ipv6_backup_valid "${BOX_DIR}/ipv6_backup.conf"; then
    TPROXY_KEEP_IPV6_DISABLED=1 "$TPROXY_SH" -d "$BOX_DIR" start
  else
    "$TPROXY_SH" -d "$BOX_DIR" start
  fi
}

_do_stop() {
  local stop_intent="${1:-0}"
  local PID=""
  local marker_pid=""
  local starting_pid=""
  local pid_source=""
  local pid_valid=0

  case "$stop_intent" in
    0|1) ;;
    *) log Error "Invalid stop transaction intent: $stop_intent"; return 1 ;;
  esac
  if [ -f "$BOX_STOPPING" ]; then
    if ! _read_stop_marker; then
      log Error "Invalid stop transaction marker: $BOX_STOPPING"
      return 1
    fi
    marker_pid=$STOP_MARKER_PID
  fi
  if [ -f "$BOX_PID" ]; then
    PID="$(cat "$BOX_PID" 2>/dev/null)"
    case "$PID" in ''|*[!0-9]*) log Error "Invalid PID file: $BOX_PID"; return 1 ;; esac
    pid_source=committed
  fi
  if [ -f "$BOX_STARTING" ]; then
    if ! _read_start_marker; then
      log Error "Invalid start transaction marker: $BOX_STARTING"
      return 1
    fi
    starting_pid=$START_MARKER_PID
    if [ -n "$PID" ] && [ "$PID" != "$starting_pid" ]; then
      log Error "Conflicting lifecycle PIDs: box.pid=$PID, box.starting=$starting_pid"
      return 1
    fi
    if [ -z "$PID" ]; then
      PID=$starting_pid
      pid_source=starting
    fi
  fi
  if [ -n "$marker_pid" ] && [ -n "$PID" ] && [ "$marker_pid" != "$PID" ]; then
    log Error "Conflicting stop transaction PID $marker_pid and active PID $PID"
    return 1
  fi
  [ -n "$PID" ] || PID=$marker_pid
  if [ "$pid_source" = starting ] && kill -0 "$PID" 2>/dev/null && \
     ! runtime_pid_is_core "$PID" "$BIN_PATH"; then
    local exec_wait=0
    while kill -0 "$PID" 2>/dev/null && [ "$exec_wait" -lt 2 ]; do
      sleep 1
      runtime_pid_is_core "$PID" "$BIN_PATH" && break
      exec_wait=$((exec_wait+1))
    done
    if kill -0 "$PID" 2>/dev/null && ! runtime_pid_is_core "$PID" "$BIN_PATH"; then
      log Error "Start marker PID $PID is live but has not exec'd the expected core"
      return 1
    fi
  fi
  if [ -n "$PID" ] && runtime_pid_is_core "$PID" "$BIN_PATH"; then
    pid_valid=1
  fi
  # Persist the exact PID before removing box.pid. A watchdog can then finish
  # teardown if this process is interrupted. Intent is durable too: 0 means a
  # deliberate stop, 1 means finish teardown and resume afterward.
  _write_stop_marker "$PID" "$stop_intent" || {
    log Error "Cannot persist stop transaction marker"
    return 1
  }
  # Clear desired/recovery state first so the watchdog observes a clean stop.
  _remove_state_files "$BOX_WANT" "$BOX_RECOVERY" || return 1
  # Remove the pid file first so the boot watchdog and action.sh observe a clean
  # stop and do not resurrect the core during the teardown window.
  _remove_state_files "$BOX_PID" "$BOX_STARTING" || return 1

  log Info "Removing tproxy rules..."
  _stop_tproxy_for_intent "$stop_intent" 2>/dev/null
  local cleanup_rc=$?
  if [ "$cleanup_rc" -ne 0 ]; then
    log Error "tproxy cleanup failed (exit $cleanup_rc); sing-box was not killed"
    if [ "$pid_valid" -eq 1 ]; then
      case "$pid_source" in
        committed) _write_state_file "$BOX_PID" "$PID" || true ;;
        starting) _write_state_file "$BOX_STARTING" "$PID" || true ;;
      esac
    fi
    return "$cleanup_rc"
  fi

  if [ "$pid_valid" -eq 1 ]; then
    if ! _terminate_core "$PID"; then
      case "$pid_source" in
        committed) _write_state_file "$BOX_PID" "$PID" || true ;;
        starting) _write_state_file "$BOX_STARTING" "$PID" || true ;;
      esac
      return 1
    fi
  elif [ -n "$PID" ]; then
    log Warning "Refusing to kill unverified PID $PID"
  else
    log Info "No verified sing-box PID to stop"
  fi
  if [ "$stop_intent" -eq 1 ]; then
    # Publish resume intent before committing marker removal. An interrupted
    # caller can safely repeat this idempotent stop transaction.
    _write_state_file "$BOX_WANT" || return 1
    _write_state_file "$BOX_RECOVERY" || return 1
  fi
  _remove_state_files "$BOX_STOPPING" || {
    log Error "Stop completed but transaction marker could not be removed"
    return 1
  }
  log Info "sing-box stopped"
  return 0
}

_do_restart() {
  _do_stop 1 || return 1
  _do_start
}

_do_recover() {
  # Recovery callers must never create desired state after a user stop. Check
  # both markers after acquiring box.lock so a queued watchdog call cannot
  # consume a recovery marker that net.inotify already cleared.
  if [ ! -f "$BOX_WANT" ]; then
    _remove_state_files "$BOX_RECOVERY" || true
    return 0
  fi
  [ -f "$BOX_RECOVERY" ] || return 0
  _do_start
}

_do_finish_stop() {
  # A watchdog retry is conditional on the marker observed before dispatch.
  # Recheck it after taking box.lock so a concurrent explicit start that
  # completed the transaction cannot be stopped by a stale retry.
  [ -f "$BOX_STOPPING" ] || return 0
  if ! _read_stop_marker; then
    log Error "Invalid stop transaction marker: $BOX_STOPPING"
    return 1
  fi
  _do_stop "$STOP_MARKER_INTENT"
}

_do_toggle() {
  if [ -f "$BOX_STOPPING" ]; then
    if ! _read_stop_marker; then
      log Error "Invalid stop transaction marker: $BOX_STOPPING"
      return 1
    fi
    if [ "$STOP_MARKER_INTENT" -eq 1 ]; then
      _do_stop 0
    else
      _do_start
    fi
    return $?
  fi

  if [ -f "$BOX_WANT" ] || [ -f "$BOX_PID" ] || [ -f "$BOX_STARTING" ]; then
    _do_stop 0
  else
    _do_start
  fi
}

do_status() {
  local PID=""
  [ -f "$BOX_PID" ] && PID="$(cat "$BOX_PID" 2>/dev/null)"

  if [ -n "$PID" ] && runtime_pid_is_core "$PID" "$BIN_PATH"; then
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
  start)
    do_start; rv=$?; _update_description; exit "$rv" ;;
  stop)
    do_stop; rv=$?; _update_description; exit "$rv" ;;
  restart)
    do_restart; rv=$?; _update_description; exit "$rv" ;;
  recover)
    do_recover; rv=$?; _update_description; exit "$rv" ;;
  finish-stop)
    do_finish_stop; rv=$?; _update_description; exit "$rv" ;;
  toggle)
    do_toggle; rv=$?; _update_description; exit "$rv" ;;
  status)
    do_status; rv=$?; exit "$rv" ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}" >&2
    exit 1
    ;;
esac
