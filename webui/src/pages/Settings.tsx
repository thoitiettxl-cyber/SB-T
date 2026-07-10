import { useState } from 'react'
import {
  Smartphone, Wifi, Share2, Usb, Download, Upload,
  ArrowLeftRight, Globe, ShieldOff, Zap, Network,
  AppWindow, Sun, Languages, HardDrive, Shield,
  SlidersHorizontal, Layers,
} from 'lucide-react'
import { exec, isKsuAvailable } from '../lib/bridge'
import { useI18n } from '../lib/i18n'
import { useTheme } from '../hooks/useTheme'
import type { BoxController } from '../hooks/useBoxController'
import { Card, SectionTitle, SwitchRow, SelectRow } from '../components/ui'

interface Props { ctrl: BoxController }

const BACKUP_DIR = '/sdcard/SB-Tproxy-backup'
const BOX_DIR    = '/data/adb/box'

export default function Settings({ ctrl }: Props) {
  const { t, lang, setLang } = useI18n()
  const { theme, setTheme } = useTheme()
  const { config, setConfig, ksuAvail } = ctrl
  const [backupMsg, setBackupMsg] = useState('')
  const [backupLoading, setBackupLoading] = useState(false)
  const ksu = isKsuAvailable()

  async function exportConfig() {
    setBackupLoading(true)
    setBackupMsg('')
    try {
      const { errno } = await exec(
        `mkdir -p '${BACKUP_DIR}' && cp '${BOX_DIR}/tproxy.conf' '${BACKUP_DIR}/tproxy.conf.bak' && cp '${BOX_DIR}/settings.ini' '${BACKUP_DIR}/settings.ini.bak'`
      )
      setBackupMsg(errno === 0 ? t('exportSuccess') : 'Export failed')
    } catch (e) {
      setBackupMsg(String(e))
    } finally {
      setBackupLoading(false)
    }
  }

  async function importConfig() {
    setBackupLoading(true)
    setBackupMsg('')
    try {
      const check = await exec(`[ -f '${BACKUP_DIR}/tproxy.conf.bak' ] && echo ok || echo miss`)
      if (check.stdout.trim() !== 'ok') {
        setBackupMsg(t('importFail'))
        setBackupLoading(false)
        return
      }
      const { errno } = await exec(
        `cp '${BACKUP_DIR}/tproxy.conf.bak' '${BOX_DIR}/tproxy.conf' && cp '${BACKUP_DIR}/settings.ini.bak' '${BOX_DIR}/settings.ini'`
      )
      if (errno === 0) {
        await ctrl.refresh()
        setBackupMsg(t('importSuccess'))
      } else {
        setBackupMsg(t('importFail'))
      }
    } catch (e) {
      setBackupMsg(String(e))
    } finally {
      setBackupLoading(false)
    }
  }

  if (!config) return null

  return (
    <div className="space-y-4 pb-4">

      {/* ── Proxy Config ────────────────────────────────────────────────── */}
      <Card>
        <SectionTitle>{t('settingsProxySec')}</SectionTitle>
        <SwitchRow
          label={t('mobile')} icon={<Smartphone size={16} />} iconColor="sky"
          checked={config.PROXY_MOBILE === 1}
          onChange={v => setConfig({ PROXY_MOBILE: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
        <SwitchRow
          label={t('wifi')} icon={<Wifi size={16} />} iconColor="teal"
          checked={config.PROXY_WIFI === 1}
          onChange={v => setConfig({ PROXY_WIFI: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
        <SwitchRow
          label={t('hotspot')} icon={<Share2 size={16} />} iconColor="emerald"
          checked={config.PROXY_HOTSPOT === 1}
          onChange={v => setConfig({ PROXY_HOTSPOT: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
        <SwitchRow
          label={t('usb')} icon={<Usb size={16} />} iconColor="indigo"
          checked={config.PROXY_USB === 1}
          onChange={v => setConfig({ PROXY_USB: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
        <SelectRow
          label={t('proxyMode')} icon={<Layers size={16} />} iconColor="violet"
          value={config.PROXY_MODE}
          options={[
            { value: 0, label: t('proxyModeAuto') },
            { value: 1, label: t('proxyModeTproxy') },
            { value: 2, label: t('proxyModeRedirect') },
          ]}
          onChange={v => setConfig({ PROXY_MODE: Number(v) })}
          disabled={!ksuAvail}
        />
        <SelectRow
          label={t('ipv6Mode')} icon={<Globe size={16} />} iconColor="sky"
          value={config.PROXY_IPV6}
          options={[
            { value: -1, label: t('ipv6Disable') },
            { value: 0,  label: t('ipv6Auto') },
            { value: 1,  label: t('ipv6Enable') },
          ]}
          onChange={v => setConfig({ PROXY_IPV6: Number(v) })}
          disabled={!ksuAvail}
        />
        <SwitchRow
          label={t('proxyTcp')} icon={<ArrowLeftRight size={16} />} iconColor="sky"
          checked={config.PROXY_TCP === 1}
          onChange={v => setConfig({ PROXY_TCP: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
        <SwitchRow
          label={t('proxyUdp')} icon={<ArrowLeftRight size={16} />} iconColor="indigo"
          checked={config.PROXY_UDP === 1}
          onChange={v => setConfig({ PROXY_UDP: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
      </Card>

      {/* ── Advanced ────────────────────────────────────────────────────── */}
      <Card>
        <SectionTitle>{t('settingsAdvancedSec')}</SectionTitle>
        <SwitchRow
          label={t('blockQuic')} icon={<ShieldOff size={16} />} iconColor="orange"
          checked={config.BLOCK_QUIC === 1}
          onChange={v => setConfig({ BLOCK_QUIC: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
        <SwitchRow
          label={t('bypassCnIp')} icon={<Globe size={16} />} iconColor="amber"
          checked={config.BYPASS_CN_IP === 1}
          onChange={v => setConfig({ BYPASS_CN_IP: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
        <SwitchRow
          label={t('perfMode')} icon={<Zap size={16} />} iconColor="violet"
          checked={config.PERFORMANCE_MODE === 1}
          onChange={v => setConfig({ PERFORMANCE_MODE: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
        <SwitchRow
          label={t('dnsHijack')} icon={<Network size={16} />} iconColor="teal"
          checked={config.DNS_HIJACK_ENABLE === 1}
          onChange={v => setConfig({ DNS_HIJACK_ENABLE: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
        <SelectRow
          label={t('appProxy')} icon={<AppWindow size={16} />} iconColor="rose"
          value={config.APP_PROXY_ENABLE === 0 ? 'off' : config.APP_PROXY_MODE}
          options={[
            { value: 'off',       label: t('appProxyOff') },
            { value: 'blacklist', label: t('appProxyBlacklist') },
            { value: 'whitelist', label: t('appProxyWhitelist') },
          ]}
          onChange={v => {
            if (v === 'off') setConfig({ APP_PROXY_ENABLE: 0 })
            else setConfig({ APP_PROXY_ENABLE: 1, APP_PROXY_MODE: v as 'blacklist' | 'whitelist' })
          }}
          disabled={!ksuAvail}
        />
        <SwitchRow
          label="Force Mark Bypass" icon={<Shield size={16} />} iconColor="slate"
          checked={config.FORCE_MARK_BYPASS === 1}
          onChange={v => setConfig({ FORCE_MARK_BYPASS: v ? 1 : 0 })}
          disabled={!ksuAvail}
        />
      </Card>

      {/* ── Network Interfaces ──────────────────────────────────────────── */}
      <Card>
        <SectionTitle>
          <SlidersHorizontal size={11} className="shrink-0" />
          {t('settingsNetworkSec')}
        </SectionTitle>
        <div className="px-4 py-3 border-b border-slate-100 dark:border-slate-700">
          <div className="text-sm font-medium text-slate-700 dark:text-slate-200 mb-0.5">{t('bypassInterfaces')}</div>
          <div className="text-xs text-slate-400 mb-2">{t('bypassInterfacesSub')}</div>
          <input
            type="text"
            value={config.OTHER_BYPASS_INTERFACES}
            onChange={e => setConfig({ OTHER_BYPASS_INTERFACES: e.target.value })}
            disabled={!ksuAvail}
            placeholder="eth0 dummy0"
            className="w-full px-3 py-2 rounded-xl text-sm bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-200 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-sky-400 border-0 font-mono disabled:opacity-50"
          />
        </div>
        <div className="px-4 py-3">
          <div className="text-sm font-medium text-slate-700 dark:text-slate-200 mb-0.5">{t('proxyInterfaces')}</div>
          <div className="text-xs text-slate-400 mb-2">{t('proxyInterfacesSub')}</div>
          <input
            type="text"
            value={config.OTHER_PROXY_INTERFACES}
            onChange={e => setConfig({ OTHER_PROXY_INTERFACES: e.target.value })}
            disabled={!ksuAvail}
            placeholder="wlan1 eth1"
            className="w-full px-3 py-2 rounded-xl text-sm bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-200 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-sky-400 border-0 font-mono disabled:opacity-50"
          />
        </div>
      </Card>

      {/* ── Appearance ──────────────────────────────────────────────────── */}
      <Card>
        <SectionTitle>
          <Sun size={11} className="shrink-0" />
          {t('settingsAppearanceSec')}
        </SectionTitle>
        <SelectRow
          label={t('themeLabel')} icon={<Sun size={16} />} iconColor="amber"
          value={theme}
          options={[
            { value: 'light',  label: t('themeLight') },
            { value: 'dark',   label: t('themeDark') },
            { value: 'system', label: t('themeSystem') },
          ]}
          onChange={v => setTheme(v as 'light' | 'dark' | 'system')}
        />
        <SelectRow
          label={t('langLabel')} icon={<Languages size={16} />} iconColor="indigo"
          value={lang}
          options={[
            { value: 'en', label: 'English' },
            { value: 'vi', label: 'Tiếng Việt' },
          ]}
          onChange={v => setLang(v as 'en' | 'vi')}
        />
      </Card>

      {/* ── Backup & Restore ────────────────────────────────────────────── */}
      <Card className="p-4">
        <div className="flex items-center gap-2 mb-3">
          <span className="w-7 h-7 rounded-lg bg-slate-100 dark:bg-slate-700 flex items-center justify-center">
            <HardDrive size={14} className="text-slate-500 dark:text-slate-400" />
          </span>
          <div>
            <div className="text-xs font-semibold uppercase tracking-widest text-slate-400">{t('settingsBackupSec')}</div>
          </div>
        </div>
        <p className="text-xs text-slate-400 mb-3">
          {t('backupPath')}: <span className="font-mono text-slate-500">{BACKUP_DIR}</span>
        </p>
        <div className="grid grid-cols-2 gap-2">
          <button
            onClick={exportConfig}
            disabled={!ksu || backupLoading}
            className="flex items-center justify-center gap-2 py-2.5 rounded-xl bg-sky-500/10 hover:bg-sky-500/20 text-sky-600 dark:text-sky-400 text-sm font-semibold disabled:opacity-40 transition-colors active:scale-[0.97]"
          >
            <Download size={15} />
            {t('exportBtn')}
          </button>
          <button
            onClick={importConfig}
            disabled={!ksu || backupLoading}
            className="flex items-center justify-center gap-2 py-2.5 rounded-xl bg-emerald-500/10 hover:bg-emerald-500/20 text-emerald-600 dark:text-emerald-400 text-sm font-semibold disabled:opacity-40 transition-colors active:scale-[0.97]"
          >
            <Upload size={15} />
            {t('importBtn')}
          </button>
        </div>
        {backupMsg && (
          <p className="mt-2 text-xs text-slate-500 text-center">{backupMsg}</p>
        )}
      </Card>

    </div>
  )
}
