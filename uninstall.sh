#!/system/bin/sh

box_data_dir="/data/adb/box"
rm_data() {
  if [ ! -d "${box_data_dir}" ]; then
    exit 1
  else
    # Tear down tproxy rules and stop sing-box while the scripts still exist, so
    # uninstalling a running module doesn't strand kernel rules until reboot.
    if [ ! -x "${box_data_dir}/scripts/start.sh" ]; then
      printf '%s\n' "SB-Tproxy: refusing to remove runtime data because lifecycle script is missing" >&2
      return 1
    fi
    "${box_data_dir}/scripts/start.sh" stop 2>/dev/null || {
      printf '%s\n' "SB-Tproxy: refusing to remove runtime data because tproxy cleanup failed" >&2
      return 1
    }
    rm -rf "${box_data_dir}"
  fi
  
  if [ -f "/data/adb/ksu/service.d/box_service.sh" ]; then
    rm -rf "/data/adb/ksu/service.d/box_service.sh"
  fi

  if [ -f "/data/adb/service.d/box_service.sh" ]; then
    rm -rf "/data/adb/service.d/box_service.sh"
  fi

}

rm_data
