import { exec, toast, listPackages as _listPackages, getPackagesInfo as _getPackagesInfo } from 'kernelsu'
import type { BoxConfig, BoxStatus, PackageInfo } from '../types/box'

const BRIDGE_PATH = '/data/adb/box/scripts/box.webui'

function shellQuote(value: string): string {
  return `'${value.split("'").join("'\\''")}'`
}

function extractJson(out: string): string {
  const idx = out.indexOf('{')
  if (idx === -1) throw new Error(`No JSON in output: ${out.slice(0, 200)}`)
  return out.slice(idx)
}

async function runApi<T>(args: string[]): Promise<T> {
  const command = `${shellQuote(BRIDGE_PATH)} ${args.map(shellQuote).join(' ')}`
  let result: { errno: number; stdout: string; stderr: string }
  try {
    result = await exec(command)
  } catch (e) {
    throw new Error(`KSU exec failed: ${e}`)
  }
  const jsonStr = extractJson(result.stdout || result.stderr || '')
  const payload: { ok: boolean; command: string; data?: T; error?: string } = JSON.parse(jsonStr)
  if (!payload.ok) throw new Error(payload.error || 'Bridge error')
  return payload.data as T
}

export const boxBridge = {
  status:    ()                                                           => runApi<BoxStatus>(['status']),
  getConfig: ()                                                           => runApi<BoxConfig>(['get-config']),
  service:   (action: 'start' | 'stop' | 'restart')                      => runApi<string>(['service', action]),
  toggle:    (key: string, value: number)                                 => runApi<null>(['toggle', key, String(value)]),
  setNumber: (key: string, value: number)                                 => runApi<null>(['set-number', key, String(value)]),
  setConfig: (key: string, value: string)                                 => runApi<null>(['set-config', key, value]),
  checkLog:  (type = 'runs', lines = 80)                                  => runApi<string>(['check-log', type, String(lines)]),
  setApps:   (mode: 'whitelist' | 'blacklist' | 'disable', value = '')    => runApi<null>(['set-apps', mode, value]),
}

export function notify(msg: string): void {
  try { toast(msg) } catch {}
}

export function isKsuAvailable(): boolean {
  try { return typeof (globalThis as Record<string, unknown>)['ksu'] !== 'undefined' } catch { return false }
}

export function listInstalledPackages(type = 'all'): string[] {
  try { return _listPackages(type) } catch { return [] }
}

export function getPackagesInfo(packages: string[]): PackageInfo[] {
  try { return _getPackagesInfo(packages) as PackageInfo[] } catch { return [] }
}

// Re-export raw exec for legacy callers (Logs, Update, Config)
export { exec } from 'kernelsu'

// writeFile via base64 pipeline (used by Config.tsx raw editor)
export async function writeFile(path: string, content: string): Promise<{ ok: boolean; error: string }> {
  const bytes = new TextEncoder().encode(content)
  let binary = ''
  bytes.forEach(b => (binary += String.fromCharCode(b)))
  const b64 = btoa(binary)
  const { errno, stderr } = await exec(`printf '%s' '${b64}' | base64 -d > '${path}'`)
  return { ok: errno === 0, error: stderr }
}
