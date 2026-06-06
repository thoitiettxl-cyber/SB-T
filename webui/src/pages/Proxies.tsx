import { useEffect, useState, useCallback } from 'react'
import { RefreshCw, Zap, ChevronDown, ChevronRight } from 'lucide-react'
import { ClashClient, type ClashProxy } from '../lib/clash'
import { useI18n } from '../lib/i18n'
import { Card, Badge, Spinner } from '../components/ui'
import { cn } from '../lib/cn'

interface Props {
  apiPort?: string
  apiSecret?: string
}

type GroupedProxy = ClashProxy & { type: string; now: string; all: string[] }
type DelayMap = Record<string, number>

function latencyColor(ms: number): 'green' | 'yellow' | 'red' | 'gray' {
  if (ms <= 0) return 'gray'
  if (ms < 300) return 'green'
  if (ms < 800) return 'yellow'
  return 'red'
}

export default function Proxies({ apiPort = '9090', apiSecret = '' }: Props) {
  const { t } = useI18n()
  const [groups, setGroups] = useState<GroupedProxy[]>([])
  const [all, setAll] = useState<Record<string, ClashProxy>>({})
  const [delays, setDelays] = useState<DelayMap>({})
  const [loading, setLoading] = useState(true)
  const [testing, setTesting] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())  // all collapsed by default

  const client = new ClashClient(apiPort, apiSecret)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const alive = await client.isAlive()
      if (!alive) { setError(t('apiUnavail')); setLoading(false); return }
      const { proxies } = await client.proxies()
      setAll(proxies)
      const gs = Object.values(proxies).filter(
        p => (p.type === 'Selector' || p.type === 'URLTest' || p.type === 'Fallback') && Array.isArray(p.all)
      ) as GroupedProxy[]
      setGroups(gs)
      // Seed delays from history
      const dm: DelayMap = {}
      for (const [name, p] of Object.entries(proxies)) {
        const h = p.history
        if (h && h.length > 0) dm[name] = h[h.length - 1].delay
      }
      setDelays(dm)
    } catch (e) {
      setError(String(e))
    } finally {
      setLoading(false)
    }
  }, [apiPort, apiSecret])

  useEffect(() => { load() }, [load])

  function toggleExpand(name: string) {
    setExpanded(prev => {
      const next = new Set(prev)
      if (next.has(name)) next.delete(name)
      else next.add(name)
      return next
    })
  }

  async function selectProxy(group: string, proxy: string) {
    try {
      await client.selectProxy(group, proxy)
      setGroups(gs => gs.map(g => g.name === group ? { ...g, now: proxy } : g))
    } catch {}
  }

  async function testGroup(group: GroupedProxy, e: React.MouseEvent) {
    e.stopPropagation()  // don't toggle expand when clicking test button
    setTesting(group.name)
    // Auto-expand so user can see results
    setExpanded(prev => new Set(prev).add(group.name))
    const entries = group.all.filter(n => all[n]?.type !== 'Selector')
    const results = await Promise.all(
      entries.map(async name => ({ name, delay: await client.testDelay(name) }))
    )
    const dm: DelayMap = {}
    results.forEach(({ name, delay }) => { dm[name] = delay })
    setDelays(prev => ({ ...prev, ...dm }))
    setTesting(null)
  }

  if (loading) return <div className="flex justify-center pt-16"><Spinner size={8} /></div>

  if (error) return (
    <div className="rounded-2xl bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 p-4 text-amber-600 dark:text-amber-400 text-sm">
      {error}
    </div>
  )

  if (groups.length === 0) return (
    <div className="text-center text-slate-400 py-16">{t('noProxies')}</div>
  )

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <h2 className="font-bold text-base">{t('proxyGroups')}</h2>
        <button onClick={load} className="p-1.5 rounded-lg hover:bg-slate-200 dark:hover:bg-slate-700 text-slate-400 transition-colors">
          <RefreshCw size={15} />
        </button>
      </div>

      {groups.map(group => {
        const isOpen = expanded.has(group.name)
        const nowDelay = group.now ? delays[group.now] : undefined
        return (
          <Card key={group.name} className="overflow-hidden">
            {/* Group header — click to expand/collapse */}
            <button
              onClick={() => toggleExpand(group.name)}
              className="w-full flex items-center gap-3 px-4 py-3.5 text-left hover:bg-slate-50 dark:hover:bg-slate-700/40 transition-colors"
            >
              {isOpen
                ? <ChevronDown size={15} className="text-slate-400 shrink-0" />
                : <ChevronRight size={15} className="text-slate-400 shrink-0" />
              }
              <div className="flex-1 min-w-0">
                <div className="font-semibold text-sm truncate">{group.name}</div>
                <div className="text-xs text-slate-400 flex items-center gap-1.5 mt-0.5">
                  <span>{group.type}</span>
                  {group.now && (
                    <>
                      <span>·</span>
                      <span className="text-blue-500 truncate max-w-[120px]">{group.now}</span>
                      {nowDelay !== undefined && nowDelay > 0 && (
                        <Badge color={latencyColor(nowDelay)} className="ml-0.5">{nowDelay}ms</Badge>
                      )}
                    </>
                  )}
                </div>
              </div>
              <button
                onClick={(e) => testGroup(group, e)}
                disabled={testing === group.name}
                className="flex items-center gap-1 px-2.5 py-1 rounded-lg text-xs font-medium bg-blue-500/10 text-blue-600 dark:text-blue-400 hover:bg-blue-500/20 disabled:opacity-50 transition-colors shrink-0"
              >
                <Zap size={11} />
                {testing === group.name ? t('testing') : t('testDelay')}
              </button>
            </button>

            {/* Proxy list — only rendered when expanded */}
            {isOpen && (
              <div className="border-t border-slate-100 dark:border-slate-700 divide-y divide-slate-100 dark:divide-slate-700">
                {group.all.map(name => {
                  const p = all[name]
                  const delay = delays[name]
                  const isSelected = group.now === name
                  return (
                    <button
                      key={name}
                      onClick={() => group.type === 'Selector' && selectProxy(group.name, name)}
                      disabled={group.type !== 'Selector'}
                      className={cn(
                        'w-full flex items-center justify-between px-4 py-2.5 text-left transition-colors',
                        group.type === 'Selector' && 'hover:bg-slate-50 dark:hover:bg-slate-700/50 active:bg-slate-100 dark:active:bg-slate-700',
                        isSelected && 'bg-blue-50 dark:bg-blue-900/20',
                      )}
                    >
                      <div className="flex items-center gap-2 min-w-0">
                        {isSelected && <span className="w-1.5 h-1.5 rounded-full bg-blue-500 shrink-0" />}
                        <span className={cn('text-sm truncate', isSelected ? 'font-semibold text-blue-600 dark:text-blue-400' : 'text-slate-700 dark:text-slate-200')}>
                          {name}
                        </span>
                        {p && <span className="text-xs text-slate-400 shrink-0">{p.type}</span>}
                      </div>
                      {delay !== undefined && delay > 0 && (
                        <Badge color={latencyColor(delay)}>{delay}ms</Badge>
                      )}
                      {delay !== undefined && delay <= 0 && (
                        <Badge color="red">{t('timeout')}</Badge>
                      )}
                    </button>
                  )
                })}
              </div>
            )}
          </Card>
        )
      })}
    </div>
  )
}
