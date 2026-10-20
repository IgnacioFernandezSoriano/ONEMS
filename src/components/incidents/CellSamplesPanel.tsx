import type { DragEvent } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { fmtDay, fmtWeekRange, nodesLabel, planLabel, planTitle } from '@/lib/incidentFormat'
import type { CellSample, MoveDragPayload } from '@/lib/types'

interface Props {
  nodeId: string
  nodeCode: string
  weekStart: string
  samples: CellSample[]
  loading: boolean
  error: string | null
  // Incidencia abierta: sus lineas pendientes se mueven con el par de RPC de linea.
  unavailabilityId: string
  busy: boolean
  draggingDetailId: string | null
  onDragStart: (e: DragEvent, payload: MoveDragPayload) => void
  onDragEnd: () => void
  onClose: () => void
}

const SAMPLE_STATUS_CLASS: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-800',
  notified: 'bg-blue-100 text-blue-800',
  sent: 'bg-green-100 text-green-800',
  received: 'bg-gray-100 text-gray-700',
}

// Muestras no canceladas de una casilla (nodo x semana). Las que se pueden mover son
// arrastrables a otra casilla del balance; las demas muestran el motivo.
export function CellSamplesPanel({
  nodeId, nodeCode, weekStart, samples, loading, error, unavailabilityId, busy, draggingDetailId,
  onDragStart, onDragEnd, onClose,
}: Props) {
  const { t } = useTranslation()
  const th = 'px-3 py-2 text-start text-xs font-medium text-gray-500 uppercase'
  const td = 'px-3 py-2 text-sm align-top'

  // Como se arrastra cada muestra (o por que no).
  const dragInfo = (s: CellSample): { payload: MoveDragPayload | null; reason: string | null; thisIncident: boolean; otherIncident: boolean } => {
    const pendingLines = (s.lines ?? []).filter(l => l.status === 'pending')
    const own = pendingLines.find(l => l.unavailability_id === unavailabilityId) ?? null
    const other = pendingLines.some(l => l.unavailability_id !== unavailabilityId)
    const sends = s.origin_node_id === nodeId
    const otherEnd = sends ? s.destination_node_id : s.origin_node_id
    const label = nodesLabel(s.origin_node?.auto_id, s.destination_node?.auto_id)
    const base = { detailId: s.id, fromNodeId: nodeId, otherEndNodeId: otherEnd, fecha: s.fecha_programada, label, plan: s.plan ?? null }
    const movable = s.status === 'pending' || s.status === 'notified'
    if (!movable) return { payload: null, reason: t('incidents.move_reason.sample_not_movable'), thisIncident: !!own, otherIncident: other }
    if (other) return { payload: null, reason: t('incidents.move_reason.has_incident_line'), thisIncident: !!own, otherIncident: true }
    if (own) {
      // Solo desde la casilla del nodo afectado de la linea (el otro extremo no se mueve con ella).
      const affectedNode = own.affected_role === 'origin' ? s.origin_node_id : s.destination_node_id
      if (affectedNode !== nodeId) return { payload: null, reason: t('incidents.move_reason.has_incident_line'), thisIncident: true, otherIncident: false }
      return { payload: { kind: 'line', lineId: own.id, ...base }, reason: null, thisIncident: true, otherIncident: false }
    }
    return { payload: { kind: 'sample', ...base }, reason: null, thisIncident: false, otherIncident: false }
  }

  return (
    <section className="bg-white rounded-lg shadow mb-6" aria-labelledby="cell-samples-title">
      <div className="px-4 py-3 border-b flex items-center justify-between gap-3">
        <h3 id="cell-samples-title" className="text-sm font-semibold text-gray-900">
          {t('incidents.cell.title', { node: nodeCode, week: fmtWeekRange(weekStart) })}
        </h3>
        <button
          type="button"
          onClick={onClose}
          aria-label={t('common.close')}
          className="text-gray-500 hover:text-gray-800"
        >
          ✕
        </button>
      </div>
      {error ? (
        <div className="px-4 py-3 text-sm text-red-600">{t('common.error')}: {error}</div>
      ) : loading && samples.length === 0 ? (
        <div className="px-4 py-3 text-sm text-gray-500">{t('common.loading')}</div>
      ) : samples.length === 0 ? (
        <div className="px-4 py-3 text-sm text-gray-500">{t('incidents.cell.empty')}</div>
      ) : (
        <div className={`overflow-x-auto ${loading ? 'opacity-60' : ''}`}>
          <p className="px-4 pt-3 text-xs text-gray-500">{t('incidents.cell.drag_hint')}</p>
          <table className="w-full">
            <thead className="bg-gray-50 border-b">
              <tr>
                <th className={th}><span className="sr-only">{t('incidents.cell.drag')}</span></th>
                <th className={th}>{t('incidents.cell.date')}</th>
                <th className={th}>{t('incidents.detail.sample')}</th>
                <th className={th}>{t('incidents.detail.carrier_product')}</th>
                <th className={th}>{t('incidents.detail.role')}</th>
                <th className={th}>{t('incidents.inbox.status')}</th>
                <th className={th}>{t('incidents.cell.incident')}</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-200">
              {samples.map(s => {
                const info = dragInfo(s)
                const canDrag = !!info.payload && !busy
                const sends = s.origin_node_id === nodeId
                return (
                  <tr
                    key={s.id}
                    draggable={canDrag}
                    onDragStart={e => { if (info.payload && !busy) onDragStart(e, info.payload); else e.preventDefault() }}
                    onDragEnd={onDragEnd}
                    title={info.reason ?? t('incidents.cell.drag_hint')}
                    className={`${canDrag ? 'cursor-grab hover:bg-gray-50' : 'text-gray-500'} ${draggingDetailId === s.id ? 'bg-blue-50 opacity-60' : ''} ${info.thisIncident ? 'bg-amber-50' : ''}`}
                  >
                    <td className={`${td} w-6 text-gray-400`} aria-hidden="true">{canDrag ? '⠿' : ''}</td>
                    <td className={`${td} whitespace-nowrap`}>{fmtDay(s.fecha_programada)}</td>
                    <td className={`${td} font-mono whitespace-nowrap`}>{nodesLabel(s.origin_node?.auto_id, s.destination_node?.auto_id)}</td>
                    <td className={`${td} whitespace-nowrap`} title={planTitle(s.plan)}>{planLabel(s.plan)}</td>
                    <td className={td}>{sends ? t('incidents.cell.role_sends') : t('incidents.cell.role_receives')}</td>
                    <td className={td}>
                      <span className={`inline-flex px-2 py-0.5 text-xs font-semibold rounded-full ${SAMPLE_STATUS_CLASS[s.status] ?? 'bg-gray-100 text-gray-700'}`}>
                        {t(`allocation_plans.${s.status}`, undefined, s.status)}
                      </span>
                    </td>
                    <td className={td}>
                      {info.thisIncident && (
                        <span className="inline-flex px-2 py-0.5 text-xs font-semibold rounded-full bg-amber-100 text-amber-800">
                          {t('incidents.cell.this_incident')}
                        </span>
                      )}
                      {info.otherIncident && (
                        <span className="inline-flex px-2 py-0.5 text-xs font-semibold rounded-full bg-purple-100 text-purple-800">
                          {t('incidents.cell.other_incident')}
                        </span>
                      )}
                      {info.reason && <div className="text-xs text-gray-500 mt-1">{info.reason}</div>}
                    </td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  )
}
