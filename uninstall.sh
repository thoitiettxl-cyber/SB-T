#!/system/bin/sh

box_data_dir="/data/adb/box"
rm_data() {
  if [ ! -d "${box_data_dir}" ]; then
    exit 1
  else
    # Tear down tproxy rules and stop sing-box while the scripts still exist, so
    # uninstalling a running module doesn't strand kernel rules until reboot.
    [ -x "${box_data_dir}/scripts/start.sh" ] && "${box_data_dir}/scripts/start.sh" stop 2>/dev/null
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