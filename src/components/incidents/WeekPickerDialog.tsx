import { useEffect, useRef, useState } from 'react'
import { parseISO, getISOWeek } from 'date-fns'
import { useTranslation } from '@/hooks/useTranslation'
import { fmtDay, fmtWeekRange, sampleLabel, toMonday, SATURATION_BADGE_CLASS } from '@/lib/incidentFormat'
import type { ReassignmentProposal, WeekSuggestion } from '@/lib/types'

interface Props {
  line: ReassignmentProposal
  weekStart: string | null
  suggestion: WeekSuggestion | null
  loading: boolean
  busy: boolean
  onPickWeek: (monday: string) => void
  onConfirm: () => void
  onClose: () => void
}

// Panel flotante NO bloqueante: el manager tiene que poder pulsar la cabecera de una
// semana en el panel de carga mientras esta abierto, por eso no hay fondo modal
// (aria-modal="false"). Escape (con el foco dentro) lo cierra; al abrirse recibe el foco.
// La fecha tecleada se guarda en local y solo se ajusta al lunes al salir del campo o
// con Enter, para que escribir digito a digito no salte de mes.
export function WeekPickerDialog({ line, weekStart, suggestion, loading, busy, onPickWeek, onConfirm, onClose }: Props) {
  const { t } = useTranslation()
  const inputRef = useRef<HTMLInputElement>(null)

  const [draft, setDraft] = useState(weekStart ?? '')

  useEffect(() => { inputRef.current?.focus() }, [line.id])
  // La semana puede llegar de fuera (cabecera del panel de carga): se refleja en el campo.
  useEffect(() => { setDraft(weekStart ?? '') }, [weekStart])

  const commitDraft = () => {
    const monday = toMonday(draft)
    if (monday) {
      if (monday !== weekStart) onPickWeek(monday)
      else setDraft(monday)
    } else {
      setDraft(weekStart ?? '')
    }
  }

  const titleId = `week-picker-title-${line.id}`
  const canConfirm = !!weekStart && !!suggestion?.found && !loading && !busy

  return (
    <div
      role="dialog"
      aria-modal="false"
      aria-labelledby={titleId}
      onKeyDown={e => {
        if (e.key === 'Escape' && !busy) { e.stopPropagation(); onClose() }
      }}
      className="fixed bottom-4 end-4 z-50 w-[calc(100%-2rem)] max-w-md bg-white rounded-lg shadow-2xl border border-gray-200"
    >
      <div className="p-4 border-b">
        <h2 id={titleId} className="text-base font-semibold">{t('incidents.week.title')}</h2>
        <div className="text-xs text-gray-500 mt-1">
          <span className="font-mono">{sampleLabel(line)}</span>
          {' · '}{fmtDay(line.detail?.original_fecha_programada ?? line.detail?.fecha_programada)}
        </div>
      </div>
      <div className="p-4 space-y-3">
        <p className="text-sm text-gray-600">{t('incidents.week.hint')}</p>
        <input
          ref={inputRef}
          type="date"
          aria-label={t('incidents.week.title')}
          value={draft}
          onChange={e => setDraft(e.target.value)}
          onBlur={commitDraft}
          onKeyDown={e => { if (e.key === 'Enter') { e.preventDefault(); commitDraft() } }}
          className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
        />
        <div className="text-sm min-h-[2.5rem]" aria-live="polite">
          {!weekStart ? null : loading ? (
            <span className="text-gray-500">{t('common.loading')}</span>
          ) : suggestion?.found ? (
            <div className="flex flex-wrap items-center gap-2">
              <span>
                {t('incidents.week.proposal', {
                  week: `${getISOWeek(parseISO(weekStart))} (${fmtWeekRange(weekStart)})`,
                  date: fmtDay(suggestion.date),
                  node: suggestion.node_code ?? '-',
                  load: suggestion.load_after ?? '-',
                })}
              </span>
              {suggestion.saturation_level && (
                <span className={`inline-flex px-2 py-0.5 text-xs font-semibold rounded-full ${SATURATION_BADGE_CLASS[suggestion.saturation_level] ?? SATURATION_BADGE_CLASS.normal}`}>
                  {t(`incidents.balance.saturation_${suggestion.saturation_level}`)}
                </span>
              )}
            </div>
          ) : suggestion ? (
            <span className="text-amber-700">{t('incidents.week.no_slot')}</span>
          ) : null}
        </div>
      </div>
      <div className="border-t p-4 flex gap-2">
        <button
          type="button"
          onClick={onConfirm}
          disabled={!canConfirm}
          className="flex-1 bg-blue-600 text-white px-4 py-2 rounded-lg text-sm hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {t('incidents.week.confirm')}
        </button>
        <button
          type="button"
          onClick={onClose}
          disabled={busy}
          className="flex-1 bg-gray-200 text-gray-700 px-4 py-2 rounded-lg text-sm hover:bg-gray-300 disabled:opacity-50"
        >
          {t('common.cancel')}
        </button>
      </div>
    </div>
  )
}
