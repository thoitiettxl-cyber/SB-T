#!/system/bin/sh
# Magisk action UI — toggle sing-box service, then print status and log tail

export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin"

BOX_SCRIPTS="/data/adb/box/scripts"
BOX_WANT="/data/adb/box/run/box.want"
BIN_LOG="/data/adb/box/run/sing-box.log"

# The lifecycle owner decides start versus stop while holding box.lock.
echo "Toggling service..."
"${BOX_SCRIPTS}/start.sh" toggle
toggle_rc=$?
if [ "$toggle_rc" -eq 0 ] && [ -f "$BOX_WANT" ]; then
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

exit "$toggle_rc"
