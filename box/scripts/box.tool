#!/system/bin/sh
# Tool coordinator — source this file to get shared utilities.
# Provides: $busybox detection, log(), _tool_download()
# Set LOG_FILE before calling log() to enable file logging.

# busybox detection
busybox="/data/adb/magisk/busybox"
[ -f "/data/adb/ksu/bin/busybox" ] && busybox="/data/adb/ksu/bin/busybox"
[ -f "/data/adb/ap/bin/busybox" ] && busybox="/data/adb/ap/bin/busybox"
[ -f "$busybox" ] || busybox="busybox"
export busybox

# Shared log: log <level> <message>
# Writes to stdout. Also appends to $LOG_FILE if set by the caller.
log() {
  local msg
  msg="$(date +%H:%M:%S) [$1] $2"
  echo "$msg"
  [ -n "${LOG_FILE:-}" ] && echo "$msg" >> "$LOG_FILE" 2>/dev/null
  return 0
}

# Shared download helper: _tool_download <url> <dest>
# Uses curl or busybox wget; returns 1 on failure.
_tool_download() {
  local url="$1" dest="$2"
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL -L --connect-timeout 20 --retry 2 "$url" -o "$dest"
  else
    $busybox wget -q -T 20 -t 2 -O "$dest" "$url"
  fi
}
