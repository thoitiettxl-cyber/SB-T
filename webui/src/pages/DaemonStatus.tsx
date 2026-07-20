import { useState } from 'react'
import { Activity, RefreshCw } from 'lucide-react'
import { exec, isKsuAvailable } from '../lib/bridge'
import { useI18n } from '../lib/i18n'
import { Card, SectionTitle, Badge, Btn } from '../components/ui'

interface DaemonState {
  inotify: 'alive' | 'dead' | 'unknown'
  singbox: 'alive' | 'dead' | 'unknown'
  lastNetChange: string
}

const BOX_RUN = '/data/adb/box/run'

export default function DaemonStatus() {
  const { t } = useI18n()
  const [state, setState] = useState<DaemonState | null>(null)
  const [loading, setLoading] = useState(false)
  const ksuAvail = isKsuAvailable()

  async function check() {
    if (!ksuAvail) return
    setLoading(true)
    try {
      const [r1, r2, r3] = await Promise.all([
        exec(`pgrep -f 'inotifyd.*net.inotify' >/dev/null 2>&1 && echo alive || echo dead`),
        exec(`P=$(cat '${BOX_RUN}/box.pid' 2>/dev/null); [ -n "$P" ] && kill -0 "$P" 2>/dev/null && echo alive || echo dead`),
        exec(`cat '${BOX_RUN}/net_tproxy.lock' 2>/dev/null || echo never`),
      ])
      setState({
        inotify:       r1.stdout.trim() === 'alive' ? 'alive' : 'dead',
        singbox:       r2.stdout.trim() === 'alive' ? 'alive' : 'dead',
        lastNetChange: r3.stdout.trim() || 'never',
      })
    } catch {
      setState(null)
    } finally {
      setLoading(false)
    }
  }

  function badge(s: 'alive' | 'dead' | 'unknown') {
    if (s === 'alive') return <Badge color="green">{t('daemonAlive')}</Badge>
    if (s === 'dead')  return <Badge color="red">{t('daemonDead')}</Badge>
    return <Badge color="gray">{t('daemonUnknown')}</Badge>
  }

  return (
    <div className="space-y-4">
      <Card>
        <SectionTitle>
          <Activity size={13} className="inline mr-1.5" />
          {t('daemonStatusNav')}
        </SectionTitle>

        {state ? (
          <div className="divide-y divide-slate-100 dark:divide-slate-700">
            <div className="flex items-center justify-between px-4 py-3">
              <span className="text-sm font-medium text-slate-700 dark:text-slate-200">{t('inotifyLabel')}</span>
              {badge(state.inotify)}
            </div>
            <div className="flex items-center justify-between px-4 py-3">
              <span className="text-sm font-medium text-slate-700 dark:text-slate-200">{t('watchdogLabel')}</span>
              {badge(state.singbox)}
            </div>
            <div className="flex items-center justify-between px-4 py-3 pb-4">
              <span className="text-sm font-medium text-slate-700 dark:text-slate-200">{t('lastNetLabel')}</span>
              <span className="text-xs text-slate-400 font-mono max-w-[180px] truncate text-right">{state.lastNetChange}</span>
            </div>
          </div>
        ) : (
          <div className="px-4 pb-4 text-sm text-slate-400">
            {ksuAvail ? t('daemonStatusNavSub') : t('ksuUnavail')}
          </div>
        )}
      </Card>

      <Btn
        variant="secondary"
        onClick={check}
        disabled={!ksuAvail || loading}
        loading={loading}
        className="w-full py-3 flex items-center justify-center gap-2"
      >
        <RefreshCw size={15} className={loading ? 'animate-spin' : ''} />
        {t('daemonCheckBtn')}
      </Btn>
    </div>
  )
}
