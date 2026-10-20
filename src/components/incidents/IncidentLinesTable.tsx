import type { DragEvent } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { fmtDay, fmtDateTime, sampleLabel, planLabel, planTitle } from '@/lib/incidentFormat'
import type { ReassignmentProposal } from '@/lib/types'

const LINE_STATUS_CLASS: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-800',
  auto_resolved: 'bg-green-100 text-green-800',
  manager_resolved: 'bg-blue-100 text-blue-800',
  info: 'bg-gray-100 text-gray-800',
  dismissed: 'bg-gray-100 text-gray-500',
}

// Fecha original de la muestra: si ya se movio, la previa al cambio.
const originalDate = (l: ReassignmentProposal) =>
  l.detail?.original_fecha_programada ?? l.detail?.fecha_programada ?? null

interface Props {
  lines: ReassignmentProposal[]
  selectedIds: Set<string>
  onToggle: (id: string) => void
  onToggleAll: (ids: string[]) => void
  onAccept: (line: ReassignmentProposal) => void
  onCancel: (line: ReassignmentProposal) => void
  busyId: string | null
  // Arrastrar una linea pendiente a una casilla del balance de la ciudad.
  onDragStartLine: (e: DragEvent, line: ReassignmentProposal) => void
  onDragEnd: () => void
  draggingLineId: string | null
  // Mensaje para el bloque de pendientes vacio (p. ej. filtro de semana activo).
  pendingEmptyText: string
}

export function IncidentLinesTable({
  lines, selectedIds, onToggle, onToggleAll, onAccept, onCancel, busyId, onDragStartLine, onDragEnd,
  draggingLineId, pendingEmptyText,
}: Props) {
  const { t } = useTranslation()
  const pending = lines.filter(l => l.status === 'pending')
  const resolved = lines.filter(l => l.status !== 'pending')
  const busy = busyId !== null
  const allSelected = pending.length > 0 && pending.every(l => selectedIds.has(l.id))

  const roleLabel = (l: ReassignmentProposal) =>
    l.affected_role === 'origin' ? t('incidents.detail.role_origin') : t('incidents.detail.role_destination')
  const reasonLabel = (code: string | null) =>
    code ? t(`incidents.reason.${code}`, undefined, code) : null

  // Solo se arrastran lineas cuya muestra sigue pendiente o notificada.
  const canDrag = (l: ReassignmentProposal) =>
    !busy && (l.detail?.status === 'pending' || l.detail?.status === 'notified')

  const th = 'px-4 py-3 text-start text-xs font-medium text-gray-500 uppercase'
  const td = 'px-4 py-3 text-sm align-top'

  const proposalCell = (l: ReassignmentProposal) => {
    const reason = reasonLabel(l.suggested_reason)
    let what: string
    if (l.suggested_action === 'cancel') what = t('incidents.proposal.cancel')
    else if (l.suggested_action === 'none') what = '-'
    else {
      const parts: string[] = []
      if (l.suggested_date) parts.push(`${t('incidents.detail.new_date')}: ${fmtDay(l.suggested_date)}`)
      if (l.suggested_target_node?.auto_id) parts.push(`${t('incidents.detail.new_node')}: ${l.suggested_target_node.auto_id}`)
      what = parts.length > 0 ? parts.join(' · ') : '-'
    }
    return (
      <>
        <div>{what}</div>
        {reason && <div className="text-xs text-gray-500">{reason}</div>}
      </>
    )
  }

  const doneCell = (l: ReassignmentProposal) => {
    if (l.status === 'info') {
      return (
        <>
          <div>{t('incidents.detail.info_line')}</div>
          {reasonLabel(l.suggested_reason) && <div className="text-xs text-gray-500">{reasonLabel(l.suggested_reason)}</div>}
        </>
      )
    }
    if (l.status === 'dismissed') {
      return l.resolution_note === 'unavailability_cancelled'
        ? <div>{t('incidents.resolution.unavailability_cancelled')}</div>
        : <div>{t('incidents.line_status.dismissed')}</div>
    }
    const parts: string[] = []
    if (l.final_action) parts.push(t(`incidents.final_action.${l.final_action}`, undefined, l.final_action))
    if (l.final_date && l.final_action !== 'cancel') parts.push(`${t('incidents.detail.new_date')}: ${fmtDay(l.final_date)}`)
    if (l.final_target_node?.auto_id && l.final_action !== 'cancel') parts.push(`${t('incidents.detail.new_node')}: ${l.final_target_node.auto_id}`)
    return <div>{parts.length > 0 ? parts.join(' · ') : '-'}</div>
  }

  const doneBy = (l: ReassignmentProposal) => {
    if (l.status === 'auto_resolved' || l.status === 'info') return t('incidents.detail.resolved_by_system')
    if (l.status === 'manager_resolved') return t('incidents.detail.resolved_by_manager')
    return '-'
  }

  return (
    <div className="space-y-6">
      <section className="bg-white rounded-lg shadow overflow-hidden">
        <h3 className="px-4 py-3 text-sm font-semibold text-gray-900 border-b">
          {t('incidents.detail.pending_lines')} ({pending.length})
        </h3>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className={th}>
                  <input
                    type="checkbox"
                    aria-label={t('incidents.action.selected_count', { count: selectedIds.size })}
                    checked={allSelected}
                    disabled={pending.length === 0 || busy}
                    onChange={() => onToggleAll(pending.map(l => l.id))}
                    className="rounded"
                  />
                </th>
                <th className={th}>{t('incidents.detail.sample')}</th>
                <th className={th}>{t('incidents.detail.carrier_product')}</th>
                <th className={th}>{t('incidents.detail.role')}</th>
                <th className={th}>{t('incidents.detail.original_date')}</th>
                <th className={th}>{t('incidents.detail.system_proposal')}</th>
                <th className={th}>{t('incidents.detail.actions')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {pending.length > 0 ? pending.map(l => (
                <tr
                  key={l.id}
                  draggable={canDrag(l)}
                  onDragStart={e => { if (canDrag(l)) onDragStartLine(e, l); else e.preventDefault() }}
                  onDragEnd={onDragEnd}
                  title={canDrag(l) ? t('incidents.detail.drag_hint') : undefined}
                  className={draggingLineId === l.id ? 'bg-blue-50 opacity-60' : `hover:bg-gray-50 ${canDrag(l) ? 'cursor-grab' : ''}`}
                >
                  <td className={td}>
                    <input
                      type="checkbox"
                      aria-label={sampleLabel(l)}
                      checked={selectedIds.has(l.id)}
                      disabled={busy}
                      onChange={() => onToggle(l.id)}
                      className="rounded"
                    />
                  </td>
                  <td className={`${td} font-mono whitespace-nowrap`}>
                    {canDrag(l) && <span className="me-1 text-gray-400" aria-hidden="true">⠿</span>}
                    {sampleLabel(l)}
                  </td>
                  <td className={`${td} whitespace-nowrap`} title={planTitle(l.detail?.plan)}>{planLabel(l.detail?.plan)}</td>
                  <td className={td}>{roleLabel(l)}</td>
                  <td className={td}>{fmtDay(originalDate(l))}</td>
                  <td className={td}>{proposalCell(l)}</td>
                  <td className={td}>
                    <div className="flex flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => onAccept(l)}
                        disabled={busy || l.suggested_action === 'none'}
                        className="text-green-700 hover:text-green-900 disabled:opacity-40 disabled:cursor-not-allowed"
                      >
                        {t('incidents.action.confirm_line')}
                      </button>
                      <button
                        type="button"
                        onClick={() => onCancel(l)}
                        disabled={busy}
                        className="text-red-600 hover:text-red-800 disabled:opacity-40 disabled:cursor-not-allowed"
                      >
                        {t('incidents.action.void_line')}
                      </button>
                    </div>
                    {busyId === l.id && <div className="text-xs text-gray-500 mt-1">{t('common.loading')}</div>}
                  </td>
                </tr>
              )) : (
                <tr><td colSpan={7} className="px-4 py-4 text-center text-sm text-gray-500">{pendingEmptyText}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </section>

      <section className="bg-white rounded-lg shadow overflow-hidden">
        <h3 className="px-4 py-3 text-sm font-semibold text-gray-900 border-b">
          {t('incidents.detail.resolved_lines')} ({resolved.length})
        </h3>
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className={th}>{t('incidents.inbox.status')}</th>
                <th className={th}>{t('incidents.detail.sample')}</th>
                <th className={th}>{t('incidents.detail.carrier_product')}</th>
                <th className={th}>{t('incidents.detail.role')}</th>
                <th className={th}>{t('incidents.detail.original_date')}</th>
                <th className={th}>{t('incidents.detail.done')}</th>
                <th className={th}>{t('incidents.detail.done_by')}</th>
                <th className={th}>{t('incidents.detail.done_at')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {resolved.length > 0 ? resolved.map(l => (
                <tr key={l.id}>
                  <td className={td}>
                    <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${LINE_STATUS_CLASS[l.status] ?? LINE_STATUS_CLASS.info}`}>
                      {t(`incidents.line_status.${l.status}`)}
                    </span>
                  </td>
                  <td className={`${td} font-mono whitespace-nowrap`}>{sampleLabel(l)}</td>
                  <td className={`${td} whitespace-nowrap`} title={planTitle(l.detail?.plan)}>{planLabel(l.detail?.plan)}</td>
                  <td className={td}>{roleLabel(l)}</td>
                  <td className={td}>{fmtDay(originalDate(l))}</td>
                  <td className={td}>{doneCell(l)}</td>
                  <td className={td}>{doneBy(l)}</td>
                  <td className={`${td} whitespace-nowrap`}>{fmtDateTime(l.applied_at ?? l.confirmed_at ?? l.updated_at)}</td>
                </tr>
              )) : (
                <tr><td colSpan={8} className="px-4 py-4 text-center text-sm text-gray-500">{t('incidents.detail.no_resolved')}</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  )
}
