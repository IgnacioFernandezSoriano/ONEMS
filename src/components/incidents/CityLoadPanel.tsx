import { useState, useEffect, Fragment } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { fmtDay, SATURATION_BADGE_CLASS } from '@/lib/incidentFormat'
import type { CityLoadWeek, CityNodeLoadRow } from '@/lib/types'

interface Props {
  cityName: string | null
  bajaStart: string
  bajaEnd: string
  releasedNodeId: string | null
  highlightNodeIds: string[]
  weeks: CityLoadWeek[]
  rows: CityNodeLoadRow[]
  loading: boolean
  error: string | null
  referenceLoad: number
  deviationPercent: number
  onChangeParams: (referenceLoad: number, deviationPercent: number) => void
  rangeEnd: string
  onChangeRangeEnd: (d: string) => void
  selectedWeekStart: string | null
  onSelectWeek: (weekStart: string | null) => void
  // true cuando hay una linea "en edicion" (dialogo de otra semana abierto).
  pickingWeek: boolean
}

// Balance de la ciudad por semanas: nodos x semanas con subcolumnas Env/Rec,
// semaforo de saturacion y marcadores (nodo liberado / nodo propuesto).
// Pulsar la cabecera de una semana llama a onSelectWeek(lunes de esa semana).
export function CityLoadPanel({
  cityName, bajaStart, bajaEnd, releasedNodeId, highlightNodeIds, weeks, rows, loading, error,
  referenceLoad, deviationPercent, onChangeParams, rangeEnd, onChangeRangeEnd,
  selectedWeekStart, onSelectWeek, pickingWeek,
}: Props) {
  const { t } = useTranslation()
  const [open, setOpen] = useState(true)
  // Borradores de los inputs numericos: se propagan solo cuando son validos.
  const [refDraft, setRefDraft] = useState(String(referenceLoad))
  const [devDraft, setDevDraft] = useState(String(deviationPercent))
  useEffect(() => { setRefDraft(String(referenceLoad)) }, [referenceLoad])
  useEffect(() => { setDevDraft(String(deviationPercent)) }, [deviationPercent])

  const highlight = new Set(highlightNodeIds)
  const isAffected = (w: CityLoadWeek) => w.week_start_date <= bajaEnd && w.week_end_date >= bajaStart
  const selectedWeek = weeks.find(w => w.week_start_date === selectedWeekStart) ?? null

  const changeRef = (v: string) => {
    setRefDraft(v)
    const n = Number(v)
    if (v !== '' && Number.isFinite(n) && n > 0) onChangeParams(n, deviationPercent)
  }
  const changeDev = (v: string) => {
    setDevDraft(v)
    const n = Number(v)
    if (v !== '' && Number.isFinite(n) && n >= 0) onChangeParams(referenceLoad, n)
  }

  const clickWeek = (w: CityLoadWeek) => {
    // Eligiendo semana para una linea: siempre se fija. Sin linea: alterna el filtro.
    if (pickingWeek) onSelectWeek(w.week_start_date)
    else onSelectWeek(selectedWeekStart === w.week_start_date ? null : w.week_start_date)
  }

  return (
    <div className="bg-white rounded-lg shadow p-4 mb-6">
      <button
        type="button"
        onClick={() => setOpen(o => !o)}
        aria-expanded={open}
        className="w-full flex items-center justify-between text-start"
      >
        <span className="text-sm font-semibold text-gray-900">
          {t('incidents.balance.title')}{cityName ? ` · ${cityName}` : ''}
        </span>
        <span className="text-gray-500 text-sm" aria-hidden="true">{open ? '▾' : '▸'}</span>
      </button>
      {open && (
        <div className="mt-4">
          <div className="flex flex-wrap items-end gap-4 mb-4">
            <label className="text-xs text-gray-600">
              <span className="block mb-1">{t('incidents.load.reference')}</span>
              <input
                type="number" min={1} step={1} value={refDraft}
                onChange={e => changeRef(e.target.value)}
                className="w-24 border border-gray-300 rounded px-2 py-1 text-sm"
              />
            </label>
            <label className="text-xs text-gray-600">
              <span className="block mb-1">{t('incidents.load.deviation')}</span>
              <input
                type="number" min={0} step={1} value={devDraft}
                onChange={e => changeDev(e.target.value)}
                className="w-24 border border-gray-300 rounded px-2 py-1 text-sm"
              />
            </label>
            <label className="text-xs text-gray-600">
              <span className="block mb-1">{t('incidents.load.range')}</span>
              <span className="flex items-center gap-2">
                <span className="text-sm text-gray-700">{fmtDay(bajaStart)} –</span>
                <input
                  type="date" value={rangeEnd} min={bajaStart}
                  onChange={e => { if (e.target.value) onChangeRangeEnd(e.target.value) }}
                  className="border border-gray-300 rounded px-2 py-1 text-sm"
                />
              </span>
            </label>
          </div>

          {error ? (
            <div className="text-sm text-red-600">{t('common.error')}: {error}</div>
          ) : loading && rows.length === 0 ? (
            <div className="text-sm text-gray-500">{t('common.loading')}</div>
          ) : rows.length > 0 && weeks.length > 0 ? (
            <>
              <div className={`overflow-x-auto ${loading ? 'opacity-60' : ''}`}>
                <table className="w-full">
                  <thead>
                    <tr className="border-b">
                      <th rowSpan={2} className="px-3 py-2 text-start text-xs font-medium text-gray-500 uppercase sticky start-0 bg-white align-bottom">{t('incidents.balance.node')}</th>
                      <th rowSpan={2} className="px-3 py-2 text-start text-xs font-medium text-gray-500 uppercase align-bottom">{t('incidents.balance.status')}</th>
                      {weeks.map(w => (
                        <th
                          key={w.week_start_date}
                          colSpan={2}
                          scope="colgroup"
                          title={`${fmtDay(w.week_start_date)} – ${fmtDay(w.week_end_date)}`}
                          className={`p-0 text-center text-xs font-medium uppercase ${selectedWeekStart === w.week_start_date ? 'ring-2 ring-inset ring-blue-400 ' : ''}${isAffected(w) ? 'bg-amber-100 text-amber-800' : 'text-gray-500 hover:bg-gray-100'}`}
                        >
                          <button
                            type="button"
                            onClick={() => clickWeek(w)}
                            aria-pressed={selectedWeekStart === w.week_start_date}
                            className="w-full px-3 py-2 uppercase select-none"
                          >
                            {t('incidents.balance.week_prefix')}{w.week_number}
                          </button>
                        </th>
                      ))}
                      <th colSpan={2} className="px-3 py-2 text-center text-xs font-medium text-gray-500 uppercase">{t('incidents.balance.total')}</th>
                      <th rowSpan={2} className="px-3 py-2"></th>
                    </tr>
                    <tr className="border-b">
                      {weeks.map(w => (
                        <Fragment key={w.week_start_date}>
                          <th title={t('incidents.balance.send_full')} className={`px-2 py-1 text-center text-[10px] font-medium text-gray-400 ${isAffected(w) ? 'bg-amber-50' : ''}`}>{t('incidents.balance.send')}</th>
                          <th title={t('incidents.balance.receive_full')} className={`px-2 py-1 text-center text-[10px] font-medium text-gray-400 ${isAffected(w) ? 'bg-amber-50' : ''}`}>{t('incidents.balance.receive')}</th>
                        </Fragment>
                      ))}
                      <th title={t('incidents.balance.send_full')} className="px-2 py-1 text-center text-[10px] font-medium text-gray-400">{t('incidents.balance.send')}</th>
                      <th title={t('incidents.balance.receive_full')} className="px-2 py-1 text-center text-[10px] font-medium text-gray-400">{t('incidents.balance.receive')}</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-100">
                    {rows.map(n => (
                      <tr key={n.node_id} className={n.node_id === releasedNodeId ? 'bg-gray-50' : ''}>
                        <td className="px-3 py-2 text-sm font-mono sticky start-0 bg-inherit">{n.node_code}</td>
                        <td className="px-3 py-2">
                          <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${SATURATION_BADGE_CLASS[n.saturation_level] ?? SATURATION_BADGE_CLASS.normal}`}>
                            {t(`incidents.balance.saturation_${n.saturation_level}`)}
                          </span>
                        </td>
                        {weeks.map(w => {
                          const cell = n.counts[w.week_number] ?? { sent: 0, received: 0 }
                          const sel = selectedWeekStart === w.week_start_date
                          const hi = isAffected(w)
                          const cls = `px-2 py-2 text-center text-sm ${sel ? 'bg-blue-50' : hi ? 'bg-amber-50 font-semibold' : ''}`
                          return (
                            <Fragment key={w.week_start_date}>
                              <td className={cls}>{cell.sent}</td>
                              <td className={cls}>{cell.received}</td>
                            </Fragment>
                          )
                        })}
                        <td className="px-2 py-2 text-center text-sm font-semibold">{n.total.sent}</td>
                        <td className="px-2 py-2 text-center text-sm font-semibold">{n.total.received}</td>
                        <td className="px-3 py-2 text-xs text-gray-600 whitespace-nowrap">
                          {n.node_id === releasedNodeId && <span className="me-2">🚫 {t('incidents.balance.freed')}</span>}
                          {highlight.has(n.node_id) && <span>⭐ {t('incidents.balance.suggested')}</span>}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <div className="mt-2 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-gray-500">
                <span>
                  <span className="inline-block w-3 h-3 bg-amber-100 rounded-sm align-middle me-1"></span>
                  {t('incidents.balance.affected_week')}
                </span>
                {pickingWeek ? (
                  <span className="text-blue-700">{t('incidents.week.hint')}</span>
                ) : selectedWeekStart == null ? (
                  <span className="text-gray-400">{t('incidents.balance.week_filter_hint')}</span>
                ) : (
                  <button
                    type="button"
                    onClick={() => onSelectWeek(null)}
                    className="inline-flex items-center gap-1 rounded-full bg-blue-50 px-2 py-0.5 text-blue-700 hover:bg-blue-100"
                  >
                    {t('incidents.balance.week_filter_active')}{' '}
                    {selectedWeek ? `${t('incidents.balance.week_prefix')}${selectedWeek.week_number}` : fmtDay(selectedWeekStart)}
                    <span className="font-semibold" aria-hidden="true">✕</span>
                  </button>
                )}
              </div>
            </>
          ) : (
            <div className="text-sm text-gray-500">{t('incidents.balance.no_data')}</div>
          )}
        </div>
      )}
    </div>
  )
}
