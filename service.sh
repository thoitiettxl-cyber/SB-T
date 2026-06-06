#!/system/bin/sh
# Magisk module service — runs at late boot via LATESTARTSERVICE

export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin"

BOX_SCRIPTS="/data/adb/box/scripts"
MODULE_DIR="/data/adb/modules/SB_Tproxy"

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

  # Load IPSET kernel modules if LKM bundle present (no-op if kernel already has ip_set)
  "${BOX_SCRIPTS}/ipset.sh" load

  /data/adb/box/scripts/start.sh start

  # ColorOS 16 / RedMagic OS: clean Google-blocking firewall rules after a
  # short delay to ensure system chains are fully loaded before we sweep them.
  ( sleep 10 && "${BOX_SCRIPTS}/colfixer.sh" boot ) &

  # Start network interface monitor after routing table is ready
  until [ -f /data/misc/net/rt_tables ]; do
    sleep 3
  done
  inotifyd "${BOX_SCRIPTS}/net.inotify" /data/misc/net >/dev/null 2>&1 &

  # Watchdog: if sing-box crashes (pid file present but process dead), restart it.
  # A clean stop removes box.pid, so this never resurrects a deliberately stopped core.
  BOX_PID="/data/adb/box/run/box.pid"
  WATCHDOG_INTERVAL=30  # seconds between crash checks; directly sets worst-case recovery latency
  while sleep $WATCHDOG_INTERVAL; do
    [ -f "${MODULE_DIR}/disable" ] && break
    if [ -f "$BOX_PID" ] && ! kill -0 "$(cat "$BOX_PID" 2>/dev/null)" 2>/dev/null; then
      /data/adb/box/scripts/start.sh start
    fi
  done &
) &
