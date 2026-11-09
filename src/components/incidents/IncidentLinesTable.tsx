import { useTranslation } from '@/hooks/useTranslation'
import { fmtDay, fmtDateTime, sampleLabel, planTitle } from '@/lib/incidentFormat'
import type { ReassignmentProposal } from '@/lib/types'

// Fecha original de la muestra: si ya se movio, la previa al cambio.
const originalDate = (l: ReassignmentProposal) =>
  l.detail?.original_fecha_programada ?? l.detail?.fecha_programada ?? null

// Motivos de una linea informativa con texto propio en la columna «resultado».
const INFO_REASONS = new Set(['already_sent', 'in_transit', 'back_before_arrival', 'handled_by_other_incident', 'engine_error'])

interface Props {
  lines: ReassignmentProposal[]
  // Mensaje cuando no hay lineas que mostrar (p. ej. filtro de semana activo).
  emptyText: string
}

// Tabla informativa con todas las lineas de una baja: el motor ya las ha resuelto todas.
// No hay acciones por linea; las correcciones se hacen arrastrando la muestra en el balance.
export function IncidentLinesTable({ lines, emptyText }: Props) {
  const { t } = useTranslation()

  const roleLabel = (l: ReassignmentProposal) =>
    l.affected_role === 'origin' ? t('incidents.detail.role_origin') : t('incidents.detail.role_destination')

  // Que se hizo con la muestra (auto_resolved / manager_resolved).
  const actionText = (l: ReassignmentProposal, manual: boolean): string => {
    const node = l.final_target_node?.auto_id ?? null
    const date = l.final_date ? fmtDay(l.final_date) : null
    if (l.final_action === 'cancel') {
      // La anulacion automatica es siempre por falta de hueco; la manual no tiene por que.
      return manual ? t('incidents.final_action.cancel') : t('incidents.result.cancel')
    }
    if (l.final_action === 'reroute' || (l.final_action !== 'shift_date' && node)) {
      return date
        ? t('incidents.result.reroute_on', { node: node ?? '-', date })
        : t('incidents.result.reroute', { node: node ?? '-' })
    }
    if (l.final_action === 'shift_date' || date) {
      return t('incidents.result.shift_date', { date: date ?? '-' })
    }
    return l.final_action ? t(`incidents.final_action.${l.final_action}`, undefined, l.final_action) : '-'
  }

  const resultCell = (l: ReassignmentProposal) => {
    if (l.status === 'pending') {
      // Solo en datos antiguos: el motor ya no deja lineas pendientes.
      return <span className="text-yellow-800">{t('incidents.result.pending')}</span>
    }
    if (l.status === 'info') {
      const code = l.suggested_reason
      const text = code && INFO_REASONS.has(code)
        ? t(`incidents.result.info.${code}`)
        : t('incidents.result.info.other')
      return (
        <>
          <div className={code === 'engine_error' ? 'text-red-700' : undefined}>{text}</div>
          {code === 'engine_error' && l.resolution_note && (
            <div className="text-xs text-gray-500 break-words">{l.resolution_note}</div>
          )}
        </>
      )
    }
    if (l.status === 'dismissed') {
      return l.resolution_note === 'unavailability_cancelled'
        ? <div>{t('incidents.resolution.unavailability_cancelled')}</div>
        : <div>{t('incidents.line_status.dismissed')}</div>
    }
    const manual = l.status === 'manager_resolved'
    return (
      <div>
        {actionText(l, manual)}
        {manual && <span className="ms-1 text-gray-500">{t('incidents.result.manual_suffix')}</span>}
      </div>
    )
  }

  const whenCell = (l: ReassignmentProposal) =>
    l.status === 'pending' ? '-' : fmtDateTime(l.applied_at ?? l.confirmed_at ?? l.updated_at)

  const th = 'px-4 py-3 text-start text-xs font-medium text-gray-500 uppercase'
  const td = 'px-4 py-3 text-sm align-top'

  return (
    <section className="bg-white rounded-lg shadow overflow-hidden mb-6">
      <h3 className="px-4 py-3 text-sm font-semibold text-gray-900 border-b">
        {t('incidents.detail.lines')} ({lines.length})
      </h3>
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b">
            <tr>
              <th className={th}>{t('incidents.detail.sample')}</th>
              <th className={th}>{t('incidents.detail.role')}</th>
              <th className={th}>{t('incidents.detail.original_date')}</th>
              <th className={th}>{t('incidents.detail.result')}</th>
              <th className={th}>{t('incidents.detail.done_at')}</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {lines.length > 0 ? lines.map(l => (
              <tr key={l.id} className="hover:bg-gray-50">
                <td className={`${td} font-mono whitespace-nowrap`} title={planTitle(l.detail?.plan)}>{sampleLabel(l)}</td>
                <td className={td}>{roleLabel(l)}</td>
                <td className={`${td} whitespace-nowrap`}>{fmtDay(originalDate(l))}</td>
                <td className={td}>{resultCell(l)}</td>
                <td className={`${td} whitespace-nowrap`}>{whenCell(l)}</td>
              </tr>
            )) : (
              <tr><td colSpan={5} className="px-4 py-4 text-center text-sm text-gray-500">{emptyText}</td></tr>
            )}
          </tbody>
        </table>
      </div>
    </section>
  )
}
