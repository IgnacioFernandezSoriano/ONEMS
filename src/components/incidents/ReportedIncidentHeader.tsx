import { format, isValid, parseISO } from 'date-fns'
import { useTranslation } from '@/hooks/useTranslation'
import type { ReportedIncidentDetail } from '@/lib/types'

function fmtDate(d: string | null | undefined): string | null {
  if (!d) return null
  const p = parseISO(d)
  return isValid(p) ? format(p, 'dd/MM/yyyy') : null
}

export function ReportedIncidentHeader({ inc, role }: {
  inc: ReportedIncidentDetail
  role: 'sender' | 'receiver' | null
}) {
  const { t } = useTranslation()
  const p = inc.panelist
  const d = inc.detail
  const name = inc.panelist_name ?? p?.name ?? '-'
  const code = inc.panelist_code ?? p?.panelist_code ?? '-'

  const contact: string[] = []
  if (p?.mobile) contact.push(`📞 ${p.mobile}`)
  if (p?.email) contact.push(`✉ ${p.email}`)
  contact.push(p?.telegram_id ? t('reported_incidents.header.telegram_yes') : t('reported_incidents.header.telegram_no'))
  if (p?.language) contact.push(p.language)
  if (p?.address_city) contact.push(p.address_city)

  const date = fmtDate(d?.fecha_programada)
  const route = d && (d.origin_node?.auto_id || d.destination_node?.auto_id)
    ? `${d.origin_node?.auto_id ?? '-'} → ${d.destination_node?.auto_id ?? '-'}`
    : null
  const shipmentParts = d
    ? [route, d.plan?.carrier?.name, d.plan?.product?.description, date].filter(Boolean) as string[]
    : []

  return (
    <div className="text-sm text-gray-600 mb-4 space-y-1">
      <div>{name} · <span className="font-mono">{code}</span></div>
      <div aria-label={t('reported_incidents.header.contact')}>{contact.join(' · ')}</div>
      {d && (
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
          {role && (
            <span className={`text-xs px-2 py-0.5 rounded ${role === 'sender' ? 'bg-blue-100 text-blue-700' : 'bg-green-100 text-green-700'}`}>
              {t(`reported_incidents.role.${role}`)}
            </span>
          )}
          <span>{shipmentParts.join(' · ')}</span>
          {d.tag_id && <span className="font-mono">{d.tag_id}</span>}
        </div>
      )}
    </div>
  )
}
