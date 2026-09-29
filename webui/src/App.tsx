import { useState } from 'react'
import { Home as HomeIcon, Wrench, Settings as SettingsIcon, ChevronLeft } from 'lucide-react'
import { I18nProvider, useI18n } from './lib/i18n'
import { useBoxController } from './hooks/useBoxController'
import { Btn } from './components/ui'
import PageHome from './pages/Home'
import PageTools from './pages/Tools'
import PageSettings from './pages/Settings'
import PageConfig from './pages/Config'
import PageApps from './pages/Apps'
import PageLogs from './pages/Logs'
import PageProxies from './pages/Proxies'
import PageUpdate from './pages/Update'
import PageDaemon from './pages/DaemonStatus'
import type { SubPage } from './types/box'

type Tab = 'home' | 'tools' | 'settings'

const SUB_PAGE_TITLE_KEY: Record<SubPage, 'subPageConfig' | 'subPageApps' | 'subPageLogs' | 'subPageProxies' | 'subPageUpdate' | 'subPageDaemon'> = {
  config:  'subPageConfig',
  apps:    'subPageApps',
  logs:    'subPageLogs',
  proxies: 'subPageProxies',
  update:  'subPageUpdate',
  daemon:  'subPageDaemon',
}

function AppInner() {
  const { t, lang, setLang } = useI18n()
  const [tab, setTab] = useState<Tab>('home')
  const [subPage, setSubPage] = useState<SubPage | null>(null)
  const ctrl = useBoxController()

  const tabs: Array<{ id: Tab; icon: typeof HomeIcon; label: string }> = [
    { id: 'home',     icon: HomeIcon,        label: t('tabHome') },
    { id: 'tools',    icon: Wrench,          label: t('tabTools') },
    { id: 'settings', icon: SettingsIcon,    label: t('tabSettings') },
  ]

  function navigate(page: SubPage) { setSubPage(page) }
  function goBack() { setSubPage(null) }

  function switchTab(id: Tab) {
    setTab(id)
    setSubPage(null)
  }

  const subTitle = subPage ? t(SUB_PAGE_TITLE_KEY[subPage]) : undefined

  const isHomePage = !subPage && tab === 'home'

  return (
    <div className="min-h-screen bg-miu-bg text-miu-text flex flex-col max-w-md mx-auto">

      {/* Header — transparent/minimal on home tab, blurred on other tabs + sub-pages */}
      <header className={`sticky top-0 z-20 px-4 py-3 flex items-center gap-3 transition-colors ${
        isHomePage
          ? 'bg-miu-bg/90'
          : 'bg-miu-bg/80 backdrop-blur-md'
      }`}>
        {subPage ? (
          <button
            onClick={goBack}
            className="p-1.5 rounded-full hover:bg-black/[0.04] dark:hover:bg-white/10 text-miu-text transition-colors"
          >
            <ChevronLeft size={20} />
          </button>
        ) : isHomePage ? (
          /* Home tab: no logo — title is rendered inside Home.tsx page content */
          <div className="flex-1" />
        ) : (
          <div className="w-9 h-9 rounded-[10px] bg-miu-primary flex items-center justify-center text-white font-bold text-[15px] select-none">
            S
          </div>
        )}
        {!isHomePage && (
          <div className="flex-1 min-w-0">
            <div className={`font-semibold leading-tight text-miu-text truncate ${subPage ? 'text-[15px]' : 'text-base'}`}>
              {subTitle ?? 'SB Tproxy'}
            </div>
            {!subPage && (
              <div className="text-xs text-miu-sub truncate mt-0.5">Transparent proxy · sing-box</div>
            )}
          </div>
        )}
        {!subPage && (
          <button
            onClick={() => setLang(lang === 'en' ? 'vi' : 'en')}
            className="px-2 py-1 rounded-lg text-xs font-bold text-miu-faint hover:bg-black/[0.04] dark:hover:bg-white/10 transition-colors select-none"
          >
            {lang === 'en' ? 'VI' : 'EN'}
          </button>
        )}
      </header>

      {/* Page content */}
      <main className="flex-1 overflow-y-auto px-3 pb-2">
        {subPage === 'config'  && <PageConfig />}
        {subPage === 'apps'    && <PageApps ctrl={ctrl} />}
        {subPage === 'logs'    && <PageLogs />}
        {subPage === 'proxies' && <PageProxies apiPort={ctrl.status?.clash_api_port} apiSecret={ctrl.status?.clash_api_secret} />}
        {subPage === 'update'  && <PageUpdate />}
        {subPage === 'daemon'  && <PageDaemon />}

        {!subPage && tab === 'home'     && <PageHome ctrl={ctrl} onNavigate={navigate} />}
        {!subPage && tab === 'tools'    && <PageTools onNavigate={navigate} />}
        {!subPage && tab === 'settings' && <PageSettings ctrl={ctrl} />}
      </main>

      {/* Floating save bar */}
      {ctrl.hasChanges && !subPage && (
        <div className="sticky bottom-20 z-10 mx-4 mb-2 bg-miu-card rounded-[20px] shadow-lg px-5 py-3.5 flex items-center gap-3">
          <div className="flex-1 text-[15px] font-medium text-miu-warn">{t('unsavedChanges')}</div>
          <Btn variant="ghost" onClick={ctrl.discardChanges} className="py-1.5">{t('discard')}</Btn>
          <Btn
            variant="primary"
            onClick={ctrl.saveChanges}
            loading={ctrl.saving}
            className="py-1.5"
          >
            {ctrl.saving ? t('saving') : t('save')}
          </Btn>
        </div>
      )}

      {/* Bottom navigation — hidden when in a sub-page */}
      {!subPage && (
        <nav className="sticky bottom-0 z-20 bg-miu-card/90 backdrop-blur-md border-t border-miu-divider/70 flex">
          {tabs.map(({ id, icon: Icon, label }) => (
            <button
              key={id}
              onClick={() => switchTab(id)}
              className={`flex-1 flex flex-col items-center gap-1 py-2.5 text-[11px] transition-colors ${
                tab === id
                  ? 'text-miu-primary'
                  : 'text-miu-faint'
              }`}
            >
              <Icon size={22} strokeWidth={tab === id ? 2.4 : 1.8} />
              <span className="font-medium leading-tight">{label}</span>
            </button>
          ))}
        </nav>
      )}
    </div>
  )
}

export default function App() {
  return (
    <I18nProvider>
      <AppInner />
    </I18nProvider>
  )
}
