import type { ReactNode } from 'react'
import { ChevronRight } from 'lucide-react'
import { cn } from '../lib/cn'

// ── Shared icon tiles ─────────────────────────────────────────────────── //
// HyperOS-style solid rounded tiles with white glyphs (cf. Eta settings).

export type NavIconColor =
  | 'blue' | 'green' | 'teal' | 'indigo' | 'violet'
  | 'amber' | 'orange' | 'rose' | 'slate'
// legacy aliases kept for existing call sites
  | 'emerald' | 'red'

export const navIconCls: Record<NavIconColor, string> = {
  blue:    'bg-[#3482ff] text-white',
  green:   'bg-[#4caf50] text-white',
  teal:    'bg-[#00acc1] text-white',
  indigo:  'bg-[#5c6bc0] text-white',
  violet:  'bg-[#af52de] text-white',
  amber:   'bg-[#ffb300] text-white',
  orange:  'bg-[#ff9500] text-white',
  rose:    'bg-[#f5453c] text-white',
  slate:   'bg-[#8e8e93] text-white',
  emerald: 'bg-[#4caf50] text-white',
  red:     'bg-[#e53935] text-white',
}

// ── Card ──────────────────────────────────────────────────────────────────── //
// Miuix Card: flat surface, 16-20dp radius, zero elevation, no border.

export function Card({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn('rounded-[20px] bg-miu-card', className)}>
      {children}
    </div>
  )
}

// ── Section title ─────────────────────────────────────────────────────────── //
// MIUI section header: small gray label, normal case.

export function SectionTitle({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <h3 className={cn('text-[13px] font-medium text-miu-sub px-5 pt-5 pb-2 flex items-center gap-1.5', className)}>
      {children}
    </h3>
  )
}

// ── Row wrapper ───────────────────────────────────────────────────────────── //

function Row({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn('flex items-center justify-between px-5 py-3 border-b border-miu-divider last:border-0', className)}>
      {children}
    </div>
  )
}

// ── Switch row ────────────────────────────────────────────────────────────── //
// Miuix Switch proportions: 49x28dp track, 20dp thumb.

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
            ? <span className={cn('w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0', navIconCls[iconColor])}>{icon}</span>
            : <span className="text-miu-faint shrink-0">{icon}</span>
        )}
        <div className="min-w-0">
          <div className="text-[15px] font-medium text-miu-text truncate">{label}</div>
          {sub && <div className="text-[13px] text-miu-sub truncate mt-0.5">{sub}</div>}
        </div>
      </div>
      <button
        role="switch"
        aria-checked={checked}
        disabled={disabled}
        onClick={() => !disabled && onChange(!checked)}
        className={cn(
          'relative inline-flex h-7 w-[49px] shrink-0 rounded-full transition-colors duration-200 ml-3',
          checked ? 'bg-miu-primary' : 'bg-miu-track',
          disabled && 'opacity-50 cursor-not-allowed',
        )}
      >
        <span
          className={cn(
            'absolute top-1 left-1 h-5 w-5 rounded-full bg-white shadow transition-transform duration-200',
            checked ? 'translate-x-[21px]' : 'translate-x-0',
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
            ? <span className={cn('w-9 h-9 rounded-[10px] flex items-center justify-center shrink-0', navIconCls[iconColor])}>{icon}</span>
            : <span className="text-miu-faint shrink-0">{icon}</span>
        )}
        <span className="text-[15px] font-medium text-miu-text truncate">{label}</span>
      </div>
      <select
        value={String(value)}
        disabled={disabled}
        onChange={e => onChange(e.target.value)}
        className={cn(
          'text-[15px] font-medium bg-transparent text-miu-primary text-right',
          'focus:outline-none',
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
  primary:   'bg-miu-primary text-white font-semibold',
  secondary: 'bg-miu-primary/12 text-miu-primary font-semibold',
  danger:    'bg-miu-danger text-white font-semibold',
  success:   'bg-miu-healthy text-white font-semibold',
  ghost:     'bg-black/[0.04] dark:bg-white/10 text-miu-text',
}

export function Btn({ children, onClick, variant = 'primary', disabled, className, loading }: BtnProps) {
  return (
    <button
      onClick={onClick}
      disabled={disabled || loading}
      className={cn(
        'px-4 py-2 rounded-full text-sm transition-all duration-150 active:scale-[0.97]',
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
      className={`animate-spin h-${size} w-${size} text-miu-primary`}
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

export function NavRow({ icon, title, sub, onPress, badge, iconColor = 'blue' }: NavRowProps) {
  return (
    <button
      onClick={onPress}
      className="w-full flex items-center gap-3 px-5 py-3 hover:bg-black/[0.03] dark:hover:bg-white/5 active:bg-black/[0.05] dark:active:bg-white/10 transition-colors border-b border-miu-divider last:border-0"
    >
      <span className={cn('w-10 h-10 rounded-[12px] flex items-center justify-center shrink-0', navIconCls[iconColor])}>
        {icon}
      </span>
      <div className="flex-1 min-w-0 text-left">
        <div className="text-[15px] font-medium text-miu-text truncate">{title}</div>
        {sub && <div className="text-[13px] text-miu-sub truncate mt-0.5">{sub}</div>}
      </div>
      {badge && <div className="shrink-0">{badge}</div>}
      <ChevronRight size={16} className="text-miu-faint shrink-0" />
    </button>
  )
}

// ── Badge ─────────────────────────────────────────────────────────────────── //

export function Badge({ children, color = 'gray', className }: { children: ReactNode; color?: 'green' | 'red' | 'gray' | 'blue' | 'yellow'; className?: string }) {
  const colorCls = {
    green:  'bg-miu-healthy-bg text-miu-healthy',
    red:    'bg-miu-danger-bg text-miu-danger',
    gray:   'bg-black/[0.05] dark:bg-white/10 text-miu-sub',
    blue:   'bg-miu-primary/12 text-miu-primary',
    yellow: 'bg-[#ffb300]/15 text-[#b27a00] dark:text-[#ffca5f]',
  }
  return (
    <span className={cn('text-xs font-semibold px-2 py-0.5 rounded-full tabular-nums', colorCls[color], className)}>
      {children}
    </span>
  )
}
