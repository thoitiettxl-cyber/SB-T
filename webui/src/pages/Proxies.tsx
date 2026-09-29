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
    <div className="rounded-[20px] bg-miu-card p-5 text-miu-warn text-sm">
      {error}
    </div>
  )

  if (groups.length === 0) return (
    <div className="text-center text-miu-sub py-16">{t('noProxies')}</div>
  )

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between px-2">
        <h2 className="font-semibold text-[17px] text-miu-text">{t('proxyGroups')}</h2>
        <button onClick={load} className="p-2 rounded-full hover:bg-black/[0.04] dark:hover:bg-white/10 text-miu-faint transition-colors">
          <RefreshCw size={16} />
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
              className="w-full flex items-center gap-3 px-5 py-3.5 text-left hover:bg-black/[0.03] dark:hover:bg-white/5 transition-colors"
            >
              {isOpen
                ? <ChevronDown size={16} className="text-miu-faint shrink-0" />
                : <ChevronRight size={16} className="text-miu-faint shrink-0" />
              }
              <div className="flex-1 min-w-0">
                <div className="font-medium text-[15px] text-miu-text truncate">{group.name}</div>
                <div className="text-[13px] text-miu-sub flex items-center gap-1.5 mt-0.5">
                  <span>{group.type}</span>
                  {group.now && (
                    <>
                      <span>·</span>
                      <span className="text-miu-primary truncate max-w-[120px]">{group.now}</span>
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
                className="flex items-center gap-1 px-3 py-1.5 rounded-full text-[13px] font-medium bg-miu-primary/12 text-miu-primary disabled:opacity-50 transition-colors shrink-0"
              >
                <Zap size={11} />
                {testing === group.name ? t('testing') : t('testDelay')}
              </button>
            </button>

            {/* Proxy list — only rendered when expanded */}
            {isOpen && (
              <div className="border-t border-miu-divider divide-y divide-miu-divider">
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
                        'w-full flex items-center justify-between px-5 py-2.5 text-left transition-colors',
                        group.type === 'Selector' && 'hover:bg-black/[0.03] dark:hover:bg-white/5',
                        isSelected && 'bg-miu-primary/[0.07]',
                      )}
                    >
                      <div className="flex items-center gap-2 min-w-0">
                        {isSelected && <span className="w-1.5 h-1.5 rounded-full bg-miu-primary shrink-0" />}
                        <span className={cn('text-sm truncate', isSelected ? 'font-semibold text-miu-primary' : 'text-miu-text')}>
                          {name}
                        </span>
                        {p && <span className="text-[13px] text-miu-sub shrink-0">{p.type}</span>}
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
