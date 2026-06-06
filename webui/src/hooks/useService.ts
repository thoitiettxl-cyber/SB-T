import { useState, useCallback, useEffect } from 'react'
import { exec } from '../lib/bridge'

export interface ServiceState {
  running: boolean
  pid: string
  sbVersion: string
  moduleVersion: string
  loading: boolean
  actionOutput: string
}

const BOX_DIR = '/data/adb/box'
const MODULE_PROP = '/data/adb/modules/SB_Tproxy/module.prop'

export function useService() {
  const [state, setState] = useState<ServiceState>({
    running: false,
    pid: '',
    sbVersion: '',
    moduleVersion: '',
    loading: true,
    actionOutput: '',
  })

  const refresh = useCallback(async () => {
    setState(s => ({ ...s, loading: true }))

    const statusCmd = [
      `PID=$(cat ${BOX_DIR}/run/box.pid 2>/dev/null)`,
      `if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then echo "running:$PID"; else echo "stopped:"; fi`,
    ].join('; ')

    const [statusRes, verRes, modRes] = await Promise.all([
      exec(statusCmd),
      exec(`${BOX_DIR}/bin/sing-box version 2>/dev/null | head -1`),
      exec(`grep "^version=" ${MODULE_PROP} 2>/dev/null | cut -d= -f2`),
    ])

    const [runState, pid] = (statusRes.stdout.trim() || 'stopped:').split(':')

    setState(s => ({
      ...s,
      running: runState === 'running',
      pid: pid || '',
      sbVersion: verRes.stdout.trim().replace(/^sing-box\s+/i, ''),
      moduleVersion: modRes.stdout.trim() || '1.3.3',
      loading: false,
    }))
  }, [])

  const control = useCallback(
    async (action: 'start' | 'stop' | 'restart') => {
      setState(s => ({ ...s, loading: true, actionOutput: '' }))
      const { stdout, stderr } = await exec(`sh ${BOX_DIR}/scripts/start.sh ${action}`)
      setState(s => ({ ...s, actionOutput: (stdout + stderr).trim() }))
      setTimeout(refresh, 1500)
    },
    [refresh],
  )

  useEffect(() => {
    refresh()
  }, [refresh])

  return { ...state, refresh, control }
}
