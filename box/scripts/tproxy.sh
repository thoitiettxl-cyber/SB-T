#!/system/bin/sh
# LOCAL PATCH: upstream uses #!/bin/sh; Android requires #!/system/bin/sh

readonly SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
# Version (use YY.MM.DD format)
readonly SCRIPT_VERSION="v26.05.28"

export TZ=Asia/Shanghai

# Configuration (modify as needed)

# Proxy core configuration
# Proxy running user and group
readonly DEFAULT_CORE_USER_GROUP="root:net_admin"
# Proxy traffic mark
readonly DEFAULT_ROUTING_MARK=""
readonly DEFAULT_FORCE_MARK_BYPASS=0
# Proxy ports (transparent proxy listening ports)
readonly DEFAULT_PROXY_TCP_PORT="1536"
readonly DEFAULT_PROXY_UDP_PORT="1536"

# Proxy mode: 0=auto (check TPROXY support), 1=force TPROXY, 2=force REDIRECT
readonly DEFAULT_PROXY_MODE=0

# Performance mode (0=normal, 1=performance optimized)
# When enabled, may enable some features (e.g. conntrack) for better speed
readonly DEFAULT_PERFORMANCE_MODE=0

# DNS configuration
# DNS hijack method (0: disabled, 1: tproxy, 2: redirect)
readonly DEFAULT_DNS_HIJACK_ENABLE=1
# DNS listening port
readonly DEFAULT_DNS_PORT="1053"

# Interface definitions
# Mobile data interface
readonly DEFAULT_MOBILE_INTERFACE="rmnet_data+"
# WiFi interface
readonly DEFAULT_WIFI_INTERFACE="wlan0"
# Hotspot interface
readonly DEFAULT_HOTSPOT_INTERFACE="wlan2"
# USB tethering interface
readonly DEFAULT_USB_INTERFACE="rndis+"

# Other interfaces that require bypassing or proxying. Multiple interfaces can be separated by spaces
readonly DEFAULT_OTHER_BYPASS_INTERFACES=""
readonly DEFAULT_OTHER_PROXY_INTERFACES=""

# Proxy switches
readonly DEFAULT_PROXY_MOBILE=1
readonly DEFAULT_PROXY_WIFI=1
readonly DEFAULT_PROXY_HOTSPOT=0
readonly DEFAULT_PROXY_USB=0
readonly DEFAULT_PROXY_TCP=1
readonly DEFAULT_PROXY_UDP=1

# IPv6 proxy control:
#  0 = disable proxy (but IPv6 stack remains active)
#  1 = enable proxy (normal IPv6 proxy)
# -1 = force disable IPv6 stack entirely (disable_ipv6=1 on all interfaces)
readonly DEFAULT_PROXY_IPV6=0

# The use of 100.0.0.0/8 instead of 100.64.0.0/10 is purely due to a mistake by China Telecom's service provider, and you can change it back
readonly DEFAULT_BYPASS_IPv4_LIST="0.0.0.0/8 10.0.0.0/8 100.0.0.0/8 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24 192.0.2.0/24 192.88.99.0/24 192.168.0.0/16 198.51.100.0/24 203.0.113.0/24 224.0.0.0/4 240.0.0.0/4 255.255.255.255/32"
readonly DEFAULT_BYPASS_IPv6_LIST="::/128 ::1/128 ::ffff:0:0/96 100::/64 64:ff9b::/96 2001::/32 2001:10::/28 2001:20::/28 2001:db8::/32 2002::/16 fe80::/10 ff00::/8"
readonly DEFAULT_PROXY_IPv4_LIST=""
readonly DEFAULT_PROXY_IPv6_LIST=""

# Hotspot subnet when WiFi and hotspot share the same interface (common on older devices)
# Only used when HOTSPOT_INTERFACE == WIFI_INTERFACE
readonly DEFAULT_HOTSPOT_SUBNET_IPV4="192.168.43.0/24"
readonly DEFAULT_HOTSPOT_SUBNET_IPV6="fe80::/10"

# Mark values
readonly DEFAULT_MARK_VALUE=20
readonly DEFAULT_MARK_VALUE6=25

# Routing table ID
readonly DEFAULT_TABLE_ID=2025

# Per-app proxy (use space to separate package names, supports user:package format)
readonly DEFAULT_APP_PROXY_ENABLE=0
readonly DEFAULT_PROXY_APPS_LIST=""
# Example: "com.example.app com.other"
readonly DEFAULT_BYPASS_APPS_LIST=""
# Example: "com.android.shell"
readonly DEFAULT_APP_PROXY_MODE="blacklist"
# "blacklist" or "whitelist"

# CN IP bypass configuration
readonly DEFAULT_BYPASS_CN_IP=0
# CN IP list file name
readonly DEFAULT_CN_IP_FILE="cn.zone"
readonly DEFAULT_CN_IPV6_FILE="cn_ipv6.zone"
# CN IP source URLs
readonly DEFAULT_CN_IP_URL="https://raw.githubusercontent.com/Hackl0us/GeoIP2-CN/release/CN-ip-cidr.txt"
readonly DEFAULT_CN_IPV6_URL="https://ispip.clang.cn/all_cn_ipv6.txt"

# MAC address blacklist/whitelist configuration (hotspot mode)
readonly DEFAULT_MAC_FILTER_ENABLE=0
# MAC address blacklist/whitelist (use space to separate MAC addresses)
readonly DEFAULT_PROXY_MACS_LIST=""
# Example: "AA:BB:CC:DD:EE:FF 11:22:33:44:55:66"
readonly DEFAULT_BYPASS_MACS_LIST=""
# Example: "FF:EE:DD:CC:BB:AA"
readonly DEFAULT_MAC_PROXY_MODE="blacklist"
# "blacklist" or "whitelist"

# block quic
readonly DEFAULT_BLOCK_QUIC=0

# Whether to include timestamp in logs (0=disable, 1=enable)
# Disabling this can improve performance by avoiding a process fork for each log entry.
readonly DEFAULT_LOG_TIMESTAMP=1

# Dry-run mode (disabled by default)
readonly DEFAULT_DRY_RUN=0

log() {
    local level="$1"
    local message="$2"
    local color_code

    case "$level" in
        Debug) color_code="\033[0;36m" ;;
        Info) color_code="\033[1;32m" ;;
        Warn) color_code="\033[1;33m" ;;
        Error) color_code="\033[1;31m" ;;
        *)
            level="Unknown"
            color_code="\033[0m"
            ;;
    esac

    local should_print=0

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$VERBOSE" -eq 1 ]; then
            should_print=1
        elif [ "$level" = "Debug" ] && case "$message" in "[EXEC] "*) true ;; *) false ;; esac then
            should_print=1
        fi
    else
        if [ "$level" = "Info" ] || [ "$level" = "Warn" ] || [ "$level" = "Error" ]; then
            should_print=1
        elif [ "$VERBOSE" -eq 1 ] && [ "$level" = "Debug" ]; then
            should_print=1
        fi
    fi

    [ "$should_print" -eq 0 ] && return 0

    local timestamp=""
    if [ "$LOG_TIMESTAMP" -eq 1 ]; then
        timestamp="$(date +"%Y-%m-%d %H:%M:%S") "
    fi

    if [ -t 2 ]; then
        printf "%b\n" "${color_code}${timestamp}[${level}]: ${message}\033[0m" >&2
    else
        printf "%s\n" "${timestamp}[${level}]: ${message}" >&2
    fi
}

load_config() {
    if [ -z "$CONFIG_DIR" ]; then
        CONFIG_DIR="$SCRIPT_DIR"
        log Warn "CONFIG_DIR not specified, fallback to script directory: $CONFIG_DIR"
    fi

    if [ -f "$CONFIG_DIR/tproxy.conf" ]; then
        log Info "Sourcing configuration file: $CONFIG_DIR/tproxy.conf"
        . "$CONFIG_DIR/tproxy.conf"
    else
        log Info "No tproxy.conf found in $CONFIG_DIR, using script defaults + environment variables"
    fi

    log Info "Loading configuration from environment or defaults..."

    DRY_RUN="${DRY_RUN:-$DEFAULT_DRY_RUN}"
    CORE_USER_GROUP="${CORE_USER_GROUP:-$DEFAULT_CORE_USER_GROUP}"
    ROUTING_MARK="${ROUTING_MARK:-$DEFAULT_ROUTING_MARK}"
    FORCE_MARK_BYPASS="${FORCE_MARK_BYPASS:-$DEFAULT_FORCE_MARK_BYPASS}"
    PROXY_TCP_PORT="${PROXY_TCP_PORT:-$DEFAULT_PROXY_TCP_PORT}"
    PROXY_UDP_PORT="${PROXY_UDP_PORT:-$DEFAULT_PROXY_UDP_PORT}"
    PROXY_MODE="${PROXY_MODE:-$DEFAULT_PROXY_MODE}"
    PERFORMANCE_MODE="${PERFORMANCE_MODE:-$DEFAULT_PERFORMANCE_MODE}"
    DNS_HIJACK_ENABLE="${DNS_HIJACK_ENABLE:-$DEFAULT_DNS_HIJACK_ENABLE}"
    DNS_PORT="${DNS_PORT:-$DEFAULT_DNS_PORT}"
    MOBILE_INTERFACE="${MOBILE_INTERFACE:-$DEFAULT_MOBILE_INTERFACE}"
    WIFI_INTERFACE="${WIFI_INTERFACE:-$DEFAULT_WIFI_INTERFACE}"
    HOTSPOT_INTERFACE="${HOTSPOT_INTERFACE:-$DEFAULT_HOTSPOT_INTERFACE}"
    USB_INTERFACE="${USB_INTERFACE:-$DEFAULT_USB_INTERFACE}"
    OTHER_BYPASS_INTERFACES="${OTHER_BYPASS_INTERFACES:-$DEFAULT_OTHER_BYPASS_INTERFACES}"
    OTHER_PROXY_INTERFACES="${OTHER_PROXY_INTERFACES:-$DEFAULT_OTHER_PROXY_INTERFACES}"
    PROXY_MOBILE="${PROXY_MOBILE:-$DEFAULT_PROXY_MOBILE}"
    PROXY_WIFI="${PROXY_WIFI:-$DEFAULT_PROXY_WIFI}"
    PROXY_HOTSPOT="${PROXY_HOTSPOT:-$DEFAULT_PROXY_HOTSPOT}"
    PROXY_USB="${PROXY_USB:-$DEFAULT_PROXY_USB}"
    PROXY_TCP="${PROXY_TCP:-$DEFAULT_PROXY_TCP}"
    PROXY_UDP="${PROXY_UDP:-$DEFAULT_PROXY_UDP}"
    PROXY_IPV6="${PROXY_IPV6:-$DEFAULT_PROXY_IPV6}"
    MARK_VALUE="${MARK_VALUE:-$DEFAULT_MARK_VALUE}"
    MARK_VALUE6="${MARK_VALUE6:-$DEFAULT_MARK_VALUE6}"
    TABLE_ID="${TABLE_ID:-$DEFAULT_TABLE_ID}"
    PROXY_IPv4_LIST="${PROXY_IPv4_LIST:-$DEFAULT_PROXY_IPv4_LIST}"
    PROXY_IPv6_LIST="${PROXY_IPv6_LIST:-$DEFAULT_PROXY_IPv6_LIST}"
    BYPASS_IPv4_LIST="${BYPASS_IPv4_LIST:-$DEFAULT_BYPASS_IPv4_LIST}"
    BYPASS_IPv6_LIST="${BYPASS_IPv6_LIST:-$DEFAULT_BYPASS_IPv6_LIST}"
    HOTSPOT_SUBNET_IPV4="${HOTSPOT_SUBNET_IPV4:-$DEFAULT_HOTSPOT_SUBNET_IPV4}"
    HOTSPOT_SUBNET_IPV6="${HOTSPOT_SUBNET_IPV6:-$DEFAULT_HOTSPOT_SUBNET_IPV6}"
    APP_PROXY_ENABLE="${APP_PROXY_ENABLE:-$DEFAULT_APP_PROXY_ENABLE}"
    PROXY_APPS_LIST="${PROXY_APPS_LIST:-$DEFAULT_PROXY_APPS_LIST}"
    BYPASS_APPS_LIST="${BYPASS_APPS_LIST:-$DEFAULT_BYPASS_APPS_LIST}"
    APP_PROXY_MODE="${APP_PROXY_MODE:-$DEFAULT_APP_PROXY_MODE}"
    BYPASS_CN_IP="${BYPASS_CN_IP:-$DEFAULT_BYPASS_CN_IP}"
    CN_IP_FILE="${CN_IP_FILE:-$DEFAULT_CN_IP_FILE}"
    CN_IPV6_FILE="${CN_IPV6_FILE:-$DEFAULT_CN_IPV6_FILE}"
    CN_IP_URL="${CN_IP_URL:-$DEFAULT_CN_IP_URL}"
    CN_IPV6_URL="${CN_IPV6_URL:-$DEFAULT_CN_IPV6_URL}"
    MAC_FILTER_ENABLE="${MAC_FILTER_ENABLE:-$DEFAULT_MAC_FILTER_ENABLE}"
    PROXY_MACS_LIST="${PROXY_MACS_LIST:-$DEFAULT_PROXY_MACS_LIST}"
    BYPASS_MACS_LIST="${BYPASS_MACS_LIST:-$DEFAULT_BYPASS_MACS_LIST}"
    MAC_PROXY_MODE="${MAC_PROXY_MODE:-$DEFAULT_MAC_PROXY_MODE}"
    BLOCK_QUIC="${BLOCK_QUIC:-$DEFAULT_BLOCK_QUIC}"
    LOG_TIMESTAMP="${LOG_TIMESTAMP:-$DEFAULT_LOG_TIMESTAMP}"
    SKIP_CHECK_FEATURE="${SKIP_CHECK_FEATURE:-0}"

    if [ "$VERBOSE" -eq 1 ]; then
        for _var in DRY_RUN CORE_USER_GROUP ROUTING_MARK FORCE_MARK_BYPASS \
            PROXY_TCP_PORT PROXY_UDP_PORT PROXY_MODE PERFORMANCE_MODE \
            DNS_HIJACK_ENABLE DNS_PORT \
            MOBILE_INTERFACE WIFI_INTERFACE HOTSPOT_INTERFACE USB_INTERFACE \
            OTHER_BYPASS_INTERFACES OTHER_PROXY_INTERFACES \
            PROXY_MOBILE PROXY_WIFI PROXY_HOTSPOT PROXY_USB \
            PROXY_TCP PROXY_UDP PROXY_IPV6 \
            MARK_VALUE MARK_VALUE6 TABLE_ID \
            PROXY_IPv4_LIST PROXY_IPv6_LIST BYPASS_IPv4_LIST BYPASS_IPv6_LIST \
            HOTSPOT_SUBNET_IPV4 HOTSPOT_SUBNET_IPV6 \
            APP_PROXY_ENABLE PROXY_APPS_LIST BYPASS_APPS_LIST APP_PROXY_MODE \
            BYPASS_CN_IP CN_IP_FILE CN_IPV6_FILE CN_IP_URL CN_IPV6_URL \
            MAC_FILTER_ENABLE PROXY_MACS_LIST BYPASS_MACS_LIST MAC_PROXY_MODE \
            BLOCK_QUIC LOG_TIMESTAMP SKIP_CHECK_FEATURE; do
            eval "log Debug \"$_var: \$$_var\""
        done
    fi

    log Info "Configuration loading completed"
}


is_safe_config_scalar() {
    # Snapshot values must stay single-line data. Newline/CR would create a
    # second pseudo-key on the next line and break the fixed-key parser.
    local value="$1"
    local cleaned
    cleaned=$(printf '%s' "$value" | tr -d '\n\r')
    [ "$cleaned" = "$value" ]
}

validate_runtime_snapshot_scalars() {
    local value
    for value in "$CONFIG_DIR" "$CORE_USER_GROUP" "$OTHER_PROXY_INTERFACES" \
        "$MOBILE_INTERFACE" "$WIFI_INTERFACE" "$HOTSPOT_INTERFACE" "$USB_INTERFACE"; do
        if ! is_safe_config_scalar "$value"; then
            log Error "Runtime snapshot scalar contains CR/LF: invalid value"
            return 1
        fi
    done
    return 0
}

save_runtime_config() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "Skip saving runtime config"
        return 0
    fi

    if ! validate_runtime_snapshot_scalars; then
        return 1
    fi

    local runtime_file="$CONFIG_DIR/runtime_tproxy.conf"
    local runtime_tmp="${runtime_file}.tmp.$$"
    log Info "Saving runtime config to $runtime_file"

    (
        umask 077
        {
            printf '# Runtime config slice for stop/cleanup only (generated at %s)\n' "$(date)"
            printf 'CONFIG_DIR=%s\n' "$CONFIG_DIR"
            printf 'CORE_USER_GROUP=%s\n' "$CORE_USER_GROUP"
            printf 'PROXY_TCP=%s\n' "$PROXY_TCP"
            printf 'PROXY_UDP=%s\n' "$PROXY_UDP"
            printf 'PROXY_TCP_PORT=%s\n' "$PROXY_TCP_PORT"
            printf 'PROXY_UDP_PORT=%s\n' "$PROXY_UDP_PORT"
            printf 'PROXY_IPV6=%s\n' "$PROXY_IPV6"
            printf 'PROXY_MODE=%s\n' "$PROXY_MODE"
            printf 'OTHER_PROXY_INTERFACES=%s\n' "$OTHER_PROXY_INTERFACES"
            printf 'BYPASS_CN_IP=%s\n' "$BYPASS_CN_IP"
            printf 'BLOCK_QUIC=%s\n' "$BLOCK_QUIC"
            printf 'DNS_HIJACK_ENABLE=%s\n' "$DNS_HIJACK_ENABLE"
            printf 'DNS_PORT=%s\n' "$DNS_PORT"
            printf 'TABLE_ID=%s\n' "$TABLE_ID"
            printf 'MARK_VALUE=%s\n' "$MARK_VALUE"
            printf 'MARK_VALUE6=%s\n' "$MARK_VALUE6"
            printf 'MOBILE_INTERFACE=%s\n' "$MOBILE_INTERFACE"
            printf 'WIFI_INTERFACE=%s\n' "$WIFI_INTERFACE"
            printf 'HOTSPOT_INTERFACE=%s\n' "$HOTSPOT_INTERFACE"
            printf 'USB_INTERFACE=%s\n' "$USB_INTERFACE"
            printf 'PROXY_MOBILE=%s\n' "$PROXY_MOBILE"
            printf 'PROXY_WIFI=%s\n' "$PROXY_WIFI"
            printf 'PROXY_HOTSPOT=%s\n' "$PROXY_HOTSPOT"
            printf 'PROXY_USB=%s\n' "$PROXY_USB"
            printf 'ORIG_IP_FORWARD=%s\n' "$ORIG_IP_FORWARD"
            printf 'ORIG_IP6_FORWARDING=%s\n' "$ORIG_IP6_FORWARDING"
            printf 'USE_TPROXY=%s\n' "$USE_TPROXY"
        } > "$runtime_tmp"
    ) || {
        rm -f "$runtime_tmp" 2> /dev/null
        log Error "Failed to write runtime config to $runtime_tmp"
        return 1
    }
    mv -f "$runtime_tmp" "$runtime_file" 2> /dev/null || {
        rm -f "$runtime_tmp" 2> /dev/null
        log Error "Failed to install runtime config at $runtime_file"
        return 1
    }
    return 0
}

runtime_start_journal_valid() {
    local marker="$CONFIG_DIR/runtime_tproxy.starting"
    local pid

    [ -f "$marker" ] && [ ! -L "$marker" ] || return 1
    pid=$(cat "$marker" 2> /dev/null) || return 1
    case "$pid" in ''|*[!0-9]*) return 1 ;; esac
    [ "$pid" -gt 1 ] 2> /dev/null
}

begin_runtime_start_journal() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    local marker="$CONFIG_DIR/runtime_tproxy.starting"
    local tmp="${marker}.tmp.$$"

    (
        umask 077
        printf '%s' "$$" > "$tmp"
    ) && mv -f "$tmp" "$marker" 2> /dev/null || {
        rm -f "$tmp" 2> /dev/null
        log Error "Cannot create runtime start journal"
        return 1
    }
    if ! save_runtime_config; then
        rm -f "$marker" 2> /dev/null
        return 1
    fi
    return 0
}

commit_runtime_start_journal() {
    save_runtime_config || return 1
    [ "$DRY_RUN" -eq 1 ] && return 0
    rm -f "$CONFIG_DIR/runtime_tproxy.starting" 2> /dev/null || {
        log Error "Runtime state is active but start journal could not be committed"
        return 1
    }
}

commit_runtime_cleanup() {
    local keep_ipv6_backup="${1:-0}"
    [ "$DRY_RUN" -eq 1 ] && return 0

    rm -f "$CONFIG_DIR/runtime_tproxy.conf" 2> /dev/null || {
        log Error "Cleanup succeeded but runtime snapshot could not be removed"
        return 1
    }
    rm -f "$CONFIG_DIR/runtime_tproxy.starting" 2> /dev/null || {
        log Error "Cleanup succeeded but start journal could not be removed"
        return 1
    }
    if [ "$keep_ipv6_backup" -ne 1 ]; then
        rm -f "$CONFIG_DIR/ipv6_backup.conf" 2> /dev/null || {
            log Error "Cleanup succeeded but IPv6 backup could not be removed"
            return 1
        }
    fi
    return 0
}

load_runtime_config() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "Skip loading runtime config"
        return 0
    fi

    local runtime_file="$CONFIG_DIR/runtime_tproxy.conf"
    local line key value seen="" required optional optional_seen=0 full_snapshot=1
    local rt_config_dir="" rt_core_user_group=""
    local rt_proxy_tcp="" rt_proxy_udp=""
    local rt_proxy_tcp_port="$DEFAULT_PROXY_TCP_PORT"
    local rt_proxy_udp_port="$DEFAULT_PROXY_UDP_PORT"
    local rt_proxy_ipv6="" rt_proxy_mode="" rt_other_proxy_interfaces=""
    local rt_bypass_cn_ip="" rt_block_quic="" rt_dns_hijack_enable=""
    local rt_dns_port="$DEFAULT_DNS_PORT"
    local rt_table_id="" rt_mark_value="" rt_mark_value6=""
    local rt_mobile_interface="$DEFAULT_MOBILE_INTERFACE"
    local rt_wifi_interface="$DEFAULT_WIFI_INTERFACE"
    local rt_hotspot_interface="$DEFAULT_HOTSPOT_INTERFACE"
    local rt_usb_interface="$DEFAULT_USB_INTERFACE"
    local rt_proxy_mobile="$DEFAULT_PROXY_MOBILE"
    local rt_proxy_wifi="$DEFAULT_PROXY_WIFI"
    local rt_proxy_hotspot="$DEFAULT_PROXY_HOTSPOT"
    local rt_proxy_usb="$DEFAULT_PROXY_USB"
    local rt_orig_ip_forward="" rt_orig_ip6_forwarding="" rt_use_tproxy=""

    RUNTIME_SNAPSHOT_KIND=invalid
    FORWARDING_META_KNOWN=0

    if [ ! -f "$runtime_file" ]; then
        log Warn "No runtime config found at $runtime_file, using current config for cleanup"
        return 1
    fi

    log Info "Loading runtime config from $runtime_file for cleanup"
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            \#*|'') continue ;;
            *=*)
                key=${line%%=*}
                value=${line#*=}
                ;;
            *)
                log Error "Malformed runtime config line: $line"
                return 1
                ;;
        esac
        case ":$seen:" in
            *":$key:"*)
                log Error "Duplicate runtime config key: $key"
                return 1
                ;;
        esac
        seen="${seen}:$key"
        case "$key" in
            CONFIG_DIR) rt_config_dir=$value ;;
            CORE_USER_GROUP) rt_core_user_group=$value ;;
            PROXY_TCP) rt_proxy_tcp=$value ;;
            PROXY_UDP) rt_proxy_udp=$value ;;
            PROXY_TCP_PORT) rt_proxy_tcp_port=$value ;;
            PROXY_UDP_PORT) rt_proxy_udp_port=$value ;;
            PROXY_IPV6) rt_proxy_ipv6=$value ;;
            PROXY_MODE) rt_proxy_mode=$value ;;
            OTHER_PROXY_INTERFACES) rt_other_proxy_interfaces=$value ;;
            BYPASS_CN_IP) rt_bypass_cn_ip=$value ;;
            BLOCK_QUIC) rt_block_quic=$value ;;
            DNS_HIJACK_ENABLE) rt_dns_hijack_enable=$value ;;
            DNS_PORT) rt_dns_port=$value ;;
            TABLE_ID) rt_table_id=$value ;;
            MARK_VALUE) rt_mark_value=$value ;;
            MARK_VALUE6) rt_mark_value6=$value ;;
            MOBILE_INTERFACE) rt_mobile_interface=$value ;;
            WIFI_INTERFACE) rt_wifi_interface=$value ;;
            HOTSPOT_INTERFACE) rt_hotspot_interface=$value ;;
            USB_INTERFACE) rt_usb_interface=$value ;;
            PROXY_MOBILE) rt_proxy_mobile=$value ;;
            PROXY_WIFI) rt_proxy_wifi=$value ;;
            PROXY_HOTSPOT) rt_proxy_hotspot=$value ;;
            PROXY_USB) rt_proxy_usb=$value ;;
            ORIG_IP_FORWARD) rt_orig_ip_forward=$value ;;
            ORIG_IP6_FORWARDING) rt_orig_ip6_forwarding=$value ;;
            USE_TPROXY) rt_use_tproxy=$value ;;
            *)
                log Error "Unknown runtime config key: $key"
                return 1
                ;;
        esac
    done < "$runtime_file"

    # v1.3.4 wrote this exact 14-key schema. It must remain usable for upgrade
    # teardown even though it did not record ports, interfaces, or sysctl origin.
    for required in CONFIG_DIR CORE_USER_GROUP PROXY_TCP PROXY_UDP PROXY_IPV6 \
        PROXY_MODE OTHER_PROXY_INTERFACES BYPASS_CN_IP BLOCK_QUIC \
        DNS_HIJACK_ENABLE TABLE_ID MARK_VALUE MARK_VALUE6 USE_TPROXY; do
        case ":$seen:" in
            *":$required:"*) ;;
            *)
                log Error "Missing runtime config key: $required"
                return 1
                ;;
        esac
    done

    optional="PROXY_TCP_PORT PROXY_UDP_PORT DNS_PORT MOBILE_INTERFACE WIFI_INTERFACE HOTSPOT_INTERFACE USB_INTERFACE PROXY_MOBILE PROXY_WIFI PROXY_HOTSPOT PROXY_USB ORIG_IP_FORWARD ORIG_IP6_FORWARDING"
    for required in $optional; do
        case ":$seen:" in
            *":$required:"*) optional_seen=1 ;;
            *) full_snapshot=0 ;;
        esac
    done
    if [ "$optional_seen" -eq 1 ] && [ "$full_snapshot" -ne 1 ]; then
        log Error "Runtime config mixes legacy and current snapshot schemas"
        return 1
    fi

    [ "$rt_config_dir" = "$CONFIG_DIR" ] || {
        log Error "Runtime config directory mismatch: $rt_config_dir != $CONFIG_DIR"
        return 1
    }
    for value in "$rt_proxy_tcp" "$rt_proxy_udp" "$rt_bypass_cn_ip" \
        "$rt_block_quic" "$rt_proxy_mobile" "$rt_proxy_wifi" \
        "$rt_proxy_hotspot" "$rt_proxy_usb" "$rt_use_tproxy"; do
        case "$value" in
            0|1) ;;
            *) log Error "Invalid boolean in runtime config"; return 1 ;;
        esac
    done
    case "$rt_proxy_ipv6" in -1|0|1) ;; *) log Error "Invalid runtime PROXY_IPV6"; return 1 ;; esac
    case "$rt_proxy_mode" in 0|1|2) ;; *) log Error "Invalid runtime PROXY_MODE"; return 1 ;; esac
    case "$rt_dns_hijack_enable" in 0|1|2) ;; *) log Error "Invalid runtime DNS_HIJACK_ENABLE"; return 1 ;; esac
    if ! is_positive_integer "$rt_table_id" || [ "$rt_table_id" -lt 1 ] || [ "$rt_table_id" -gt 65535 ] || \
       ! is_positive_integer "$rt_mark_value" || [ "$rt_mark_value" -lt 1 ] || [ "$rt_mark_value" -gt 2147483647 ] || \
       ! is_positive_integer "$rt_mark_value6" || [ "$rt_mark_value6" -lt 1 ] || [ "$rt_mark_value6" -gt 2147483647 ]; then
        log Error "Invalid numeric value in runtime config"
        return 1
    fi
    if [ "$full_snapshot" -eq 1 ]; then
        for value in "$rt_proxy_mobile" "$rt_proxy_wifi" "$rt_proxy_hotspot" "$rt_proxy_usb"; do
            case "$value" in 0|1) ;; *) log Error "Invalid interface toggle in runtime config"; return 1 ;; esac
        done
        case "$rt_orig_ip_forward" in 0|1) ;; *) log Error "Invalid original IPv4 forwarding state"; return 1 ;; esac
        case "$rt_orig_ip6_forwarding" in 0|1) ;; *) log Error "Invalid original IPv6 forwarding state"; return 1 ;; esac
        if ! is_positive_integer "$rt_proxy_tcp_port" || [ "$rt_proxy_tcp_port" -lt 1 ] || [ "$rt_proxy_tcp_port" -gt 65535 ] || \
           ! is_positive_integer "$rt_proxy_udp_port" || [ "$rt_proxy_udp_port" -lt 1 ] || [ "$rt_proxy_udp_port" -gt 65535 ] || \
           ! is_positive_integer "$rt_dns_port" || [ "$rt_dns_port" -lt 1 ] || [ "$rt_dns_port" -gt 65535 ]; then
            log Error "Invalid port in runtime config"
            return 1
        fi
    fi

    for value in "$rt_core_user_group" "$rt_other_proxy_interfaces" \
        "$rt_mobile_interface" "$rt_wifi_interface" "$rt_hotspot_interface" \
        "$rt_usb_interface" "$rt_config_dir"; do
        if ! is_safe_config_scalar "$value"; then
            log Error "Runtime config scalar contains CR/LF"
            return 1
        fi
    done

    CORE_USER_GROUP=$rt_core_user_group
    PROXY_TCP=$rt_proxy_tcp
    PROXY_UDP=$rt_proxy_udp
    PROXY_TCP_PORT=$rt_proxy_tcp_port
    PROXY_UDP_PORT=$rt_proxy_udp_port
    PROXY_IPV6=$rt_proxy_ipv6
    PROXY_MODE=$rt_proxy_mode
    OTHER_PROXY_INTERFACES=$rt_other_proxy_interfaces
    BYPASS_CN_IP=$rt_bypass_cn_ip
    BLOCK_QUIC=$rt_block_quic
    DNS_HIJACK_ENABLE=$rt_dns_hijack_enable
    DNS_PORT=$rt_dns_port
    TABLE_ID=$rt_table_id
    MARK_VALUE=$rt_mark_value
    MARK_VALUE6=$rt_mark_value6
    MOBILE_INTERFACE=$rt_mobile_interface
    WIFI_INTERFACE=$rt_wifi_interface
    HOTSPOT_INTERFACE=$rt_hotspot_interface
    USB_INTERFACE=$rt_usb_interface
    PROXY_MOBILE=$rt_proxy_mobile
    PROXY_WIFI=$rt_proxy_wifi
    PROXY_HOTSPOT=$rt_proxy_hotspot
    PROXY_USB=$rt_proxy_usb
    ORIG_IP_FORWARD=$rt_orig_ip_forward
    ORIG_IP6_FORWARDING=$rt_orig_ip6_forwarding
    USE_TPROXY=$rt_use_tproxy
    if [ "$full_snapshot" -eq 1 ]; then
        RUNTIME_SNAPSHOT_KIND=full
        FORWARDING_META_KNOWN=1
    else
        RUNTIME_SNAPSHOT_KIND=legacy
        log Warn "Using v1.3.4 runtime snapshot; forwarding origin is unknown"
    fi
    return 0
}

init_tmpdir() {
    for d in /tmp /data/local/tmp "$CONFIG_DIR/tmp"; do
        if [ -d "$d" ] && [ -w "$d" ]; then
            export TMPDIR="$d"
            log Debug "Using TMPDIR: $TMPDIR"
            return 0
        fi
    done

    if mkdir -p "$CONFIG_DIR/tmp" 2> /dev/null && [ -w "$CONFIG_DIR/tmp" ]; then
        export TMPDIR="$CONFIG_DIR/tmp"
        log Debug "Created fallback TMPDIR: $TMPDIR"
        return 0
    else
        log Error "Failed to find or create writable TMPDIR"
        exit 1
    fi
}

init_kernel_config_cache() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    [ "$SKIP_CHECK_FEATURE" = "1" ] && return 0

    if [ -f /proc/config.gz ]; then
        if zcat /proc/config.gz > "$TMPDIR/kernel_config.cache" 2> /dev/null; then
            log Debug "Kernel config cached to $TMPDIR/kernel_config.cache"
        else
            log Warn "Failed to cache /proc/config.gz"
            rm -f "$TMPDIR/kernel_config.cache" 2> /dev/null
        fi
    fi
}

# Helper: validate a value is a positive integer (zero forks)
is_positive_integer() {
    case "$1" in
        '' | *[!0-9]*) return 1 ;;
    esac
    return 0
}

parse_core_identity() {
    CORE_USER=""
    CORE_GROUP=""

    case "${CORE_USER_GROUP:-}" in
        *:*:*) return 1 ;;
        *:*)
            CORE_USER="${CORE_USER_GROUP%%:*}"
            CORE_GROUP="${CORE_USER_GROUP#*:}"
            ;;
        *) return 1 ;;
    esac

    [ -n "$CORE_USER" ] && [ -n "$CORE_GROUP" ] || return 1
    case "$CORE_USER" in *[!A-Za-z0-9_.-]*) return 1 ;; esac
    case "$CORE_GROUP" in *[!A-Za-z0-9_.-]*) return 1 ;; esac
    return 0
}

validate_cleanup_config() {
    local value

    for value in "$PROXY_TCP" "$PROXY_UDP" "$BYPASS_CN_IP" "$BLOCK_QUIC"; do
        case "$value" in 0|1) ;; *) return 1 ;; esac
    done
    case "$PROXY_IPV6" in -1|0|1) ;; *) return 1 ;; esac
    case "$PROXY_MODE" in 0|1|2) ;; *) return 1 ;; esac
    case "$DNS_HIJACK_ENABLE" in 0|1|2) ;; *) return 1 ;; esac
    if ! is_positive_integer "$PROXY_TCP_PORT" || [ "$PROXY_TCP_PORT" -lt 1 ] || [ "$PROXY_TCP_PORT" -gt 65535 ] || \
       ! is_positive_integer "$PROXY_UDP_PORT" || [ "$PROXY_UDP_PORT" -lt 1 ] || [ "$PROXY_UDP_PORT" -gt 65535 ] || \
       ! is_positive_integer "$DNS_PORT" || [ "$DNS_PORT" -lt 1 ] || [ "$DNS_PORT" -gt 65535 ] || \
       ! is_positive_integer "$TABLE_ID" || [ "$TABLE_ID" -lt 1 ] || [ "$TABLE_ID" -gt 65535 ] || \
       ! is_positive_integer "$MARK_VALUE" || [ "$MARK_VALUE" -lt 1 ] || [ "$MARK_VALUE" -gt 2147483647 ] || \
       ! is_positive_integer "$MARK_VALUE6" || [ "$MARK_VALUE6" -lt 1 ] || [ "$MARK_VALUE6" -gt 2147483647 ]; then
        return 1
    fi
    if [ "$DRY_RUN" -eq 0 ] && [ "${FORWARDING_META_KNOWN:-0}" -eq 1 ]; then
        case "$ORIG_IP_FORWARD" in 0|1) ;; *) return 1 ;; esac
        case "$ORIG_IP6_FORWARDING" in 0|1) ;; *) return 1 ;; esac
    fi
    return 0
}

validate_config() {
    log Debug "Validating configuration..."

    if ! is_positive_integer "$PROXY_TCP_PORT" || [ "$PROXY_TCP_PORT" -lt 1 ] || [ "$PROXY_TCP_PORT" -gt 65535 ]; then
        log Error "Invalid PROXY_TCP_PORT: $PROXY_TCP_PORT"
        return 1
    fi

    if ! is_positive_integer "$PROXY_UDP_PORT" || [ "$PROXY_UDP_PORT" -lt 1 ] || [ "$PROXY_UDP_PORT" -gt 65535 ]; then
        log Error "Invalid PROXY_UDP_PORT: $PROXY_UDP_PORT"
        return 1
    fi

    case "$PROXY_MODE" in
        0 | 1 | 2) ;;
        *)
            log Error "Invalid PROXY_MODE: $PROXY_MODE (must be 0=auto, 1=force TPROXY, 2=force REDIRECT)"
            return 1
            ;;
    esac

    case "$DNS_HIJACK_ENABLE" in
        0 | 1 | 2) ;;
        *)
            log Error "Invalid DNS_HIJACK_ENABLE: $DNS_HIJACK_ENABLE (must be 0=disabled, 1=tproxy, 2=redirect)"
            return 1
            ;;
    esac

    if ! is_positive_integer "$DNS_PORT" || [ "$DNS_PORT" -lt 1 ] || [ "$DNS_PORT" -gt 65535 ]; then
        log Error "Invalid DNS_PORT: $DNS_PORT"
        return 1
    fi

    if ! is_positive_integer "$MARK_VALUE" || [ "$MARK_VALUE" -lt 1 ] || [ "$MARK_VALUE" -gt 2147483647 ]; then
        log Error "Invalid MARK_VALUE: $MARK_VALUE"
        return 1
    fi

    if ! is_positive_integer "$MARK_VALUE6" || [ "$MARK_VALUE6" -lt 1 ] || [ "$MARK_VALUE6" -gt 2147483647 ]; then
        log Error "Invalid MARK_VALUE6: $MARK_VALUE6"
        return 1
    fi

    if ! is_positive_integer "$TABLE_ID" || [ "$TABLE_ID" -lt 1 ] || [ "$TABLE_ID" -gt 65535 ]; then
        log Error "Invalid TABLE_ID: $TABLE_ID"
        return 1
    fi

    if ! parse_core_identity; then
        log Error "Invalid CORE_USER_GROUP: ${CORE_USER_GROUP:-missing}"
        return 1
    fi
    log Debug "Parsed user:group as '$CORE_USER:$CORE_GROUP'"

    case "$APP_PROXY_MODE" in
        blacklist | whitelist) ;;
        *)
            log Error "Invalid APP_PROXY_MODE: $APP_PROXY_MODE"
            return 1
            ;;
    esac

    case "$MAC_PROXY_MODE" in
        blacklist | whitelist) ;;
        *)
            log Error "Invalid MAC_PROXY_MODE: $MAC_PROXY_MODE"
            return 1
            ;;
    esac

    log Debug "Configuration validation passed"
    return 0
}

check_root() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "Skip root check"
        return 0
    fi
    if [ "$(id -u 2> /dev/null || echo 1)" != "0" ]; then
        log Error "Must run with root privileges"
        exit 1
    fi
}

check_dependencies() {
    export PATH="$PATH:/data/data/com.termux/files/usr/bin:/data/adb/box/bin"

    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "Skip dependency check"
        return 0
    fi

    local missing=""
    local required_commands="awk ip iptables ip6tables"
    local cmd

    for cmd in $required_commands; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        log Error "Missing required commands: $missing"
        log Error "Please check PATH: $PATH"
        exit 1
    fi
}

setup_busybox() {
    local resolved_bb
    resolved_bb=$(command -v busybox 2> /dev/null)
    if [ -n "$resolved_bb" ] && [ -x "$resolved_bb" ]; then
        busybox=$resolved_bb
        export busybox
        log Debug "BusyBox already available in PATH: $busybox"
        return 0
    fi

    log Debug "BusyBox not found in PATH, starting detection..."

    local bb_paths="
        /data/adb/ksu/bin/busybox
        /data/adb/ap/bin/busybox
        /data/adb/magisk/busybox
    "

    local found_bb=""
    for bb in $bb_paths; do
        if [ -f "$bb" ] && [ -x "$bb" ]; then
            found_bb="$bb"
            break
        fi
    done

    if [ -n "$found_bb" ]; then
        local bb_dir=$(dirname "$found_bb")
        export PATH="$PATH:$bb_dir"
        busybox=$found_bb
        export busybox
        log Info "BusyBox detected and added to PATH: $found_bb"
    else
        log Error "No executable BusyBox found in PATH or common root paths"
        return 1
    fi
    return 0
}

check_kernel_feature() {
    local feature="$1"
    local config_name="CONFIG_${feature}"

    # Check compile-time config (/proc/config.gz)
    if [ -f "$TMPDIR/kernel_config.cache" ]; then
        if grep -qE "^${config_name}=[ym]$" "$TMPDIR/kernel_config.cache" 2> /dev/null; then
            log Debug "Kernel feature $feature is enabled (config)"
            return 0
        fi
    fi

    # check runtime loaded modules (/sys/module/)
    local module_name=""
    case "$feature" in
        IP_SET)                       module_name="ip_set" ;;
        NETFILTER_XT_SET)             module_name="xt_set" ;;
        NETFILTER_XT_MATCH_ADDRTYPE)  module_name="xt_addrtype" ;;
        NETFILTER_XT_TARGET_TPROXY)   module_name="xt_TPROXY" ;;
    esac
    if [ -n "$module_name" ] && [ -d "/sys/module/$module_name" ]; then
        log Debug "Kernel feature $feature is enabled (loaded module)"
        return 0
    fi

    log Warn "Kernel feature $feature is disabled or not found"
    return 1
}

init_feature_flags() {
    if [ "$SKIP_CHECK_FEATURE" = "1" ] || [ "$DRY_RUN" -eq 1 ]; then
        log Warn "Kernel feature check skipped"
        HAS_TPROXY=1
        HAS_CONNTRACK=1
        HAS_OWNER=1
        HAS_MARK_MT=1
        HAS_MARK_TG=1
        HAS_SOCKET=1
        HAS_ADDRTYPE=1
        HAS_MAC=1
        HAS_IPSET=1
        HAS_XT_SET=1
        HAS_NAT6=1
        HAS_REDIRECT6=1
        return 0
    fi

    log Info "Detecting kernel features..."

    # Single awk pass replaces 12 grep calls — reduces process forks from O(N) to O(1)
    if [ -f "$TMPDIR/kernel_config.cache" ]; then
        eval "$(awk '
            /^CONFIG_NETFILTER_XT_TARGET_TPROXY=[ym]$/   { print "HAS_TPROXY=1" }
            /^CONFIG_NETFILTER_XT_MATCH_CONNTRACK=[ym]$/  { print "HAS_CONNTRACK=1" }
            /^CONFIG_NETFILTER_XT_MATCH_OWNER=[ym]$/      { print "HAS_OWNER=1" }
            /^CONFIG_NETFILTER_XT_MATCH_MARK=[ym]$/       { print "HAS_MARK_MT=1" }
            /^CONFIG_NETFILTER_XT_TARGET_MARK=[ym]$/      { print "HAS_MARK_TG=1" }
            /^CONFIG_NETFILTER_XT_MATCH_SOCKET=[ym]$/     { print "HAS_SOCKET=1" }
            /^CONFIG_NETFILTER_XT_MATCH_ADDRTYPE=[ym]$/   { print "HAS_ADDRTYPE=1" }
            /^CONFIG_NETFILTER_XT_MATCH_MAC=[ym]$/        { print "HAS_MAC=1" }
            /^CONFIG_IP_SET=[ym]$/                        { print "HAS_IPSET=1" }
            /^CONFIG_NETFILTER_XT_SET=[ym]$/              { print "HAS_XT_SET=1" }
            /^CONFIG_IP6_NF_NAT=[ym]$/                    { print "HAS_NAT6=1" }
            /^CONFIG_IP6_NF_TARGET_REDIRECT=[ym]$/        { print "HAS_REDIRECT6=1" }
        ' "$TMPDIR/kernel_config.cache")"
    fi

    # Loaded module check via shell builtins (no fork)
    [ -d /sys/module/xt_TPROXY ]    && HAS_TPROXY=1
    [ -d /sys/module/nf_conntrack ] && HAS_CONNTRACK=1
    [ -d /sys/module/xt_owner ]     && HAS_OWNER=1
    [ -d /sys/module/xt_mark ]      && { HAS_MARK_MT=1; HAS_MARK_TG=1; }
    [ -d /sys/module/xt_socket ]    && HAS_SOCKET=1
    [ -d /sys/module/xt_addrtype ]  && HAS_ADDRTYPE=1
    [ -d /sys/module/xt_mac ]       && HAS_MAC=1
    [ -d /sys/module/ip_set ]       && HAS_IPSET=1
    [ -d /sys/module/xt_set ]       && HAS_XT_SET=1

    # Log results — warn for any missing feature
    for _feat in TPROXY CONNTRACK OWNER MARK_MT MARK_TG SOCKET ADDRTYPE MAC IPSET XT_SET NAT6 REDIRECT6; do
        eval "_fv=\${HAS_${_feat}:-0}"
        if [ "$_fv" -eq 1 ]; then
            log Debug "Kernel feature $_feat: enabled"
        else
            log Warn "Kernel feature $_feat is disabled or not found"
        fi
    done
    unset _feat _fv
}

check_tproxy_support() {
    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "TPROXY support check skipped"
        return 0
    fi

    if [ "$HAS_TPROXY" -eq 1 ]; then
        log Info "Kernel TPROXY support confirmed"
        return 0
    else
        log Warn "Kernel TPROXY support not available"
        return 1
    fi
}

# Unified command wrapper functions
run_ipt_command() {
    local cmd="$1"
    shift

    log Debug "[EXEC] $cmd -w 100 $*"

    [ "$DRY_RUN" -eq 1 ] && return 0

    command "$cmd" -w 100 "$@"
    local rv=$?
    if [ "${TRACK_IPT_ERRORS:-0}" -eq 1 ] && [ "$rv" -ne 0 ]; then
        IPT_ERROR=1
        log Error "iptables command failed ($rv): $cmd $*"
    fi
    return "$rv"
}

iptables() {
    run_ipt_command iptables "$@"
}

ip6tables() {
    run_ipt_command ip6tables "$@"
}

ip_rule() {
    log Debug "[EXEC] ip rule $*"
    [ "$DRY_RUN" -eq 1 ] && return 0
    command ip rule "$@"
}

ip6_rule() {
    log Debug "[EXEC] ip -6 rule $*"
    [ "$DRY_RUN" -eq 1 ] && return 0
    command ip -6 rule "$@"
}

ip_route() {
    log Debug "[EXEC] ip route $*"
    [ "$DRY_RUN" -eq 1 ] && return 0
    command ip route "$@"
}

ip6_route() {
    log Debug "[EXEC] ip -6 route $*"
    [ "$DRY_RUN" -eq 1 ] && return 0
    command ip -6 route "$@"
}

delete_rule_all() {
    local cmd="$1"
    shift
    local count=0

    while "$cmd" "$@" 2> /dev/null; do
        count=$((count + 1))
        if [ "$count" -ge 50 ]; then
            log Warn "Stopped duplicate rule cleanup after $count removals: $cmd $*"
            break
        fi
    done

    return 0
}

find_packages_uid() {
    [ $# -eq 0 ] && return 0

    awk -v tokens="$*" '
    BEGIN {
        n = split(tokens, t_arr, " ")
        for (i = 1; i <= n; i++) {
            t = t_arr[i]
            if (t ~ /:/) {
                split(t, parts, ":")
                pfx = parts[1]; pkg = parts[2]
            } else {
                pfx = 0; pkg = t
            }
            # Record that we want this package and store its prefix(es)
            wanted[pkg] = 1
            # Multiple prefixes might exist for the same package
            pfxs[pkg] = (pkg in pfxs) ? pfxs[pkg] " " pfx : pfx
        }
    }
    ($1 in wanted) {
        base_uid = ""
        if ($2 ~ /^[0-9]+$/) base_uid = $2
        else if ($(NF-1) ~ /^[0-9]+$/) base_uid = $(NF-1)
        
        if (base_uid != "") {
            m = split(pfxs[$1], p_arr, " ")
            for (j = 1; j <= m; j++) {
                # Store result keyed by package and prefix to preserve order later
                res[$1, p_arr[j]] = (p_arr[j] * 100000 + base_uid)
            }
        }
    }
    END {
        final_out = ""
        for (i = 1; i <= n; i++) {
            t = t_arr[i]
            if (t ~ /:/) {
                split(t, parts, ":")
                pfx = parts[1]; pkg = parts[2]
            } else {
                pfx = 0; pkg = t
            }
            
            if ((pkg, pfx) in res) {
                final_out = (final_out == "") ? res[pkg, pfx] : final_out " " res[pkg, pfx]
            }
        }
        print final_out
    }
    ' /data/system/packages.list
}

safe_chain_create() {
    local family="$1"
    local table="$2"
    local chain="$3"
    local cmd="iptables"

    [ "$family" = "6" ] && cmd="ip6tables"

    $cmd -t "$table" -N "$chain" 2> /dev/null || true
    $cmd -t "$table" -F "$chain"
}

download_file() {
    local url="$1"
    local output="$2"

    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "[EXEC] download $url -> $output (skipped, dry-run)"
        return 0
    fi

    if command -v curl > /dev/null 2>&1; then
        log Debug "[EXEC] curl -fsSL --connect-timeout 10 --retry 3 $url -o $output"
        curl -fsSL --connect-timeout 10 --retry 3 "$url" -o "$output"
    else
        log Debug "[EXEC] busybox wget -q -T 10 -t 3 -O $output $url"
        busybox wget -q -T 10 -t 3 -O "$output" "$url"
    fi
}

download_cn_ip_list() {
    if [ "$BYPASS_CN_IP" -eq 0 ]; then
        log Debug "CN IP bypass is disabled, download skipped"
        return 0
    fi

    log Info "Checking/Downloading China mainland IP list to $CONFIG_DIR/$CN_IP_FILE"

    # Re-download if file doesn't exist or is older than 7 days
    if [ ! -f "$CONFIG_DIR/$CN_IP_FILE" ] || [ "$(find "$CONFIG_DIR/$CN_IP_FILE" -mtime +7 2> /dev/null)" ]; then
        log Info "Fetching latest China IP list from $CN_IP_URL"

        if ! download_file "$CN_IP_URL" "$CONFIG_DIR/$CN_IP_FILE.tmp"; then
            log Error "Failed to download China IP list"
            log Debug "[EXEC] rm -f $CONFIG_DIR/$CN_IP_FILE.tmp"
            rm -f "$CONFIG_DIR/$CN_IP_FILE.tmp"
            return 1
        fi

        log Debug "[EXEC] mv $CONFIG_DIR/$CN_IP_FILE.tmp $CONFIG_DIR/$CN_IP_FILE"
        if [ "$DRY_RUN" -eq 0 ]; then
            mv "$CONFIG_DIR/$CN_IP_FILE.tmp" "$CONFIG_DIR/$CN_IP_FILE"
        fi
        log Info "China IP list saved to $CONFIG_DIR/$CN_IP_FILE"
    else
        log Debug "Using existing China IP list: $CONFIG_DIR/$CN_IP_FILE"
    fi

    if [ "$PROXY_IPV6" -eq 1 ]; then
        log Info "Checking/Downloading China mainland IPv6 list to $CONFIG_DIR/$CN_IPV6_FILE"

        if [ ! -f "$CONFIG_DIR/$CN_IPV6_FILE" ] || [ "$(find "$CONFIG_DIR/$CN_IPV6_FILE" -mtime +7 2> /dev/null)" ]; then
            log Info "Fetching latest China IPv6 list from $CN_IPV6_URL"

            if ! download_file "$CN_IPV6_URL" "$CONFIG_DIR/$CN_IPV6_FILE.tmp"; then
                log Error "Failed to download China IPv6 list"
                log Debug "[EXEC] rm -f $CONFIG_DIR/$CN_IPV6_FILE.tmp"
                rm -f "$CONFIG_DIR/$CN_IPV6_FILE.tmp"
                return 1
            fi

            log Debug "[EXEC] mv $CONFIG_DIR/$CN_IPV6_FILE.tmp $CONFIG_DIR/$CN_IPV6_FILE"
            if [ "$DRY_RUN" -eq 0 ]; then
                mv "$CONFIG_DIR/$CN_IPV6_FILE.tmp" "$CONFIG_DIR/$CN_IPV6_FILE"
            fi
            log Info "China IPv6 list saved to $CONFIG_DIR/$CN_IPV6_FILE"
        else
            log Debug "Using existing China IPv6 list: $CONFIG_DIR/$CN_IPV6_FILE"
        fi
    fi
}

setup_cn_ipset() {
    if [ "$BYPASS_CN_IP" -eq 0 ]; then
        log Debug "CN IP bypass is disabled, ipset setup skipped"
        return 0
    fi

    if ! command -v ipset > /dev/null 2>&1; then
        log Error "ipset command not found. Cannot bypass CN IPs"
        return 1
    fi

    log Info "Setting up ipset for China mainland IPs"

    log Debug "[EXEC] ipset destroy cnip"
    log Debug "[EXEC] ipset destroy cnip6"
    if [ "$DRY_RUN" -eq 0 ]; then
        ipset destroy cnip 2> /dev/null || true
        ipset destroy cnip6 2> /dev/null || true
    fi

    local ipv4_count
    local ipv6_count

    if [ -f "$CONFIG_DIR/$CN_IP_FILE" ]; then
        log Debug "Loading IPv4 CIDR from $CONFIG_DIR/$CN_IP_FILE"

        ipv4_count=$(wc -l < "$CONFIG_DIR/$CN_IP_FILE" 2> /dev/null || echo "0")

        log Debug "[EXEC] ipset create cnip hash:net family inet hashsize 8192 maxelem 65536"
        log Debug "[EXEC] Generating temporary ipset restore file with $ipv4_count entries"

        if [ "$DRY_RUN" -eq 0 ]; then
            temp_file=$(mktemp) || {
                log Error "Failed to create temporary file for ipset restore"
                return 1
            }
            {
                echo "create cnip hash:net family inet hashsize 8192 maxelem 65536"
                awk '!/^[[:space:]]*#/ && NF > 0 {printf "add cnip %s\n", $0}' "$CONFIG_DIR/$CN_IP_FILE"
            } > "$temp_file" || {
                log Error "Failed to write to temporary file: $temp_file"
                rm -f "$temp_file"
                return 1
            }
        else
            log Debug "[EXEC] Would create temporary file and add $ipv4_count entries to cnip"
        fi

        log Debug "[EXEC] ipset restore -f \"$temp_file\""

        if [ "$DRY_RUN" -eq 0 ]; then
            if ipset restore -f "$temp_file" 2> /dev/null; then
                log Info "Successfully loaded $ipv4_count IPv4 CIDR entries into ipset 'cnip'"
            else
                log Error "Failed to create ipset 'cnip' or load IPv4 CIDR entries"
                rm -f "$temp_file" 2> /dev/null
                return 1
            fi
            log Debug "[EXEC] rm -f $temp_file"
            rm -f "$temp_file"
        else
            log Debug "[EXEC] Would load $ipv4_count IPv4 CIDR entries via ipset restore"
        fi

    else
        log Error "CN IP file not found: $CONFIG_DIR/$CN_IP_FILE"
        return 1
    fi
    log Info "ipset 'cnip' loaded with China mainland IPs"

    if [ "$PROXY_IPV6" -eq 1 ]; then
        if [ -f "$CONFIG_DIR/$CN_IPV6_FILE" ]; then
            log Debug "Loading IPv6 CIDR from $CONFIG_DIR/$CN_IPV6_FILE"

            ipv6_count=$(wc -l < "$CONFIG_DIR/$CN_IPV6_FILE" 2> /dev/null || echo "0")

            log Debug "[EXEC] ipset create cnip6 hash:net family inet6 hashsize 8192 maxelem 65536"
            log Debug "[EXEC] Generating temporary ipset restore file with $ipv6_count entries"

            if [ "$DRY_RUN" -eq 0 ]; then
                temp_file6=$(mktemp) || {
                    log Error "Failed to create temporary file for ipset restore"
                    return 1
                }
                {
                    echo "create cnip6 hash:net family inet6 hashsize 8192 maxelem 65536"
                    awk '!/^[[:space:]]*#/ && NF > 0 {printf "add cnip6 %s\n", $0}' "$CONFIG_DIR/$CN_IPV6_FILE"
                } > "$temp_file6" || {
                    log Error "Failed to write to temporary file: $temp_file6"
                    rm -f "$temp_file6"
                    return 1
                }
            else
                log Debug "[EXEC] Would create temporary file and add $ipv6_count entries to cnip6"
            fi

            log Debug "[EXEC] ipset restore -f \"$temp_file6\""

            if [ "$DRY_RUN" -eq 0 ]; then
                if ipset restore -f "$temp_file6" 2> /dev/null; then
                    log Info "Successfully loaded $ipv6_count IPv6 CIDR entries into ipset 'cnip6'"
                else
                    log Error "Failed to create ipset 'cnip6' or load IPv6 CIDR entries"
                    rm -f "$temp_file6" 2> /dev/null
                    return 1
                fi
                log Debug "[EXEC] rm -f $temp_file6"
                rm -f "$temp_file6"
            else
                log Debug "[EXEC] Would load $ipv6_count IPv6 CIDR entries via ipset restore"
            fi

        else
            log Error "CN IPv6 file not found: $CONFIG_DIR/$CN_IPV6_FILE"
            return 1
        fi

        log Info "ipset 'cnip6' loaded with China mainland IPv6 IPs"
    fi
}

# Helper: add sub-chain jump rules with optional performance mode conntrack optimization
# Uses dynamic scoping for $cmd and $table from the calling function
_add_chain_jumps() {
    local parent="$1" perf="$2"
    shift 2
    local target
    for target in "$@"; do
        if [ "$perf" -eq 1 ]; then
            $cmd -t "$table" -A "$parent" -p tcp --syn -j "$target"
            $cmd -t "$table" -A "$parent" -p udp -m conntrack --ctstate NEW,RELATED -j "$target"
        else
            $cmd -t "$table" -A "$parent" -j "$target"
        fi
    done
}

setup_proxy_chain() {
    local family="$1"
    local mode="$2" # tproxy or redirect
    local suffix=""
    local mark="$MARK_VALUE"
    local cmd="iptables"
    local old_track="${TRACK_IPT_ERRORS:-0}"
    TRACK_IPT_ERRORS=1
    IPT_ERROR=0

    if [ "$family" = "6" ]; then
        suffix="6"
        mark="$MARK_VALUE6"
        cmd="ip6tables"
    fi

    # Set mode name for logging
    local mode_name="$mode"
    if [ "$mode" = "tproxy" ]; then
        mode_name="TPROXY"
    else
        mode_name="REDIRECT"
    fi

    log Info "Setting up $mode_name chains for IPv${family}"

    # Define chains based on family
    local chains=""
    chains="PROXY_PREROUTING$suffix PROXY_OUTPUT$suffix DIVERT$suffix PROXY_IP$suffix BYPASS_IP$suffix BYPASS_INTERFACE$suffix PROXY_INTERFACE$suffix DNS_HIJACK_PRE$suffix DNS_HIJACK_OUT$suffix APP_CHAIN$suffix MAC_CHAIN$suffix"

    local table="mangle"
    if [ "$mode" = "redirect" ]; then
        table="nat"
    fi

    # Create chains
    for c in $chains; do
        safe_chain_create "$family" "$table" "$c"
    done

    # 1. 优先建立连接追踪放行，如果是 WAN 回包，直接在这里 ACCEPT 出去，保留 Android netd 原有标记，通过 wlan0 的 Strict RPF 校验
    if [ "$HAS_CONNTRACK" -eq 1 ]; then
        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -m conntrack --ctdir REPLY -j ACCEPT
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m conntrack --ctdir REPLY -j ACCEPT
        log Info "Added reply connection direction bypass"
    fi

    # 2. 只有不是常规回包的流量（比如本地 App 经由 OUTPUT 标记后重定向进入 lo 的 Established 流量），才去走 socket 性能优化
    if [ "$PERFORMANCE_MODE" -eq 1 ] && [ "$HAS_MARK_TG" -eq 1 ] && [ "$HAS_SOCKET" -eq 1 ]; then
        $cmd -t "$table" -A DIVERT$suffix -j MARK --set-mark "$mark"
        $cmd -t "$table" -A DIVERT$suffix -j ACCEPT

        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p tcp -m socket --transparent -j DIVERT$suffix
    fi

    local bypass_success=0
    if [ "$FORCE_MARK_BYPASS" -eq 1 ] && [ "$HAS_MARK_MT" -eq 1 ] && [ -n "$ROUTING_MARK" ]; then
        $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -m mark --mark "$ROUTING_MARK" -j ACCEPT
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m mark --mark "$ROUTING_MARK" -j ACCEPT
        log Info "Added bypass for marked traffic with core mark $ROUTING_MARK (forced)"
        bypass_success=1
    elif [ "$HAS_OWNER" -eq 1 ]; then
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -j ACCEPT
        log Info "Added bypass for core user $CORE_USER:$CORE_GROUP"
        bypass_success=1
    elif [ "$HAS_MARK_MT" -eq 1 ] && [ -n "$ROUTING_MARK" ]; then
        $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m mark --mark "$ROUTING_MARK" -j ACCEPT
        log Info "Added bypass for marked traffic with core mark $ROUTING_MARK"
        bypass_success=1
    fi
    if [ "$bypass_success" -eq 0 ]; then
        log Error "Core traffic bypass not configured, may cause traffic loop"
    fi

    # Pre-check performance mode with conntrack
    local _perf_ct=0
    if [ "$PERFORMANCE_MODE" -eq 1 ] && [ "$HAS_CONNTRACK" -eq 1 ]; then
        _perf_ct=1
    fi

    _add_chain_jumps "PROXY_PREROUTING$suffix" "$_perf_ct" \
        "PROXY_IP$suffix" "BYPASS_IP$suffix" "PROXY_INTERFACE$suffix" "MAC_CHAIN$suffix" "DNS_HIJACK_PRE$suffix"

    _add_chain_jumps "PROXY_OUTPUT$suffix" "$_perf_ct" \
        "PROXY_IP$suffix" "BYPASS_IP$suffix" "BYPASS_INTERFACE$suffix" "APP_CHAIN$suffix" "DNS_HIJACK_OUT$suffix"

    local subnet4
    local subnet6
    if [ "$family" = "6" ]; then
        if [ -n "$PROXY_IPv6_LIST" ]; then
            for subnet6 in $PROXY_IPv6_LIST; do
                $cmd -t "$table" -A "PROXY_IP$suffix" -d "$subnet6" -j RETURN
            done
            log Info "Added proxy rules for PROXY IPv6 ranges"
        fi
    else
        if [ -n "$PROXY_IPv4_LIST" ]; then
            for subnet4 in $PROXY_IPv4_LIST; do
                $cmd -t "$table" -A "PROXY_IP$suffix" -d "$subnet4" -j RETURN
            done
            log Info "Added proxy rules for PROXY IPv4 ranges"
        fi
    fi

    if [ "$HAS_ADDRTYPE" -eq 1 ]; then
        $cmd -t "$table" -A "BYPASS_IP$suffix" -m addrtype --dst-type LOCAL -p udp ! --dport 53 -j ACCEPT
        $cmd -t "$table" -A "BYPASS_IP$suffix" -m addrtype --dst-type LOCAL ! -p udp -j ACCEPT
        log Info "Added local address type bypass"
    fi

    if [ "$family" = "6" ]; then
        for subnet6 in $BYPASS_IPv6_LIST; do
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet6" -p udp ! --dport 53 -j ACCEPT
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet6" -p tcp --dport 53 -j RETURN
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet6" ! -p udp -j ACCEPT
        done
        log Info "Added bypass rules for BYPASS IPv6 ranges"
    else
        for subnet4 in $BYPASS_IPv4_LIST; do
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet4" -p udp ! --dport 53 -j ACCEPT
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet4" -p tcp --dport 53 -j RETURN
            $cmd -t "$table" -A "BYPASS_IP$suffix" -d "$subnet4" ! -p udp -j ACCEPT
        done
        log Info "Added bypass rules for BYPASS IPv4 ranges"
    fi

    if [ "$BYPASS_CN_IP" -eq 1 ]; then
        local ipset_name="cnip"
        if [ "$family" = "6" ]; then
            ipset_name="cnip6"
        fi
        if command -v ipset > /dev/null 2>&1 && ipset list "$ipset_name" > /dev/null 2>&1; then
            $cmd -t "$table" -A "BYPASS_IP$suffix" -m set --match-set "$ipset_name" dst -p udp ! --dport 53 -j ACCEPT
            $cmd -t "$table" -A "BYPASS_IP$suffix" -m set --match-set "$ipset_name" dst ! -p udp -j ACCEPT
            log Info "Added ipset-based CN IP bypass rule"
        else
            log Warn "ipset '$ipset_name' not available, skipping CN IP bypass"
        fi
    fi

    log Info "Configuring interface proxy rules"
    $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i lo -j RETURN
    if [ "$PROXY_MOBILE" -eq 1 ]; then
        $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$MOBILE_INTERFACE" -j RETURN
        log Info "Mobile interface $MOBILE_INTERFACE will be proxied"
    else
        $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$MOBILE_INTERFACE" -j ACCEPT
        $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$MOBILE_INTERFACE" -j ACCEPT
        log Info "Mobile interface $MOBILE_INTERFACE will bypass proxy"
    fi

    local subnet
    if [ "$family" = "6" ]; then
        subnet="$HOTSPOT_SUBNET_IPV6"
    else
        subnet="$HOTSPOT_SUBNET_IPV4"
    fi

    if [ "$HOTSPOT_INTERFACE" = "$WIFI_INTERFACE" ]; then
        if [ "$PROXY_HOTSPOT" -eq 1 ]; then
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$HOTSPOT_INTERFACE" -s "$subnet" -j RETURN
            log Info "Hotspot interface $HOTSPOT_INTERFACE will be proxied"
        else
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$HOTSPOT_INTERFACE" -s "$subnet" -j ACCEPT
            log Info "Hotspot interface $HOTSPOT_INTERFACE will bypass proxy"
        fi

        if [ "$PROXY_WIFI" -eq 1 ]; then
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$WIFI_INTERFACE" ! -s "$subnet" -j RETURN
            log Info "WiFi interface $WIFI_INTERFACE will be proxied"
        else
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$WIFI_INTERFACE" ! -s "$subnet" -j ACCEPT
            $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$WIFI_INTERFACE" -j ACCEPT
            log Info "WiFi interface $WIFI_INTERFACE will bypass proxy"
        fi
    else
        if [ "$PROXY_WIFI" -eq 1 ]; then
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$WIFI_INTERFACE" -j RETURN
            log Info "WiFi interface $WIFI_INTERFACE will be proxied"
        else
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$WIFI_INTERFACE" -j ACCEPT
            $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$WIFI_INTERFACE" -j ACCEPT
            log Info "WiFi interface $WIFI_INTERFACE will bypass proxy"
        fi

        if [ "$PROXY_HOTSPOT" -eq 1 ]; then
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$HOTSPOT_INTERFACE" -j RETURN
            log Info "Hotspot interface $HOTSPOT_INTERFACE will be proxied"
        else
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$HOTSPOT_INTERFACE" -j ACCEPT
            $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$HOTSPOT_INTERFACE" -j ACCEPT
            log Info "Hotspot interface $HOTSPOT_INTERFACE will bypass proxy"
        fi
    fi

    if [ "$PROXY_USB" -eq 1 ]; then
        $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$USB_INTERFACE" -j RETURN
        log Info "USB interface $USB_INTERFACE will be proxied"
    else
        $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$USB_INTERFACE" -j ACCEPT
        $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$USB_INTERFACE" -j ACCEPT
        log Info "USB interface $USB_INTERFACE will bypass proxy"
    fi

    local interface
    if [ -n "$OTHER_PROXY_INTERFACES" ]; then
        for interface in $OTHER_PROXY_INTERFACES; do
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$interface" -j RETURN
        done
        log Info "Other interface $OTHER_PROXY_INTERFACES will be proxied"
    fi

    if [ -n "$OTHER_BYPASS_INTERFACES" ]; then
        for interface in $OTHER_BYPASS_INTERFACES; do
            $cmd -t "$table" -A "PROXY_INTERFACE$suffix" -i "$interface" -j ACCEPT
            $cmd -t "$table" -A "BYPASS_INTERFACE$suffix" -o "$interface" -j ACCEPT
        done
        log Info "Other interface $OTHER_PROXY_INTERFACES will bypass proxy"
    fi

    log Info "Interface proxy rules configuration completed"

    local mac
    if [ "$MAC_FILTER_ENABLE" -eq 1 ] && [ "$PROXY_HOTSPOT" -eq 1 ] && [ -n "$HOTSPOT_INTERFACE" ]; then
        if [ "$HAS_MAC" -eq 1 ]; then
            log Info "Setting up MAC address filter rules for interface $HOTSPOT_INTERFACE"
            case "$MAC_PROXY_MODE" in
                blacklist)
                    if [ -n "$BYPASS_MACS_LIST" ]; then
                        for mac in $BYPASS_MACS_LIST; do
                            if [ -n "$mac" ]; then
                                $cmd -t "$table" -A "MAC_CHAIN$suffix" -m mac --mac-source "$mac" -i "$HOTSPOT_INTERFACE" -j ACCEPT
                                log Info "Added MAC bypass rule for $mac"
                            fi
                        done
                    else
                        log Warn "MAC blacklist mode enabled but no bypass MACs configured"
                    fi
                    $cmd -t "$table" -A "MAC_CHAIN$suffix" -i "$HOTSPOT_INTERFACE" -j RETURN
                    ;;
                whitelist)
                    if [ -n "$PROXY_MACS_LIST" ]; then
                        for mac in $PROXY_MACS_LIST; do
                            if [ -n "$mac" ]; then
                                $cmd -t "$table" -A "MAC_CHAIN$suffix" -m mac --mac-source "$mac" -i "$HOTSPOT_INTERFACE" -j RETURN
                                log Info "Added MAC proxy rule for $mac"
                            fi
                        done
                    else
                        log Warn "MAC whitelist mode enabled but no proxy MACs configured"
                    fi
                    $cmd -t "$table" -A "MAC_CHAIN$suffix" -i "$HOTSPOT_INTERFACE" -j ACCEPT
                    ;;
            esac
        else
            log Warn "MAC filtering requires NETFILTER_XT_MATCH_MAC kernel feature which is not available"
        fi
    fi

    local uids
    local uid
    if [ "$APP_PROXY_ENABLE" -eq 1 ]; then
        if [ "$HAS_OWNER" -eq 1 ]; then
            log Info "Setting up application filter rules in $APP_PROXY_MODE mode"
            case "$APP_PROXY_MODE" in
                blacklist)
                    if [ -n "$BYPASS_APPS_LIST" ]; then
                        uids=$(find_packages_uid $BYPASS_APPS_LIST)
                        if [ $? -eq 0 ] && [ -n "$uids" ]; then
                            for uid in $uids; do
                                if [ -n "$uid" ]; then
                                    $cmd -t "$table" -A "APP_CHAIN$suffix" -m owner --uid-owner "$uid" -j ACCEPT
                                    log Info "Added bypass for UID $uid"
                                fi
                            done
                        fi
                    else
                        log Warn "App blacklist mode enabled but no bypass apps configured"
                    fi
                    $cmd -t "$table" -A "APP_CHAIN$suffix" -j RETURN
                    ;;
                whitelist)
                    if [ -n "$PROXY_APPS_LIST" ]; then
                        uids=$(find_packages_uid $PROXY_APPS_LIST)
                        if [ $? -eq 0 ] && [ -n "$uids" ]; then
                            for uid in $uids; do
                                if [ -n "$uid" ]; then
                                    $cmd -t "$table" -A "APP_CHAIN$suffix" -m owner --uid-owner "$uid" -j RETURN
                                    log Info "Added proxy for UID $uid"
                                fi
                            done
                        fi
                    else
                        log Warn "App whitelist mode enabled but no proxy apps configured"
                    fi
                    $cmd -t "$table" -A "APP_CHAIN$suffix" -j ACCEPT
                    ;;
            esac
        else
            log Warn "Application filtering requires NETFILTER_XT_MATCH_OWNER kernel feature which is not available"
        fi
    fi

    if [ "$DNS_HIJACK_ENABLE" -ne 0 ]; then
        if [ "$mode" = "redirect" ]; then
            setup_dns_hijack "$family" "redirect"
        else
            if [ "$DNS_HIJACK_ENABLE" -eq 2 ]; then
                setup_dns_hijack "$family" "redirect2"
            else
                setup_dns_hijack "$family" "tproxy"
            fi
        fi
    fi

    if [ "$_perf_ct" -eq 1 ]; then
        if [ "$mode" = "tproxy" ]; then
            $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -m conntrack --ctstate NEW,RELATED -j CONNMARK --set-mark "$mark"
            # 【修复】：PREROUTING 阶段加上 /$mark 掩码识别被 MIUI 染色的连接
            $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p tcp -m connmark --mark "$mark/0xff" -j TPROXY --on-port "$PROXY_TCP_PORT" --tproxy-mark "$mark"
            $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p udp -m connmark --mark "$mark/0xff" -j TPROXY --on-port "$PROXY_UDP_PORT" --tproxy-mark "$mark"

            $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m conntrack --ctstate NEW,RELATED -j CONNMARK --set-mark "$mark"
            # 【修复】：OUTPUT 阶段通过 /$mark 掩码抓取包含 ESTABLISHED 在内的后续所有包，并强行洗成干净的 $mark 给策略路由
            $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m connmark --mark "$mark/0xff" -j MARK --set-mark "$mark"
            log Info "TPROXY mode rules added"
        else
            $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -m conntrack --ctstate NEW,RELATED -j CONNMARK --set-mark "$mark"
            # 【修复】：REDIRECT 模式同理加掩码
            $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -m connmark --mark "$mark/0xff" -j REDIRECT --to-ports "$PROXY_TCP_PORT"

            $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m conntrack --ctstate NEW,RELATED -j CONNMARK --set-mark "$mark"
            $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -m connmark --mark "$mark/0xff" -j REDIRECT --to-ports "$PROXY_TCP_PORT"
            log Info "REDIRECT mode rules added"
        fi
    else
        if [ "$mode" = "tproxy" ]; then
            $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p tcp -j TPROXY --on-port "$PROXY_TCP_PORT" --tproxy-mark "$mark"
            $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -p udp -j TPROXY --on-port "$PROXY_UDP_PORT" --tproxy-mark "$mark"
            $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -j MARK --set-mark "$mark"
            log Info "TPROXY mode rules added"
        else
            $cmd -t "$table" -A "PROXY_PREROUTING$suffix" -j REDIRECT --to-ports "$PROXY_TCP_PORT"
            $cmd -t "$table" -A "PROXY_OUTPUT$suffix" -j REDIRECT --to-ports "$PROXY_TCP_PORT"
            log Info "REDIRECT mode rules added"
        fi
    fi

    TRACK_IPT_ERRORS="$old_track"
    if [ "$IPT_ERROR" -ne 0 ]; then
        log Error "$mode_name chains for IPv${family} setup failed"
        return 1
    fi

    TRACK_IPT_ERRORS=1
    # Add rules to main chains
    if [ "$PROXY_UDP" -eq 1 ] || [ "$mode" = "redirect" ]; then
        $cmd -t "$table" -I PREROUTING -p udp -j "PROXY_PREROUTING$suffix"
        $cmd -t "$table" -I OUTPUT -p udp -j "PROXY_OUTPUT$suffix"
        log Info "Added UDP rules to PREROUTING and OUTPUT chains"
    fi
    if [ "$PROXY_TCP" -eq 1 ]; then
        $cmd -t "$table" -I PREROUTING -p tcp -j "PROXY_PREROUTING$suffix"
        $cmd -t "$table" -I OUTPUT -p tcp -j "PROXY_OUTPUT$suffix"
        log Info "Added TCP rules to PREROUTING and OUTPUT chains"
    fi

    TRACK_IPT_ERRORS="$old_track"
    if [ "$IPT_ERROR" -ne 0 ]; then
        log Error "$mode_name top-level jumps for IPv${family} setup failed"
        return 1
    fi

    log Info "$mode_name chains for IPv${family} setup completed"
}

setup_dns_hijack() {
    local family="$1"
    local mode="$2"
    local suffix=""
    local mark="$MARK_VALUE"
    local cmd="iptables"

    if [ "$family" = "6" ]; then
        suffix="6"
        mark="$MARK_VALUE6"
        cmd="ip6tables"
    fi

    case "$mode" in
        tproxy)
            # Handle DNS from interfaces in PREROUTING chain (DNS_HIJACK_PRE)
            $cmd -t mangle -A "DNS_HIJACK_PRE$suffix" -j RETURN
            # Handle local DNS hijacking in OUTPUT chain (DNS_HIJACK_OUT)
            $cmd -t mangle -A "DNS_HIJACK_OUT$suffix" -j RETURN

            log Info "DNS hijack enabled using TPROXY mode"
            ;;
        redirect)
            # Handle DNS using REDIRECT method
            $cmd -t nat -A "PROXY_PREROUTING$suffix" -p tcp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
            $cmd -t nat -A "PROXY_PREROUTING$suffix" -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
            $cmd -t nat -A "PROXY_OUTPUT$suffix" -p tcp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
            $cmd -t nat -A "PROXY_OUTPUT$suffix" -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
            log Info "DNS hijack enabled using REDIRECT mode to port $DNS_PORT"
            ;;
        redirect2)
            # Handle DNS using REDIRECT method
            if [ "$family" = "6" ] && {
                [ "$HAS_NAT6" -eq 0 ] || [ "$HAS_REDIRECT6" -eq 0 ]
            }; then
                log Warn "IPv6: Kernel does not support IPv6 NAT or REDIRECT, IPv6 DNS hijack skipped"
                return 0
            fi
            safe_chain_create "$family" "nat" "NAT_DNS_HIJACK$suffix"
            $cmd -t nat -A "NAT_DNS_HIJACK$suffix" -p tcp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"
            $cmd -t nat -A "NAT_DNS_HIJACK$suffix" -p udp --dport 53 -j REDIRECT --to-ports "$DNS_PORT"

            [ "$PROXY_MOBILE" -eq 1 ] && $cmd -t nat -A PREROUTING -i "$MOBILE_INTERFACE" -j "NAT_DNS_HIJACK$suffix"
            [ "$PROXY_WIFI" -eq 1 ] && $cmd -t nat -A PREROUTING -i "$WIFI_INTERFACE" -j "NAT_DNS_HIJACK$suffix"
            [ "$PROXY_USB" -eq 1 ] && $cmd -t nat -A PREROUTING -i "$USB_INTERFACE" -j "NAT_DNS_HIJACK$suffix"
            local interface
            if [ -n "$OTHER_PROXY_INTERFACES" ]; then
                for interface in $OTHER_PROXY_INTERFACES; do
                    $cmd -t nat -A PREROUTING -i "$interface" -j "NAT_DNS_HIJACK$suffix"
                done
            fi

            $cmd -t nat -A OUTPUT -p udp --dport 53 -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -j ACCEPT
            $cmd -t nat -A OUTPUT -p tcp --dport 53 -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -j ACCEPT
            $cmd -t nat -A OUTPUT -j "NAT_DNS_HIJACK$suffix"

            log Info "DNS hijack enabled using REDIRECT mode to port $DNS_PORT"
            ;;
    esac
}

setup_tproxy_chain4() {
    setup_proxy_chain 4 "tproxy"
}

setup_redirect_chain4() {
    log Warn "REDIRECT mode only supports TCP"
    setup_proxy_chain 4 "redirect"
}

setup_tproxy_chain6() {
    setup_proxy_chain 6 "tproxy"
}

setup_redirect_chain6() {
    if [ "$HAS_NAT6" -eq 0 ] || [ "$HAS_REDIRECT6" -eq 0 ]; then
        log Warn "IPv6: Kernel does not support IPv6 NAT or REDIRECT, IPv6 proxy setup skipped"
        return 0
    fi
    log Warn "REDIRECT mode only supports TCP"
    setup_proxy_chain 6 "redirect"
}

setup_routing4() {
    log Info "Setting up routing rules for IPv4"

    ip_rule add fwmark "$MARK_VALUE" table "$TABLE_ID" pref "$TABLE_ID" || {
        log Error "Failed to add IPv4 routing rule"
        return 1
    }
    ip_route add local 0.0.0.0/0 dev lo table "$TABLE_ID" || {
        log Error "Failed to add IPv4 route"
        return 1
    }

    log Debug "[EXEC] echo 1 > /proc/sys/net/ipv4/ip_forward"
    if [ "$DRY_RUN" -eq 0 ]; then
        echo 1 > /proc/sys/net/ipv4/ip_forward || {
            log Error "Failed to enable IPv4 forwarding"
            return 1
        }
    fi

    log Info "IPv4 routing setup completed"
}

setup_routing6() {
    log Info "Setting up routing rules for IPv6"

    ip6_rule add fwmark "$MARK_VALUE6" table "$TABLE_ID" pref "$TABLE_ID" || {
        log Error "Failed to add IPv6 routing rule"
        return 1
    }
    ip6_route add local ::/0 dev lo table "$TABLE_ID" || {
        log Error "Failed to add IPv6 route"
        return 1
    }

    log Debug "[EXEC] echo 1 > /proc/sys/net/ipv6/conf/all/forwarding"
    if [ "$DRY_RUN" -eq 0 ]; then
        echo 1 > /proc/sys/net/ipv6/conf/all/forwarding || {
            log Error "Failed to enable IPv6 forwarding"
            return 1
        }
    fi

    log Info "IPv6 routing setup completed"
}

cleanup_chain() {
    local family="$1"
    local mode="$2"
    local suffix=""
    local cmd="iptables"

    if [ "$family" = "6" ]; then
        suffix="6"
        cmd="ip6tables"
    fi

    local mode_name="$mode"
    if [ "$mode" = "tproxy" ]; then
        mode_name="TPROXY"
    else
        mode_name="REDIRECT"
    fi

    log Info "Cleaning up $mode_name chains for IPv${family}"

    local table="mangle"
    if [ "$mode" = "redirect" ]; then
        table="nat"
    fi

    # Cleanup is intentionally independent of current protocol toggles. A
    # config change must not strand jumps installed by the previous runtime.
    delete_rule_all "$cmd" -t "$table" -D PREROUTING -p tcp -j "PROXY_PREROUTING$suffix"
    delete_rule_all "$cmd" -t "$table" -D OUTPUT -p tcp -j "PROXY_OUTPUT$suffix"
    delete_rule_all "$cmd" -t "$table" -D PREROUTING -p udp -j "PROXY_PREROUTING$suffix"
    delete_rule_all "$cmd" -t "$table" -D OUTPUT -p udp -j "PROXY_OUTPUT$suffix"

    # Define chains based on family
    local chains="PROXY_PREROUTING$suffix PROXY_OUTPUT$suffix DIVERT$suffix PROXY_IP$suffix BYPASS_IP$suffix BYPASS_INTERFACE$suffix PROXY_INTERFACE$suffix DNS_HIJACK_PRE$suffix DNS_HIJACK_OUT$suffix APP_CHAIN$suffix MAC_CHAIN$suffix"

    # Clean up chains
    for c in $chains; do
        $cmd -t "$table" -F "$c" 2> /dev/null || true
        $cmd -t "$table" -X "$c" 2> /dev/null || true
    done

    # Remove DNS rules if applicable
    if [ "$mode" = "tproxy" ] && [ "$DNS_HIJACK_ENABLE" -eq 2 ]; then
        delete_rule_all "$cmd" -t nat -D PREROUTING -i "$MOBILE_INTERFACE" -j "NAT_DNS_HIJACK$suffix"
        delete_rule_all "$cmd" -t nat -D PREROUTING -i "$WIFI_INTERFACE" -j "NAT_DNS_HIJACK$suffix"
        delete_rule_all "$cmd" -t nat -D PREROUTING -i "$USB_INTERFACE" -j "NAT_DNS_HIJACK$suffix"
        local interface
        if [ -n "$OTHER_PROXY_INTERFACES" ]; then
            for interface in $OTHER_PROXY_INTERFACES; do
                delete_rule_all "$cmd" -t nat -D PREROUTING -i "$interface" -j "NAT_DNS_HIJACK$suffix"
            done
        fi
        delete_rule_all "$cmd" -t nat -D OUTPUT -p udp --dport 53 -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -j ACCEPT
        delete_rule_all "$cmd" -t nat -D OUTPUT -p tcp --dport 53 -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -j ACCEPT
        delete_rule_all "$cmd" -t nat -D OUTPUT -j "NAT_DNS_HIJACK$suffix"
        $cmd -t nat -F "NAT_DNS_HIJACK$suffix" 2> /dev/null || true
        $cmd -t nat -X "NAT_DNS_HIJACK$suffix" 2> /dev/null || true
    fi

    log Info "$mode_name chains for IPv${family} cleanup completed"
}

cleanup_tproxy_chain4() {
    cleanup_chain 4 "tproxy"
}

cleanup_tproxy_chain6() {
    cleanup_chain 6 "tproxy"
}

cleanup_redirect_chain4() {
    cleanup_chain 4 "redirect"
}

cleanup_redirect_chain6() {
    # Cleanup must use the saved runtime mode, not current feature detection.
    # A capability flap after a previous IPv6 REDIRECT start must not strand
    # its jumps/chains simply because NAT6 is unavailable now.
    cleanup_chain 6 "redirect"
}

cleanup_routing4() {
    log Info "Cleaning up IPv4 routing rules"

    delete_rule_all ip_rule del fwmark "$MARK_VALUE" table "$TABLE_ID" pref "$TABLE_ID"
    delete_rule_all ip_route del local 0.0.0.0/0 dev lo table "$TABLE_ID"

    log Info "IPv4 routing cleanup completed"
}

cleanup_routing6() {
    log Info "Cleaning up IPv6 routing rules"

    delete_rule_all ip6_rule del fwmark "$MARK_VALUE6" table "$TABLE_ID" pref "$TABLE_ID"
    delete_rule_all ip6_route del local ::/0 dev lo table "$TABLE_ID"

    log Info "IPv6 routing cleanup completed"
}

restore_forwarding_state() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    local failed=0
    local proc_root="${SB_PROC_ROOT:-/proc}"

    if [ "${FORWARDING_META_KNOWN:-0}" -ne 1 ]; then
        log Warn "Forwarding origin unavailable; owned network state will still be removed"
        return 0
    fi
    if [ "$USE_TPROXY" -eq 1 ]; then
        write_sysctl_checked "$proc_root/sys/net/ipv4/ip_forward" \
            "$ORIG_IP_FORWARD" "IPv4 forwarding" || failed=1
        if [ "$PROXY_IPV6" -eq 1 ] && [ "${TPROXY_KEEP_IPV6_DISABLED:-0}" -ne 1 ]; then
            write_sysctl_checked "$proc_root/sys/net/ipv6/conf/all/forwarding" \
                "$ORIG_IP6_FORWARDING" "IPv6 forwarding" || failed=1
        fi
    fi
    # PROXY_IPV6=-1 is restored only by manage_ipv6(), whose backup also owns
    # accept_ra/autoconf and every per-interface disable_ipv6 value.
    [ "$failed" -eq 0 ]
}

cleanup_ipset() {
    log Debug "[EXEC] ipset destroy cnip"
    log Debug "[EXEC] ipset destroy cnip6"
    if [ "$DRY_RUN" -eq 0 ]; then
        ipset destroy cnip 2> /dev/null || true
        ipset destroy cnip6 2> /dev/null || true
        log Info "Module-owned ipset 'cnip' and 'cnip6' removed"
    fi
}

verify_xtables_table_clean() {
    local cmd="$1"
    local table="$2"
    local family="$3"
    local allow_ipv6_guard="${4:-0}"
    local output probe_rc leftover

    output=$(command "$cmd" -w 5 -t "$table" -S 2>&1)
    probe_rc=$?
    if [ "$probe_rc" -ne 0 ]; then
        # Android kernels frequently lack ip6table_nat / ip6table_mangle. Cleanup
        # already ran best-effort; a missing table cannot retain module chains.
        # Only treat an explicit missing-table signal as clean — never generic rc=1.
        case "$output" in
            *[Tt]"able does not exist"*)
                log Debug "Cleanup postcondition: ${cmd}/${table} unsupported"
                return 0
                ;;
        esac
        log Error "Cleanup postcondition probe failed (${probe_rc}): ${cmd}/${table}"
        return 1
    fi

    leftover=$(printf '%s\n' "$output" | command awk \
        -v family="$family" -v table="$table" -v port="$PROXY_TCP_PORT" \
        -v allow_ipv6_guard="$allow_ipv6_guard" '
        BEGIN {
            suffix=(family == "6" ? "6" : "")
            owned["PROXY_PREROUTING" suffix]=1
            owned["PROXY_OUTPUT" suffix]=1
            owned["DIVERT" suffix]=1
            owned["PROXY_IP" suffix]=1
            owned["BYPASS_IP" suffix]=1
            owned["BYPASS_INTERFACE" suffix]=1
            owned["PROXY_INTERFACE" suffix]=1
            owned["DNS_HIJACK_PRE" suffix]=1
            owned["DNS_HIJACK_OUT" suffix]=1
            owned["APP_CHAIN" suffix]=1
            owned["MAC_CHAIN" suffix]=1
            owned["NAT_DNS_HIJACK" suffix]=1
            owned[(family == "6" ? "BLOCK_QUIC6" : "BLOCK_QUIC")]=1
        }
        {
            for (i=1; i<=NF; i++) {
                if ($i in owned) {
                    print $0
                    exit
                }
            }

            if (table != "filter" && table != "nat") next
            if ($1 != "-A" || $2 != "OUTPUT") next

            dest=""; proto=""; dport=""; jump=""; uid=""; has_owner=0
            for (i=3; i<=NF; i++) {
                if ($i == "-d") dest=$(i+1)
                if ($i == "-p") proto=$(i+1)
                if ($i == "--dport") dport=$(i+1)
                if ($i == "-j") jump=$(i+1)
                if ($i == "--uid-owner") uid=$(i+1)
                if ($i == "-m" && $(i+1) == "owner") has_owner=1
            }

            loopback=(family == "6" ? "::1" : "127.0.0.1")
            if (index(dest, loopback) == 1 && proto == "tcp" &&
                dport == port && jump == "REJECT" && has_owner) {
                print $0
                exit
            }

            if (table == "nat" && dport == "53" && jump == "ACCEPT" &&
                has_owner && (proto == "tcp" || proto == "udp")) {
                print $0
                exit
            }

            if (family == "6" && table == "filter") {
                if (has_owner && (uid == "0" || uid == "0-0") &&
                    dest == "" && proto == "" && dport == "" && jump == "ACCEPT") {
                    if (allow_ipv6_guard == 1) next
                    print $0
                    exit
                }
                if (NF == 4 && $3 == "-j" && $4 == "DROP") {
                    if (allow_ipv6_guard == 1) next
                    print $0
                    exit
                }
            }
        }
    ')
    probe_rc=$?
    if [ "$probe_rc" -ne 0 ]; then
        log Error "Cleanup postcondition parser failed (${probe_rc}): ${cmd}/${table}"
        return 1
    fi

    if [ -n "$leftover" ]; then
        log Error "Cleanup postcondition failed: ${cmd}/${table} still has module state: $leftover"
        return 1
    fi
    return 0
}

verify_ipv6_output_guard() {
    local output

    output=$(command ip6tables -w 5 -t filter -S OUTPUT 2> /dev/null) || {
        log Error "Cannot inspect retained IPv6 output guard"
        return 1
    }
    printf '%s\n' "$output" | command awk '
        $1 == "-A" && $2 == "OUTPUT" {
            has_owner=0; uid=""; jump=""
            for (i=3; i<=NF; i++) {
                if ($i == "-m" && $(i+1) == "owner") has_owner=1
                if ($i == "--uid-owner") uid=$(i+1)
                if ($i == "-j") jump=$(i+1)
            }
            if (NF == 4 && jump == "DROP") have_drop=1
            if (has_owner && (uid == "0" || uid == "0-0" || uid == "root") &&
                jump == "ACCEPT") have_root=1
        }
        END { exit(have_drop && have_root ? 0 : 1) }
    ' || {
        log Error "Retained IPv6 output guard is incomplete"
        return 1
    }
}

verify_ipv6_output_guard_absent() {
    local output

    output=$(command ip6tables -w 5 -t filter -S OUTPUT 2> /dev/null) || {
        log Error "Cannot inspect IPv6 output guard removal"
        return 1
    }
    printf '%s\n' "$output" | command awk '
        $1 == "-A" && $2 == "OUTPUT" {
            has_owner=0; uid=""; jump=""
            for (i=3; i<=NF; i++) {
                if ($i == "-m" && $(i+1) == "owner") has_owner=1
                if ($i == "--uid-owner") uid=$(i+1)
                if ($i == "-j") jump=$(i+1)
            }
            if (NF == 4 && jump == "DROP") stale=1
            if (has_owner && (uid == "0" || uid == "0-0" || uid == "root") &&
                jump == "ACCEPT") stale=1
        }
        END { exit(stale ? 1 : 0) }
    ' || {
        log Error "IPv6 output guard removal is incomplete"
        return 1
    }
}

verify_ipv6_disabled_state() {
    local proc_root="${SB_PROC_ROOT:-/proc}"
    local path seen=0

    [ "$(cat "$proc_root/sys/net/ipv6/conf/all/accept_ra" 2> /dev/null)" = "0" ] || return 1
    [ "$(cat "$proc_root/sys/net/ipv6/conf/all/autoconf" 2> /dev/null)" = "0" ] || return 1
    [ "$(cat "$proc_root/sys/net/ipv6/conf/all/forwarding" 2> /dev/null)" = "0" ] || return 1
    for path in "$proc_root"/sys/net/ipv6/conf/*/disable_ipv6; do
        [ -f "$path" ] || continue
        seen=1
        [ "$(cat "$path" 2> /dev/null)" = "1" ] || return 1
    done
    [ "$seen" -eq 1 ]
}

verify_forwarding_restored() {
    local path="$1"
    local expected="$2"
    local label="$3"
    local current

    case "$expected" in
        0|1) ;;
        *)
            log Error "Cleanup postcondition missing original $label state"
            return 1
            ;;
    esac
    current=$(cat "$path" 2> /dev/null) || {
        log Error "Cleanup postcondition cannot read $label state"
        return 1
    }
    if [ "$current" != "$expected" ]; then
        log Error "Cleanup postcondition failed: $label=$current, expected $expected"
        return 1
    fi
    return 0
}

verify_host_state_restored() {
    [ "$DRY_RUN" -eq 1 ] && return 0
    [ "${FORWARDING_META_KNOWN:-0}" -eq 1 ] || return 0

    local failed=0
    local proc_root="${SB_PROC_ROOT:-/proc}"
    if [ "$USE_TPROXY" -eq 1 ]; then
        verify_forwarding_restored "$proc_root/sys/net/ipv4/ip_forward" \
            "$ORIG_IP_FORWARD" "IPv4 forwarding" || failed=1
        if [ "$PROXY_IPV6" -eq 1 ] && [ "${TPROXY_KEEP_IPV6_DISABLED:-0}" -ne 1 ]; then
            verify_forwarding_restored "$proc_root/sys/net/ipv6/conf/all/forwarding" \
                "$ORIG_IP6_FORWARDING" "IPv6 forwarding" || failed=1
        fi
    fi
    if [ "$PROXY_IPV6" -eq -1 ] && [ "${TPROXY_KEEP_IPV6_DISABLED:-0}" -ne 1 ]; then
        verify_forwarding_restored "$proc_root/sys/net/ipv6/conf/all/forwarding" \
            "$ORIG_IP6_FORWARDING" "IPv6 forwarding" || failed=1
    fi
    [ "$failed" -eq 0 ]
}

verify_proxy_stopped() {
    [ "$DRY_RUN" -eq 1 ] && return 0

    local failed=0
    local probe_rc output

    verify_xtables_table_clean iptables mangle 4 || failed=1
    verify_xtables_table_clean iptables nat 4 || failed=1
    verify_xtables_table_clean iptables filter 4 || failed=1
    # A network reapply may intentionally retain only the IPv6 disable guard
    # across teardown. Every other IPv6 filter artifact must still be absent.
    if [ "${TPROXY_KEEP_IPV6_DISABLED:-0}" -eq 1 ]; then
        verify_xtables_table_clean ip6tables filter 6 1 || failed=1
        verify_ipv6_output_guard || failed=1
        validate_ipv6_backup "$CONFIG_DIR/ipv6_backup.conf" || failed=1
        verify_ipv6_disabled_state || failed=1
    else
        # IPv6 filter rules are installed even in PROXY_IPV6=-1 (leak closure)
        # and PROXY_IPV6=0 (loopback guard), so this probe is unconditional.
        verify_xtables_table_clean ip6tables filter 6 || failed=1
    fi
    # stop_proxy always tears down IPv6 mangle/nat chains regardless of the
    # saved PROXY_IPV6 mode. Probe both tables; unsupported tables are clean.
    verify_xtables_table_clean ip6tables mangle 6 || failed=1
    verify_xtables_table_clean ip6tables nat 6 || failed=1

    output=$(command ip rule show 2>&1)
    probe_rc=$?
    if [ "$probe_rc" -ne 0 ]; then
        log Error "Cleanup postcondition probe failed (${probe_rc}): ip rule show"
        failed=1
    else
        printf '%s\n' "$output" | command awk -v mark="$MARK_VALUE" -v table_id="$TABLE_ID" '
            BEGIN { wanted=tolower(sprintf("fwmark 0x%x", mark)) }
            {
                line=tolower($0)
                if (index(line, wanted) &&
                    (index(line, "lookup " table_id) || index(line, "table " table_id))) found=1
            }
            END { exit(found ? 0 : 1) }
        '
        probe_rc=$?
        case "$probe_rc" in
            0) log Error "Cleanup postcondition failed: IPv4 policy rule for table $TABLE_ID remains"; failed=1 ;;
            1) : ;;
            *) log Error "Cleanup postcondition parser failed (${probe_rc}): IPv4 policy rules"; failed=1 ;;
        esac
    fi

    output=$(command ip route show table "$TABLE_ID" 2>&1)
    probe_rc=$?
    case "$output" in
        *"FIB table does not exist"*) probe_rc=0; output="" ;;
    esac
    if [ "$probe_rc" -ne 0 ]; then
        log Error "Cleanup postcondition probe failed (${probe_rc}): ip route show table $TABLE_ID"
        failed=1
    elif [ -n "$output" ]; then
        log Error "Cleanup postcondition failed: IPv4 local route in table $TABLE_ID remains"
        failed=1
    fi

    output=$(command ip -6 rule show 2>&1)
    probe_rc=$?
    if [ "$probe_rc" -ne 0 ]; then
        log Error "Cleanup postcondition probe failed (${probe_rc}): ip -6 rule show"
        failed=1
    else
        printf '%s\n' "$output" | command awk -v mark="$MARK_VALUE6" -v table_id="$TABLE_ID" '
            BEGIN { wanted=tolower(sprintf("fwmark 0x%x", mark)) }
            {
                line=tolower($0)
                if (index(line, wanted) &&
                    (index(line, "lookup " table_id) || index(line, "table " table_id))) found=1
            }
            END { exit(found ? 0 : 1) }
        '
        probe_rc=$?
        case "$probe_rc" in
            0) log Error "Cleanup postcondition failed: IPv6 policy rule for table $TABLE_ID remains"; failed=1 ;;
            1) : ;;
            *) log Error "Cleanup postcondition parser failed (${probe_rc}): IPv6 policy rules"; failed=1 ;;
        esac
    fi

    output=$(command ip -6 route show table "$TABLE_ID" 2>&1)
    probe_rc=$?
    case "$output" in
        *"FIB table does not exist"*) probe_rc=0; output="" ;;
    esac
    if [ "$probe_rc" -ne 0 ]; then
        log Error "Cleanup postcondition probe failed (${probe_rc}): ip -6 route show table $TABLE_ID"
        failed=1
    elif [ -n "$output" ]; then
        log Error "Cleanup postcondition failed: IPv6 local route in table $TABLE_ID remains"
        failed=1
    fi

    output=$(command ipset list 2>&1)
    probe_rc=$?
    if [ "$probe_rc" -ne 0 ]; then
        case "$output:$BYPASS_CN_IP" in
            *"Kernel error received: Invalid argument:0")
                log Debug "Cleanup postcondition: IPSET unsupported and disabled"
                ;;
            *)
                log Error "Cleanup postcondition probe failed (${probe_rc}): ipset list"
                failed=1
                ;;
        esac
    else
        printf '%s\n' "$output" | command awk '
            /^Name:[[:space:]]+(cnip|cnip6)$/ { found=1 }
            END { exit(found ? 0 : 1) }
        '
        probe_rc=$?
        case "$probe_rc" in
            0)
                log Error "Cleanup postcondition failed: cnip/cnip6 ipset remains"
                failed=1
                ;;
            1) : ;;
            *)
                log Error "Cleanup postcondition parser failed (${probe_rc}): ipset list"
                failed=1
                ;;
        esac
    fi

    verify_host_state_restored || failed=1

    [ "$failed" -eq 0 ]
}

rollback_proxy_start() {
    local rc=0
    local ipv6_restore_ok=1
    local keep_ipv6_disabled="${TPROXY_KEEP_IPV6_DISABLED:-0}"
    log Warn "Rolling back partial proxy setup"
    cleanup_tproxy_chain4
    cleanup_routing4
    cleanup_tproxy_chain6
    cleanup_routing6
    cleanup_redirect_chain4
    cleanup_redirect_chain6
    block_loopback_traffic disable
    block_quic disable
    cleanup_ipset
    if [ "$keep_ipv6_disabled" -eq 1 ]; then
        log Info "Retaining IPv6 transition guard during start rollback"
    elif [ -f "$CONFIG_DIR/ipv6_backup.conf" ]; then
        TPROXY_RETAIN_IPV6_BACKUP=1 manage_ipv6 restore || {
            log Error "Failed to restore IPv6 settings after rollback"
            rc=1
            ipv6_restore_ok=0
        }
    fi
    if [ "$keep_ipv6_disabled" -eq 1 ]; then
        :
    elif [ "$ipv6_restore_ok" -eq 1 ]; then
        block_ipv6_output disable || rc=1
    else
        log Warn "Retaining IPv6 output guard after incomplete rollback restore"
    fi
    restore_forwarding_state || {
        log Error "Failed to restore forwarding state after rollback"
        rc=1
    }
    verify_proxy_stopped || {
        log Error "Rollback left residual proxy state"
        rc=1
    }
    if [ "$rc" -eq 0 ]; then
        commit_runtime_cleanup "$keep_ipv6_disabled" || rc=1
    fi
    return "$rc"
}

detect_proxy_mode() {
    USE_TPROXY=0
    case "$PROXY_MODE" in
        0)
            if check_tproxy_support; then
                USE_TPROXY=1
                log Info "Kernel supports TPROXY, using TPROXY mode (auto)"
            else
                log Warn "Kernel does not support TPROXY, falling back to REDIRECT mode (auto)"
            fi
            ;;
        1)
            if check_tproxy_support; then
                USE_TPROXY=1
                log Info "Using TPROXY mode (forced by configuration)"
            else
                log Error "TPROXY mode forced but kernel does not support TPROXY"
                exit 1
            fi
            ;;
        2)
            log Info "Using REDIRECT mode (forced by configuration)"
            ;;
    esac
}

read_ipv6_backup_forwarding() {
    local backup_file="$1"
    local value

    validate_ipv6_backup "$backup_file" || return 1
    value=$(command awk -F= '$1 == "forwarding" { print $2; found=1; exit } END { if (!found) exit 1 }' \
        "$backup_file") || return 1
    case "$value" in 0|1) printf '%s\n' "$value" ;; *) return 1 ;; esac
}

start_proxy() {
    local proc_root="${SB_PROC_ROOT:-/proc}"
    log Info "Starting proxy setup..."
    if [ "$DRY_RUN" -eq 0 ] && \
       { [ -e "$CONFIG_DIR/runtime_tproxy.conf" ] || \
         [ -e "$CONFIG_DIR/runtime_tproxy.starting" ] || \
         [ -L "$CONFIG_DIR/runtime_tproxy.starting" ]; }; then
        log Error "Runtime snapshot already exists; run stop before another start"
        return 1
    fi
    ORIG_IP_FORWARD=$(cat "$proc_root/sys/net/ipv4/ip_forward" 2> /dev/null)
    ORIG_IP6_FORWARDING=$(cat "$proc_root/sys/net/ipv6/conf/all/forwarding" 2> /dev/null)
    case "$ORIG_IP_FORWARD" in 0|1) ;; *) log Error "Cannot snapshot IPv4 forwarding state"; return 1 ;; esac
    case "$ORIG_IP6_FORWARDING" in 0|1) ;; *) log Error "Cannot snapshot IPv6 forwarding state"; return 1 ;; esac
    if [ -f "$CONFIG_DIR/ipv6_backup.conf" ]; then
        ORIG_IP6_FORWARDING=$(read_ipv6_backup_forwarding \
            "$CONFIG_DIR/ipv6_backup.conf") || {
            log Error "Cannot recover IPv6 forwarding origin from existing backup"
            return 1
        }
    fi
    FORWARDING_META_KNOWN=1
    if ! begin_runtime_start_journal; then
        return 1
    fi
    # Idempotency guard: remove any pre-existing top-level jumps, routing rules
    # and block rules before re-adding them, so a second start without an
    # intervening stop (PID-file race, rapid-tap TOCTOU, crash-restart with a
    # stale pid, manual parallel start) does not stack duplicate -I PREROUTING/
    # OUTPUT jumps, duplicate ip rules/routes, or duplicate QUIC/loopback rules.
    # Mirrors stop_proxy cleanup; all deletes are safe no-ops when absent.
    if [ "$USE_TPROXY" -eq 1 ]; then
        cleanup_tproxy_chain4
        cleanup_routing4
        if [ "$PROXY_IPV6" -eq 1 ]; then
            cleanup_tproxy_chain6
            cleanup_routing6
        fi
    else
        cleanup_redirect_chain4
        if [ "$PROXY_IPV6" -eq 1 ]; then
            cleanup_redirect_chain6
        fi
    fi
    block_loopback_traffic disable
    block_quic disable
    if [ "$BYPASS_CN_IP" -eq 1 ]; then
        if [ "$HAS_IPSET" -eq 0 ] || [ "$HAS_XT_SET" -eq 0 ]; then
            log Error "Kernel does not support ipset (CONFIG_IP_SET, CONFIG_NETFILTER_XT_SET). Cannot bypass CN IPs"
            BYPASS_CN_IP=0
        else
            download_cn_ip_list || log Warn "Failed to download CN IP list, continuing without it"
            if ! setup_cn_ipset; then
                log Error "Failed to setup ipset, CN bypass disabled"
                cleanup_ipset
                BYPASS_CN_IP=0
            fi
        fi
    fi

    if [ "$USE_TPROXY" -eq 1 ]; then
        setup_tproxy_chain4 || { rollback_proxy_start || log Error "Proxy start rollback incomplete"; return 1; }
        setup_routing4 || { rollback_proxy_start || log Error "Proxy start rollback incomplete"; return 1; }
        if [ "$PROXY_IPV6" -eq 1 ]; then
            setup_tproxy_chain6 || { rollback_proxy_start || log Error "Proxy start rollback incomplete"; return 1; }
            setup_routing6 || { rollback_proxy_start || log Error "Proxy start rollback incomplete"; return 1; }
        fi
    else
        setup_redirect_chain4 || { rollback_proxy_start || log Error "Proxy start rollback incomplete"; return 1; }
        if [ "$PROXY_IPV6" -eq 1 ]; then
            setup_redirect_chain6 || { rollback_proxy_start || log Error "Proxy start rollback incomplete"; return 1; }
        fi
    fi
    if [ "$PROXY_IPV6" -ne -1 ]; then
        # A reapply can cross from -1 to 0/1. Keep the old output DROP in place
        # until the new mode's chains are ready, then restore the saved stack.
        if [ -f "$CONFIG_DIR/ipv6_backup.conf" ]; then
            if ! manage_ipv6 restore; then
                log Error "Failed to restore transition IPv6 state; rolling back proxy setup"
                rollback_proxy_start || log Error "Proxy start rollback incomplete"
                return 1
            fi
            if [ "$PROXY_IPV6" -eq 1 ] && [ "$USE_TPROXY" -eq 1 ]; then
                write_sysctl_checked "$proc_root/sys/net/ipv6/conf/all/forwarding" \
                    1 "IPv6 forwarding(runtime)" || {
                    rollback_proxy_start || log Error "Proxy start rollback incomplete"
                    return 1
                }
            fi
        fi
        if ! block_ipv6_output disable; then
            log Error "Failed to remove transition IPv6 guard; rolling back proxy setup"
            rollback_proxy_start || log Error "Proxy start rollback incomplete"
            return 1
        fi
    fi
    if ! block_loopback_traffic enable; then
        log Error "Failed to install loopback guard; rolling back proxy setup"
        rollback_proxy_start || log Error "Proxy start rollback incomplete"
        return 1
    fi
    if [ "$BLOCK_QUIC" -eq 1 ] && ! block_quic enable; then
        log Error "Failed to install QUIC guard; rolling back proxy setup"
        rollback_proxy_start || log Error "Proxy start rollback incomplete"
        return 1
    fi
    if [ "$PROXY_IPV6" -eq -1 ]; then
        if ! manage_ipv6 disable; then
            log Error "Failed to disable IPv6 stack; rolling back proxy setup"
            rollback_proxy_start || log Error "Proxy start rollback incomplete"
            return 1
        fi
        # Block IPv6 at filter level — prevents traffic/WebRTC leaks even when
        # Android carrier re-assigns the IPv6 address on the mobile interface
        if ! block_ipv6_output enable; then
            log Error "Failed to install IPv6 leak guard; rolling back proxy setup"
            rollback_proxy_start || log Error "Proxy start rollback incomplete"
            return 1
        fi
    fi
    if ! commit_runtime_start_journal; then
        rollback_proxy_start || log Error "Proxy start rollback incomplete"
        return 1
    fi
    log Info "Proxy setup completed"
    return 0
}

stop_proxy() {
    local cleanup_rc=0
    local identity_ok=1
    local ipv6_restore_ok=1
    local runtime_snapshot_loaded=0
    local runtime_starting=0
    local keep_ipv6_disabled="${TPROXY_KEEP_IPV6_DISABLED:-0}"
    log Info "Stopping proxy..."
    if load_runtime_config; then
        runtime_snapshot_loaded=1
        log Info "Using runtime config for cleanup"
    else
        RUNTIME_SNAPSHOT_KIND=missing
        FORWARDING_META_KNOWN=0
        if [ "${STOP_FAST_PATH:-0}" -eq 1 ]; then
            log Warn "Runtime cleanup snapshot invalid; loading current tproxy.conf fallback"
            load_config
        fi
        log Warn "Using current config for cleanup (runtime config unavailable)"
    fi
    check_dependencies
    if ! validate_cleanup_config; then
        log Error "Cleanup config is incomplete or invalid; refusing unsafe teardown"
        return 1
    fi
    if [ -e "$CONFIG_DIR/runtime_tproxy.starting" ] || \
       [ -L "$CONFIG_DIR/runtime_tproxy.starting" ]; then
        if ! runtime_start_journal_valid; then
            log Error "Runtime start journal is invalid; refusing teardown"
            return 1
        fi
        runtime_starting=1
    fi
    if [ -e "$CONFIG_DIR/ipv6_backup.conf" ] || [ -L "$CONFIG_DIR/ipv6_backup.conf" ] || \
       { [ "$runtime_snapshot_loaded" -eq 1 ] && [ "$PROXY_IPV6" -eq -1 ] && \
         [ "$runtime_starting" -ne 1 ]; }; then
        if ! validate_ipv6_backup "$CONFIG_DIR/ipv6_backup.conf"; then
            log Error "IPv6 origin backup is missing or invalid; refusing teardown before network mutation"
            return 1
        fi
    fi
    if ! parse_core_identity; then
        log Error "Invalid CORE_USER_GROUP in cleanup config: ${CORE_USER_GROUP:-missing}"
        identity_ok=0
        cleanup_rc=1
    fi
    # Clean up BOTH tables (mangle/tproxy + nat/redirect) regardless of the
    # currently detected USE_TPROXY. detect_proxy_mode can flip USE_TPROXY
    # between start and stop (e.g. transient kernel feature-detection change on
    # an airplane-mode toggle), and the runtime config can be missing. Branching
    # on USE_TPROXY would then clean the wrong table and leave the previous
    # start's jumps in place forever (permanent double-intercept). All cleanup
    # -D/-F/-X are guarded with '2>/dev/null || true', so dual-table cleanup is
    # safe.
    log Info "Cleaning up TPROXY chains"
    cleanup_tproxy_chain4
    cleanup_routing4
    # Remove stale IPv6 chains even when the editable/runtime mode currently
    # says IPv6 is disabled; only policy routes are gated by the saved mode.
    cleanup_tproxy_chain6
    cleanup_routing6
    log Info "Cleaning up REDIRECT chains"
    cleanup_redirect_chain4
    cleanup_redirect_chain6
    log Info "Proxy stopped"
    if [ "$identity_ok" -eq 1 ]; then
        block_loopback_traffic disable
    else
        log Error "Loopback owner rules cannot be removed without a valid core identity"
    fi
    block_quic disable
    cleanup_ipset
    if [ "$keep_ipv6_disabled" -eq 1 ]; then
        log Info "Preserving disabled IPv6 state for immediate reapply"
    elif [ -f "$CONFIG_DIR/ipv6_backup.conf" ]; then
        if ! TPROXY_RETAIN_IPV6_BACKUP=1 manage_ipv6 restore; then
            log Warn "Failed to restore IPv6 settings"
            cleanup_rc=1
            ipv6_restore_ok=0
        fi
    fi
    if [ "$keep_ipv6_disabled" -eq 1 ]; then
        :
    elif [ "$ipv6_restore_ok" -eq 1 ]; then
        block_ipv6_output disable || cleanup_rc=1
    else
        log Warn "Retaining IPv6 output guard until sysctl restore can be retried"
    fi
    restore_forwarding_state || {
        log Warn "Failed to restore forwarding state"
        cleanup_rc=1
    }
    verify_proxy_stopped || cleanup_rc=1
    if [ "$cleanup_rc" -eq 0 ]; then
        commit_runtime_cleanup "$keep_ipv6_disabled" || cleanup_rc=1
    else
        log Error "Proxy cleanup incomplete; preserving runtime_tproxy.conf for retry"
    fi
    return "$cleanup_rc"
}

# Blocks all IPv6 output from non-proxy processes.
# Used when PROXY_IPV6=-1 to prevent IPv6 traffic/WebRTC leaks even when
# the carrier re-assigns an IPv6 address to the mobile interface.
block_ipv6_output() {
    local rc=0
    case "$1" in
        enable)
            # Two-rule pattern: allow root (uid 0 = sing-box), drop all other IPv6 output.
            # Avoids "! -m owner" which fails on Android 11+ ip6tables (legacy backend).
            # Never remove a working guard during repair. Ensure DROP first,
            # then put the root allowance ahead of it if either rule is absent.
            ip6tables -t filter -C OUTPUT -j DROP 2> /dev/null || \
                ip6tables -t filter -A OUTPUT -j DROP || rc=1
            ip6tables -t filter -C OUTPUT -m owner --uid-owner 0 -j ACCEPT 2> /dev/null || \
                ip6tables -t filter -I OUTPUT -m owner --uid-owner 0 -j ACCEPT || rc=1
            if [ "$rc" -eq 0 ]; then
                log Info "IPv6 output blocked (carrier address leak prevention)"
            else
                log Error "IPv6 output guard installation incomplete"
            fi
            ;;
        disable)
            delete_rule_all ip6tables -t filter -D OUTPUT -m owner --uid-owner 0 -j ACCEPT
            delete_rule_all ip6tables -t filter -D OUTPUT -j DROP
            if [ "$DRY_RUN" -eq 0 ] && ! verify_ipv6_output_guard_absent; then
                rc=1
                log Error "IPv6 output block removal incomplete"
            else
                log Info "IPv6 output block removed"
            fi
            ;;
        *) return 2 ;;
    esac
    return "$rc"
}

# This rule blocks local access to tproxy-port to prevent traffic loopback.
block_loopback_traffic() {
    local rc=0
    case "$1" in
        enable)
            block_loopback_traffic disable
            ip6tables -t filter -A OUTPUT -d ::1 -p tcp -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -m tcp --dport "$PROXY_TCP_PORT" -j REJECT || rc=1
            iptables -t filter -A OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -m tcp --dport "$PROXY_TCP_PORT" -j REJECT || rc=1
            ;;
        disable)
            delete_rule_all ip6tables -t filter -D OUTPUT -d ::1 -p tcp -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -m tcp --dport "$PROXY_TCP_PORT" -j REJECT
            delete_rule_all iptables -t filter -D OUTPUT -d 127.0.0.1 -p tcp -m owner --uid-owner "$CORE_USER" --gid-owner "$CORE_GROUP" -m tcp --dport "$PROXY_TCP_PORT" -j REJECT
            ;;
        *) return 2 ;;
    esac
    return "$rc"
}

block_quic() {
    local rc=0
    case "$1" in
        enable)
            block_quic disable
            iptables -N BLOCK_QUIC 2> /dev/null || true
            iptables -F BLOCK_QUIC || rc=1
            if [ "$BYPASS_CN_IP" -eq 1 ]; then
                iptables -A BLOCK_QUIC -p udp --dport 443 -m set ! --match-set cnip dst -j REJECT || rc=1
            else
                iptables -A BLOCK_QUIC -p udp --dport 443 -j REJECT || rc=1
            fi
            iptables -I INPUT -j BLOCK_QUIC || rc=1
            iptables -I FORWARD -j BLOCK_QUIC || rc=1
            iptables -I OUTPUT -j BLOCK_QUIC || rc=1

            if [ "$PROXY_IPV6" -eq 1 ]; then
                ip6tables -N BLOCK_QUIC6 2> /dev/null || true
                ip6tables -F BLOCK_QUIC6 || rc=1
                if [ "$BYPASS_CN_IP" -eq 1 ]; then
                    ip6tables -A BLOCK_QUIC6 -p udp --dport 443 -m set ! --match-set cnip6 dst -j REJECT || rc=1
                else
                    ip6tables -A BLOCK_QUIC6 -p udp --dport 443 -j REJECT || rc=1
                fi
                ip6tables -I INPUT -j BLOCK_QUIC6 || rc=1
                ip6tables -I FORWARD -j BLOCK_QUIC6 || rc=1
                ip6tables -I OUTPUT -j BLOCK_QUIC6 || rc=1
            fi
            if [ "$rc" -eq 0 ]; then
                log Info "QUIC traffic blocked"
            else
                log Error "QUIC traffic guard installation incomplete"
            fi
            ;;
        disable)
            local chain
            for chain in INPUT FORWARD OUTPUT; do
                delete_rule_all iptables -D "$chain" -j BLOCK_QUIC
                delete_rule_all ip6tables -D "$chain" -j BLOCK_QUIC6
            done
            iptables -F BLOCK_QUIC 2> /dev/null || true
            iptables -X BLOCK_QUIC 2> /dev/null || true
            ip6tables -F BLOCK_QUIC6 2> /dev/null || true
            ip6tables -X BLOCK_QUIC6 2> /dev/null || true
            log Info "QUIC traffic blocking disabled"
            ;;
        *) return 2 ;;
    esac
    return "$rc"
}

write_sysctl_checked() {
    local path="$1"
    local value="$2"
    local label="$3"
    local allow_missing="${4:-0}"
    local current

    case "$value" in
        0|1|2) ;;
        *)
            log Error "Invalid saved sysctl value for $label: ${value:-missing}"
            return 1
            ;;
    esac
    if [ ! -f "$path" ]; then
        if [ "$allow_missing" -eq 1 ]; then
            # Dynamic interfaces can disappear between discovery and write.
            return 0
        fi
        log Error "Missing required sysctl $label"
        return 1
    fi
    if ! echo "$value" > "$path" 2> /dev/null; then
        log Error "Failed to write sysctl $label"
        return 1
    fi
    current=$(cat "$path" 2> /dev/null) || {
        log Error "Cannot read back sysctl $label"
        return 1
    }
    if [ "$current" != "$value" ]; then
        log Error "Sysctl $label readback=$current, expected $value"
        return 1
    fi
    return 0
}

validate_ipv6_backup() {
    local backup_file="$1"

    [ -f "$backup_file" ] && [ ! -L "$backup_file" ] || return 1
    command awk -F= '
        /^#/ || NF == 0 { next }
        NF != 2 { bad=1; next }
        {
            key=$1
            value=$2
            if (seen[key]++) bad=1
            if (key == "accept_ra") {
                have_ra=1
                if (value !~ /^(0|1|2)$/) bad=1
            } else if (key == "autoconf") {
                have_autoconf=1
                if (value !~ /^(0|1)$/) bad=1
            } else if (key == "forwarding") {
                have_forwarding=1
                if (value !~ /^(0|1)$/) bad=1
            } else {
                if (key !~ /^[A-Za-z0-9_.:-]+$/ || value !~ /^(0|1)$/) bad=1
                if (key == "default") have_default=1
            }
        }
        END {
            if (!have_ra || !have_autoconf || !have_forwarding || !have_default) bad=1
            exit(bad ? 1 : 0)
        }
    ' "$backup_file"
}

create_ipv6_backup() {
    local backup_file="$1"
    local proc_root="$2"
    local forwarding_override="${3:-}"
    local tmp="${backup_file}.tmp.$$"
    local iface iface_name current

    case "$forwarding_override" in ''|0|1) ;; *) return 1 ;; esac

    (
        umask 077
        {
            echo "# IPv6 settings backup (generated at $(date))"
            echo "accept_ra=$(cat "$proc_root/sys/net/ipv6/conf/all/accept_ra" 2> /dev/null || echo unknown)"
            echo "autoconf=$(cat "$proc_root/sys/net/ipv6/conf/all/autoconf" 2> /dev/null || echo unknown)"
            if [ -n "$forwarding_override" ]; then
                echo "forwarding=$forwarding_override"
            else
                echo "forwarding=$(cat "$proc_root/sys/net/ipv6/conf/all/forwarding" 2> /dev/null || echo unknown)"
            fi

            for iface in "$proc_root"/sys/net/ipv6/conf/*; do
                [ -f "$iface/disable_ipv6" ] || continue
                iface_name=$(basename "$iface")
                current=$(cat "$iface/disable_ipv6" 2> /dev/null || echo unknown)
                echo "$iface_name=$current"
            done
        } > "$tmp"
    ) || {
        rm -f "$tmp" 2> /dev/null
        log Error "Failed to create IPv6 backup"
        return 1
    }
    if ! validate_ipv6_backup "$tmp"; then
        rm -f "$tmp" 2> /dev/null
        log Error "IPv6 backup contains unreadable or invalid sysctl values"
        return 1
    fi
    if [ -e "$backup_file" ]; then
        rm -f "$tmp" 2> /dev/null
        validate_ipv6_backup "$backup_file"
        return $?
    fi
    mv -f "$tmp" "$backup_file" 2> /dev/null || {
        rm -f "$tmp" 2> /dev/null
        log Error "Failed to install IPv6 backup at $backup_file"
        return 1
    }
    return 0
}

manage_ipv6() {
    local action="$1"
    local ipv6_backup_file="$CONFIG_DIR/ipv6_backup.conf"
    local proc_root="${SB_PROC_ROOT:-/proc}"

    case "$action" in
        backup | disable | restore) ;;
        *)
            log Error "Invalid action for manage_ipv6: $action (must be backup, disable, or restore)"
            return 1
            ;;
    esac

    if [ "$DRY_RUN" -eq 1 ]; then
        log Debug "Would $action IPv6 settings"
        return 0
    fi

    if [ "$action" = "backup" ] || [ "$action" = "disable" ]; then
        if [ -f "$ipv6_backup_file" ]; then
            if ! validate_ipv6_backup "$ipv6_backup_file"; then
                log Error "Existing IPv6 backup is invalid; refusing to overwrite it"
                return 1
            fi
            log Debug "Reusing existing IPv6 backup at $ipv6_backup_file"
        else
            log Info "Backing up current IPv6 settings to $ipv6_backup_file"
            create_ipv6_backup "$ipv6_backup_file" "$proc_root" \
                "${TPROXY_IPV6_FORWARDING_ORIGIN:-}" || return 1
        fi
        log Debug "IPv6 backup completed"
    fi

    if [ "$action" = "disable" ]; then
        log Info "Force disabling IPv6 stack (disable_ipv6=1)"

        local disable_rc=0
        write_sysctl_checked \
            "$proc_root/sys/net/ipv6/conf/all/accept_ra" 0 accept_ra || disable_rc=1
        write_sysctl_checked \
            "$proc_root/sys/net/ipv6/conf/all/autoconf" 0 autoconf || disable_rc=1
        write_sysctl_checked \
            "$proc_root/sys/net/ipv6/conf/all/forwarding" 0 forwarding || disable_rc=1

        for iface in "$proc_root"/sys/net/ipv6/conf/*; do
            if [ -f "$iface/disable_ipv6" ]; then
                write_sysctl_checked "$iface/disable_ipv6" 1 \
                    "$(basename "$iface")/disable_ipv6" 1 || disable_rc=1
            fi
        done

        if [ "$disable_rc" -ne 0 ]; then
            log Error "IPv6 stack disable incomplete"
            return 1
        fi

        log Info "IPv6 stack fully disabled"
    fi

    if [ "$action" = "restore" ]; then
        if [ ! -f "$ipv6_backup_file" ]; then
            log Error "No IPv6 backup file found: $ipv6_backup_file"
            return 1
        fi
        if ! validate_ipv6_backup "$ipv6_backup_file"; then
            log Error "IPv6 backup is invalid; refusing partial restore"
            return 1
        fi

        log Info "Restoring IPv6 settings from $ipv6_backup_file"

        local restore_rc=0
        local saved_ifaces=":"
        local default_disable=""

        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            case "$key" in
                \#* | "") continue ;;
            esac

            case "$key" in
                accept_ra)
                    write_sysctl_checked \
                        "$proc_root/sys/net/ipv6/conf/all/accept_ra" "$value" accept_ra || restore_rc=1
                    ;;
                autoconf)
                    write_sysctl_checked \
                        "$proc_root/sys/net/ipv6/conf/all/autoconf" "$value" autoconf || restore_rc=1
                    ;;
                forwarding)
                    write_sysctl_checked \
                        "$proc_root/sys/net/ipv6/conf/all/forwarding" "$value" forwarding || restore_rc=1
                    ;;
                *)
                    saved_ifaces="${saved_ifaces}${key}:"
                    [ "$key" = "default" ] && default_disable=$value
                    if [ -f "$proc_root/sys/net/ipv6/conf/$key/disable_ipv6" ]; then
                        write_sysctl_checked \
                            "$proc_root/sys/net/ipv6/conf/$key/disable_ipv6" "$value" "$key/disable_ipv6" 1 || restore_rc=1
                    fi
                    ;;
            esac
        done < "$ipv6_backup_file"

        # Interfaces created while IPv6 was disabled were not present in the
        # original backup. Restore them to the saved kernel default.
        for iface in "$proc_root"/sys/net/ipv6/conf/*; do
            [ -f "$iface/disable_ipv6" ] || continue
            key=$(basename "$iface")
            case "$saved_ifaces" in *":$key:"*) continue ;; esac
            write_sysctl_checked "$iface/disable_ipv6" "$default_disable" \
                "$key/disable_ipv6(default)" 1 || restore_rc=1
        done

        if [ "$restore_rc" -ne 0 ]; then
            log Error "IPv6 settings restore incomplete; retaining $ipv6_backup_file for retry"
            return 1
        fi
        if [ "${TPROXY_RETAIN_IPV6_BACKUP:-0}" -eq 1 ]; then
            log Info "IPv6 settings restored; backup retained until cleanup commit"
        else
            rm -f "$ipv6_backup_file" 2> /dev/null || {
                log Error "IPv6 settings restored but backup cleanup failed: $ipv6_backup_file"
                return 1
            }
            log Info "IPv6 settings restored"
        fi
    fi

    return 0
}

guard_ipv6() {
    local rc=0
    # Always attempt the packet-level fail-closed guard even if one sysctl is
    # temporarily unwritable; the caller still receives the aggregate failure.
    manage_ipv6 disable || rc=1
    block_ipv6_output enable || rc=1
    return "$rc"
}

is_func() {
    command -v "$1" > /dev/null 2>&1
}

call_func() {
    local func="$1"
    shift
    if is_func "$func"; then
        log Info "Calling user hook: $func"
        "$func" "$@"
    else
        log Debug "No user hook defined: $func"
    fi
}

show_usage() {
    local script_name
    script_name=$(basename "$0")

    cat << EOF
Usage: $script_name {start|stop|restart} [options]

This script sets up / cleans up transparent proxy (TPROXY or REDIRECT) rules
for TCP/UDP traffic redirection, DNS hijacking, per-app proxy, CN IP bypass, etc.

Commands:
  start     Apply proxy rules, routing tables, ipset, sysctl changes
  stop      Remove all added rules, routes, ipset sets, restore sysctl
  restart   Equivalent to stop → short delay → start

Options:
  -v, --version              Show version number and exit

  -d DIR, --dir DIR
      Specify the base configuration directory.
      Default: the directory where this script is located.
      
      Files that may be read from or written to in this directory:
      • tproxy.conf          (optional) user configuration overrides
      • runtime_tproxy.conf  (generated/used during runtime for cleanup)
      • cn.zone              (China IPv4 CIDR list, auto-downloaded if missing/old)
      • cn_ipv6.zone         (China IPv6 CIDR list, auto-downloaded if IPv6 enabled)
      • tmp/                 (temporary subdirectory for mktemp files, downloads, etc.)

      Requirements:
      - The directory must exist and be writable by the script (root usually).
      - If using custom location (e.g. /data/adb/modules/xxx), ensure it has
        read/write/execute permissions for root, and is persistent across reboots
        if you want downloaded lists and runtime config to survive.

  --dry-run
      Simulate all operations without actually modifying:
      • iptables / ip6tables rules
      • ip rules / routes
      • ipset sets
      • sysctl settings (/proc/sys/...)
      • file system writes (downloads, temp files, runtime config)
      Ideal for previewing what changes would be made.

  --verbose
      Increase logging detail:
      • With --dry-run: shows ALL log levels (Info, Warn, Error, Debug, [EXEC])
      • Without --dry-run: shows normal output + Debug-level messages
      • Without this flag: shows only Info, Warn, Error (quiet mode)

  -h, --help
      Show this help message and exit

Examples:
  $script_name start --dry-run
      # Preview changes without applying anything

  $script_name start --dry-run --verbose
      # Very detailed simulation (shows every command that would run)

  $script_name start -d /data/adb/myproxy
      # Use custom config directory

  $script_name restart --verbose
      # Restart with extra debug output

  $script_name stop -d /sdcard/myproxy
      # Stop using a specific config directory

Note:
  • Almost all operations require root privileges.
  • Some features (TPROXY, ipset, owner matching, etc.) depend on kernel support.
EOF
}

parse_args() {
    MAIN_CMD=""
    VERBOSE=0
    while [ $# -gt 0 ]; do
        case "$1" in
            start | stop | restart | guard-ipv6)
                if [ -n "$MAIN_CMD" ]; then
                    log Error "Multiple commands specified."
                    exit 1
                fi
                MAIN_CMD="$1"
                ;;
            --dry-run)
                DRY_RUN=1
                ;;
            --verbose)
                VERBOSE=1
                ;;
            -v | --version)
                echo "$SCRIPT_VERSION"
                exit 0
                ;;
            -d | --dir)
                shift
                if [ $# -eq 0 ] || [ -z "$1" ]; then
                    log Error "Option -d/--dir requires a directory argument"
                    show_usage
                    exit 1
                fi
                if [ ! -d "$1" ]; then
                    log Error "Directory does not exist or is not a directory: $1"
                    show_usage
                    exit 1
                fi
                CONFIG_DIR="$(cd "$1" 2> /dev/null && pwd -P)" || {
                    log Error "Failed to resolve absolute path for directory: $1"
                    exit 1
                }
                ;;
            -h | --help)
                show_usage
                exit 0
                ;;
            *)
                log Error "Invalid argument: $1"
                show_usage
                exit 1
                ;;
        esac
        shift
    done
    if [ -z "$MAIN_CMD" ]; then
        log Error "No command specified"
        show_usage
        exit 1
    fi
}

run_tproxy_locked() {
    local target="$1"
    local lock_dir="$CONFIG_DIR/run"
    local lock_file="$lock_dir/tproxy.lock"

    if [ "$DRY_RUN" -eq 1 ]; then
        "$target"
        return $?
    fi
    mkdir -p "$lock_dir" || {
        log Error "Cannot create tproxy lock directory: $lock_dir"
        return 1
    }
    (
        local waited=0
        while ! "$busybox" flock -n 8; do
            if [ "$waited" -ge 30 ]; then
                log Error "TPROXY owner lock timed out after 30 seconds"
                exit 75
            fi
            sleep 1
            waited=$((waited + 1))
        done
        "$target"
    ) 8>"$lock_file"
}

dispatch_main_command() {
    local rc hook_rc

    case "$MAIN_CMD" in
        start)
            call_func pre_start_hook || return $?
            start_proxy
            ;;
        stop)
            stop_proxy
            rc=$?
            call_func post_stop_hook
            hook_rc=$?
            [ "$rc" -ne 0 ] && return "$rc"
            return "$hook_rc"
            ;;
        restart)
            log Info "Restarting proxy..."
            stop_proxy
            rc=$?
            call_func post_stop_hook
            hook_rc=$?
            [ "$rc" -ne 0 ] && return "$rc"
            [ "$hook_rc" -ne 0 ] && return "$hook_rc"
            sleep 2
            call_func pre_start_hook || return $?
            start_proxy || return $?
            log Info "Proxy restarted"
            ;;
        *)
            log Error "Invalid command: $MAIN_CMD"
            return 2
            ;;
    esac
}

main() {
    local script_name
    local rc hook_rc
    script_name=$(basename "$0")
    log Debug "Starting ${script_name} ${SCRIPT_VERSION}"
    [ -n "$CONFIG_DIR" ] || CONFIG_DIR="$SCRIPT_DIR"

    if [ "$MAIN_CMD" = "guard-ipv6" ]; then
        LOG_TIMESTAMP="${LOG_TIMESTAMP:-$DEFAULT_LOG_TIMESTAMP}"
        check_root
        check_dependencies
        setup_busybox || return 1
        run_tproxy_locked guard_ipv6
        return $?
    fi

    # Stop can use the immutable runtime snapshot without sourcing the
    # editable tproxy.conf first. This keeps a broken current config from
    # blocking teardown of a previously started instance.
    if [ "$MAIN_CMD" = "stop" ] && [ "$DRY_RUN" -eq 0 ] && \
       [ -f "$CONFIG_DIR/runtime_tproxy.conf" ]; then
        LOG_TIMESTAMP="${LOG_TIMESTAMP:-$DEFAULT_LOG_TIMESTAMP}"
        STOP_FAST_PATH=1
        check_root
        setup_busybox || return 1
        run_tproxy_locked stop_proxy
        rc=$?
        # The repository hook is intentionally a no-op; do not source a
        # potentially malformed current config merely to discover it.
        [ "$rc" -eq 0 ] || return "$rc"
        return 0
    fi

    load_config

    if [ "$DRY_RUN" -eq 1 ]; then
        if [ "$VERBOSE" -eq 1 ]; then
            log Info "Dry-run mode + verbose: showing ALL logs"
        else
            log Info "Dry-run mode: only showing commands that would be executed"
        fi
    elif [ "$VERBOSE" -eq 1 ]; then
        log Info "Verbose mode: showing debug information"
    fi

    # Stop must remain available even if the editable current config is invalid
    # or forced TPROXY detection now fails. stop_proxy loads the saved runtime
    # slice and cleans both TPROXY/REDIRECT tables.
    if [ "$MAIN_CMD" != "stop" ] && ! validate_config; then
        log Error "Configuration validation failed"
        exit 1
    fi

    check_root
    check_dependencies
    setup_busybox || return 1

    init_tmpdir
    init_kernel_config_cache
    init_feature_flags

    if [ "$MAIN_CMD" != "stop" ]; then
        detect_proxy_mode
    fi

    run_tproxy_locked dispatch_main_command
}

# Pre-initialize variables for set -u safety
DRY_RUN=0
VERBOSE=0
CONFIG_DIR=""
USE_TPROXY=0
HAS_TPROXY=0
HAS_CONNTRACK=0
HAS_OWNER=0
HAS_MARK_MT=0
HAS_MARK_TG=0
HAS_SOCKET=0
HAS_ADDRTYPE=0
HAS_MAC=0
HAS_IPSET=0
HAS_XT_SET=0
HAS_NAT6=0
HAS_REDIRECT6=0
ORIG_IP_FORWARD=""
ORIG_IP6_FORWARDING=""
RUNTIME_SNAPSHOT_KIND=missing
FORWARDING_META_KNOWN=0
STOP_FAST_PATH=0

parse_args "$@"

main
