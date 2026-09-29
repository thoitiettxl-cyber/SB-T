import { useState, useCallback } from 'react'
import { exec } from '../lib/bridge'

export type LogType = 'runs' | 'singbox' | 'net'

const BOX_RUN = '/data/adb/box/run'

const LOG_PATHS: Record<LogType, string> = {
  runs: `${BOX_RUN}/runs.log`,
  singbox: `${BOX_RUN}/sing-box.log`,
  net: `${BOX_RUN}/net.log`,
}

export function useLogs() {
  const [content, setContent] = useState('')
  const [loading, setLoading] = useState(false)
  const [active, setActive] = useState<LogType>('runs')

  const fetch = useCallback(async (type: LogType = active, lines = 200) => {
    setLoading(true)
    setActive(type)
    const { stdout } = await exec(`tail -n ${lines} ${LOG_PATHS[type]} 2>/dev/null || echo "(empty)"`)
    setContent(stdout.trim())
    setLoading(false)
  }, [active])

  const clear = useCallback(async (type: LogType = active) => {
    await exec(`> ${LOG_PATHS[type]}`)
    setContent('')
  }, [active])

  return { content, loading, active, fetch, clear }
}
