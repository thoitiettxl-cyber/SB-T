import { useEffect, useMemo, useState } from 'react'
import { Search } from 'lucide-react'
import { useI18n } from '../lib/i18n'
import { listInstalledPackages, getPackagesInfo, notify } from '../lib/bridge'
import { boxBridge } from '../lib/bridge'
import type { BoxController } from '../hooks/useBoxController'
import type { PackageInfo } from '../types/box'
import { Card, SectionTitle, Btn, Spinner } from '../components/ui'
import { cn } from '../lib/cn'

interface Props { ctrl: BoxController }

type AppMode = 'off' | 'blacklist' | 'whitelist'

export default function Apps({ ctrl }: Props) {
  const { t } = useI18n()
  const { config, status, ksuAvail } = ctrl

  const [apps, setApps] = useState<PackageInfo[]>([])
  const [appsLoading, setAppsLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [showSystem, setShowSystem] = useState(false)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  // Local mode + checked set (independent of main ctrl config)
  const [mode, setMode] = useState<AppMode>(() => {
    if (!config) return 'off'
    if (config.APP_PROXY_ENABLE === 0) return 'off'
    return config.APP_PROXY_MODE === 'whitelist' ? 'whitelist' : 'blacklist'
  })
  const [checkedPkgs, setCheckedPkgs] = useState<Set<string>>(() => {
    if (!config) return new Set()
    const listKey = config.APP_PROXY_MODE === 'whitelist' ? 'PROXY_APPS_LIST' : 'BYPASS_APPS_LIST'
    return new Set(String(config[listKey] || '').split('\n').map(s => s.trim()).filter(Boolean))
  })

  // Sync from ctrl when config loads
  useEffect(() => {
    if (!config) return
    const m: AppMode = config.APP_PROXY_ENABLE === 0 ? 'off' : (config.APP_PROXY_MODE === 'whitelist' ? 'whitelist' : 'blacklist')
    setMode(m)
    const listKey = config.APP_PROXY_MODE === 'whitelist' ? 'PROXY_APPS_LIST' : 'BYPASS_APPS_LIST'
    setCheckedPkgs(new Set(String(config[listKey] || '').split('\n').map(s => s.trim()).filter(Boolean)))
  }, [config?.APP_PROXY_ENABLE, config?.APP_PROXY_MODE])

  useEffect(() => {
    if (!ksuAvail) { setAppsLoading(false); return }
    setAppsLoading(true)
    try {
      const pkgs = listInstalledPackages('all')
      if (pkgs.length > 0) {
        const infos = getPackagesInfo(pkgs)
        setApps(infos.sort((a, b) => a.appLabel.localeCompare(b.appLabel)))
      }
    } catch {}
    setAppsLoading(false)
  }, [ksuAvail])

  const filtered = useMemo(() => {
    return apps.filter(a => {
      if (!showSystem && a.isSystem) return false
      if (search) {
        const q = search.toLowerCase()
        return a.appLabel.toLowerCase().includes(q) || a.packageName.toLowerCase().includes(q)
      }
      return true
    })
  }, [apps, search, showSystem])

  function togglePkg(pkg: string) {
    setCheckedPkgs(prev => {
      const next = new Set(prev)
      next.has(pkg) ? next.delete(pkg) : next.add(pkg)
      return next
    })
    setSaved(false)
  }

  async function saveApps() {
    if (!ksuAvail) return
    setSaving(true)
    try {
      const list = Array.from(checkedPkgs).join('\n')
      if (mode === 'off') {
        await boxBridge.setApps('disable')
      } else {
        await boxBridge.setApps(mode, list)
      }
      if (status?.running) {
        await boxBridge.service('restart')
      }
      notify(t('appsSaved'))
      setSaved(true)
    } catch (e) {
      notify(`Failed: ${e}`)
    } finally {
      setSaving(false)
    }
  }

  function onModeChange(m: AppMode) {
    setMode(m)
    setSaved(false)
    // When switching mode, swap the checked set to the appropriate list
    if (!config) return
    if (m === 'whitelist') {
      setCheckedPkgs(new Set(String(config.PROXY_APPS_LIST || '').split('\n').filter(Boolean)))
    } else if (m === 'blacklist') {
      setCheckedPkgs(new Set(String(config.BYPASS_APPS_LIST || '').split('\n').filter(Boolean)))
    } else {
      setCheckedPkgs(new Set())
    }
  }

  return (
    <div className="space-y-4">
      <h2 className="font-bold text-base">{t('appsTitle')}</h2>

      {/* Mode selector */}
      <Card className="p-4">
        <div className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">{t('appsMode')}</div>
        <div className="grid grid-cols-3 gap-2">
          {(['off', 'blacklist', 'whitelist'] as AppMode[]).map(m => (
            <button
              key={m}
              onClick={() => onModeChange(m)}
              disabled={!ksuAvail}
              className={cn(
                'py-2.5 rounded-xl text-xs font-semibold transition-colors',
                mode === m
                  ? 'bg-blue-500 text-white'
                  : 'bg-slate-100 dark:bg-slate-700 text-slate-600 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-600',
                !ksuAvail && 'opacity-50 cursor-not-allowed',
              )}
            >
              {m === 'off' ? t('appsOff') : m === 'blacklist' ? t('appsBlacklist') : t('appsWhitelist')}
            </button>
          ))}
        </div>
        {mode !== 'off' && (
          <p className="mt-2 text-xs text-slate-400">
            {mode === 'blacklist' ? t('appsBlacklistHint') : t('appsWhitelistHint')}
          </p>
        )}
      </Card>

      {mode !== 'off' && (
        <>
          {/* Search + filter */}
          <Card className="p-3">
            <div className="flex gap-2 items-center">
              <div className="relative flex-1">
                <Search size={14} className="absolute left-2.5 top-1/2 -translate-y-1/2 text-slate-400" />
                <input
                  type="text"
                  value={search}
                  onChange={e => setSearch(e.target.value)}
                  placeholder={t('appsSearch')}
                  className="w-full pl-8 pr-3 py-2 rounded-xl text-sm bg-slate-100 dark:bg-slate-700 text-slate-700 dark:text-slate-200 placeholder-slate-400 focus:outline-none focus:ring-2 focus:ring-blue-400 border-0"
                />
              </div>
              <button
                onClick={() => setShowSystem(s => !s)}
                className={cn(
                  'px-3 py-2 rounded-xl text-xs font-medium transition-colors',
                  showSystem ? 'bg-blue-100 text-blue-600 dark:bg-blue-900/40 dark:text-blue-400' : 'bg-slate-100 dark:bg-slate-700 text-slate-500',
                )}
              >
                {t('systemApps')}
              </button>
            </div>
          </Card>

          {/* App list */}
          <Card>
            {appsLoading ? (
              <div className="flex justify-center py-8"><Spinner /></div>
            ) : filtered.length === 0 ? (
              <div className="text-center text-slate-400 py-8 text-sm">{t('appsLoading')}</div>
            ) : (
              <>
                <SectionTitle>
                  {filtered.length} apps · {checkedPkgs.size} selected
                </SectionTitle>
                <div className="divide-y divide-slate-100 dark:divide-slate-700 max-h-96 overflow-y-auto">
                  {filtered.map(app => {
                    const checked = checkedPkgs.has(app.packageName)
                    return (
                      <button
                        key={app.packageName}
                        onClick={() => togglePkg(app.packageName)}
                        className="w-full flex items-center gap-3 px-4 py-3 hover:bg-slate-50 dark:hover:bg-slate-700/50 transition-colors"
                      >
                        <img
                          src={`ksu://icon/${app.packageName}`}
                          alt=""
                          className="w-8 h-8 rounded-lg shrink-0 bg-slate-100 dark:bg-slate-700"
                          onError={e => { (e.target as HTMLImageElement).style.display = 'none' }}
                        />
                        <div className="flex-1 min-w-0 text-left">
                          <div className="text-sm font-medium text-slate-700 dark:text-slate-200 truncate">{app.appLabel}</div>
                          <div className="text-xs text-slate-400 truncate">{app.packageName}</div>
                        </div>
                        <div className={cn(
                          'w-5 h-5 rounded-full border-2 shrink-0 flex items-center justify-center transition-colors',
                          checked ? 'bg-blue-500 border-blue-500' : 'border-slate-300 dark:border-slate-600',
                        )}>
                          {checked && <span className="text-white text-xs font-bold">✓</span>}
                        </div>
                      </button>
                    )
                  })}
                </div>
              </>
            )}
          </Card>
        </>
      )}

      {/* Save button */}
      <div className="pb-2">
        <Btn
          variant="primary"
          onClick={saveApps}
          disabled={!ksuAvail}
          loading={saving}
          className="w-full py-3"
        >
          {saving ? t('saving') : saved ? t('appsSaved') : t('appsSave')}
        </Btn>
      </div>
    </div>
  )
}
