import { useCallback, useEffect, useState } from 'react'
import { boxBridge, isKsuAvailable, notify } from '../lib/bridge'
import type { BoxConfig, BoxStatus } from '../types/box'

export interface BoxController {
  status: BoxStatus | null
  config: BoxConfig | null
  originalConfig: BoxConfig | null
  hasChanges: boolean
  loading: boolean
  saving: boolean
  busy: boolean                                          // true during any service action
  activeAction: 'start' | 'stop' | 'restart' | null    // which action is in-flight
  ksuAvail: boolean
  error: string | null
  refresh: () => Promise<void>
  setConfig: (patch: Partial<BoxConfig>) => void
  saveChanges: () => Promise<void>
  discardChanges: () => void
  serviceAction: (action: 'start' | 'stop' | 'restart') => Promise<void>
}

const NUMERIC_KEYS: (keyof BoxConfig)[] = [
  'PROXY_MODE', 'PERFORMANCE_MODE', 'DNS_HIJACK_ENABLE',
  'PROXY_MOBILE', 'PROXY_WIFI', 'PROXY_HOTSPOT', 'PROXY_USB',
  'PROXY_TCP', 'PROXY_UDP', 'PROXY_IPV6',
  'APP_PROXY_ENABLE', 'BYPASS_CN_IP', 'BLOCK_QUIC', 'FORCE_MARK_BYPASS',
]

// Poll until expectedRunning state is reached.
// start.sh wait_singbox_ready() can take up to 15s, so allow 20s total.
async function pollStatus(expectedRunning: boolean, maxMs = 20_000): Promise<BoxStatus | null> {
  const deadline = Date.now() + maxMs
  while (Date.now() < deadline) {
    await new Promise(r => setTimeout(r, 600))
    try {
      const s = await boxBridge.status()
      if (s.running === expectedRunning) return s
    } catch {}
  }
  // One final attempt after deadline
  try { return await boxBridge.status() } catch { return null }
}

export function useBoxController(): BoxController {
  const [status, setStatus] = useState<BoxStatus | null>(null)
  const [config, setConfigState] = useState<BoxConfig | null>(null)
  const [originalConfig, setOriginalConfig] = useState<BoxConfig | null>(null)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [busy, setBusy] = useState(false)
  const [activeAction, setActiveAction] = useState<'start' | 'stop' | 'restart' | null>(null)
  const [error, setError] = useState<string | null>(null)
  const ksuAvail = isKsuAvailable()

  const refresh = useCallback(async () => {
    if (!ksuAvail) { setLoading(false); return }
    setLoading(true)
    try {
      const [s, c] = await Promise.all([boxBridge.status(), boxBridge.getConfig()])
      setStatus(s)
      setConfigState(c)
      setOriginalConfig(c)
      setError(null)
    } catch (e) {
      setError(String(e))
    } finally {
      setLoading(false)
    }
  }, [ksuAvail])

  useEffect(() => { refresh() }, [refresh])

  const setConfig = useCallback((patch: Partial<BoxConfig>) => {
    setConfigState(prev => (prev ? { ...prev, ...patch } : prev))
  }, [])

  const hasChanges = JSON.stringify(config) !== JSON.stringify(originalConfig)

  const saveChanges = useCallback(async () => {
    if (!config || !originalConfig || !ksuAvail) return
    setSaving(true)
    try {
      const ops: (() => Promise<unknown>)[] = []

      for (const key of NUMERIC_KEYS) {
        if (config[key] !== originalConfig[key]) {
          ops.push(() => boxBridge.toggle(key as string, config[key] as number))
        }
      }

      if (config.APP_PROXY_MODE !== originalConfig.APP_PROXY_MODE) {
        ops.push(() => boxBridge.setConfig('APP_PROXY_MODE', config.APP_PROXY_MODE))
      }

      // App lists: convert newline-separated (WebUI) → space-separated (tproxy.conf)
      for (const key of ['BYPASS_APPS_LIST', 'PROXY_APPS_LIST'] as const) {
        if (config[key] !== originalConfig[key]) {
          const spaceSep = config[key].split('\n').filter(Boolean).join(' ')
          ops.push(() => boxBridge.setConfig(key, spaceSep))
        }
      }

      // Plain string keys saved as-is
      for (const key of ['OTHER_BYPASS_INTERFACES', 'OTHER_PROXY_INTERFACES'] as const) {
        if (config[key] !== originalConfig[key]) {
          ops.push(() => boxBridge.setConfig(key, config[key]))
        }
      }

      for (const op of ops) {
        await op()
      }

      if (status?.running) {
        setBusy(true)
        setActiveAction('restart')
        await boxBridge.service('restart')
        const newStatus = await pollStatus(true)
        if (newStatus) setStatus(newStatus)
        setBusy(false)
        setActiveAction(null)
      }

      setOriginalConfig({ ...config })
      notify('Saved')
    } catch (e) {
      setBusy(false)
      setActiveAction(null)
      notify(`Save failed: ${String(e).slice(0, 100)}`)
      throw e
    } finally {
      setSaving(false)
    }
  }, [config, originalConfig, status, ksuAvail])

  const discardChanges = useCallback(() => {
    if (originalConfig) setConfigState({ ...originalConfig })
  }, [originalConfig])

  const serviceAction = useCallback(async (action: 'start' | 'stop' | 'restart') => {
    if (!ksuAvail || busy) return
    setBusy(true)
    setActiveAction(action)
    try {
      await boxBridge.service(action)
      const expectedRunning = action !== 'stop'
      const newStatus = await pollStatus(expectedRunning)
      if (newStatus) {
        setStatus(newStatus)
      }
      // If pollStatus returned the final attempt result (may still be wrong state),
      // do one extra refresh to be sure
      else {
        try { setStatus(await boxBridge.status()) } catch {}
      }
    } catch (e) {
      notify(`${action} failed: ${String(e).slice(0, 100)}`)
    } finally {
      setBusy(false)
      setActiveAction(null)
    }
  }, [ksuAvail, busy])

  return {
    status, config, originalConfig, hasChanges,
    loading, saving, busy, activeAction, ksuAvail, error,
    refresh, setConfig, saveChanges, discardChanges, serviceAction,
  }
}
