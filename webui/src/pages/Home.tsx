import { useEffect, useState } from 'react'
import {
  RefreshCw, Play, Square, RotateCcw,
  LayoutGrid, FileText, SlidersHorizontal,
  Shield, AlertCircle,
  ArrowUp, ArrowDown,
} from 'lucide-react'
import { useI18n } from '../lib/i18n'
import type { BoxController } from '../hooks/useBoxController'
import { ClashClient } from '../lib/clash'
import { exec } from '../lib/bridge'
import { Spinner } from '../components/ui'
import type { SubPage } from '../types/box'

interface Props {
  ctrl: BoxController
  onNavigate: (page: SubPage) => void
}

interface ConnStats {
  count: number
  totalDown: number
  totalUp: number
  dlRate: number
  ulRate: number
}

interface PingResult {
  name: string
  url: string
  ms: number | null
  testing: boolean
}

function fmtSpeed(n: number): string {
  if (n >= 1e9) return (n / 1e9).toFixed(2) + ' GB/s'
  if (n >= 1e6) return (n / 1e6).toFixed(1) + ' MB/s'
  if (n >= 1e3) return (n / 1e3).toFixed(1) + ' KB/s'
  return n.toFixed(1) + ' B/s'
}

function Sparkline({ data, color = '#22c55e' }: { data: number[]; color?: string }) {
  const H = 28, W = 100
  if (data.length < 2) {
    return (
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-7" preserveAspectRatio="none">
        <line x1="0" y1={H - 1} x2={W} y2={H - 1} stroke={color} strokeWidth="1.5" opacity="0.3" />
      </svg>
    )
  }
  const max = Math.max(...data, 1)
  const pts = data
    .map((v, i) => `${(i / (data.length - 1)) * W},${H - 2 - (v / max) * (H - 4)}`)
    .join(' ')
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-7" preserveAspectRatio="none">
      <polyline
        points={pts}
        fill="none"
        stroke={color}
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

const PING_TARGETS = [
  { name: 'Baidu',      url: 'https://www.baidu.com/favicon.ico' },
  { name: 'Cloudflare', url: 'https://1.1.1.1/favicon.ico' },
  { name: 'Google',     url: 'https://www.google.com/favicon.ico' },
]

async function measureMs(url: string): Promise<number | null> {
  const controller = new AbortController()
  const tid = setTimeout(() => controller.abort(), 5000)
  const t0 = performance.now()
  try {
    await fetch(url, { signal: controller.signal, mode: 'no-cors', cache: 'no-store' })
    return Math.round(performance.now() - t0)
  } catch {
    return null
  } finally {
    clearTimeout(tid)
  }
}

export default function Home({ ctrl, onNavigate }: Props) {
  const { t } = useI18n()
  const { status, config, loading, busy, activeAction, ksuAvail, serviceAction, refresh } = ctrl

  const running = status?.running ?? false
  const apiPort  = status?.clash_api_port  ?? '9090'
  const apiSecret = status?.clash_api_secret ?? ''

  // ── Traffic polling ───────────────────────────────────────────────────── //
  const [stats, setStats] = useState<ConnStats | null>(null)
  const [dlHistory, setDlHistory] = useState<number[]>([])

  useEffect(() => {
    if (!running) { setStats(null); setDlHistory([]); return }
    const client = new ClashClient(apiPort, apiSecret)
    let alive = true
    let prevDown = 0, prevUp = 0

    async function poll() {
      try {
        const d = await client.connections()
        if (!alive) return
        const dl = d.downloadTotal ?? 0
        const ul = d.uploadTotal  ?? 0
        const dlRate = Math.max(0, dl - prevDown) / 3
        const ulRate = Math.max(0, ul - prevUp)   / 3
        prevDown = dl; prevUp = ul
        setStats({ count: d.connections?.length ?? 0, totalDown: dl, totalUp: ul, dlRate, ulRate })
        setDlHistory(h => [...h.slice(-19), dlRate])
      } catch {
        if (alive) setStats(null)
      }
    }

    poll()
    const timer = setInterval(poll, 3000)
    return () => { alive = false; clearInterval(timer) }
  }, [running, apiPort, apiSecret])

  // ── Local IP detection ────────────────────────────────────────────────── //
  const [localIp, setLocalIp]   = useState('')
  const [netIface, setNetIface] = useState('')

  useEffect(() => {
    let alive = true
    exec("ip route get 1.1.1.1 2>/dev/null | head -1")
      .then(r => {
        if (!alive) return
        const line = r.stdout.trim()
        const src = line.match(/src\s+([0-9.]+)/)?.[1] ?? ''
        const dev = line.match(/dev\s+(\S+)/)?.[1]   ?? ''
        if (src) setLocalIp(src)
        if (dev) setNetIface(dev)
      })
      .catch(() => {})
    return () => { alive = false }
  }, [])

  // ── Latency test ─────────────────────────────────────────────────────── //
  const [pings, setPings] = useState<PingResult[]>(
    PING_TARGETS.map(p => ({ ...p, ms: null, testing: false })),
  )

  async function testPing(idx: number) {
    setPings(prev => prev.map((p, i) => i === idx ? { ...p, testing: true } : p))
    const ms = await measureMs(PING_TARGETS[idx].url)
    setPings(prev => prev.map((p, i) => i === idx ? { ...p, ms, testing: false } : p))
  }

  function testAll() {
    PING_TARGETS.forEach((_, i) => testPing(i))
  }

  // ── Derived values ────────────────────────────────────────────────────── //
  const modeLabel = (() => {
    if (!config) return '–'
    const labels: Record<number, string> = { 0: 'Auto', 1: 'TProxy', 2: 'Redirect' }
    return labels[config.PROXY_MODE] ?? '–'
  })()

  const ipv6Label = (() => {
    if (!config) return '–'
    const labels: Record<number, string> = { [-1]: 'Off', 0: 'Auto', 1: 'On' }
    return labels[config.PROXY_IPV6] ?? '–'
  })()

  const isUnavail = !ksuAvail
  const statusText = isUnavail
    ? 'Unavailable'
    : busy && activeAction
    ? `${activeAction.charAt(0).toUpperCase() + activeAction.slice(1)}ing…`
    : running ? t('running') : t('stopped')

  const statusSub = isUnavail
    ? t('ksuUnavail')
    : running && status?.pid
    ? `PID ${status.pid}${status.sb_version ? ` · v${status.sb_version}` : ''}`
    : status?.sb_version
    ? `sing-box v${status.sb_version}`
    : ''

  const statusBg = isUnavail || (!running && !busy)
    ? 'bg-rose-50 dark:bg-rose-500/10 border-rose-100 dark:border-rose-500/20'
    : busy
    ? 'bg-amber-50 dark:bg-amber-500/10 border-amber-100 dark:border-amber-500/25'
    : 'bg-emerald-50 dark:bg-emerald-500/10 border-emerald-100 dark:border-emerald-500/20'

  const statusColor = isUnavail || (!running && !busy)
    ? 'text-rose-500'
    : busy
    ? 'text-amber-500'
    : 'text-emerald-500'

  const ringHex = isUnavail || (!running && !busy) ? '#f43f5e' : busy ? '#f59e0b' : '#10b981'

  // Circumference for SVG arc
  const R = 42
  const CIRC = 2 * Math.PI * R
  const arcLen = CIRC * 0.72

  return (
    <div className="space-y-3 pt-1 pb-4">

      {/* ── Page title ───────────────────────────────────────────────────── */}
      <div className="flex items-center justify-between px-0.5 mb-1">
        <div>
          <h1 className="text-3xl font-black tracking-tight text-slate-900 dark:text-white leading-none">
            SB<span className="text-sky-500">·</span>T
          </h1>
          <p className="text-[11px] text-slate-400 mt-0.5">Transparent proxy · sing-box</p>
        </div>
        <button
          onClick={refresh}
          disabled={loading || busy}
          className="p-2 rounded-xl text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 disabled:opacity-40 transition-colors active:scale-95"
          title={t('refresh')}
        >
          <RefreshCw size={17} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {/* ── Hero bento (2-col) ───────────────────────────────────────────── */}
      <div className="grid grid-cols-5 gap-3">

        {/* Status tile — 3/5 */}
        <div
          className={`col-span-3 rounded-3xl border p-4 relative overflow-hidden min-h-[148px] flex flex-col justify-between transition-colors duration-500 ${statusBg}`}
        >
          <div className="relative z-10">
            <div className={`text-[15px] font-bold leading-snug truncate ${statusColor}`}>
              {statusText}
            </div>
            <div className="text-xs text-slate-400 mt-0.5 truncate leading-relaxed">
              {statusSub || ' '}
            </div>
          </div>

          {/* Decorative ring */}
          <div className="absolute -bottom-5 -right-5 pointer-events-none select-none">
            <svg viewBox="0 0 100 100" className="w-28 h-28">
              {/* Background track */}
              <circle
                cx="50" cy="50" r={R}
                fill="none"
                stroke={ringHex}
                strokeWidth="5"
                opacity="0.18"
              />
              {/* Arc */}
              <circle
                cx="50" cy="50" r={R}
                fill="none"
                stroke={ringHex}
                strokeWidth="5"
                strokeDasharray={`${arcLen} ${CIRC - arcLen}`}
                strokeDashoffset={CIRC * 0.25}
                strokeLinecap="round"
                opacity="0.55"
                style={{ transform: 'rotate(-90deg)', transformOrigin: '50% 50%' }}
              />
            </svg>
            {/* Icon over ring */}
            <div
              className={`absolute inset-0 flex items-center justify-center ${statusColor}`}
              style={{ opacity: 0.75 }}
            >
              {busy
                ? <Spinner size={6} />
                : running
                ? <Shield size={26} />
                : <AlertCircle size={26} />
              }
            </div>
          </div>
        </div>

        {/* Info tiles stack — 2/5 */}
        <div className="col-span-2 flex flex-col gap-3">
          <div className="flex-1 rounded-2xl bg-white dark:bg-slate-800/90 border border-slate-100 dark:border-slate-700/60 shadow-[0_1px_3px_rgba(0,0,0,0.07)] p-3 flex flex-col justify-center">
            <div className="text-[11px] text-slate-400 mb-0.5">Mode</div>
            <div className="font-bold text-slate-800 dark:text-slate-200 text-sm truncate">{modeLabel}</div>
          </div>
          <div className="flex-1 rounded-2xl bg-white dark:bg-slate-800/90 border border-slate-100 dark:border-slate-700/60 shadow-[0_1px_3px_rgba(0,0,0,0.07)] p-3 flex flex-col justify-center">
            <div className="text-[11px] text-slate-400 mb-0.5">IPv6</div>
            <div className="font-bold text-slate-800 dark:text-slate-200 text-sm">{ipv6Label}</div>
          </div>
        </div>

      </div>

      {/* ── Action row ───────────────────────────────────────────────────── */}
      {isUnavail && (
        <p className="text-xs text-amber-500 text-center font-medium">{t('ksuUnavail')}</p>
      )}
      <div className="flex gap-2">
        {/* Primary: Start / Stop */}
        <button
          onClick={() => serviceAction(running ? 'stop' : 'start')}
          disabled={loading || !ksuAvail || busy}
          className={`flex-1 flex items-center justify-center gap-2 py-[15px] rounded-2xl font-semibold text-[15px] transition-all active:scale-[0.97] disabled:opacity-40 border
            ${running
              ? 'bg-red-50 dark:bg-red-500/10 text-red-500 border-red-200 dark:border-red-500/25 hover:bg-red-100 dark:hover:bg-red-500/20'
              : 'bg-sky-50 dark:bg-sky-500/10 text-sky-600 dark:text-sky-400 border-sky-200 dark:border-sky-500/25 hover:bg-sky-100 dark:hover:bg-sky-500/20'
            }`}
        >
          {busy && (activeAction === 'start' || activeAction === 'stop')
            ? <Spinner size={5} />
            : running ? <Square size={17} fill="currentColor" /> : <Play size={17} fill="currentColor" />
          }
          <span>{running ? t('stop') : t('start')}</span>
        </button>

        {/* Secondary: Restart */}
        <button
          onClick={() => serviceAction('restart')}
          disabled={loading || !ksuAvail || busy}
          title={t('restart')}
          className="w-[52px] flex items-center justify-center rounded-2xl bg-slate-100 dark:bg-slate-700/60 text-slate-500 dark:text-slate-400 hover:bg-slate-200 dark:hover:bg-slate-700 active:scale-95 disabled:opacity-40 transition-all border border-slate-200 dark:border-slate-700"
        >
          {busy && activeAction === 'restart' ? <Spinner size={4} /> : <RotateCcw size={17} />}
        </button>
      </div>

      {/* ── Quick links (2-col bento) ─────────────────────────────────────── */}
      <div className="grid grid-cols-2 gap-3">
        <a
          href={`http://127.0.0.1:${apiPort}/ui/`}
          target="_blank"
          rel="noopener noreferrer"
          className="rounded-2xl bg-white dark:bg-slate-800/90 border border-slate-100 dark:border-slate-700/60 shadow-[0_1px_3px_rgba(0,0,0,0.07)] p-4 flex items-end justify-between active:opacity-70 transition-opacity"
        >
          <div>
            <div className="font-bold text-slate-900 dark:text-slate-100 text-sm">Panel</div>
            <div className="text-xs text-slate-400 mt-0.5">Web UI</div>
          </div>
          <LayoutGrid size={22} className="text-slate-300 dark:text-slate-600 shrink-0" />
        </a>
        <button
          onClick={() => onNavigate('logs')}
          className="rounded-2xl bg-white dark:bg-slate-800/90 border border-slate-100 dark:border-slate-700/60 shadow-[0_1px_3px_rgba(0,0,0,0.07)] p-4 flex items-end justify-between active:opacity-70 transition-opacity text-left w-full"
        >
          <div>
            <div className="font-bold text-slate-900 dark:text-slate-100 text-sm">Logs</div>
            <div className="text-xs text-slate-400 mt-0.5">Inspect</div>
          </div>
          <FileText size={22} className="text-slate-300 dark:text-slate-600 shrink-0" />
        </button>
      </div>

      {/* ── Connection status row ─────────────────────────────────────────── */}
      <div className="flex items-center gap-2 px-0.5">
        <span className={`text-xs font-bold tracking-wide ${running ? 'text-emerald-500' : 'text-red-400'}`}>
          {running ? 'UP' : 'DOWN'}
        </span>
        <span className={`w-2 h-2 rounded-full shrink-0 ${running ? 'bg-emerald-500' : 'bg-red-500'}`} />
        {running && stats !== null && (
          <span className="text-xs text-slate-400">{stats.count} connections</span>
        )}
        <div className="flex-1" />
        <button
          onClick={testAll}
          className="p-1.5 rounded-lg text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors"
          title="Test connectivity"
        >
          <SlidersHorizontal size={15} />
        </button>
        <button
          onClick={refresh}
          disabled={loading || busy}
          className="p-1.5 rounded-lg text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 disabled:opacity-40 transition-colors"
        >
          <RefreshCw size={15} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {/* ── Connectivity test card ────────────────────────────────────────── */}
      <div className="rounded-2xl bg-white dark:bg-slate-800/90 border border-slate-100 dark:border-slate-700/60 shadow-[0_1px_3px_rgba(0,0,0,0.07)] px-4 py-3.5">
        <div className="grid grid-cols-3 divide-x divide-slate-100 dark:divide-slate-700/60">
          {pings.map((p) => (
            <div key={p.name} className="flex flex-col items-center gap-1.5 px-2">
              <div className="flex items-center gap-1.5">
                <span className={`w-2 h-2 rounded-full shrink-0 transition-colors ${
                  p.testing      ? 'bg-amber-400 animate-pulse' :
                  p.ms === null  ? 'bg-slate-300 dark:bg-slate-600' :
                  p.ms > 500     ? 'bg-red-400' :
                  p.ms > 200     ? 'bg-amber-400' :
                                   'bg-emerald-500'
                }`} />
                <span className="text-xs text-slate-500 dark:text-slate-400 font-medium">{p.name}</span>
              </div>
              <div className="text-sm font-bold text-slate-700 dark:text-slate-200 tabular-nums leading-none">
                {p.testing
                  ? <span className="text-amber-400">…</span>
                  : p.ms === null
                  ? <span className="text-slate-400">—</span>
                  : <>{p.ms}<span className="text-xs font-normal text-slate-400 ml-0.5">ms</span></>
                }
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* ── IP + Net Speed (2-col bento) ──────────────────────────────────── */}
      <div className="grid grid-cols-2 gap-3">

        {/* IP / LAN card */}
        <div className="rounded-2xl bg-sky-50/80 dark:bg-sky-500/10 border border-sky-100 dark:border-sky-500/20 p-3">
          <div className="flex items-center justify-between mb-2">
            <span className="text-[11px] font-semibold text-slate-500 dark:text-slate-400">IP</span>
            <span className="text-[11px] text-slate-400">LAN</span>
          </div>
          <div className="font-bold text-slate-800 dark:text-slate-200 text-sm leading-tight break-all">
            {localIp || (loading ? '…' : '–')}
          </div>
          {netIface && (
            <div className="text-[11px] text-slate-400 mt-1.5">Interface: {netIface}</div>
          )}
        </div>

        {/* Net Speed card */}
        <div className="rounded-2xl bg-white dark:bg-slate-800/90 border border-slate-100 dark:border-slate-700/60 shadow-[0_1px_3px_rgba(0,0,0,0.07)] p-3">
          <div className="text-[11px] font-semibold text-slate-500 dark:text-slate-400 mb-1">Net Speed</div>
          <Sparkline data={dlHistory} color={running ? '#22c55e' : '#94a3b8'} />
          <div className="space-y-0.5 mt-1.5">
            <div className="flex justify-between items-center">
              <div className="flex items-center gap-1 text-[11px] text-slate-400">
                <ArrowUp size={10} className="text-violet-400" />
                Upload
              </div>
              <span className="text-[11px] font-bold text-slate-600 dark:text-slate-300 tabular-nums">
                {stats ? fmtSpeed(stats.ulRate) : '0.0 B/s'}
              </span>
            </div>
            <div className="flex justify-between items-center">
              <div className="flex items-center gap-1 text-[11px] text-slate-400">
                <ArrowDown size={10} className="text-sky-400" />
                Download
              </div>
              <span className="text-[11px] font-bold text-slate-600 dark:text-slate-300 tabular-nums">
                {stats ? fmtSpeed(stats.dlRate) : '0.0 B/s'}
              </span>
            </div>
          </div>
        </div>

      </div>

    </div>
  )
}
