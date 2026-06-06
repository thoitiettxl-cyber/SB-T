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
      <div className="flex gap-1.5 bg-slate-100 dark:bg-slate-800 p-1 rounded-xl">
        {CONFIG_FILES.map(f => (
          <button
            key={f}
            onClick={() => loadFile(f)}
            className={`flex-1 flex items-center justify-center gap-1.5 py-1.5 rounded-lg text-xs font-semibold transition-colors ${
              activeFile === f
                ? 'bg-white dark:bg-slate-700 text-slate-900 dark:text-slate-100 shadow-sm'
                : 'text-slate-500 hover:text-slate-700 dark:hover:text-slate-300'
            }`}
          >
            <FileText size={12} />
            {f}
          </button>
        ))}
      </div>

      {/* Warning */}
      {activeFile === 'config.json' && (
        <div className="flex gap-2 items-start p-3 bg-amber-500/10 border border-amber-500/30 rounded-xl">
          <AlertTriangle size={14} className="text-amber-500 flex-shrink-0 mt-0.5" />
          <p className="text-xs text-amber-600 dark:text-amber-400">Editing config.json directly may break your proxy. Restart after saving.</p>
        </div>
      )}

      {/* Load button (if not loaded) */}
      {!loaded && !loading && (
        <button
          onClick={() => loadFile(activeFile)}
          disabled={!ksuAvail}
          className="w-full py-3 rounded-xl bg-sky-500/10 hover:bg-sky-500/20 text-sky-600 dark:text-sky-400 text-sm font-semibold disabled:opacity-40 transition-colors"
        >
          {t('loading').replace('...', '')} {activeFile}
        </button>
      )}

      {loading && (
        <div className="flex items-center justify-center py-8 text-slate-500 text-sm">{t('loading')}</div>
      )}

      {/* Editor */}
      {loaded && (
        <>
          <textarea
            value={content}
            onChange={e => { setContent(e.target.value); setSaveState('idle') }}
            spellCheck={false}
            className="w-full bg-slate-900 text-slate-200 font-mono text-xs p-3 rounded-xl border border-slate-700 focus:outline-none focus:border-sky-500 resize-none leading-relaxed"
            style={{ minHeight: '320px', height: `${Math.max(320, content.split('\n').length * 18 + 24)}px` }}
          />

          {saveError && (
            <p className="text-xs text-red-500">Save failed: {saveError}</p>
          )}

          <button
            onClick={save}
            disabled={saveState === 'saving' || !ksuAvail}
            className={`flex items-center justify-center gap-2 w-full py-3 rounded-xl text-sm font-bold transition-all active:scale-95 disabled:opacity-40 ${
              saveState === 'saved'
                ? 'bg-green-500 text-white'
                : saveState === 'error'
                ? 'bg-red-500 text-white'
                : 'bg-sky-500 hover:bg-sky-600 text-white'
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
