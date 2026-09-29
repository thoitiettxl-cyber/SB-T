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
      <div className="flex gap-1 p-1.5 rounded-full bg-miu-card shrink-0">
        {logTabs.map(tab => (
          <button
            key={tab.id}
            onClick={() => fetchLog(tab.id)}
            className={`flex-1 py-2 rounded-full text-[13px] font-semibold transition-colors ${
              active === tab.id
                ? 'bg-miu-primary text-white'
                : 'text-miu-sub'
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
          className="flex items-center gap-1.5 px-3.5 py-2 rounded-full bg-miu-primary/12 text-miu-primary text-[13px] font-semibold disabled:opacity-40 transition-colors"
        >
          <RefreshCw size={13} className={loading ? 'animate-spin' : ''} />
          {t('refresh')}
        </button>
        <button
          onClick={() => clearLog(active)}
          disabled={!ksuAvail}
          className="flex items-center gap-1.5 px-3.5 py-2 rounded-full bg-miu-danger/10 text-miu-danger text-[13px] font-semibold disabled:opacity-40 transition-colors"
        >
          <Trash2 size={13} />
          {t('clear')}
        </button>
      </div>

      {/* Log content */}
      <div className="flex-1 bg-[#1c1c1e] dark:bg-black rounded-[20px] overflow-hidden">
        {loading ? (
          <div className="flex items-center justify-center h-full text-miu-faint text-sm">{t('loading')}</div>
        ) : content ? (
          <pre
            ref={preRef}
            className="p-4 text-xs font-mono text-slate-300 overflow-auto h-full leading-relaxed whitespace-pre-wrap break-all"
          >
            {content}
          </pre>
        ) : (
          <div className="flex items-center justify-center h-full text-miu-faint text-sm">{t('noLogs')}</div>
        )}
      </div>
    </div>
  )
}
