#!/system/bin/sh
# upkernel.sh — download & install latest sing-box binary from GitHub

export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin"

SCRIPTS_DIR="${0%/*}"
. "${SCRIPTS_DIR}/box.tool"
SETTINGS="/data/adb/box/settings.ini"
[ -f "$SETTINGS" ] && . "$SETTINGS"

BOX_DIR="${box_dir:-/data/adb/box}"
BIN_DIR="${BOX_DIR}/bin"
BIN_PATH="${bin_path:-${BIN_DIR}/sing-box}"
BOX_PID="${box_pid:-${BOX_DIR}/run/box.pid}"
USER_GROUP="${box_user_group:-root:net_admin}"
START_SH="${SCRIPTS_DIR}/start.sh"

USE_GHPROXY="${use_ghproxy:-false}"
GHPROXY_URL="${url_ghproxy:-https://ghproxy.net}"
SINGBOX_STABLE="${singbox_stable:-true}"
GITHUB_TOKEN="${github_token:-}"

FORCE=false
RESTART=false

# log() provided by box.tool (sourced above)

# Fetch URL content; uses GitHub token if configured
api_get() {
  local url="$1"
  if [ -n "$GITHUB_TOKEN" ]; then
    if command -v curl >/dev/null 2>&1; then
      curl -sL -H "Authorization: token ${GITHUB_TOKEN}" "$url"
    else
      $busybox wget -qO- --header "Authorization: token ${GITHUB_TOKEN}" "$url"
    fi
  elif command -v curl >/dev/null 2>&1; then
    curl -sL "$url"
  else
    $busybox wget -qO- "$url"
  fi
}

# Route GitHub URLs through ghproxy when USE_GHPROXY=true
_proxy_url() {
  local url="$1"
  if [ "$USE_GHPROXY" = "true" ]; then
    case "$url" in
      https://github.com/*|https://raw.githubusercontent.com/*)
        echo "${GHPROXY_URL}/${url}"; return ;;
    esac
  fi
  echo "$url"
}

download_file() {
  local dest="$1" url="$2"
  local bak="${dest}.bak"
  [ -f "$dest" ] && cp "$dest" "$bak"

  url=$(_proxy_url "$url")
  log Info "Downloading $(basename "$dest")..."

  local ok=0
  if command -v curl >/dev/null 2>&1; then
    local code
    code=$(curl -L -s --http1.1 -o "$dest" -w "%{http_code}" "$url")
    [ "$code" = "200" ] && ok=1 || log Error "curl HTTP $code"
  else
    $busybox wget -q -O "$dest" "$url" && ok=1 || log Error "wget failed"
  fi

  if [ $ok -eq 0 ] || [ ! -s "$dest" ]; then
    log Error "Download failed: $url"
    [ -f "$bak" ] && mv "$bak" "$dest" || rm -f "$dest"
    return 1
  fi

  rm -f "$bak"
}

detect_arch() {
  case $(uname -m) in
    aarch64)       ARCH=arm64; PLATFORM=android ;;
    armv7l|armv8l) ARCH=armv7; PLATFORM=linux ;;
    i686)          ARCH=386;   PLATFORM=linux ;;
    x86_64)        ARCH=amd64; PLATFORM=linux ;;
    *) log Error "Unsupported arch: $(uname -m)"; return 1 ;;
  esac
}

get_latest_version() {
  local api_url ver
  if [ "$SINGBOX_STABLE" = "true" ]; then
    api_url="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    ver=$(api_get "$api_url" | command grep '"tag_name"' | $busybox grep -oE 'v[0-9.]+' | head -1)
  else
    api_url="https://api.github.com/repos/SagerNet/sing-box/releases"
    ver=$(api_get "$api_url" | command grep '"tag_name"' | $busybox grep -oE 'v[0-9][^"]*' | head -1 | cut -d'"' -f1)
  fi

  if [ -z "$ver" ]; then
    log Error "Failed to fetch latest version from GitHub API"
    return 1
  fi
  LATEST_VERSION="$ver"
}

do_upkernel() {
  detect_arch  || return 1
  get_latest_version || return 1

  # Validate version string — prevent path traversal in tmp filenames
  case "$LATEST_VERSION" in
    v[0-9]*) ;;
    *) log Error "Invalid version string from API: $LATEST_VERSION"; return 1 ;;
  esac
  local ver="${LATEST_VERSION#v}"
  case "$ver" in
    */*|*..*) log Error "Version string contains unsafe characters: $ver"; return 1 ;;
  esac

  local cur_ver=""
  [ -x "$BIN_PATH" ] && cur_ver=$("$BIN_PATH" version 2>/dev/null | $busybox grep -oE 'v[0-9][^ ]*' | head -1)

  log Info "Current: ${cur_ver:-none}  →  Latest: $LATEST_VERSION"

  if [ "$cur_ver" = "$LATEST_VERSION" ] && [ "$FORCE" != "true" ]; then
    log Info "Already at $LATEST_VERSION — nothing to do (--force to reinstall)"
    return 0
  fi

  local tarball="sing-box-${ver}-${PLATFORM}-${ARCH}.tar.gz"
  local dl_url="https://github.com/SagerNet/sing-box/releases/download/${LATEST_VERSION}/${tarball}"
  local tmp_tar="${BOX_DIR}/${tarball}"

  mkdir -p "${BIN_DIR}/backup"
  if [ -x "$BIN_PATH" ]; then
    cp "$BIN_PATH" "${BIN_DIR}/backup/sing-box.bak"
    log Info "Backed up current binary → backup/sing-box.bak"
  fi

  download_file "$tmp_tar" "$dl_url" || return 1

  log Info "Extracting..."
  local extract_dir="${BIN_DIR}/sing-box-${ver}-${PLATFORM}-${ARCH}"
  rm -rf "$extract_dir"

  if ! $busybox tar -xf "$tmp_tar" -C "$BIN_DIR" 2>/dev/null; then
    log Error "Extraction failed"
    rm -f "$tmp_tar"
    [ -f "${BIN_DIR}/backup/sing-box.bak" ] && cp "${BIN_DIR}/backup/sing-box.bak" "$BIN_PATH"
    return 1
  fi
  rm -f "$tmp_tar"

  local new_bin="${extract_dir}/sing-box"
  if [ ! -f "$new_bin" ]; then
    log Error "Binary not found in archive (expected: $new_bin)"
    rm -rf "$extract_dir"
    [ -f "${BIN_DIR}/backup/sing-box.bak" ] && cp "${BIN_DIR}/backup/sing-box.bak" "$BIN_PATH"
    return 1
  fi

  # Verify new binary is executable before replacing the live binary
  if ! "$new_bin" version >/dev/null 2>&1; then
    log Error "New binary failed sanity check — aborting install"
    rm -rf "$extract_dir"
    return 1
  fi

  if ! mv "$new_bin" "$BIN_PATH"; then
    log Error "Failed to install binary to $BIN_PATH"
    rm -rf "$extract_dir"
    [ -f "${BIN_DIR}/backup/sing-box.bak" ] && cp "${BIN_DIR}/backup/sing-box.bak" "$BIN_PATH"
    return 1
  fi
  rm -rf "$extract_dir"

  chown "$USER_GROUP" "$BIN_PATH" 2>/dev/null
  chmod 6755 "$BIN_PATH"

  local installed_ver
  installed_ver=$("$BIN_PATH" version 2>/dev/null | $busybox grep -oE 'v[0-9][^ ]*' | head -1)
  log Info "sing-box installed: ${installed_ver:-$LATEST_VERSION}"

  if [ "$RESTART" = "true" ]; then
    if [ -f "$BOX_PID" ] && kill -0 "$(cat "$BOX_PID" 2>/dev/null)" 2>/dev/null; then
      log Info "Restarting sing-box..."
      rm -f "${BOX_DIR}/sing-box/cache.db"
      "$START_SH" restart
    else
      log Info "sing-box not running — skipping restart"
    fi
  fi
}

for arg in "$@"; do
  case "$arg" in
    --force|-f)          FORCE=true ;;
    --restart|-r)        RESTART=true ;;
    --pre|--prerelease)  SINGBOX_STABLE=false ;;
    --stable)            SINGBOX_STABLE=true ;;
    --help|-h)
      echo "Usage: $0 [--force] [--restart] [--pre|--stable]"
      echo "  --force, -f    Reinstall even if already at latest version"
      echo "  --restart, -r  Restart sing-box after update (if running)"
      echo "  --pre          Use pre-release versions"
      echo "  --stable       Use stable releases only (default)"
      exit 0
      ;;
    *) log Error "Unknown option: $arg"; exit 1 ;;
  esac
done

do_upkernel
