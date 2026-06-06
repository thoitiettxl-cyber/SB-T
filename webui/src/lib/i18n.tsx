import { createContext, useContext, useState, type ReactNode } from 'react'

type Lang = 'en' | 'vi'

const T = {
  en: {
    // Nav tabs
    tabHome: 'Home', tabProxies: 'Proxies', tabApps: 'Apps', tabLogs: 'Logs', tabUpdate: 'Update',
    tabTools: 'Tools', tabSettings: 'Settings',
    // Sub-page titles
    subPageConfig: 'Config Editor', subPageApps: 'App Rules', subPageLogs: 'Logs',
    subPageProxies: 'Proxy Groups', subPageUpdate: 'Updates', subPageDaemon: 'Daemon Status',
    // Tools sections
    sectionConfig: 'Configuration', sectionRules: 'Rules & Data',
    sectionDiagnostics: 'Diagnostics', sectionUpdate: 'Updates',
    configFilesNav: 'Config Files', configFilesSub: 'config.json · tproxy.conf',
    proxyGroupsNav: 'Proxy Groups & Nodes', proxyGroupsNavSub: 'Clash-compatible API',
    appRulesNav: 'Per-app Proxy Rules', appRulesNavSub: 'Blacklist / Whitelist',
    logsNav: 'Log Viewer', logsNavSub: 'Module · sing-box · Network',
    daemonStatusNav: 'Daemon Status', daemonStatusNavSub: 'watchdog · net.inotify',
    updateNav: 'Binary & IPSET Updates', updateNavSub: 'sing-box · IPSET modules',
    // Home stats
    statsTitle: 'Statistics', activeConns: 'Active', downloaded: 'Download', uploaded: 'Upload',
    statsUnavail: 'Start service to see statistics',
    // Settings
    settingsProxySec: 'Proxy Config', settingsNetworkSec: 'Network Interfaces',
    settingsAdvancedSec: 'Advanced', settingsAppearanceSec: 'Appearance',
    settingsBackupSec: 'Backup & Restore',
    bypassInterfaces: 'Bypass Interfaces', bypassInterfacesSub: 'Not proxied (space-separated)',
    proxyInterfaces: 'Force-proxy Interfaces', proxyInterfacesSub: 'Always proxied (space-separated)',
    themeLabel: 'Theme', themeLight: 'Light', themeDark: 'Dark', themeSystem: 'System',
    langLabel: 'Language',
    exportBtn: 'Export to /sdcard', importBtn: 'Import from /sdcard',
    backupPath: 'Backup location', exportSuccess: 'Exported to /sdcard/SB-Tproxy-backup',
    importSuccess: 'Imported — reload to apply', importFail: 'Import failed — check backup exists',
    // Daemon status
    daemonCheckBtn: 'Check', daemonAlive: 'Running', daemonDead: 'Not found', daemonUnknown: '…',
    inotifyLabel: 'net.inotify', watchdogLabel: 'sing-box PID', lastNetLabel: 'Last net change',
    // Status card
    running: 'Running', stopped: 'Stopped',
    pid: 'PID', version: 'Version', moduleVer: 'Module',
    // Control buttons
    start: 'Start', stop: 'Stop', restart: 'Restart', refresh: 'Refresh',
    // Interface section
    interfaces: 'Interfaces',
    mobile: 'Mobile Data', wifi: 'Wi-Fi', hotspot: 'Hotspot', usb: 'USB Tether',
    // Proxy settings
    proxySettings: 'Proxy Settings',
    proxyMode: 'Proxy Mode', proxyModeAuto: 'Auto', proxyModeTproxy: 'TProxy', proxyModeRedirect: 'Redirect',
    ipv6Mode: 'IPv6', ipv6Disable: 'Disable', ipv6Auto: 'Auto', ipv6Enable: 'Enable',
    proxyTcp: 'Proxy TCP', proxyUdp: 'Proxy UDP',
    blockQuic: 'Block QUIC', bypassCnIp: 'Bypass CN IP',
    perfMode: 'Performance Mode', dnsHijack: 'DNS Hijack',
    // App proxy (home)
    appProxy: 'App Proxy', appProxyOff: 'Off', appProxyBlacklist: 'Blacklist', appProxyWhitelist: 'Whitelist',
    // Quick links
    quickLinks: 'Quick Links', openDashboard: 'Dashboard',
    // Save/discard
    save: 'Save & Restart', saving: 'Saving…', unsavedChanges: 'Unsaved changes', discard: 'Discard',
    // Proxies tab
    proxyGroups: 'Proxy Groups', noProxies: 'No proxy groups found', testDelay: 'Test',
    latency: 'ms', timeout: 'Timeout', testing: 'Testing…',
    apiUnavail: 'Clash API unavailable — start the service first',
    // Apps tab
    appsTitle: 'App Proxy Rules',
    appsMode: 'Mode', appsOff: 'Disable', appsBlacklist: 'Blacklist', appsWhitelist: 'Whitelist',
    appsBlacklistHint: 'Checked apps bypass the proxy',
    appsWhitelistHint: 'Only checked apps use the proxy',
    appsLoading: 'Loading apps…', appsSearch: 'Search apps…',
    appsSave: 'Apply', appsSaved: 'Applied', systemApps: 'System', userApps: 'User',
    // Logs tab
    logModule: 'Module', logSingbox: 'sing-box', logNet: 'Network', clear: 'Clear',
    // Update tab
    updateBin: 'Update sing-box', updateIpset: 'Update IPSET', running_update: 'Updating…',
    confirmUpdate: 'This will download and replace the current binary. Continue?',
    confirmYes: 'Confirm',
    // Generic
    ksuUnavail: 'KernelSU bridge unavailable', loading: 'Loading…', error: 'Error',
    noLogs: 'No logs.',
  },
  vi: {
    tabHome: 'Trang chủ', tabProxies: 'Proxy', tabApps: 'Ứng dụng', tabLogs: 'Nhật ký', tabUpdate: 'Cập nhật',
    tabTools: 'Công cụ', tabSettings: 'Cài đặt',
    subPageConfig: 'Sửa cấu hình', subPageApps: 'Quy tắc app', subPageLogs: 'Nhật ký',
    subPageProxies: 'Nhóm Proxy', subPageUpdate: 'Cập nhật', subPageDaemon: 'Trạng thái daemon',
    sectionConfig: 'Cấu hình', sectionRules: 'Quy tắc & Dữ liệu',
    sectionDiagnostics: 'Chẩn đoán', sectionUpdate: 'Cập nhật',
    configFilesNav: 'Files cấu hình', configFilesSub: 'config.json · tproxy.conf',
    proxyGroupsNav: 'Nhóm & Nút Proxy', proxyGroupsNavSub: 'API tương thích Clash',
    appRulesNav: 'Quy tắc per-app', appRulesNavSub: 'Danh sách đen / trắng',
    logsNav: 'Xem nhật ký', logsNavSub: 'Module · sing-box · Mạng',
    daemonStatusNav: 'Trạng thái daemon', daemonStatusNavSub: 'watchdog · net.inotify',
    updateNav: 'Cập nhật binary & IPSET', updateNavSub: 'sing-box · IPSET modules',
    statsTitle: 'Thống kê', activeConns: 'Đang kết nối', downloaded: 'Đã tải', uploaded: 'Đã gửi',
    statsUnavail: 'Bật dịch vụ để xem thống kê',
    settingsProxySec: 'Cấu hình Proxy', settingsNetworkSec: 'Giao diện mạng',
    settingsAdvancedSec: 'Nâng cao', settingsAppearanceSec: 'Giao diện',
    settingsBackupSec: 'Sao lưu & Khôi phục',
    bypassInterfaces: 'Interface bỏ qua', bypassInterfacesSub: 'Không qua proxy (cách nhau bởi dấu cách)',
    proxyInterfaces: 'Interface bắt buộc proxy', proxyInterfacesSub: 'Luôn qua proxy (cách nhau bởi dấu cách)',
    themeLabel: 'Giao diện', themeLight: 'Sáng', themeDark: 'Tối', themeSystem: 'Hệ thống',
    langLabel: 'Ngôn ngữ',
    exportBtn: 'Xuất ra /sdcard', importBtn: 'Nhập từ /sdcard',
    backupPath: 'Vị trí sao lưu', exportSuccess: 'Đã xuất ra /sdcard/SB-Tproxy-backup',
    importSuccess: 'Đã nhập — tải lại để áp dụng', importFail: 'Nhập thất bại — kiểm tra file backup',
    daemonCheckBtn: 'Kiểm tra', daemonAlive: 'Đang chạy', daemonDead: 'Không tìm thấy', daemonUnknown: '…',
    inotifyLabel: 'net.inotify', watchdogLabel: 'sing-box PID', lastNetLabel: 'Thay đổi mạng cuối',
    running: 'Đang chạy', stopped: 'Đã dừng',
    pid: 'PID', version: 'Phiên bản', moduleVer: 'Module',
    start: 'Bật', stop: 'Tắt', restart: 'Khởi động lại', refresh: 'Làm mới',
    interfaces: 'Giao diện mạng',
    mobile: 'Dữ liệu di động', wifi: 'Wi-Fi', hotspot: 'Điểm phát sóng', usb: 'USB Tether',
    proxySettings: 'Cài đặt Proxy',
    proxyMode: 'Chế độ', proxyModeAuto: 'Tự động', proxyModeTproxy: 'TProxy', proxyModeRedirect: 'Redirect',
    ipv6Mode: 'IPv6', ipv6Disable: 'Tắt', ipv6Auto: 'Tự động', ipv6Enable: 'Bật',
    proxyTcp: 'Proxy TCP', proxyUdp: 'Proxy UDP',
    blockQuic: 'Chặn QUIC', bypassCnIp: 'Bỏ qua IP Trung Quốc',
    perfMode: 'Chế độ hiệu năng', dnsHijack: 'Bắt DNS',
    appProxy: 'Proxy ứng dụng', appProxyOff: 'Tắt', appProxyBlacklist: 'Danh sách đen', appProxyWhitelist: 'Danh sách trắng',
    quickLinks: 'Liên kết nhanh', openDashboard: 'Dashboard',
    save: 'Lưu & Khởi động lại', saving: 'Đang lưu…', unsavedChanges: 'Có thay đổi chưa lưu', discard: 'Hủy',
    proxyGroups: 'Nhóm Proxy', noProxies: 'Không có nhóm proxy', testDelay: 'Kiểm tra',
    latency: 'ms', timeout: 'Hết giờ', testing: 'Đang kiểm tra…',
    apiUnavail: 'Clash API không khả dụng — hãy bật dịch vụ trước',
    appsTitle: 'Quy tắc Proxy ứng dụng',
    appsMode: 'Chế độ', appsOff: 'Tắt', appsBlacklist: 'Danh sách đen', appsWhitelist: 'Danh sách trắng',
    appsBlacklistHint: 'Ứng dụng được chọn sẽ bỏ qua proxy',
    appsWhitelistHint: 'Chỉ ứng dụng được chọn dùng proxy',
    appsLoading: 'Đang tải ứng dụng…', appsSearch: 'Tìm ứng dụng…',
    appsSave: 'Áp dụng', appsSaved: 'Đã áp dụng', systemApps: 'Hệ thống', userApps: 'Người dùng',
    logModule: 'Module', logSingbox: 'sing-box', logNet: 'Mạng', clear: 'Xóa',
    updateBin: 'Cập nhật sing-box', updateIpset: 'Cập nhật IPSET', running_update: 'Đang cập nhật…',
    confirmUpdate: 'Lệnh này sẽ tải và thay thế binary hiện tại. Tiếp tục?',
    confirmYes: 'Xác nhận',
    ksuUnavail: 'KernelSU bridge không khả dụng', loading: 'Đang tải…', error: 'Lỗi',
    noLogs: 'Không có log.',
  },
} as const

type TranslationKey = keyof typeof T.en

const I18nCtx = createContext<{ t: (k: TranslationKey) => string; lang: Lang; setLang: (l: Lang) => void }>({
  t: k => T.en[k],
  lang: 'en',
  setLang: () => {},
})

export function I18nProvider({ children }: { children: ReactNode }) {
  const [lang, setLangState] = useState<Lang>(() => {
    try { return (localStorage.getItem('sb:lang') as Lang) || 'en' } catch { return 'en' }
  })
  function setLang(l: Lang) {
    try { localStorage.setItem('sb:lang', l) } catch {}
    setLangState(l)
  }
  const t = (k: TranslationKey): string => (T[lang] as Record<string, string>)[k] ?? T.en[k]
  return <I18nCtx.Provider value={{ t, lang, setLang }}>{children}</I18nCtx.Provider>
}

export function useI18n() {
  return useContext(I18nCtx)
}
