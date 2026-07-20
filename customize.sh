#!/system/bin/sh

SKIPUNZIP=1
SKIPMOUNT=false
PROPFILE=true
POSTFSDATA=false
LATESTARTSERVICE=true

if [ "$BOOTMODE" != true ]; then
  abort "-----------------------------------------------------------"
  ui_print "! Vui lòng cài đặt module này trong Magisk/KernelSU/APatch Manager"
  ui_print "! Không hỗ trợ cài đặt từ Recovery"
  abort "-----------------------------------------------------------"
elif [ "$KSU" = true ] && [ "$KSU_VER_CODE" -lt 10670 ]; then
  abort "-----------------------------------------------------------"
  ui_print "! Vui lòng cập nhật KernelSU và ứng dụng quản lý của bạn"
  abort "-----------------------------------------------------------"
fi

service_dir="/data/adb/service.d"
if [ "$KSU" = "true" ]; then
  ui_print "- Phát hiện phiên bản KernelSU: $KSU_VER ($KSU_VER_CODE)"
  [ "$KSU_VER_CODE" -lt 10683 ] && service_dir="/data/adb/ksu/service.d"
elif [ "$APATCH" = "true" ]; then
  APATCH_VER=$(cat "/data/adb/ap/version")
  ui_print "- Phát hiện phiên bản APatch: $APATCH_VER"
else
  ui_print "- Phát hiện phiên bản Magisk: $MAGISK_VER ($MAGISK_VER_CODE)"
fi

mkdir -p "${service_dir}"
if [ -d "/data/adb/modules/box_for_magisk" ]; then
  rm -rf "/data/adb/modules/box_for_magisk"
  ui_print "- Đã xóa module box_for_magisk cũ."
fi
if [ -d "/data/adb/modules/box_for_root" ]; then
  rm -rf "/data/adb/modules/box_for_root"
  ui_print "- Đã xóa module box_for_root cũ."
fi

ui_print "- Đang cài đặt SB Tproxy"
unzip -o "$ZIPFILE" -x 'META-INF/*' -x 'webroot/*' -d "$MODPATH" >&2
if [ -d "/data/adb/box" ]; then
  ui_print "- Đang sao lưu dữ liệu box hiện có"
  temp_bak=$(mktemp -d -p "/data/adb" box.XXXXXXXXXX)
  temp_dir="${temp_bak}"
  for item in /data/adb/box/* /data/adb/box/.[!.]* /data/adb/box/..?*; do
    [ -e "$item" ] || continue
    mv "$item" "${temp_dir}/"
  done
  mv "$MODPATH/box/"* /data/adb/box/
  backup_box="true"
else
  mv "$MODPATH/box" /data/adb/
fi

ui_print "- Đang tạo thư mục"
mkdir -p /data/adb/box/ /data/adb/box/run/ /data/adb/box/bin/

ui_print "- Đang trích xuất uninstall.sh"
unzip -j -o "$ZIPFILE" 'uninstall.sh' -d "$MODPATH" >&2

ui_print "- Đang thiết lập quyền truy cập"
set_perm_recursive $MODPATH 0 0 0755 0644
set_perm_recursive /data/adb/box/ 0 3005 0755 0644
set_perm_recursive /data/adb/box/scripts/ 0 3005 0755 0700
set_perm $MODPATH/uninstall.sh 0 0 0755
set_perm $MODPATH/system/bin/sbctl 0 0 0755
[ -f /data/adb/box/bin/ipset ] && set_perm /data/adb/box/bin/ipset 0 3005 0755
chmod ugo+x $MODPATH/uninstall.sh /data/adb/box/scripts/*

KEY_LISTENER_PID=""
KEY_FIFO=""
KEY_FIFO_DIR=""

start_key_listener() {
    if [ -n "$KEY_LISTENER_PID" ] && kill -0 "$KEY_LISTENER_PID" 2>/dev/null; then
        return
    fi
    # Use an owned temp directory so the FIFO path is not guessable (avoids mktemp -u TOCTOU)
    KEY_FIFO_DIR=$(mktemp -d 2>/dev/null || mktemp -d -p /data/local/tmp) || exit 1
    KEY_FIFO="${KEY_FIFO_DIR}/key.fifo"
    mkfifo "$KEY_FIFO" || exit 1
    getevent -ql > "$KEY_FIFO" &
    KEY_LISTENER_PID=$!
}

stop_key_listener() {
    if [ -n "$KEY_LISTENER_PID" ]; then
        kill "$KEY_LISTENER_PID" >/dev/null 2>&1
        KEY_LISTENER_PID=""
    fi
    if [ -n "$KEY_FIFO_DIR" ]; then
        rm -rf "$KEY_FIFO_DIR"
        KEY_FIFO_DIR=""
        KEY_FIFO=""
    fi
}

volume_key_detection() {
    local timeout_seconds="${1:-0}"
    local detection_result_file
    detection_result_file=$(mktemp 2>/dev/null || mktemp -p /data/local/tmp)
    
    (
        while read -r line; do
            if echo "$line" | grep -Eiq "(KEY_)?VOLUME ?UP|KEYCODE_VOLUME_UP" && echo "$line" | grep -Eiq "DOWN|PRESS"; then
                echo "0" > "$detection_result_file"
                exit 0
            elif echo "$line" | grep -Eiq "(KEY_)?VOLUME ?DOWN|KEYCODE_VOLUME_DOWN" && echo "$line" | grep -Eiq "DOWN|PRESS"; then
                echo "1" > "$detection_result_file"
                exit 0
            fi
        done < "$KEY_FIFO"
    ) &
    local detection_pid=$!
    
    if [ "$timeout_seconds" -gt 0 ]; then
        (
            sleep "$timeout_seconds"
            if kill -0 "$detection_pid" 2>/dev/null; then
                kill "$detection_pid" 2>/dev/null
                echo "2" > "$detection_result_file"
            fi
        ) &
        local timeout_pid=$!
        
        wait "$detection_pid" 2>/dev/null
        kill "$timeout_pid" 2>/dev/null
        wait "$timeout_pid" 2>/dev/null
    else
        wait "$detection_pid" 2>/dev/null
    fi
    
    if [ -f "$detection_result_file" ]; then
        local result=$(cat "$detection_result_file")
        rm -f "$detection_result_file"
        return "$result"
    fi
    
    rm -f "$detection_result_file"
    return 2
}

handle_choice() {
    local question="$1"
    local choice_yes="${2:-Đồng ý}"
    local choice_no="${3:-Không}"
    local timeout_seconds="${4:-10}"

    ui_print " "
    ui_print "-----------------------------------------------------------"
    ui_print "- ${question}"
    ui_print "- [ Tăng âm lượng (+) ]: ${choice_yes}"
    ui_print "- [ Giảm âm lượng (-) ]: ${choice_no}"
    ui_print "- [ Nếu không chọn sau ${timeout_seconds}s, mặc định sẽ chọn: ${choice_yes} ]"

    timeout 0.1 getevent -c 1 >/dev/null 2>&1

    start_key_listener
    volume_key_detection "$timeout_seconds"
    local result=$?
    stop_key_listener
    
    if [ "$result" -eq 0 ]; then
        ui_print "  => Bạn đã chọn: ${choice_yes}"
        return 0
    elif [ "$result" -eq 1 ]; then
        ui_print "  => Bạn đã chọn: ${choice_no}"
        return 1
    else
        ui_print "  => Quá thời gian, mặc định chọn: ${choice_yes}"
        return 0
    fi
}

ui_print " "
ui_print "==========================================================="
ui_print "==          Trình cài đặt SB Tproxy (sing-box)           =="
ui_print "==========================================================="




if [ "${backup_box}" = "true" ]; then
  ui_print " "
  ui_print "- Đang khôi phục cấu hình và dữ liệu người dùng..."

  if [ -f "${temp_dir}/settings.ini" ]; then
    if [ -f "/data/adb/box/settings.ini" ]; then
      if handle_choice "Phát hiện tệp settings.ini cũ, xử lý thế nào?" "Ghi đè (Dùng bản mới)" "Hợp nhất (Giữ lại các cài đặt cũ)"; then
        ui_print "  - Đã chọn sử dụng settings.ini mới (Không áp dụng cài đặt cũ)"
      else
        mv /data/adb/box/settings.ini /data/adb/box/settings.ini.new
        grep -E '^[a-zA-Z0-9_]+=' "${temp_dir}/settings.ini" | while IFS='=' read -r key value; do
          [ -z "${key}" ] && continue
          echo "${key}" | grep -qE '^[a-zA-Z0-9_]+' || continue
          if grep -q -E "^${key}=" "/data/adb/box/settings.ini.new"; then
            escaped_value=$(printf '%s' "${value}" | sed -e 's/[&\\#]/\\&/g')
            sed -i "s#^${key}=.*#${key}=${escaped_value}#" "/data/adb/box/settings.ini.new"
          fi
        done
        mv /data/adb/box/settings.ini.new /data/adb/box/settings.ini
        ui_print "  - Đã hợp nhất các tùy chỉnh của bạn vào tệp settings.ini mới"
      fi
    else
      cp -f "${temp_dir}/settings.ini" "/data/adb/box/settings.ini"
      ui_print "  - Đã khôi phục settings.ini"
    fi
  fi

  restore_config_dir() {
    config_dir="$1"
    if [ -d "${temp_dir}/${config_dir}" ]; then
        ui_print "  - Khôi phục cấu hình thư mục ${config_dir}"
        cp -af "${temp_dir}/${config_dir}/." "/data/adb/box/${config_dir}/"
    fi
  }
  for dir in sing-box; do
    restore_config_dir "$dir"
  done

  restore_binary() {
    local bin_path_fragment="$1"
    local target_path="/data/adb/box/bin/${bin_path_fragment}"
    local backup_path="${temp_dir}/bin/${bin_path_fragment}"

    if [ ! -f "${target_path}" ] && [ -f "${backup_path}" ]; then
      ui_print "  - Khôi phục tệp thực thi (binary): ${bin_path_fragment}"
      mkdir -p "$(dirname "${target_path}")"
      cp -f "${backup_path}" "${target_path}"
      chmod 755 "${target_path}"
    fi
  }
  for bin_item in curl yq sing-box ipset; do
    restore_binary "$bin_item"
  done

  if [ -d "${temp_dir}/run" ]; then
    ui_print "  - Khôi phục log, pid và các tệp runtime"
    cp -af "${temp_dir}/run/." "/data/adb/box/run/"
  fi
fi

# ── Kiểm tra binary sing-box + tùy chọn tải xuống ───────────────────────────
# Chạy SAU restore để tránh báo sai "chưa có binary" khi upgrade (binary vừa được restore)
if [ ! -x "/data/adb/box/bin/sing-box" ]; then
  ui_print " "
  ui_print "-----------------------------------------------------------"
  ui_print "! Chưa có binary sing-box"
  if handle_choice "Tải sing-box binary ngay không?" "Tải ngay" "Bỏ qua (tải thủ công sau)" 15; then
    ui_print "- Đang tải sing-box từ GitHub..."
    export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin"
    if /data/adb/box/scripts/upkernel.sh; then
      ui_print "- Tải sing-box thành công"
    else
      ui_print "! Tải thất bại — sau khi reboot chạy: sbctl update"
    fi
  else
    ui_print "! Hãy đặt binary sing-box vào /data/adb/box/bin/ sau khi reboot"
    ui_print "! Hoặc chạy: su -c sbctl update"
  fi
  ui_print "-----------------------------------------------------------"
else
  ui_print "- Binary sing-box: OK"
fi

# ── Tùy chọn tải IPSET LKMs ──────────────────────────────────────────────────
# DNS/ad blocking does not need IPSET. Only offer third-party kernel code when
# the operator explicitly enabled the CN-IP bypass feature.
_ipset_required=$(awk -F= '
  /^[[:space:]]*BYPASS_CN_IP[[:space:]]*=/ {
    value=$2
    gsub(/[[:space:]"\047]/, "", value)
    print value
    exit
  }
' /data/adb/box/tproxy.conf 2>/dev/null)
if [ "$_ipset_required" = "1" ]; then
  _kver=$(uname -r)
  if handle_choice "Tải IPSET LKMs cho kernel ${_kver} không?" "Tải ngay" "Bỏ qua (tải sau)" 10; then
    ui_print "- Đang tải và kiểm tra IPSET LKMs cho kernel ${_kver}..."
    export PATH="/data/adb/magisk:/data/adb/ksu/bin:/data/adb/ap/bin:$PATH:/system/bin"
    if /data/adb/box/scripts/upipset.sh; then
      ui_print "- Đã cài bundle IPSET; trạng thái tương thích nằm trong runs.log"
    else
      ui_print "! Tải/kiểm tra thất bại — sau khi reboot chạy: sbctl update-ipset"
    fi
  fi
else
  ui_print "- Bỏ qua IPSET LKM (BYPASS_CN_IP=0; DNS/ad blocking không cần IPSET)"
fi

[ -z "$(find /data/adb/box/bin -type f -name '*' ! -name '*.bak')" ] && sed -Ei 's/^description=(\[.*][[:space:]]*)?/description=[ 😱 Module đã cài nhưng cần tải Core thủ công ] /g' $MODPATH/module.prop

if [ "$KSU" = "true" ]; then
  sed -i "s/name=.*/name=SB Tproxy/g" $MODPATH/module.prop
elif [ "$APATCH" = "true" ]; then
  sed -i "s/name=.*/name=SB Tproxy cho APatch/g" $MODPATH/module.prop
else
  sed -i "s/name=.*/name=SB Tproxy cho Magisk/g" $MODPATH/module.prop
fi
unzip -o "$ZIPFILE" 'webroot/*' -d "$MODPATH" >&2

ui_print "- Đang dọn dẹp các tệp tạm"
rm -rf /data/adb/box/bin/.bin $MODPATH/box

if [ "$backup_box" = "true" ] && [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
  ui_print " "
  if handle_choice "Phát hiện tệp sao lưu tạm thời, bạn có muốn xóa không?" "Xóa sao lưu" "Giữ lại sao lưu"; then
    ui_print "- Đang xóa sao lưu: ${temp_dir}"
    rm -rf "${temp_dir}"
    ui_print "- Đã xóa sao lưu"
  else
    ui_print "- Sao lưu đã được giữ lại tại: ${temp_dir}"
  fi
fi

ui_print "- Cài đặt hoàn tất, vui lòng khởi động lại thiết bị."
