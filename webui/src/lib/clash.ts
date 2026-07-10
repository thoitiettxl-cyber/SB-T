export interface ClashProxy {
  name: string
  type: string
  alive: boolean
  history: Array<{ time: string; delay: number }>
  now?: string
  all?: string[]
  udp?: boolean
}

export interface ClashMemory {
  inuse: number
  oslimit: number
}

export interface ClashTraffic {
  up: number
  down: number
}

export class ClashClient {
  private base: string
  private secret: string

  constructor(port: string, secret = '') {
    this.base = `http://127.0.0.1:${port}`
    this.secret = secret
  }

  private headers(): HeadersInit {
    return this.secret ? { Authorization: `Bearer ${this.secret}` } : {}
  }

  private async get<T>(path: string): Promise<T> {
    const res = await fetch(`${this.base}${path}`, { headers: this.headers() })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return res.json()
  }

  private async put(path: string, body: unknown): Promise<void> {
    const res = await fetch(`${this.base}${path}`, {
      method: 'PUT',
      headers: { ...this.headers(), 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
  }

  proxies(): Promise<{ proxies: Record<string, ClashProxy> }> {
    return this.get('/proxies')
  }

  selectProxy(group: string, proxy: string): Promise<void> {
    return this.put(`/proxies/${encodeURIComponent(group)}`, { name: proxy })
  }

  async testDelay(name: string, url = 'https://www.gstatic.com/generate_204', timeout = 5000): Promise<number> {
    try {
      const d = await this.get<{ delay: number }>(
        `/proxies/${encodeURIComponent(name)}/delay?url=${encodeURIComponent(url)}&timeout=${timeout}`
      )
      return d.delay
    } catch {
      return -1
    }
  }

  memory(): Promise<ClashMemory> {
    return this.get('/memory')
  }

  version(): Promise<{ version: string }> {
    return this.get('/version')
  }

  connections(): Promise<{ downloadTotal: number; uploadTotal: number; connections?: unknown[] }> {
    return this.get('/connections')
  }

  async isAlive(): Promise<boolean> {
    try { await this.version(); return true } catch { return false }
  }
}
