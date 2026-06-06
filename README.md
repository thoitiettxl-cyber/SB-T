# SB Tproxy

Magisk / KernelSU / APatch module — transparent proxy toàn thiết bị Android dùng **[sing-box](https://sing-box.sagernet.org)**.

> **Chỉ hỗ trợ sing-box.** Không clash, mihomo, xray, v2ray, hysteria.

---

## Tính năng

- **Transparent proxy toàn thiết bị** — tproxy mode, không cần VPN service
- **Tự động khôi phục mạng** — re-apply tproxy rules sau WiFi ↔ Mobile handover
- **Watchdog** — tự khởi động lại sing-box nếu crash
- **IPSET hỗ trợ** — bypass theo IP list (CN, GeoIP), per-app rules
- **CLI tool `sbctl`** — quản lý module từ terminal
- **Tự cập nhật** — `sbctl update` tải binary mới nhất từ GitHub
- **Web dashboard** — sing-box UI có thể truy cập qua `http://127.0.0.1:9090/ui/`

---

## Yêu cầu

| | |
|---|---|
| Android | 8.0+ |
| Root | Magisk 24.0+ / KernelSU 0.7.0+ / APatch |
| Kernel | Hỗ trợ `tproxy` (hầu hết GKI kernels) |
| sing-box | Đặt thủ công hoặc dùng `sbctl update` (không bundle do license) |

---

## Cài đặt

### 1. Flash module

Flash file `.zip` trong Magisk / KernelSU / APatch Manager.

Trong quá trình flash, installer sẽ hỏi:
- **Tải sing-box binary ngay?** — nhấn Volume+ để tải từ GitHub, Volume− để bỏ qua
- **Tải IPSET LKMs ngay?** — nhấn Volume+ để tải cho kernel hiện tại

### 2. Đặt sing-box binary (nếu chưa tải trong bước flash)

```sh
# Tải tự động từ GitHub (khuyến nghị)
su -c "sbctl update"

# Hoặc đặt thủ công (arm64)
su -c "cp /path/to/sing-box /data/adb/box/bin/sing-box"
su -c "chmod 755 /data/adb/box/bin/sing-box"
```

### 3. Tải IPSET kernel modules (nếu cần bypass theo IP list)

```sh
su -c "sbctl update-ipset"
```

### 4. Cấu hình sing-box

Chỉnh file config theo nhu cầu:

```
/data/adb/box/sing-box/config.json
```

Kiểm tra config hợp lệ:

```sh
su -c "sbctl config"
```

### 5. Reboot

```sh
reboot
```

Module tự bật khi boot hoàn tất. Kiểm tra trạng thái sau reboot:

```sh
su -c "sbctl status"
```

---

## Sử dụng — sbctl

```
sbctl <command> [options]

Service:
  start                  Bật sing-box + áp tproxy rules
  stop                   Tắt sing-box + xóa tproxy rules
  restart                Khởi động lại
  status                 Xem trạng thái + PID + memory

Logs:
  log [svc|sb|net] [N]   Tail log (mặc định: svc, 20 dòng)
                           svc = module log, sb = sing-box log, net = network change log

Update:
  update [--force] [--pre] [--restart]
                         Cập nhật sing-box binary từ GitHub
  update-ipset [--force] Tải IPSET LKMs cho kernel hiện tại

Kernel modules:
  ipset load             Load IPSET modules ngay (không cần reboot)

Config & Info:
  config                 Kiểm tra config.json
  version                Phiên bản sing-box đang cài
```

Tất cả lệnh cần root:
```sh
su -c "sbctl status"
# hoặc trong root shell:
sbctl status
```

---

## Cấu hình

### Port tproxy

Port tproxy mặc định là **1536**. Phải khớp ở **3 nơi**:

| File | Biến | Giá trị |
|------|------|---------|
| `settings.ini` | `tproxy_port` | `1536` |
| `tproxy.conf` | `PROXY_TCP_PORT` / `PROXY_UDP_PORT` | `1536` |
| `sing-box/config.json` | tproxy inbound `listen_port` | `1536` |

### tproxy.conf — tùy chỉnh chính

```
/data/adb/box/tproxy.conf
```

Các tùy chọn quan trọng:

| Tùy chọn | Mô tả |
|----------|-------|
| `PROXY_TCP_PORT` / `PROXY_UDP_PORT` | Port tproxy inbound |
| `PROXY_IPV6` | Bật/tắt proxy IPv6 |
| `BYPASS_PRIVATE_IP` | Bỏ qua dải IP nội bộ |
| `BYPASS_CN_IP` | Bỏ qua IP Trung Quốc qua ipset |
| `PROXY_MODE` | `blacklist` hoặc `whitelist` (per-app) |
| `BYPASS_APPS` / `PROXY_APPS` | Danh sách app theo mode |

### Web Dashboard

sing-box có dashboard web tại:
```
http://127.0.0.1:9090/ui/
```

Cần cấu hình `experimental.clash_api` trong `config.json`:
```json
"experimental": {
  "clash_api": {
    "external_controller": "127.0.0.1:9090",
    "external_ui": "/data/adb/box/sing-box/ui",
    "secret": ""
  }
}
```

---

## Cấu trúc file

```
/data/adb/box/
├── bin/
│   ├── sing-box          ← Binary chính (tự đặt hoặc sbctl update)
│   ├── ipset             ← Binary ipset (bundled)
│   └── IPSET-LKM/        ← Kernel modules (sbctl update-ipset)
├── scripts/
│   ├── start.sh          ← Lifecycle: start/stop/restart/status
│   ├── tproxy.sh         ← iptables authority duy nhất
│   ├── net.inotify       ← Network change handler
│   ├── ipset.sh          ← Load IPSET LKMs
│   ├── upkernel.sh       ← Cập nhật sing-box binary
│   ├── upipset.sh        ← Tải IPSET LKMs
│   └── sbctl             ← CLI tool
├── sing-box/
│   ├── config.json       ← Cấu hình sing-box
│   └── ui/               ← Web dashboard
├── settings.ini          ← Cấu hình paths module
├── tproxy.conf           ← Cấu hình tproxy
└── run/
    ├── box.pid           ← PID của sing-box
    ├── runs.log          ← Log module
    └── sing-box.log      ← Log sing-box
```

---

## Troubleshooting

### sing-box không khởi động

```sh
# Kiểm tra log
su -c "sbctl log"

# Kiểm tra config
su -c "sbctl config"

# Kiểm tra binary
su -c "ls -la /data/adb/box/bin/sing-box"
```

### Không có internet sau khi module bật

```sh
# Kiểm tra tproxy rules được áp
su -c "iptables -t mangle -nL | grep TPROXY"

# Kiểm tra sing-box đang lắng nghe port 1536
su -c "ss -lnp | grep 1536"

# Xem log lỗi
su -c "sbctl log sb 50"
```

### IPSET không hoạt động

```sh
# Kiểm tra ip_set kernel module
su -c "ls /sys/module/ip_set"

# Load modules thủ công
su -c "sbctl ipset load"

# Tải LKMs nếu chưa có
su -c "sbctl update-ipset"
```

### Module không bật sau reboot

Kiểm tra xem module có bị disable không:
```sh
su -c "ls /data/adb/modules/SB_Tproxy/disable"
```

Nếu file `disable` tồn tại → module bị tắt trong Magisk Manager, kích hoạt lại trong UI.

---

## Boot sequence

```
LATESTARTSERVICE
    │
    ▼ service.sh
    │  chờ sys.boot_completed=1
    │  load IPSET modules
    ├──▶ start.sh start
    │       sing-box check config
    │       sing-box run
    │       wait port 1536 bind
    │       tproxy.sh start (áp iptables rules)
    │
    ├──▶ inotifyd net.inotify (giám sát thay đổi mạng)
    │
    └──▶ watchdog loop (sleep 30s, restart nếu crash)
```

---

## Changelog

Xem [Releases](https://github.com/thoitiettxl-cyber/SB-Tproxy/releases) để biết lịch sử thay đổi.

---

## Credits

- [sing-box](https://github.com/SagerNet/sing-box) — core proxy engine
- [taamarin/box_for_magisk](https://github.com/taamarin/box_for_magisk) — upstream module
- [CHIZI-0618/AndroidTProxyShell](https://github.com/CHIZI-0618/AndroidTProxyShell) — tproxy.sh + tproxy.conf
- [TanakaLun/IPSET_LKM](https://github.com/TanakaLun/IPSET_LKM) — IPSET kernel modules

---

## License

GPL-3.0
