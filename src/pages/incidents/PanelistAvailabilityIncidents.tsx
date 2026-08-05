import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { useReassignmentProposals } from '@/lib/hooks/useReassignmentProposals'
import { ProposalReviewPanel } from '@/components/incidents/ProposalReviewPanel'

export function PanelistAvailabilityIncidents() {
  const { t } = useTranslation()
  const { inbox, loading, error, fetchInbox } = useReassignmentProposals()
  const [selected, setSelected] = useState<string | null>(null)

  if (loading) return <div className="p-6">Loading...</div>
  if (error) return <div className="p-6 text-red-600">Error: {error}</div>

  if (selected) {
    return (
      <div className="p-6">
        <ProposalReviewPanel unavailabilityId={selected} onBack={() => { setSelected(null); fetchInbox() }} />
      </div>
    )
  }

  return (
    <div className="p-6">
      <h2 className="text-xl font-bold mb-6">{t('incidents.title')}</h2>
      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.panelist')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.node')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.dates')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.affected')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.breakdown')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.pending')}</th>
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
                  <td className="px-6 py-4 text-sm">{row.start_date} – {row.end_date}</td>
                  <td className="px-6 py-4 text-sm">{row.affected_count}</td>
                  <td className="px-6 py-4 text-sm">{row.origin_count} / {row.destination_count}</td>
                  <td className="px-6 py-4 text-sm">{row.pending_count}</td>
                  <td className="px-6 py-4 text-sm">
                    <button onClick={() => setSelected(row.unavailability_id)} className="text-blue-600 hover:text-blue-800">
                      {t('incidents.inbox.review')}
                    </button>
                  </td>
                </tr>
              )) : (
                <tr><td colSpan={7} className="px-6 py-4 text-center text-gray-500">{t('incidents.inbox.empty')}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
