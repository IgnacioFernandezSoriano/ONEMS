import { useState, useMemo } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { useReportedIncidents } from '@/lib/hooks/useReportedIncidents'
import { ReportedIncidentPanel } from '@/components/incidents/ReportedIncidentPanel'
import type { ReportedIncidentCategory, ReportedIncidentStatus } from '@/lib/types'

const CATEGORIES: ReportedIncidentCategory[] = [
  'missing_materials', 'unreadable_label_receipt', 'parcel_damaged', 'parcel_returned',
  'how_to_send', 'unavailability_request', 'tag_photo_problem', 'contact_data_change', 'other']

export function PanelistReportedIncidents() {
  const { t } = useTranslation()
  const { inbox, loading, error, fetchInbox } = useReportedIncidents()
  const [selected, setSelected] = useState<string | null>(null)
  const [catFilter, setCatFilter] = useState<ReportedIncidentCategory | 'all'>('all')
  const [statusFilter, setStatusFilter] = useState<ReportedIncidentStatus | 'open_active'>('open_active')

  const rows = useMemo(() => inbox.filter(r =>
    (catFilter === 'all' || r.category === catFilter) &&
    (statusFilter === 'open_active' ? (r.status === 'open' || r.status === 'in_progress') : r.status === statusFilter)
  ), [inbox, catFilter, statusFilter])

  if (loading) return <div className="p-6">{t('common.loading')}</div>
  if (error) return <div className="p-6 text-red-600">{t('common.error')}: {error}</div>
  if (selected) return (
    <div className="p-6">
      <ReportedIncidentPanel incidentId={selected} onBack={() => { setSelected(null); fetchInbox() }} />
    </div>
  )

  return (
    <div className="p-6">
      <h2 className="text-xl font-bold mb-4">{t('reported_incidents.title')}</h2>
      <div className="flex gap-3 mb-4">
        <select className="border rounded px-2 py-1 text-sm" value={catFilter} onChange={e => setCatFilter(e.target.value as ReportedIncidentCategory | 'all')}>
          <option value="all">{t('reported_incidents.filter.all_categories')}</option>
          {CATEGORIES.map(c => <option key={c} value={c}>{t(`reported_incidents.category.${c}`)}</option>)}
        </select>
        <select className="border rounded px-2 py-1 text-sm" value={statusFilter} onChange={e => setStatusFilter(e.target.value as ReportedIncidentStatus | 'open_active')}>
          <option value="open_active">{t('reported_incidents.filter.open_active')}</option>
          <option value="resolved">{t('reported_incidents.status.resolved')}</option>
          <option value="dismissed">{t('reported_incidents.status.dismissed')}</option>
        </select>
      </div>
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('reported_incidents.col.panelist')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('reported_incidents.col.category')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('reported_incidents.col.status')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('reported_incidents.col.reported_at')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase"></th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {rows.length > 0 ? rows.map(r => (
                <tr key={r.id} className="hover:bg-gray-50">
                  <td className="px-6 py-4 text-sm"><div className="font-medium">{r.panelist_name}</div><div className="text-gray-500 text-xs font-mono">{r.panelist_code}</div></td>
                  <td className="px-6 py-4 text-sm">{t(`reported_incidents.category.${r.category}`)}</td>
                  <td className="px-6 py-4 text-sm">{t(`reported_incidents.status.${r.status}`)}</td>
                  <td className="px-6 py-4 text-sm">{r.reported_at?.slice(0, 10)}</td>
                  <td className="px-6 py-4 text-sm"><button onClick={() => setSelected(r.id)} className="text-blue-600 hover:text-blue-800">{t('reported_incidents.open')}</button></td>
                </tr>
              )) : (
                <tr><td colSpan={5} className="px-6 py-4 text-center text-gray-500">{t('reported_incidents.empty')}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
