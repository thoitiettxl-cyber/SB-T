#!/system/bin/sh
# Magisk module service — runs at late boot via LATESTARTSERVICE

export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin"

BOX_SCRIPTS="/data/adb/box/scripts"
MODULE_DIR="/data/adb/modules/SB_Tproxy"
BOX_RUN="/data/adb/box/run"
BIN_PATH="/data/adb/box/bin/sing-box"

. "${BOX_SCRIPTS}/box.tool"
. "${BOX_SCRIPTS}/runtime.lib"

trim_runtime_logs() {
  runtime_trim_logs "$BOX_RUN"
}

(
  # sys.boot_completed is the canonical Android boot-complete signal.
  # resetprop -w is event-driven — no 10-second poll window — but only if resetprop is
  # available (Magisk). Loop re-checks after each wake to handle: (a) intermediate values
  # on custom ROMs, (b) TOCTOU window where property becomes '1' before resetprop -w runs.
  if command -v resetprop > /dev/null 2>&1; then
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
      resetprop -w sys.boot_completed
    done
  else
    until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
  fi

  [ -f "${MODULE_DIR}/disable" ] && exit 0

  chmod 755 "${BOX_SCRIPTS}"/*

  # Optional: ipset.sh performs no kernel mutation unless BYPASS_CN_IP=1 and
  # every essential LKM passes the exact-vermagic preflight.
  "${BOX_SCRIPTS}/ipset.sh" load || true

  mkdir -p "$BOX_RUN" || exit 1
  BOX_PID="${BOX_RUN}/box.pid"
  BOX_WANT="${BOX_RUN}/box.want"
  BOX_RECOVERY="${BOX_RUN}/box.recover"
  BOX_STOPPING="${BOX_RUN}/box.stopping"
  trim_runtime_logs
  while :; do
    /data/adb/box/scripts/start.sh start
    boot_start_rc=$?
    [ "$boot_start_rc" -eq 75 ] || break
    [ -f "${MODULE_DIR}/disable" ] && exit 0
    sleep 2
  done

  # ColorOS 16 / RedMagic OS: clean Google-blocking firewall rules after a
  # short delay to ensure system chains are fully loaded before we sweep them.
  ( sleep 10 && "${BOX_SCRIPTS}/colfixer.sh" boot ) &

  # Watch desired state independently of the rt_tables gate. A failed boot start
  # leaves box.want present; a deliberate stop removes it before teardown.
  WATCHDOG_INTERVAL=30  # seconds between crash checks; directly sets worst-case recovery latency
  LOG_GUARD_TICKS=20    # trim logs every 10 minutes without another resident process
  watchdog_ticks=0
  while sleep $WATCHDOG_INTERVAL; do
    [ -f "${MODULE_DIR}/disable" ] && break
    if [ -f "$BOX_STOPPING" ]; then
      /data/adb/box/scripts/start.sh finish-stop
    elif [ -f "$BOX_WANT" ]; then
      core_pid="$(cat "$BOX_PID" 2>/dev/null)"
      if [ -f "$BOX_RECOVERY" ]; then
        /data/adb/box/scripts/start.sh recover
      elif ! runtime_pid_is_core "$core_pid" "$BIN_PATH"; then
        if : > "$BOX_RECOVERY"; then
          /data/adb/box/scripts/start.sh recover
        fi
      fi
    fi

    watchdog_ticks=$((watchdog_ticks + 1))
    if [ "$watchdog_ticks" -ge "$LOG_GUARD_TICKS" ]; then
      trim_runtime_logs
      if [ -f "$BOX_WANT" ]; then
        core_pid="$(cat "$BOX_PID" 2>/dev/null)"
        if runtime_pid_is_core "$core_pid" "$BIN_PATH" && \
           ! runtime_tproxy_port_ready "$core_pid" 1536 "$BIN_PATH" 1; then
          if ! : > "$BOX_RECOVERY"; then
            continue
          fi
          /data/adb/box/scripts/start.sh recover
        fi
      fi
      watchdog_ticks=0
    fi
  done &

  # Start network interface monitor after routing table is ready. The watchdog
  # above remains active even on ROMs that create rt_tables late or never.
  until [ -f /data/misc/net/rt_tables ]; do
    sleep 3
  done
  inotifyd "${BOX_SCRIPTS}/net.inotify" /data/misc/net >/dev/null 2>&1 &
) &
