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
    <div className="min-h-screen bg-[#F0F4F8] dark:bg-slate-900 text-slate-900 dark:text-slate-100 flex flex-col max-w-md mx-auto">

      {/* Header — transparent/minimal on home tab, full on other tabs + sub-pages */}
      <header className={`sticky top-0 z-20 px-4 py-3 flex items-center gap-3 transition-colors ${
        isHomePage
          ? 'bg-[#F0F4F8]/90 dark:bg-slate-900/90'
          : 'bg-white/80 dark:bg-slate-900/80 backdrop-blur-md border-b border-slate-200 dark:border-slate-800'
      }`}>
        {subPage ? (
          <button
            onClick={goBack}
            className="p-1.5 rounded-lg hover:bg-slate-100 dark:hover:bg-slate-800 text-slate-600 dark:text-slate-300 transition-colors"
          >
            <ChevronLeft size={18} />
          </button>
        ) : isHomePage ? (
          /* Home tab: no logo — title is rendered inside Home.tsx page content */
          <div className="flex-1" />
        ) : (
          <div className="w-8 h-8 rounded-xl bg-gradient-to-br from-sky-500 to-indigo-600 flex items-center justify-center text-white font-black text-sm select-none">
            S
          </div>
        )}
        {!isHomePage && (
          <div className="flex-1 min-w-0">
            <div className={`font-semibold leading-tight text-slate-800 dark:text-slate-100 truncate ${subPage ? 'text-sm' : 'text-[15px]'}`}>
              {subTitle ?? 'SB Tproxy'}
            </div>
            {!subPage && (
              <div className="text-xs text-slate-400 truncate">Transparent proxy · sing-box</div>
            )}
          </div>
        )}
        {!subPage && (
          <button
            onClick={() => setLang(lang === 'en' ? 'vi' : 'en')}
            className="px-2 py-1 rounded-lg text-xs font-bold text-slate-400 hover:bg-slate-100 dark:hover:bg-slate-800 transition-colors select-none"
          >
            {lang === 'en' ? 'VI' : 'EN'}
          </button>
        )}
      </header>

      {/* Page content */}
      <main className="flex-1 overflow-y-auto p-4 pb-2">
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
        <div className="sticky bottom-16 z-10 mx-4 mb-2 bg-white dark:bg-slate-800 rounded-2xl shadow-lg border border-slate-200 dark:border-slate-700 px-4 py-3 flex items-center gap-3">
          <div className="flex-1 text-sm font-medium text-amber-500">{t('unsavedChanges')}</div>
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
        <nav className="sticky bottom-0 z-20 bg-white/95 dark:bg-slate-950/95 backdrop-blur-md border-t border-slate-100 dark:border-slate-800/80 flex">
          {tabs.map(({ id, icon: Icon, label }) => (
            <button
              key={id}
              onClick={() => switchTab(id)}
              className={`flex-1 flex flex-col items-center gap-0.5 py-2 text-xs transition-colors ${
                tab === id
                  ? 'text-sky-500'
                  : 'text-slate-400 dark:text-slate-500 hover:text-slate-600 dark:hover:text-slate-400'
              }`}
            >
              <span className={`p-1.5 rounded-xl transition-colors ${tab === id ? 'bg-sky-50 dark:bg-sky-500/15' : ''}`}>
                <Icon size={20} strokeWidth={tab === id ? 2.5 : 1.8} />
              </span>
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
