import { useState, useEffect, useCallback } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { useReassignmentProposals } from '@/lib/hooks/useReassignmentProposals'
import type { ReassignmentProposal, RerouteCandidate, ProposalAction, UnavailabilityHeader } from '@/lib/types'

// Motivo de la baja (panelist_unavailability.reason) -> clave i18n existente.
const UNAVAIL_REASON_KEY: Record<string, string> = {
  vacation: 'unavailability.reason_vacation',
  sick_leave: 'unavailability.reason_sick',
  personal: 'unavailability.reason_personal',
  training: 'unavailability.reason_training',
  other: 'unavailability.reason_other',
}

const ACTION_BADGE_CLASS: Record<string, string> = {
  reroute: 'bg-blue-100 text-blue-800',
  shift_date: 'bg-yellow-100 text-yellow-800',
  cancel: 'bg-red-100 text-red-800',
  none: 'bg-gray-100 text-gray-800',
}

const STATUS_BADGE_CLASS: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-800',
  confirmed: 'bg-green-100 text-green-800',
  dismissed: 'bg-gray-100 text-gray-800',
}

export function ProposalReviewPanel({ unavailabilityId, onBack }: { unavailabilityId: string; onBack: () => void }) {
  const { t } = useTranslation()
  const { fetchProposals, confirmProposal, overrideProposal, dismissProposal, confirmMany, dismissMany, listRerouteCandidates, markReviewed, fetchUnavailabilityHeader } = useReassignmentProposals()

  const [proposals, setProposals] = useState<ReassignmentProposal[]>([])
  const [header, setHeader] = useState<UnavailabilityHeader | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())

  const [overrideProposalTarget, setOverrideProposalTarget] = useState<ReassignmentProposal | null>(null)
  const [overrideAction, setOverrideAction] = useState<ProposalAction>('reroute')
  const [overrideNodeId, setOverrideNodeId] = useState('')
  const [overrideDate, setOverrideDate] = useState('')
  const [rerouteCandidates, setRerouteCandidates] = useState<RerouteCandidate[]>([])
  const [candidatesLoading, setCandidatesLoading] = useState(false)

  const loadProposals = useCallback(async () => {
    try {
      setLoading(true); setError(null)
      const data = await fetchProposals(unavailabilityId)
      setProposals(data)
    } catch (err: any) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }, [fetchProposals, unavailabilityId])

  useEffect(() => { loadProposals() }, [loadProposals])

  useEffect(() => {
    let cancelled = false
    fetchUnavailabilityHeader(unavailabilityId)
      .then(h => { if (!cancelled) setHeader(h) })
      .catch(() => { /* la cabecera es informativa; si falla, no bloquea el detalle */ })
    return () => { cancelled = true }
  }, [fetchUnavailabilityHeader, unavailabilityId])

  const pendingProposals = proposals.filter(p => p.status === 'pending')
  const hasPending = pendingProposals.length > 0

  const handleSelectAll = () => {
    if (selectedIds.size === pendingProposals.length) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(pendingProposals.map(p => p.id)))
    }
  }

  const handleSelectOne = (id: string) => {
    const next = new Set(selectedIds)
    if (next.has(id)) next.delete(id); else next.add(id)
    setSelectedIds(next)
  }

  const pruneSelected = (ids: string[]) => {
    setSelectedIds(prev => {
      if (ids.every(id => !prev.has(id))) return prev
      const next = new Set(prev)
      for (const id of ids) next.delete(id)
      return next
    })
  }

  const handleConfirm = async (p: ReassignmentProposal) => {
    try {
      await confirmProposal(p)
      pruneSelected([p.id])
      await loadProposals()
    } catch (err: any) {
      alert(err.message)
    }
  }

  const handleDismiss = async (id: string) => {
    try {
      await dismissProposal(id)
      pruneSelected([id])
      await loadProposals()
    } catch (err: any) {
      alert(err.message)
    }
  }

  const handleConfirmSelected = async () => {
    try {
      await confirmMany(proposals.filter(p => selectedIds.has(p.id)))
      setSelectedIds(new Set())
      await loadProposals()
    } catch (err: any) {
      alert(err.message)
    }
  }

  const handleDismissSelected = async () => {
    try {
      await dismissMany([...selectedIds])
      setSelectedIds(new Set())
      await loadProposals()
    } catch (err: any) {
      alert(err.message)
    }
  }

  const openOverrideModal = (p: ReassignmentProposal) => {
    setOverrideProposalTarget(p)
    setOverrideAction('reroute')
    setOverrideNodeId('')
    setOverrideDate('')
    setRerouteCandidates([])
  }

  const closeOverrideModal = () => {
    setOverrideProposalTarget(null)
    setRerouteCandidates([])
  }

  useEffect(() => {
    if (!overrideProposalTarget || overrideAction !== 'reroute') return
    let cancelled = false
    setCandidatesLoading(true)
    listRerouteCandidates(overrideProposalTarget.allocation_plan_detail_id, overrideProposalTarget.affected_role)
      .then(candidates => { if (!cancelled) setRerouteCandidates(candidates) })
      .catch((err: any) => { if (!cancelled) alert(err.message) })
      .finally(() => { if (!cancelled) setCandidatesLoading(false) })
    return () => { cancelled = true }
  }, [overrideProposalTarget, overrideAction, listRerouteCandidates])

  const handleApplyOverride = async () => {
    if (!overrideProposalTarget) return
    try {
      if (overrideAction === 'reroute') {
        await overrideProposal(overrideProposalTarget.id, 'reroute', overrideNodeId || null, null)
      } else if (overrideAction === 'shift_date') {
        await overrideProposal(overrideProposalTarget.id, 'shift_date', null, overrideDate || null)
      } else {
        await overrideProposal(overrideProposalTarget.id, 'cancel')
      }
      pruneSelected([overrideProposalTarget.id])
      closeOverrideModal()
      await loadProposals()
    } catch (err: any) {
      alert(err.message)
    }
  }

  const handleMarkReviewed = async () => {
    try {
      await markReviewed(unavailabilityId)
      onBack()
    } catch (err: any) {
      alert(err.message)
    }
  }

  if (loading) return <div className="p-6">{t('common.loading')}</div>
  if (error) return <div className="p-6 text-red-600">{t('common.error')}: {error}</div>

  return (
    <div>
      <div className="flex justify-between items-center mb-6">
        <button onClick={onBack} className="text-blue-600 hover:text-blue-800">← {t('incidents.detail.back')}</button>
        <button
          onClick={handleMarkReviewed}
          disabled={hasPending}
          title={hasPending ? t('incidents.detail.mark_reviewed_disabled') : undefined}
          className="bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {t('incidents.detail.mark_reviewed')}
        </button>
      </div>

      {header && (
        <div className="bg-white rounded-lg shadow p-4 mb-6 grid grid-cols-1 md:grid-cols-3 gap-4">
          <div>
            <div className="text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.panelist')}</div>
            <div className="text-sm font-medium">{header.panelist_name}</div>
            <div className="text-xs text-gray-500 font-mono">{header.panelist_code}</div>
          </div>
          <div>
            <div className="text-xs font-medium text-gray-500 uppercase">{t('incidents.inbox.dates')}</div>
            <div className="text-sm">{header.start_date} – {header.end_date}</div>
          </div>
          <div>
            <div className="text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.cause')}</div>
            <div className="text-sm">
              {header.reason ? t(UNAVAIL_REASON_KEY[header.reason] ?? '', undefined, header.reason) : '-'}
            </div>
          </div>
        </div>
      )}

      {selectedIds.size > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6 flex items-center justify-between">
          <span className="text-sm font-medium text-blue-900">
            {t('incidents.action.selected_count', { count: selectedIds.size })}
          </span>
          <div className="flex gap-2">
            <button
              onClick={handleConfirmSelected}
              className="px-3 py-1 bg-green-600 text-white text-sm rounded hover:bg-green-700"
            >
              {t('incidents.action.confirm_selected')}
            </button>
            <button
              onClick={handleDismissSelected}
              className="px-3 py-1 bg-red-600 text-white text-sm rounded hover:bg-red-700"
            >
              {t('incidents.action.dismiss_selected')}
            </button>
            <button
              onClick={() => setSelectedIds(new Set())}
              className="px-3 py-1 bg-gray-200 text-gray-700 text-sm rounded hover:bg-gray-300"
            >
              {t('incidents.override.cancel')}
            </button>
          </div>
        </div>
      )}

      <div className="bg-white rounded-lg shadow overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className="px-6 py-3 text-left">
                  <input
                    type="checkbox"
                    checked={selectedIds.size === pendingProposals.length && pendingProposals.length > 0}
                    onChange={handleSelectAll}
                    className="rounded"
                  />
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.sample')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.role')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.sample_status')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.suggested_action')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.suggestion')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.reason')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.proposal_status')}</th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('incidents.detail.actions')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {pendingProposals.length > 0 ? (
                pendingProposals.map((p) => {
                  const sampleLabel = p.detail?.fecha_programada
                    ? `${p.detail.fecha_programada} (${p.allocation_plan_detail_id.slice(0, 8)})`
                    : p.allocation_plan_detail_id.slice(0, 8)
                  const suggestion = p.suggested_action === 'reroute'
                    ? (p.suggested_target_node?.auto_id ?? '-')
                    : p.suggested_action === 'shift_date'
                      ? (p.suggested_date ?? '-')
                      : '-'

                  return (
                    <tr key={p.id} className="hover:bg-gray-50">
                      <td className="px-6 py-4">
                        <input
                          type="checkbox"
                          checked={selectedIds.has(p.id)}
                          onChange={() => handleSelectOne(p.id)}
                          className="rounded"
                        />
                      </td>
                      <td className="px-6 py-4 text-sm">{sampleLabel}</td>
                      <td className="px-6 py-4 text-sm">
                        {p.affected_role === 'origin' ? t('incidents.detail.role_origin') : t('incidents.detail.role_destination')}
                      </td>
                      <td className="px-6 py-4 text-sm">{p.sample_status_at_detection ?? '-'}</td>
                      <td className="px-6 py-4">
                        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${ACTION_BADGE_CLASS[p.suggested_action] ?? ACTION_BADGE_CLASS.none}`}>
                          {t(`incidents.act.${p.suggested_action}`)}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-sm">{suggestion}</td>
                      <td className="px-6 py-4 text-sm">
                        {p.suggested_reason ? t(`incidents.reason.${p.suggested_reason}`, undefined, p.suggested_reason) : '-'}
                      </td>
                      <td className="px-6 py-4">
                        <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${STATUS_BADGE_CLASS[p.status]}`}>
                          {t(`incidents.status.${p.status}`)}
                        </span>
                      </td>
                      <td className="px-6 py-4 text-sm">
                        <div className="flex gap-2">
                          <button onClick={() => handleConfirm(p)} className="text-green-600 hover:text-green-800">
                            {t('incidents.action.confirm')}
                          </button>
                          <button onClick={() => openOverrideModal(p)} className="text-blue-600 hover:text-blue-800">
                            {t('incidents.action.change')}
                          </button>
                          <button onClick={() => handleDismiss(p.id)} className="text-red-600 hover:text-red-800">
                            {t('incidents.action.dismiss')}
                          </button>
                        </div>
                      </td>
                    </tr>
                  )
                })
              ) : (
                <tr>
                  <td colSpan={9} className="px-6 py-4 text-center text-gray-500">
                    {t('incidents.inbox.empty')}
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>

      {overrideProposalTarget && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg w-full max-w-md max-h-[90vh] flex flex-col">
            <div className="p-6 border-b">
              <h2 className="text-xl font-bold">{t('incidents.override.title')}</h2>
            </div>
            <div className="flex-1 overflow-y-auto p-6 space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t('incidents.override.choose_action')}
                </label>
                <select
                  value={overrideAction}
                  onChange={(e) => setOverrideAction(e.target.value as ProposalAction)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                >
                  <option value="reroute">{t('incidents.override.reroute')}</option>
                  <option value="shift_date">{t('incidents.override.shift_date')}</option>
                  <option value="cancel">{t('incidents.override.cancel_sample')}</option>
                </select>
              </div>

              {overrideAction === 'reroute' && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    {t('incidents.override.target_node')}
                  </label>
                  <select
                    value={overrideNodeId}
                    onChange={(e) => setOverrideNodeId(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                    disabled={candidatesLoading}
                  >
                    <option value="">{candidatesLoading ? t('common.loading') : ''}</option>
                    {rerouteCandidates.map((c) => (
                      <option key={c.node_id} value={c.node_id}>
                        {c.node_name}{!c.is_available ? ` ${t('incidents.override.node_unavailable')}` : ''}
                      </option>
                    ))}
                  </select>
                </div>
              )}

              {overrideAction === 'shift_date' && (
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">
                    {t('incidents.override.new_date')}
                  </label>
                  <input
                    type="date"
                    value={overrideDate}
                    onChange={(e) => setOverrideDate(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg"
                  />
                </div>
              )}
            </div>
            <div className="border-t p-6 flex gap-2">
              <button
                onClick={handleApplyOverride}
                disabled={
                  (overrideAction === 'reroute' && !overrideNodeId) ||
                  (overrideAction === 'shift_date' && !overrideDate)
                }
                className="flex-1 bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {t('incidents.override.apply')}
              </button>
              <button
                onClick={closeOverrideModal}
                className="flex-1 bg-gray-200 text-gray-700 px-4 py-2 rounded-lg hover:bg-gray-300"
              >
                {t('incidents.override.cancel')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
