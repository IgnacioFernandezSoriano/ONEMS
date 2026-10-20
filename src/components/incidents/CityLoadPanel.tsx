import { useState, useEffect, useMemo, Fragment } from 'react'
import type { CSSProperties, DragEvent } from 'react'
import { parseISO, isValid } from 'date-fns'
import { useTranslation } from '@/hooks/useTranslation'
import { fmtDay, fmtWeekRange, weekCoverage, SATURATION_BADGE_CLASS } from '@/lib/incidentFormat'
import type { WeekCoverage } from '@/lib/incidentFormat'
import { readDragPayload } from '@/lib/incidentDrag'
import type { CityLoadWeek, CityNodeLoadRow, MoveDragPayload, NodeUnavailability } from '@/lib/types'

export interface SelectedCell {
  nodeId: string
  weekStart: string
}

interface Props {
  cityName: string | null
  bajaStart: string
  bajaEnd: string
  releasedNodeId: string | null
  highlightNodeIds: string[]
  weeks: CityLoadWeek[]
  rows: CityNodeLoadRow[]
  unavailability: NodeUnavailability[]
  loading: boolean
  error: string | null
  referenceLoad: number
  deviationPercent: number
  onChangeParams: (referenceLoad: number, deviationPercent: number) => void
  // Ventana visible: primer lunes, ultimo dia y lunes minimo (semana actual).
  windowStart: string
  windowEnd: string
  minWindowStart: string
  onShiftWindow: (deltaWeeks: number) => void
  todayMonday: string
  // Cabecera de semana: filtra las lineas pendientes.
  selectedWeekStart: string | null
  onSelectWeek: (weekStart: string | null) => void
  // Casilla nodo x semana: abre la lista de sus muestras.
  selectedCell: SelectedCell | null
  onSelectCell: (cell: SelectedCell) => void
  // Arrastre en curso (lo fija el padre en onDragStart) y soltado sobre una casilla.
  dragging: MoveDragPayload | null
  onDropCell: (nodeId: string, nodeCode: string, weekStart: string, payload: MoveDragPayload) => void
  busy: boolean
}

// Fondo rayado gris: panelista del nodo de baja toda la semana laborable.
const STRIPES: CSSProperties = {
  backgroundImage: 'repeating-linear-gradient(45deg, #e5e7eb 0, #e5e7eb 4px, #f9fafb 4px, #f9fafb 8px)',
}

// Balance de la ciudad por semanas: nodos x semanas con subcolumnas Env/Rec, fila de meses,
// bajas por panelista en cada casilla, semaforo de saturacion y marcadores (nodo liberado /
// nodo propuesto). Cabecera de semana -> filtro de lineas; casilla -> lista de sus muestras;
// soltar en una casilla -> onDropCell (la validacion real la hace la base de datos).
export function CityLoadPanel({
  cityName, bajaStart, bajaEnd, releasedNodeId, highlightNodeIds, weeks, rows, unavailability, loading, error,
  referenceLoad, deviationPercent, onChangeParams, windowStart, windowEnd, minWindowStart, onShiftWindow,
  todayMonday, selectedWeekStart, onSelectWeek, selectedCell, onSelectCell, dragging, onDropCell, busy,
}: Props) {
  const { t, locale, isRTL } = useTranslation()
  const [open, setOpen] = useState(true)
  // Borradores de los inputs numericos: se propagan solo cuando son validos.
  const [refDraft, setRefDraft] = useState(String(referenceLoad))
  const [devDraft, setDevDraft] = useState(String(deviationPercent))
  useEffect(() => { setRefDraft(String(referenceLoad)) }, [referenceLoad])
  useEffect(() => { setDevDraft(String(deviationPercent)) }, [deviationPercent])
  // Casilla bajo el cursor durante el arrastre.
  const [hoverKey, setHoverKey] = useState<string | null>(null)
  useEffect(() => { if (!dragging) setHoverKey(null) }, [dragging])

  const highlight = new Set(highlightNodeIds)
  const isAffected = (w: CityLoadWeek) => w.week_start_date <= bajaEnd && w.week_end_date >= bajaStart
  const selectedWeek = weeks.find(w => w.week_start_date === selectedWeekStart) ?? null
  const todayMonth = todayMonday.slice(0, 7)

  // Cobertura de bajas por casilla (nodo|lunes).
  const coverage = useMemo(() => {
    const byNode = new Map<string, NodeUnavailability[]>()
    for (const u of unavailability) {
      const list = byNode.get(u.node_id) ?? []
      list.push(u)
      byNode.set(u.node_id, list)
    }
    const m = new Map<string, WeekCoverage>()
    for (const [nodeId, list] of byNode) {
      for (const w of weeks) {
        const c = weekCoverage(list, w.week_start_date)
        if (c.ranges.length > 0) m.set(`${nodeId}|${w.week_start_date}`, c)
      }
    }
    return m
  }, [unavailability, weeks])

  // Fila de meses: grupos consecutivos de semanas por el mes de su lunes.
  const months = useMemo(() => {
    const fmt = new Intl.DateTimeFormat(locale || 'en', { month: 'long', year: 'numeric' })
    const groups: { key: string; label: string; count: number }[] = []
    for (const w of weeks) {
      const key = w.week_start_date.slice(0, 7)
      const last = groups[groups.length - 1]
      if (last && last.key === key) { last.count++; continue }
      const p = parseISO(w.week_start_date)
      groups.push({ key, label: isValid(p) ? fmt.format(p) : key, count: 1 })
    }
    return groups
  }, [weeks, locale])

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

  const clickWeek = (w: CityLoadWeek) =>
    onSelectWeek(selectedWeekStart === w.week_start_date ? null : w.week_start_date)

  // Comprobaciones baratas durante el arrastre; null = se puede soltar.
  const blockReason = (nodeId: string, weekStart: string): string | null => {
    if (!dragging) return null
    if (busy) return t('common.loading')
    if (weekStart < todayMonday) return t('incidents.move.block_past')
    if (nodeId === dragging.otherEndNodeId) return t('incidents.move_reason.other_end')
    if ((coverage.get(`${nodeId}|${weekStart}`)?.workdaysCovered ?? 0) >= 5) return t('incidents.move.block_unavailable')
    return null
  }

  const dropHandlers = (n: CityNodeLoadRow, w: CityLoadWeek, blocked: boolean) => {
    const key = `${n.node_id}|${w.week_start_date}`
    return {
      onDragOver: (e: DragEvent) => {
        if (!dragging) return
        if (blocked) { e.dataTransfer.dropEffect = 'none'; return }
        e.preventDefault()
        e.dataTransfer.dropEffect = 'move'
        if (hoverKey !== key) setHoverKey(key)
      },
      onDragLeave: () => setHoverKey(h => (h === key ? null : h)),
      onDrop: (e: DragEvent) => {
        e.preventDefault()
        setHoverKey(null)
        if (blocked) return
        const payload = readDragPayload(e) ?? dragging
        if (payload) onDropCell(n.node_id, n.node_code, w.week_start_date, payload)
      },
    }
  }

  const weekLabel = (w: CityLoadWeek) => `${t('incidents.balance.week_prefix')}${w.week_number}`
  const atMin = windowStart <= minWindowStart
  const navBtn = 'px-2 py-1 text-sm rounded border border-gray-300 text-gray-700 hover:bg-gray-100 disabled:opacity-40 disabled:cursor-not-allowed'

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
            <div className="text-xs text-gray-600">
              <span className="block mb-1">{t('incidents.balance.window')}</span>
              {/* En arabe (RTL) la tabla y estos botones se invierten: los glifos tambien. */}
              <div className="flex items-center gap-1">
                <button type="button" className={navBtn} disabled={atMin} onClick={() => onShiftWindow(-4)}
                  aria-label={t('incidents.balance.window_back_month')} title={t('incidents.balance.window_back_month')}>{isRTL ? '»' : '«'}</button>
                <button type="button" className={navBtn} disabled={atMin} onClick={() => onShiftWindow(-1)}
                  aria-label={t('incidents.balance.window_back_week')} title={t('incidents.balance.window_back_week')}>{isRTL ? '›' : '‹'}</button>
                <span className="px-2 text-sm text-gray-700 whitespace-nowrap">{fmtDay(windowStart)} – {fmtDay(windowEnd)}</span>
                <button type="button" className={navBtn} onClick={() => onShiftWindow(1)}
                  aria-label={t('incidents.balance.window_forward_week')} title={t('incidents.balance.window_forward_week')}>{isRTL ? '‹' : '›'}</button>
                <button type="button" className={navBtn} onClick={() => onShiftWindow(4)}
                  aria-label={t('incidents.balance.window_forward_month')} title={t('incidents.balance.window_forward_month')}>{isRTL ? '«' : '»'}</button>
              </div>
            </div>
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
                    <tr>
                      <th rowSpan={3} className="px-3 py-2 text-start text-xs font-medium text-gray-500 uppercase sticky start-0 bg-white align-bottom border-b">{t('incidents.balance.node')}</th>
                      <th rowSpan={3} className="px-3 py-2 text-start text-xs font-medium text-gray-500 uppercase align-bottom border-b">{t('incidents.balance.status')}</th>
                      {months.map(m => {
                        const current = m.key === todayMonth
                        return (
                          <th
                            key={m.key}
                            colSpan={m.count * 2}
                            scope="colgroup"
                            className={`px-2 py-1 text-center text-xs border-x border-white capitalize ${current ? 'bg-blue-50 text-blue-800 font-semibold' : 'bg-gray-50 text-gray-500 font-medium'}`}
                            title={current ? t('incidents.balance.current_month') : undefined}
                          >
                            {m.label}
                            {current && <span className="sr-only"> ({t('incidents.balance.current_month')})</span>}
                          </th>
                        )
                      })}
                      <th rowSpan={2} colSpan={2} className="px-3 py-2 text-center text-xs font-medium text-gray-500 uppercase align-bottom">{t('incidents.balance.total')}</th>
                      <th rowSpan={3} className="px-3 py-2 border-b"></th>
                    </tr>
                    <tr className="border-b">
                      {weeks.map(w => {
                        const sel = selectedWeekStart === w.week_start_date
                        const isToday = w.week_start_date === todayMonday
                        const affected = isAffected(w)
                        return (
                          <th
                            key={w.week_start_date}
                            colSpan={2}
                            scope="colgroup"
                            title={`${fmtDay(w.week_start_date)} – ${fmtDay(w.week_end_date)}${affected ? ` · ${t('incidents.balance.affected_week')}` : ''}`}
                            className={`p-0 text-center text-xs font-medium uppercase ${sel ? 'ring-2 ring-inset ring-blue-400 ' : ''}${isToday ? 'bg-blue-50 text-blue-800' : 'text-gray-500 hover:bg-gray-100'}`}
                          >
                            <button
                              type="button"
                              onClick={() => clickWeek(w)}
                              aria-pressed={sel}
                              className="w-full px-3 py-2 uppercase select-none leading-tight"
                            >
                              <span className="flex items-center justify-center gap-1">
                                {weekLabel(w)}
                                {isToday && (
                                  <span className="rounded-full bg-blue-600 px-1.5 text-[9px] font-semibold normal-case text-white">
                                    {t('incidents.balance.today')}
                                  </span>
                                )}
                              </span>
                              <span className="block text-[10px] font-normal normal-case whitespace-nowrap">{fmtWeekRange(w.week_start_date, w.week_end_date)}</span>
                              {affected && (
                                <>
                                  <span className="block h-1 mt-1 mx-2 rounded-full bg-amber-400" aria-hidden="true"></span>
                                  <span className="sr-only">{t('incidents.balance.affected_week')}</span>
                                </>
                              )}
                            </button>
                          </th>
                        )
                      })}
                    </tr>
                    <tr className="border-b">
                      {weeks.map(w => (
                        <Fragment key={w.week_start_date}>
                          <th title={t('incidents.balance.send_full')} className="px-2 py-1 text-center text-[10px] font-medium text-gray-400">{t('incidents.balance.send')}</th>
                          <th title={t('incidents.balance.receive_full')} className="px-2 py-1 text-center text-[10px] font-medium text-gray-400">{t('incidents.balance.receive')}</th>
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
                          const key = `${n.node_id}|${w.week_start_date}`
                          const cell = n.counts[w.week_start_date] ?? { sent: 0, received: 0 }
                          const cov = coverage.get(key)
                          const full = !!cov && cov.workdaysCovered >= 5
                          const partial = !!cov && !full
                          const unavText = cov
                            ? t(full ? 'incidents.balance.unavailable_full' : 'incidents.balance.unavailable_partial', { days: cov.ranges.join(', ') })
                            : ''
                          const blocked = blockReason(n.node_id, w.week_start_date)
                          const isSelCell = selectedCell?.nodeId === n.node_id && selectedCell.weekStart === w.week_start_date
                          const hovered = hoverKey === key && !blocked
                          const selWeek = selectedWeekStart === w.week_start_date
                          const bg = hovered ? 'bg-green-100' : partial ? 'bg-gray-100' : (!full && selWeek) ? 'bg-blue-50' : ''
                          const ring = hovered ? 'ring-2 ring-inset ring-green-500' : isSelCell ? 'ring-2 ring-inset ring-blue-500' : ''
                          const dim = dragging && blocked ? 'opacity-40 cursor-not-allowed' : ''
                          const title = [
                            `${n.node_code} · ${weekLabel(w)} (${fmtWeekRange(w.week_start_date, w.week_end_date)})`,
                            unavText,
                            dragging && blocked ? blocked : '',
                          ].filter(Boolean).join('\n')
                          const handlers = dropHandlers(n, w, !!blocked)
                          const td = `p-0 text-center text-sm ${bg} ${ring} ${dim}`
                          const btn = `w-full px-2 py-2 ${full ? 'text-gray-500' : ''} ${dragging && blocked ? 'cursor-not-allowed' : 'hover:underline'}`
                          return (
                            <Fragment key={w.week_start_date}>
                              <td className={td} style={full && !hovered ? STRIPES : undefined} title={title} {...handlers}>
                                <button type="button" className={btn} onClick={() => onSelectCell({ nodeId: n.node_id, weekStart: w.week_start_date })}
                                  aria-label={`${title.replace(/\n/g, ' · ')} · ${t('incidents.balance.send_full')}: ${cell.sent}`}
                                  aria-pressed={isSelCell}>
                                  {cell.sent}
                                </button>
                              </td>
                              <td className={td} style={full && !hovered ? STRIPES : undefined} title={title} {...handlers}>
                                <button type="button" className={btn} onClick={() => onSelectCell({ nodeId: n.node_id, weekStart: w.week_start_date })}
                                  aria-label={`${title.replace(/\n/g, ' · ')} · ${t('incidents.balance.receive_full')}: ${cell.received}`}
                                  aria-pressed={isSelCell}>
                                  {cell.received}
                                </button>
                              </td>
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
                  <span className="inline-block w-4 h-1 bg-amber-400 rounded-full align-middle me-1"></span>
                  {t('incidents.balance.affected_week')}
                </span>
                <span>
                  <span className="inline-block w-3 h-3 rounded-sm align-middle me-1 border border-gray-200" style={STRIPES}></span>
                  {t('incidents.balance.legend_unavailable')}
                </span>
                <span>
                  <span className="inline-block w-3 h-3 rounded-sm align-middle me-1 bg-gray-100 border border-gray-200"></span>
                  {t('incidents.balance.legend_partial')}
                </span>
                {selectedWeekStart == null ? (
                  <span className="text-gray-400">{t('incidents.balance.week_filter_hint')}</span>
                ) : (
                  <button
                    type="button"
                    onClick={() => onSelectWeek(null)}
                    className="inline-flex items-center gap-1 rounded-full bg-blue-50 px-2 py-0.5 text-blue-700 hover:bg-blue-100"
                  >
                    {t('incidents.balance.week_filter_active')}{' '}
                    {selectedWeek ? `${weekLabel(selectedWeek)} · ${fmtWeekRange(selectedWeek.week_start_date, selectedWeek.week_end_date)}` : fmtDay(selectedWeekStart)}
                    <span className="font-semibold" aria-hidden="true">✕</span>
                  </button>
                )}
                <span className="text-gray-400">{t('incidents.balance.drag_hint')}</span>
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
