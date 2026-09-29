import { useState, useCallback } from 'react'
import { Save, AlertTriangle, FileText } from 'lucide-react'
import { exec, writeFile, isKsuAvailable } from '../lib/bridge'
import { useI18n } from '../lib/i18n'

type ConfigFile = 'config.json' | 'tproxy.conf'

const BOX_DIR = '/data/adb/box'
const FILE_PATHS: Record<ConfigFile, string> = {
  'config.json': `${BOX_DIR}/sing-box/config.json`,
  'tproxy.conf': `${BOX_DIR}/tproxy.conf`,
}

type SaveState = 'idle' | 'saving' | 'saved' | 'error'

export default function Config() {
  const { t } = useI18n()
  const [activeFile, setActiveFile] = useState<ConfigFile>('config.json')
  const [content, setContent] = useState('')
  const [loaded, setLoaded] = useState(false)
  const [loading, setLoading] = useState(false)
  const [saveState, setSaveState] = useState<SaveState>('idle')
  const [saveError, setSaveError] = useState('')
  const ksuAvail = isKsuAvailable()

  const loadFile = useCallback(async (file: ConfigFile) => {
    setLoading(true)
    setLoaded(false)
    setActiveFile(file)
    setSaveState('idle')
    const { stdout } = await exec(`cat '${FILE_PATHS[file]}' 2>/dev/null || echo ""`)
    setContent(stdout)
    setLoaded(true)
    setLoading(false)
  }, [])

  const save = async () => {
    setSaveState('saving')
    setSaveError('')
    const { ok, error } = await writeFile(FILE_PATHS[activeFile], content)
    if (ok) {
      setSaveState('saved')
      setTimeout(() => setSaveState('idle'), 2000)
    } else {
      setSaveState('error')
      setSaveError(error)
    }
  }

  const CONFIG_FILES: ConfigFile[] = ['config.json', 'tproxy.conf']

  return (
    <div className="flex flex-col gap-3">
      {/* File selector */}
      <div className="flex gap-1 p-1.5 rounded-full bg-miu-card">
        {CONFIG_FILES.map(f => (
          <button
            key={f}
            onClick={() => loadFile(f)}
            className={`flex-1 flex items-center justify-center gap-1.5 py-2 rounded-full text-[13px] font-semibold transition-colors ${
              activeFile === f
                ? 'bg-miu-primary text-white'
                : 'text-miu-sub'
            }`}
          >
            <FileText size={13} />
            {f}
          </button>
        ))}
      </div>

      {/* Warning */}
      {activeFile === 'config.json' && (
        <div className="flex gap-2.5 items-start p-4 bg-miu-card rounded-[20px]">
          <AlertTriangle size={15} className="text-miu-warn flex-shrink-0 mt-0.5" />
          <p className="text-[13px] text-miu-sub">Editing config.json directly may break your proxy. Restart after saving.</p>
        </div>
      )}

      {/* Load button (if not loaded) */}
      {!loaded && !loading && (
        <button
          onClick={() => loadFile(activeFile)}
          disabled={!ksuAvail}
          className="w-full py-3.5 rounded-full bg-miu-primary/12 text-miu-primary text-sm font-semibold disabled:opacity-40 transition-colors"
        >
          {t('loading').replace('...', '')} {activeFile}
        </button>
      )}

      {loading && (
        <div className="flex items-center justify-center py-8 text-miu-sub text-sm">{t('loading')}</div>
      )}

      {/* Editor */}
      {loaded && (
        <>
          <textarea
            value={content}
            onChange={e => { setContent(e.target.value); setSaveState('idle') }}
            spellCheck={false}
            className="w-full bg-[#1c1c1e] dark:bg-black text-slate-200 font-mono text-xs p-4 rounded-[20px] focus:outline-none focus:ring-2 focus:ring-miu-primary resize-none leading-relaxed"
            style={{ minHeight: '320px', height: `${Math.max(320, content.split('\n').length * 18 + 24)}px` }}
          />

          {saveError && (
            <p className="text-xs text-miu-danger">Save failed: {saveError}</p>
          )}

          <button
            onClick={save}
            disabled={saveState === 'saving' || !ksuAvail}
            className={`flex items-center justify-center gap-2 w-full py-3.5 rounded-full text-sm font-semibold transition-all active:scale-[0.98] disabled:opacity-40 ${
              saveState === 'saved'
                ? 'bg-miu-healthy text-white'
                : saveState === 'error'
                ? 'bg-miu-danger text-white'
                : 'bg-miu-primary text-white'
            }`}
          >
            <Save size={15} />
            {saveState === 'saving' ? t('saving') : saveState === 'saved' ? 'Saved!' : saveState === 'error' ? 'Save failed' : t('save')}
          </button>
        </>
      )}
    </div>
  )
}
