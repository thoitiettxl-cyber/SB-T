import type { ReactNode } from 'react'
import { ChevronRight } from 'lucide-react'
import { cn } from '../lib/cn'

// ── Shared icon-color tokens (used by SwitchRow + NavRow) ────────────────── //

export type NavIconColor = 'sky' | 'indigo' | 'violet' | 'emerald' | 'amber' | 'orange' | 'rose' | 'teal' | 'red' | 'slate'

export const navIconCls: Record<NavIconColor, string> = {
  sky:     'bg-sky-50 dark:bg-sky-500/15 text-sky-500 dark:text-sky-400',
  indigo:  'bg-indigo-50 dark:bg-indigo-500/15 text-indigo-500 dark:text-indigo-400',
  violet:  'bg-violet-50 dark:bg-violet-500/15 text-violet-500 dark:text-violet-400',
  emerald: 'bg-emerald-50 dark:bg-emerald-500/15 text-emerald-500 dark:text-emerald-400',
  amber:   'bg-amber-50 dark:bg-amber-500/15 text-amber-500 dark:text-amber-400',
  orange:  'bg-orange-50 dark:bg-orange-500/15 text-orange-500 dark:text-orange-400',
  rose:    'bg-rose-50 dark:bg-rose-500/15 text-rose-500 dark:text-rose-400',
  teal:    'bg-teal-50 dark:bg-teal-500/15 text-teal-500 dark:text-teal-400',
  red:     'bg-red-50 dark:bg-red-500/15 text-red-500 dark:text-red-400',
  slate:   'bg-slate-100 dark:bg-slate-700 text-slate-500 dark:text-slate-400',
}

// ── Card ──────────────────────────────────────────────────────────────────── //

export function Card({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn('rounded-2xl bg-white dark:bg-slate-800/90 shadow-[0_1px_3px_rgba(0,0,0,0.07),0_6px_20px_rgba(0,0,0,0.05)] border border-slate-100 dark:border-slate-700/60', className)}>
      {children}
    </div>
  )
}

// ── Section title ─────────────────────────────────────────────────────────── //

export function SectionTitle({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <h3 className={cn('text-[11px] font-semibold uppercase tracking-widest text-slate-400 dark:text-slate-500 px-4 pt-4 pb-1.5 flex items-center gap-1.5', className)}>
      {children}
    </h3>
  )
}

// ── Row wrapper ───────────────────────────────────────────────────────────── //

function Row({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn('flex items-center justify-between px-4 py-3 border-b border-slate-100 dark:border-slate-700 last:border-0', className)}>
      {children}
    </div>
  )
}

// ── Switch row ────────────────────────────────────────────────────────────── //

interface SwitchRowProps {
  label: string
  sub?: string
  checked: boolean
  onChange: (v: boolean) => void
  disabled?: boolean
  icon?: ReactNode
  iconColor?: NavIconColor
}

export function SwitchRow({ label, sub, checked, onChange, disabled, icon, iconColor }: SwitchRowProps) {
  return (
    <Row>
      <div className="flex items-center gap-3 min-w-0">
        {icon && (
          iconColor
            ? <span className={cn('w-8 h-8 rounded-xl flex items-center justify-center shrink-0', navIconCls[iconColor])}>{icon}</span>
            : <span className="text-slate-400 shrink-0">{icon}</span>
        )}
        <div className="min-w-0">
          <div className="text-sm font-semibold text-slate-800 dark:text-slate-200 truncate">{label}</div>
          {sub && <div className="text-xs text-slate-400 truncate">{sub}</div>}
        </div>
      </div>
      <button
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => !disabled && onChange(!checked)}
        className={cn(
          'relative inline-flex h-6 w-11 shrink-0 rounded-full transition-colors duration-200 ml-3',
          checked ? 'bg-sky-500' : 'bg-slate-200 dark:bg-slate-600',
          disabled && 'opacity-50 cursor-not-allowed',
        )}
      >
        <span
          className={cn(
            'absolute top-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform duration-200',
            checked ? 'translate-x-5' : 'translate-x-0.5',
          )}
        />
      </button>
    </Row>
  )
}

// ── Select row ────────────────────────────────────────────────────────────── //

interface SelectRowProps {
  label: string
  value: string | number
  options: Array<{ value: string | number; label: string }>
  onChange: (v: string) => void
  disabled?: boolean
  icon?: ReactNode
  iconColor?: NavIconColor
}

export function SelectRow({ label, value, options, onChange, disabled, icon, iconColor }: SelectRowProps) {
  return (
    <Row>
      <div className="flex items-center gap-3 min-w-0 flex-1 mr-3">
        {icon && (
          iconColor
            ? <span className={cn('w-8 h-8 rounded-xl flex items-center justify-center shrink-0', navIconCls[iconColor])}>{icon}</span>
            : <span className="text-slate-400 shrink-0">{icon}</span>
        )}
        <span className="text-sm font-semibold text-slate-800 dark:text-slate-200 truncate">{label}</span>
      </div>
      <select
        value={String(value)}
        disabled={disabled}
        onChange={e => onChange(e.target.value)}
        className={cn(
          'text-sm rounded-xl px-2.5 py-1.5 border border-slate-200 dark:border-slate-600',
          'bg-white dark:bg-slate-700 text-slate-700 dark:text-slate-200',
          'focus:outline-none focus:ring-2 focus:ring-sky-400',
          disabled && 'opacity-50 cursor-not-allowed',
        )}
      >
        {options.map(o => (
          <option key={o.value} value={String(o.value)}>{o.label}</option>
        ))}
      </select>
    </Row>
  )
}

// ── Button ────────────────────────────────────────────────────────────────── //

interface BtnProps {
  children: ReactNode
  onClick?: () => void
  variant?: 'primary' | 'secondary' | 'danger' | 'success' | 'ghost'
  disabled?: boolean
  className?: string
  loading?: boolean
}

const variantCls: Record<NonNullable<BtnProps['variant']>, string> = {
  primary:   'bg-sky-500 hover:bg-sky-600 text-white',
  secondary: 'bg-indigo-500 hover:bg-indigo-600 text-white',
  danger:    'bg-red-500 hover:bg-red-600 text-white',
  success:   'bg-emerald-500 hover:bg-emerald-600 text-white',
  ghost:     'bg-slate-100 dark:bg-slate-700 hover:bg-slate-200 dark:hover:bg-slate-600 text-slate-700 dark:text-slate-200',
}

export function Btn({ children, onClick, variant = 'primary', disabled, className, loading }: BtnProps) {
  return (
    <button
      onClick={onClick}
      disabled={disabled || loading}
      className={cn(
        'px-4 py-2 rounded-xl text-sm font-medium transition-colors duration-150 active:scale-[0.97]',
        variantCls[variant],
        (disabled || loading) && 'opacity-50 cursor-not-allowed',
        className,
      )}
    >
      {children}
    </button>
  )
}

// ── Spinner ───────────────────────────────────────────────────────────────── //

export function Spinner({ size = 5 }: { size?: number }) {
  return (
    <svg
      className={`animate-spin h-${size} w-${size} text-sky-500`}
      viewBox="0 0 24 24"
      fill="none"
    >
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
    </svg>
  )
}

// ── Nav row (Tools hub) ───────────────────────────────────────────────────── //

interface NavRowProps {
  icon: ReactNode
  title: string
  sub?: string
  onPress: () => void
  badge?: ReactNode
  iconColor?: NavIconColor
}

export function NavRow({ icon, title, sub, onPress, badge, iconColor = 'sky' }: NavRowProps) {
  return (
    <button
      onClick={onPress}
      className="w-full flex items-center gap-3 px-4 py-3.5 hover:bg-slate-50 dark:hover:bg-slate-700/40 active:bg-slate-100 dark:active:bg-slate-700 transition-colors border-b border-slate-100 dark:border-slate-700/60 last:border-0"
    >
      <span className={cn('w-9 h-9 rounded-xl flex items-center justify-center shrink-0', navIconCls[iconColor])}>
        {icon}
      </span>
      <div className="flex-1 min-w-0 text-left">
        <div className="text-sm font-semibold text-slate-800 dark:text-slate-200 truncate">{title}</div>
        {sub && <div className="text-xs text-slate-400 truncate mt-0.5">{sub}</div>}
      </div>
      {badge && <div className="shrink-0">{badge}</div>}
      <ChevronRight size={15} className="text-slate-300 dark:text-slate-600 shrink-0" />
    </button>
  )
}

// ── Badge ─────────────────────────────────────────────────────────────────── //

export function Badge({ children, color = 'gray', className }: { children: ReactNode; color?: 'green' | 'red' | 'gray' | 'blue' | 'yellow'; className?: string }) {
  const colorCls = {
    green:  'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-400',
    red:    'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-400',
    gray:   'bg-slate-100 text-slate-600 dark:bg-slate-700 dark:text-slate-400',
    blue:   'bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-400',
    yellow: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/40 dark:text-yellow-400',
  }
  return (
    <span className={cn('text-xs font-medium px-2 py-0.5 rounded-full', colorCls[color], className)}>
      {children}
    </span>
  )
}
