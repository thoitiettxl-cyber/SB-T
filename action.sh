#!/system/bin/sh
# Magisk action UI — toggle sing-box service, then print status and log tail

export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin"

BOX_SCRIPTS="/data/adb/box/scripts"
BOX_PID="/data/adb/box/run/box.pid"
BIN_LOG="/data/adb/box/run/sing-box.log"

# Toggle: stop if running, start if stopped
if [ -f "$BOX_PID" ] && kill -0 "$(cat "$BOX_PID" 2>/dev/null)" 2>/dev/null; then
  echo "Stopping service..."
  "${BOX_SCRIPTS}/start.sh" stop
else
  echo "Starting service..."
  "${BOX_SCRIPTS}/start.sh" start
  echo ""
  echo "=== Cleaning ColorOS firewall ==="
  "${BOX_SCRIPTS}/colfixer.sh" manual
fi

echo ""
echo "=== Status ==="
"${BOX_SCRIPTS}/start.sh" status

echo ""
echo "=== Last 10 log lines ==="
tail -10 "$BIN_LOG" 2>/dev/null || echo "(no log)"
