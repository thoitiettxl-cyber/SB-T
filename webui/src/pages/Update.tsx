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
    <div className="bg-miu-card rounded-[20px] p-5">
      <div className="flex items-start gap-3 mb-4">
        <div className="w-10 h-10 rounded-[12px] bg-[#3482ff] flex items-center justify-center text-white shrink-0">
          {icon}
        </div>
        <div className="flex-1">
          <div className="font-medium text-[15px] text-miu-text">{title}</div>
          <div className="text-[13px] text-miu-sub mt-0.5">{desc}</div>
        </div>
      </div>

      {/* Confirm prompt shown between first and second click */}
      {confirming && (
        <div className="mb-3 flex items-start gap-2.5 p-4 rounded-[16px]" style={{ background: 'var(--miu-danger-bg)' }}>
          <AlertTriangle size={15} className="text-miu-warn shrink-0 mt-0.5" />
          <p className="text-[13px] text-miu-text flex-1">
            {t('confirmUpdate')}
          </p>
        </div>
      )}

      <div className="flex gap-2.5">
        <button
          onClick={handleClick}
          disabled={running || !ksuAvail}
          className={`flex-1 flex items-center justify-center gap-2 py-3 rounded-full text-sm font-semibold disabled:opacity-40 transition-all active:scale-[0.98] ${
            confirming
              ? 'bg-miu-warn text-white'
              : 'bg-miu-primary text-white'
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
            className="px-4 py-3 rounded-full bg-black/[0.04] dark:bg-white/[0.07] text-miu-sub transition-colors"
          >
            <X size={15} />
          </button>
        )}
      </div>

      {output && (
        <pre className="mt-3 p-3.5 bg-[#1c1c1e] dark:bg-black rounded-[16px] text-xs font-mono text-slate-300 overflow-x-auto whitespace-pre-wrap max-h-48 overflow-y-auto">
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
    </div>
  )
}
