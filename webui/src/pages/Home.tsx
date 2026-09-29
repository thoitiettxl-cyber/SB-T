import { useEffect, useState } from 'react'
import {
  RefreshCw, Play, Square, RotateCcw,
  LayoutGrid, FileText, ChevronRight,
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

function Sparkline({ data }: { data: number[] }) {
  const H = 28, W = 100
  if (data.length < 2) {
    return (
      <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-7" preserveAspectRatio="none">
        <line x1="0" y1={H - 1} x2={W} y2={H - 1} stroke="var(--miu-faint)" strokeWidth="1.5" opacity="0.5" />
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
        stroke="var(--miu-primary)"
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

  const state = isUnavail || (!running && !busy) ? 'down' : busy ? 'busy' : 'up'

  const statusColor =
    state === 'down' ? 'text-miu-danger' :
    state === 'busy' ? 'text-miu-warn' :
                      'text-miu-healthy'

  const dotBg =
    state === 'down' ? 'bg-miu-danger' :
    state === 'busy' ? 'bg-miu-warn' :
                       'bg-miu-healthy'

  // Circumference for SVG arc
  const R = 42
  const CIRC = 2 * Math.PI * R
  const arcLen = CIRC * 0.72

  const infoCells = [
    { label: 'Mode',   value: modeLabel, sub: undefined as string | undefined },
    { label: 'IPv6',   value: ipv6Label, sub: undefined as string | undefined },
    { label: 'LAN IP', value: localIp || (loading ? '…' : '–'), sub: netIface || undefined },
  ]

  return (
    <div className="space-y-3 pt-1 pb-4">

      {/* ── Page title ───────────────────────────────────────────────────── */}
      <div className="flex items-center justify-between px-2 mb-1">
        <div>
          <h1 className="text-[26px] font-bold tracking-tight text-miu-text leading-none">
            SB<span className="text-miu-primary">·</span>T
          </h1>
          <p className="text-[11px] text-miu-faint mt-1 tracking-wide">TRANSPARENT PROXY · SING-BOX</p>
        </div>
        <button
          onClick={refresh}
          disabled={loading || busy}
          className="p-2 rounded-full text-miu-faint hover:bg-black/[0.04] dark:hover:bg-white/10 disabled:opacity-40 transition-colors active:scale-95"
          title={t('refresh')}
        >
          <RefreshCw size={18} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {/* ── Status hero ──────────────────────────────────────────────────── */}
      <div className="rounded-[20px] bg-miu-card p-5">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="flex items-center gap-2.5">
              <span className="relative flex w-2.5 h-2.5 shrink-0">
                {state === 'up' && (
                  <span className={`absolute inline-flex w-full h-full rounded-full ${dotBg} animate-ping-slow`} />
                )}
                <span className={`relative inline-flex w-2.5 h-2.5 rounded-full ${dotBg}`} />
              </span>
              <span className={`text-[22px] font-bold tracking-tight truncate ${statusColor}`}>
                {statusText}
              </span>
            </div>
            <div className="text-[13px] text-miu-sub mt-1 tabular-nums truncate">
              {statusSub || ' '}
            </div>
          </div>

          {/* status ring */}
          <div className={`relative w-16 h-16 shrink-0 ${statusColor}`}>
            <svg viewBox="0 0 100 100" className="w-16 h-16 -rotate-90">
              <circle cx="50" cy="50" r={R} fill="none" stroke="currentColor" strokeWidth="8" opacity="0.15" />
              <circle
                cx="50" cy="50" r={R}
                fill="none"
                stroke="currentColor"
                strokeWidth="8"
                strokeDasharray={`${arcLen} ${CIRC - arcLen}`}
                strokeDashoffset={CIRC * 0.25}
                strokeLinecap="round"
                opacity="0.9"
              />
            </svg>
            <div className="absolute inset-0 flex items-center justify-center">
              {busy
                ? <Spinner size={5} />
                : running
                ? <Shield size={20} />
                : <AlertCircle size={20} />
              }
            </div>
          </div>
        </div>

        {/* live throughput */}
        <div className="mt-4 pt-4 border-t border-miu-divider">
          <div className="flex items-end justify-between gap-2">
            <div className="min-w-0">
              <div className="text-[11px] font-medium text-miu-faint">Download</div>
              <div className="text-[30px] leading-none font-bold tabular-nums text-miu-text mt-1.5 truncate">
                {running && stats ? fmtSpeed(stats.dlRate) : '—'}
              </div>
            </div>
            <div className="text-right shrink-0">
              <div className="text-[11px] font-medium text-miu-faint">Upload</div>
              <div className="text-sm font-semibold tabular-nums text-miu-sub mt-1.5">
                {running && stats ? fmtSpeed(stats.ulRate) : '—'}
              </div>
            </div>
          </div>
          <div className="mt-2">
            <Sparkline data={dlHistory} />
          </div>
        </div>
      </div>

      {/* ── Info strip ───────────────────────────────────────────────────── */}
      <div className="grid grid-cols-3 rounded-[20px] bg-miu-card divide-x divide-miu-divider">
        {infoCells.map(c => (
          <div key={c.label} className="px-4 py-3 min-w-0">
            <div className="text-[11px] font-medium text-miu-faint">{c.label}</div>
            <div className="text-[15px] font-semibold text-miu-text truncate mt-0.5 tabular-nums">{c.value}</div>
            {c.sub && <div className="text-[11px] text-miu-faint truncate mt-0.5">{c.sub}</div>}
          </div>
        ))}
      </div>

      {/* ── Action row ───────────────────────────────────────────────────── */}
      {isUnavail && (
        <p className="text-[13px] text-miu-warn text-center font-medium">{t('ksuUnavail')}</p>
      )}
      <div className="flex gap-2.5">
        <button
          onClick={() => serviceAction(running ? 'stop' : 'start')}
          disabled={loading || !ksuAvail || busy}
          className={`flex-1 flex items-center justify-center gap-2 py-4 rounded-full font-semibold text-[16px] transition-all active:scale-[0.98] disabled:opacity-40
            ${running
              ? 'bg-miu-danger-bg text-miu-danger'
              : 'bg-miu-primary text-white'
            }`}
        >
          {busy && (activeAction === 'start' || activeAction === 'stop')
            ? <Spinner size={5} />
            : running ? <Square size={17} fill="currentColor" /> : <Play size={17} fill="currentColor" />
          }
          <span>{running ? t('stop') : t('start')}</span>
        </button>

        <button
          onClick={() => serviceAction('restart')}
          disabled={loading || !ksuAvail || busy}
          title={t('restart')}
          className="w-[54px] flex items-center justify-center rounded-full bg-miu-card text-miu-sub active:scale-95 disabled:opacity-40 transition-all"
        >
          {busy && activeAction === 'restart' ? <Spinner size={4} /> : <RotateCcw size={18} />}
        </button>
      </div>

      {/* ── Quick links ──────────────────────────────────────────────────── */}
      <div className="grid grid-cols-2 gap-3">
        <a
          href="http://127.0.0.1:9091/"
          target="_blank"
          rel="noopener noreferrer"
          className="rounded-[20px] bg-miu-card p-4 flex items-center gap-3 active:opacity-70 transition-opacity"
        >
          <span className="w-10 h-10 rounded-[12px] bg-[#3482ff] text-white flex items-center justify-center shrink-0">
            <LayoutGrid size={18} />
          </span>
          <div className="flex-1 min-w-0">
            <div className="font-medium text-miu-text text-[15px]">Panel</div>
            <div className="text-[13px] text-miu-sub mt-0.5">Web UI</div>
          </div>
          <ChevronRight size={16} className="text-miu-faint shrink-0" />
        </a>
        <button
          onClick={() => onNavigate('logs')}
          className="rounded-[20px] bg-miu-card p-4 flex items-center gap-3 active:opacity-70 transition-opacity text-left w-full"
        >
          <span className="w-10 h-10 rounded-[12px] bg-[#4caf50] text-white flex items-center justify-center shrink-0">
            <FileText size={18} />
          </span>
          <div className="flex-1 min-w-0">
            <div className="font-medium text-miu-text text-[15px]">Logs</div>
            <div className="text-[13px] text-miu-sub mt-0.5">Inspect</div>
          </div>
          <ChevronRight size={16} className="text-miu-faint shrink-0" />
        </button>
      </div>

      {/* ── Connection status row ─────────────────────────────────────────── */}
      <div className="flex items-center gap-2 px-2">
        <span className={`text-xs font-bold tracking-[0.12em] ${running ? 'text-miu-healthy' : 'text-miu-danger'}`}>
          {running ? 'UP' : 'DOWN'}
        </span>
        <span className="relative flex w-2 h-2 shrink-0">
          {running && <span className="absolute inline-flex w-full h-full rounded-full bg-miu-healthy animate-ping-slow" />}
          <span className={`relative inline-flex w-2 h-2 rounded-full ${running ? 'bg-miu-healthy' : 'bg-miu-danger'}`} />
        </span>
        {running && stats !== null && (
          <span className="text-[13px] text-miu-sub tabular-nums">{stats.count} connections</span>
        )}
        <div className="flex-1" />
        <button
          onClick={testAll}
          className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-lg text-[13px] font-medium text-miu-faint hover:bg-black/[0.04] dark:hover:bg-white/10 transition-colors"
          title="Test connectivity"
        >
          Test
        </button>
        <button
          onClick={refresh}
          disabled={loading || busy}
          className="p-1.5 rounded-full text-miu-faint hover:bg-black/[0.04] dark:hover:bg-white/10 disabled:opacity-40 transition-colors"
        >
          <RefreshCw size={15} className={loading ? 'animate-spin' : ''} />
        </button>
      </div>

      {/* ── Connectivity test card ────────────────────────────────────────── */}
      <div className="rounded-[20px] bg-miu-card px-5 py-4">
        <div className="grid grid-cols-3 divide-x divide-miu-divider">
          {pings.map((p, i) => (
            <button key={p.name} onClick={() => testPing(i)} className="flex flex-col items-center gap-1.5 px-2 active:opacity-70 transition-opacity">
              <div className="flex items-center gap-1.5">
                <span className={`w-2 h-2 rounded-full shrink-0 transition-colors ${
                  p.testing      ? 'bg-miu-warn animate-pulse' :
                  p.ms === null  ? 'bg-miu-track' :
                  p.ms > 500     ? 'bg-miu-danger' :
                  p.ms > 200     ? 'bg-miu-warn' :
                                   'bg-miu-healthy'
                }`} />
                <span className="text-[13px] text-miu-sub font-medium">{p.name}</span>
              </div>
              <div className="text-[15px] font-bold text-miu-text tabular-nums leading-none">
                {p.testing
                  ? <span className="text-miu-warn">…</span>
                  : p.ms === null
                  ? <span className="text-miu-faint">—</span>
                  : <>{p.ms}<span className="text-xs font-medium text-miu-faint ml-0.5">ms</span></>
                }
              </div>
            </button>
          ))}
        </div>
      </div>

      {/* ── Traffic totals ───────────────────────────────────────────────── */}
      <div className="flex items-center justify-between px-2 text-[13px] text-miu-sub">
        <span className="flex items-center gap-1.5 tabular-nums">
          <ArrowUp size={12} className="text-[#af52de]" />
          {stats ? fmtSpeed(stats.totalUp).replace('/s', '') : '—'} up
        </span>
        <span className="flex items-center gap-1.5 tabular-nums">
          <ArrowDown size={12} className="text-miu-healthy" />
          {stats ? fmtSpeed(stats.totalDown).replace('/s', '') : '—'} down
        </span>
      </div>

    </div>
  )
}
