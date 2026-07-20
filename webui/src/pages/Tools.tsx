import { FileCode2, Globe, AppWindow, FileText, Activity, Download, Settings2, Stethoscope, RefreshCw } from 'lucide-react'
import { useI18n } from '../lib/i18n'
import { Card, SectionTitle, NavRow } from '../components/ui'
import type { SubPage } from '../types/box'

interface Props {
  onNavigate: (page: SubPage) => void
}

export default function Tools({ onNavigate }: Props) {
  const { t } = useI18n()

  return (
    <div className="space-y-4 pb-4">

      {/* ── Configuration ───────────────────────────────────────────────── */}
      <Card>
        <SectionTitle>
          <Settings2 size={11} className="shrink-0" />
          {t('sectionConfig')}
        </SectionTitle>
        <NavRow
          icon={<FileCode2 size={18} />}
          title={t('configFilesNav')}
          sub={t('configFilesSub')}
          onPress={() => onNavigate('config')}
          iconColor="sky"
        />
        <NavRow
          icon={<Globe size={18} />}
          title={t('proxyGroupsNav')}
          sub={t('proxyGroupsNavSub')}
          onPress={() => onNavigate('proxies')}
          iconColor="indigo"
        />
      </Card>

      {/* ── Rules & Data ────────────────────────────────────────────────── */}
      <Card>
        <SectionTitle>
          <RefreshCw size={11} className="shrink-0" />
          {t('sectionRules')}
        </SectionTitle>
        <NavRow
          icon={<AppWindow size={18} />}
          title={t('appRulesNav')}
          sub={t('appRulesNavSub')}
          onPress={() => onNavigate('apps')}
          iconColor="orange"
        />
      </Card>

      {/* ── Diagnostics ─────────────────────────────────────────────────── */}
      <Card>
        <SectionTitle>
          <Stethoscope size={11} className="shrink-0" />
          {t('sectionDiagnostics')}
        </SectionTitle>
        <NavRow
          icon={<FileText size={18} />}
          title={t('logsNav')}
          sub={t('logsNavSub')}
          onPress={() => onNavigate('logs')}
          iconColor="amber"
        />
        <NavRow
          icon={<Activity size={18} />}
          title={t('daemonStatusNav')}
          sub={t('daemonStatusNavSub')}
          onPress={() => onNavigate('daemon')}
          iconColor="emerald"
        />
      </Card>

      {/* ── Updates ─────────────────────────────────────────────────────── */}
      <Card>
        <SectionTitle>
          <Download size={11} className="shrink-0" />
          {t('sectionUpdate')}
        </SectionTitle>
        <NavRow
          icon={<Download size={18} />}
          title={t('updateNav')}
          sub={t('updateNavSub')}
          onPress={() => onNavigate('update')}
          iconColor="violet"
        />
      </Card>

    </div>
  )
}
