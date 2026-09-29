export interface BoxStatus {
  running: boolean
  pid: string
  bin_name: string
  clash_api_port: string
  clash_api_secret: string
  sb_version: string
}

export interface BoxConfig {
  PROXY_MODE: number        // 0=auto, 1=tproxy, 2=redirect
  PERFORMANCE_MODE: number  // 0=normal, 1=performance
  DNS_HIJACK_ENABLE: number
  PROXY_MOBILE: number
  PROXY_WIFI: number
  PROXY_HOTSPOT: number
  PROXY_USB: number
  PROXY_TCP: number
  PROXY_UDP: number
  PROXY_IPV6: number        // -1=disable, 0=auto, 1=enable
  APP_PROXY_ENABLE: number
  APP_PROXY_MODE: 'blacklist' | 'whitelist'
  BYPASS_APPS_LIST: string  // newline-separated package names
  PROXY_APPS_LIST: string   // newline-separated package names
  BYPASS_CN_IP: number
  BLOCK_QUIC: number
  FORCE_MARK_BYPASS: number
  OTHER_BYPASS_INTERFACES: string  // space-separated interface names
  OTHER_PROXY_INTERFACES: string   // space-separated interface names
  bin_name: string
  clash_api_port: string
  clash_api_secret: string
}

export type SubPage = 'config' | 'apps' | 'logs' | 'proxies' | 'update' | 'daemon'

export interface PackageInfo {
  packageName: string
  versionName: string
  versionCode: number
  appLabel: string
  isSystem: boolean
  uid: number
}
