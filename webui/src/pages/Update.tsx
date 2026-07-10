import { useState } from 'react'
import { Download, Package, AlertTriangle, CheckCircle, X } from 'lucide-react'
import { exec } from 'kernelsu'
import { isKsuAvailable } from '../lib/bridge'
import { useI18n } from '../lib/i18n'

const BOX_DIR = '/data/adb/box'

interface UpdateCardProps {
  icon: React.ReactNode
  title: string
  desc: string
  cmd: string
}

function UpdateCard({ icon, title, desc, cmd }: UpdateCardProps) {
  const { t } = useI18n()
  const [output, setOutput] = useState('')
  const [running, setRunning] = useState(false)
  const [confirming, setConfirming] = useState(false)  // waiting for second click
  const ksuAvail = isKsuAvailable()

  function handleClick() {
    if (!confirming) {
      // First click: enter confirm mode
      setConfirming(true)
      return
    }
    // Second click: execute
    doRun()
  }

  function cancelConfirm() {
    setConfirming(false)
  }

  async function doRun() {
    setConfirming(false)
    setRunning(true)
    setOutput('')
    try {
      const { stdout, stderr } = await exec(cmd)
      setOutput((stdout + (stderr ? '\n' + stderr : '')).trim())
    } catch (e) {
      setOutput(String(e))
    } finally {
      setRunning(false)
    }
  }

  return (
    <div className="bg-white dark:bg-slate-800 rounded-2xl p-4 border border-slate-200 dark:border-slate-700 shadow-sm">
      <div className="flex items-start gap-3 mb-3">
        <div className="w-9 h-9 rounded-xl bg-sky-500/15 flex items-center justify-center text-sky-500 shrink-0">
          {icon}
        </div>
        <div className="flex-1">
          <div className="font-semibold text-sm">{title}</div>
          <div className="text-xs text-slate-500 mt-0.5">{desc}</div>
        </div>
      </div>

      {/* Confirm prompt shown between first and second click */}
      {confirming && (
        <div className="mb-3 flex items-start gap-2 p-3 rounded-xl bg-amber-50 dark:bg-amber-900/20 border border-amber-300 dark:border-amber-700">
          <AlertTriangle size={14} className="text-amber-500 shrink-0 mt-0.5" />
          <p className="text-xs text-amber-700 dark:text-amber-400 flex-1">
            {t('confirmUpdate')}
          </p>
        </div>
      )}

      <div className="flex gap-2">
        <button
          onClick={handleClick}
          disabled={running || !ksuAvail}
          className={`flex-1 flex items-center justify-center gap-2 py-2.5 rounded-xl text-sm font-semibold disabled:opacity-40 transition-all active:scale-95 ${
            confirming
              ? 'bg-amber-500 hover:bg-amber-600 text-white'
              : 'bg-sky-500 hover:bg-sky-600 text-white'
          }`}
        >
          {running
            ? <Download size={15} className="animate-bounce" />
            : confirming
            ? <CheckCircle size={15} />
            : <Download size={15} />
          }
          {running
            ? t('running_update')
            : confirming
            ? t('confirmYes')
            : title
          }
        </button>

        {confirming && (
          <button
            onClick={cancelConfirm}
            className="px-3 py-2.5 rounded-xl bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 text-slate-600 dark:text-slate-300 transition-colors"
          >
            <X size={15} />
          </button>
        )}
      </div>

      {output && (
        <pre className="mt-3 p-2.5 bg-slate-900 rounded-xl text-xs font-mono text-slate-300 overflow-x-auto whitespace-pre-wrap max-h-48 overflow-y-auto">
          {output}
        </pre>
      )}
    </div>
  )
}

export default function Update() {
  const { t } = useI18n()

  return (
    <div className="space-y-4">
      <UpdateCard
        icon={<Package size={18} />}
        title={t('updateBin')}
        desc="Download latest sing-box binary from GitHub releases"
        cmd={`sh '${BOX_DIR}/scripts/sbctl' update`}
      />
      <UpdateCard
        icon={<Download size={18} />}
        title={t('updateIpset')}
        desc="Download IPSET kernel modules (TanakaLun/IPSET_LKM)"
        cmd={`sh '${BOX_DIR}/scripts/sbctl' update-ipset`}
      />
    </div>
  )
}
