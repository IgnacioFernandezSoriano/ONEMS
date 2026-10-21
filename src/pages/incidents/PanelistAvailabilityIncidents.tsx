import { useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useTranslation } from '@/hooks/useTranslation'
import { format, parseISO, isValid } from 'date-fns'
import { useUnavailabilityIncidents } from '@/lib/hooks/useUnavailabilityIncidents'
import { IncidentReviewPanel } from '@/components/incidents/IncidentReviewPanel'
import { IncidentStatusBadge } from '@/components/incidents/IncidentStatusBadge'
import type { IncidentStatusFilter } from '@/lib/types'

const FILTER_OPTIONS: IncidentStatusFilter[] = ['open', 'all', 'new', 'auto_resolved', 'pending_manager', 'resolved']

const fmt = (d: string | null) => {
  if (!d) return '-'
  const p = parseISO(d)
  return isValid(p) ? format(p, 'dd/MM/yyyy') : '-'
}

export function PanelistAvailabilityIncidents() {
  const { t } = useTranslation()
  const { inbox, loading, error, fetchInbox, statusFilter, setStatusFilter } = useUnavailabilityIncidents()
  const [selected, setSelected] = useState<string | null>(null)
  const [params, setParams] = useSearchParams()

  // Abre una baja concreta si llega por URL (?unavailability=<id>). La bandeja por defecto solo
  // lista las abiertas: se pasa a 'all' y, una vez cargada, se abre si el id esta en la bandeja.
  const linkedId = params.get('unavailability')
  useEffect(() => {
    if (linkedId && statusFilter !== 'all') setStatusFilter('all')
  }, [linkedId, statusFilter, setStatusFilter])
  useEffect(() => {
    if (loading || !linkedId || statusFilter !== 'all') return
    if (inbox.some((r) => r.unavailability_id === linkedId)) {
      setSelected(linkedId)
      setParams({}, { replace: true })
    }
  }, [loading, inbox, linkedId, statusFilter, setParams])

  if (loading) return <div className="p-6">{t('common.loading')}</div>
  if (error) return <div className="p-6 text-red-600">{t('common.error')}: {error}</div>

  if (selected) {
    return (
      <div className="p-6">
        <IncidentReviewPanel unavailabilityId={selected} onBack={() => { setSelected(null); fetchInbox() }} />
      </div>
    )
  }

  return (
    <div className="p-6">
      <h2 className="text-xl font-bold mb-6">{t('incidents.title')}</h2>
      <div className="mb-4 flex items-center gap-2">
        <label htmlFor="incident-status-filter" className="text-sm text-gray-600">{t('incidents.inbox.status')}</label>
        <select
          id="incident-status-filter"
          value={statusFilter}
          onChange={(e) => setStatusFilter(e.target.value as IncidentStatusFilter)}
          className="border border-gray-300 rounded px-3 py-1.5 text-sm"
        >
          {FILTER_OPTIONS.map((opt) => (
            <option key={opt} value={opt}>
              {opt === 'open' || opt === 'all' ? t('incidents.filter.' + opt) : t('incidents.status.' + opt)}
            </option>
          ))}
        </select>
      </div>
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.panelist')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.node')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.dates')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.created')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.affected')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.breakdown')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.pending')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.status')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.review')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {inbox.length > 0 ? inbox.map((row) => (
                <tr key={row.unavailability_id} className="hover:bg-gray-50">
                  <td className="px-6 py-4 text-sm">
                    <div className="font-medium">{row.panelist_name}</div>
                    <div className="text-gray-500 text-xs font-mono">{row.panelist_code}</div>
                  </td>
                  <td className="px-6 py-4 text-sm">{row.node_label} · {row.city_name}</td>
                  <td className="px-6 py-4 text-sm">{fmt(row.start_date)} – {fmt(row.end_date)}</td>
                  <td className="px-6 py-4 text-sm">{fmt(row.created_at)}</td>
                  <td className="px-6 py-4 text-sm">{row.affected_count}</td>
                  <td className="px-6 py-4 text-sm">{row.origin_count} / {row.destination_count}</td>
                  <td className="px-6 py-4 text-sm">{row.pending_count}</td>
                  <td className="px-6 py-4 text-sm"><IncidentStatusBadge status={row.incident_status} /></td>
                  <td className="px-6 py-4 text-sm">
                    <button onClick={() => setSelected(row.unavailability_id)} className="text-blue-600 hover:text-blue-800">
                      {t('incidents.inbox.review')}
                    </button>
                  </td>
                </tr>
              )) : (
                <tr><td colSpan={9} className="px-6 py-4 text-center text-gray-500">{t('incidents.inbox.empty')}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
