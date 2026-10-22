import { useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { ExternalLink, Link2 } from 'lucide-react'
import { useAuth } from '@/contexts/AuthContext'
import { useLocale } from '@/contexts/LocaleContext'
import { HELP_DOCS, HELP_LANGS, helpDocUrl, helpLang } from '@/lib/helpDocs'

export function HelpCenter() {
  const { t, locale } = useLocale()
  const { profile } = useAuth()
  const [params, setParams] = useSearchParams()
  const docs = HELP_DOCS.filter(d => !d.roles || d.roles.includes(profile?.role || ''))
  const current = docs.find(d => d.id === params.get('doc')) ?? docs[0]
  const [lang, setLang] = useState<string>(helpLang(locale))
  const [copied, setCopied] = useState(false)

  if (!current) return <div className="p-6">{t('help_center.empty')}</div>

  const src = helpDocUrl(current.file, lang)
  const copyLink = async () => {
    try {
      await navigator.clipboard.writeText(helpDocUrl(current.file, lang, undefined, true))
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch {
      setCopied(false)
    }
  }

  return (
    <div className="p-6">
      <h2 className="text-xl font-bold mb-1">{t('help_center.title')}</h2>
      <p className="text-sm text-gray-600 mb-4">{t('help_center.intro')}</p>
      <div className="grid gap-4 lg:grid-cols-[280px_minmax(0,1fr)]">
        <div className="flex flex-col gap-2">
          {docs.map(d => {
            const on = d.id === current.id
            return (
              <button
                key={d.id}
                type="button"
                onClick={() => setParams({ doc: d.id })}
                className={`text-start rounded-lg border p-3 transition-colors ${on ? 'border-blue-300 bg-blue-50' : 'border-gray-200 bg-white hover:bg-gray-50'}`}
              >
                <div className="flex flex-wrap items-center gap-2 mb-1">
                  <span className={`text-sm font-semibold ${on ? 'text-blue-700' : 'text-gray-900'}`}>{t(d.titleKey)}</span>
                </div>
                <div className="flex flex-wrap gap-1 mb-1">
                  <span className="text-xs px-2 py-0.5 rounded-full bg-gray-100 text-gray-600">{t(`help_center.audience.${d.audience}`)}</span>
                  {d.public && <span className="text-xs px-2 py-0.5 rounded-full bg-green-100 text-green-700">{t('help_center.public_badge')}</span>}
                </div>
                <p className="text-xs text-gray-600">{t(d.descKey)}</p>
              </button>
            )
          })}
        </div>
        <div className="min-w-0 rounded-lg border border-gray-200 bg-white overflow-hidden">
          <div className="flex flex-wrap items-center gap-3 border-b border-gray-200 bg-gray-50 px-3 py-2 text-sm">
            <label className="flex items-center gap-2">
              <span className="text-gray-600">{t('help_center.language')}</span>
              <select className="border rounded px-2 py-1 text-sm bg-white" value={lang} onChange={e => setLang(e.target.value)}>
                {HELP_LANGS.map(l => <option key={l} value={l}>{l.toUpperCase()}</option>)}
              </select>
            </label>
            <a href={src} target="_blank" rel="noopener noreferrer" className="flex items-center gap-1 text-blue-600 hover:underline">
              <ExternalLink className="w-4 h-4" />{t('help_center.open_new_tab')}
            </a>
            {current.public && (
              <button type="button" onClick={copyLink} className="flex items-center gap-1 text-blue-600 hover:underline">
                <Link2 className="w-4 h-4" />{copied ? t('help_center.copied') : t('help_center.copy_link')}
              </button>
            )}
          </div>
          <iframe key={src} src={src} title={t(current.titleKey)} className="block w-full border-0" style={{ height: 'calc(100vh - 220px)', minHeight: 480 }} />
        </div>
      </div>
    </div>
  )
}
