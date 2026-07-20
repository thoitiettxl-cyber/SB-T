import { useEffect, useRef, useState } from 'react'
import { RefreshCw, Trash2 } from 'lucide-react'
import { exec } from 'kernelsu'
import { isKsuAvailable } from '../lib/bridge'
import { useI18n } from '../lib/i18n'

type LogType = 'runs' | 'singbox' | 'net'

const LOG_PATHS: Record<LogType, string> = {
  runs:    '/data/adb/box/run/runs.log',
  singbox: '/data/adb/box/run/sing-box.log',
  net:     '/data/adb/box/run/net.log',
}

const LOG_LINES = 300

export default function Logs() {
  const { t } = useI18n()
  const [active, setActive] = useState<LogType>('runs')
  const [content, setContent] = useState('')
  const [loading, setLoading] = useState(false)
  const preRef = useRef<HTMLPreElement>(null)
  const ksuAvail = isKsuAvailable()

  async function fetchLog(type: LogType) {
    setActive(type)
    setLoading(true)
    try {
      const path = LOG_PATHS[type]
      const { stdout } = await exec(`tail -n ${LOG_LINES} '${path}' 2>/dev/null || true`)
      setContent(stdout.trim())
    } catch {
      setContent('')
    } finally {
      setLoading(false)
    }
  }

  async function clearLog(type: LogType) {
    if (!ksuAvail) return
    try { await exec(`> '${LOG_PATHS[type]}'`) } catch {}
    setContent('')
  }

  useEffect(() => { fetchLog('runs') }, []) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (preRef.current) preRef.current.scrollTop = preRef.current.scrollHeight
  }, [content])

  const logTabs: Array<{ id: LogType; label: string }> = [
    { id: 'runs',    label: t('logModule') },
    { id: 'singbox', label: t('logSingbox') },
    { id: 'net',     label: t('logNet') },
  ]

  return (
    <div className="flex flex-col gap-3" style={{ height: 'calc(100vh - 8rem)' }}>
      {/* Tab selector */}
      <div className="flex gap-1.5 bg-slate-100 dark:bg-slate-800 p-1 rounded-xl shrink-0">
        {logTabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => fetchLog(tab.id)}
            className={`flex-1 py-1.5 rounded-lg text-xs font-semibold transition-colors ${
              active === tab.id
                ? 'bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 shadow-sm'
                : 'text-slate-500 hover:text-slate-700 dark:hover:text-slate-300'
            }`}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Actions */}
      <div className="flex gap-2 shrink-0">
        <button
          onClick={() => fetchLog(active)}
          disabled={loading}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-sky-500/10 hover:bg-sky-500/20 text-sky-600 dark:text-sky-400 text-xs font-semibold disabled:opacity-40 transition-colors"
        >
          <RefreshCw size={13} className={loading ? 'animate-spin' : ''} />
          {t('refresh')}
        </button>
        <button
          onClick={() => clearLog(active)}
          disabled={!ksuAvail}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-lg bg-red-500/10 hover:bg-red-500/20 text-red-600 dark:text-red-400 text-xs font-semibold disabled:opacity-40 transition-colors"
        >
          <Trash2 size={13} />
          {t('clear')}
        </button>
      </div>

      {/* Log content */}
      <div className="flex-1 bg-slate-900 rounded-2xl border border-slate-700 overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center h-full text-slate-500 text-sm">{t('loading')}</div>
        ) : content ? (
          <pre
            ref={preRef}
            className="p-3 text-xs font-mono text-slate-300 overflow-auto h-full leading-relaxed whitespace-pre-wrap break-all"
          >
            {content}
          </pre>
        ) : (
          <div className="flex items-center justify-center h-full text-slate-500 text-sm">{t('noLogs')}</div>
        )}
      </div>
    </div>
  )
}
