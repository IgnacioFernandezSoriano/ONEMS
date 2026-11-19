import { useTranslation } from '@/hooks/useTranslation'
import { ACCESS_OPTIONS } from '@/lib/access'
import { CONTACT_I18N, roleLabelKey, summarizeLog, type LogEntry, type LogNames } from '@/lib/accessAdmin'
import type { AccountContactField } from '@/lib/types'

interface Props {
  log: LogEntry[]
  emails: Map<string, string>
}

const OPTION_LABEL = new Map(ACCESS_OPTIONS.map(o => [o.key as string, o.labelKey]))

/** Últimos 50 cambios de la pestaña: cuándo, quién y un resumen corto. */
export function AccessLogSection({ log, emails }: Props) {
  const { t, locale } = useTranslation()

  const shortId = (id: string) => `${id.slice(0, 8)}…`
  const names: LogNames = {
    role: r => (r ? t(roleLabelKey(r)) : '?'),
    option: o => (OPTION_LABEL.has(o) ? t(OPTION_LABEL.get(o)!) : o),
    level: l => t(l === 'edit' ? 'roles_access.level.edit' : l === 'view' ? 'roles_access.level.view' : 'roles_access.level.none'),
    user: (id, hint) => emails.get(id) ?? hint ?? (id ? shortId(id) : '?'),
    contact: f => (f in CONTACT_I18N ? t(CONTACT_I18N[f as AccountContactField]) : f),
  }

  if (log.length === 0) return <p className="text-sm text-gray-500">{t('roles_access.log_empty')}</p>

  return (
    <div className="overflow-x-auto border border-gray-200 rounded-lg">
      <table className="min-w-full text-sm">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-3 py-2 text-start font-medium text-gray-700">{t('roles_access.log_date')}</th>
            <th className="px-3 py-2 text-start font-medium text-gray-700">{t('roles_access.log_who')}</th>
            <th className="px-3 py-2 text-start font-medium text-gray-700">{t('roles_access.log_what')}</th>
          </tr>
        </thead>
        <tbody>
          {log.map(e => {
            const s = summarizeLog(e, names)
            return (
              <tr key={e.id} className="border-t border-gray-100 align-top">
                <td className="px-3 py-1.5 whitespace-nowrap text-gray-600">{new Date(e.changed_at).toLocaleString(locale)}</td>
                <td className="px-3 py-1.5 text-gray-900">
                  {e.changed_by ? emails.get(e.changed_by) ?? shortId(e.changed_by) : t('roles_access.log_system')}
                </td>
                <td className="px-3 py-1.5 text-gray-900">{t(s.key, s.vars)}</td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}
