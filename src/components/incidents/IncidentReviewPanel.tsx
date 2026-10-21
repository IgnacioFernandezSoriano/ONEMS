import { useState, useEffect, useCallback, useMemo, useRef } from 'react'
import type { DragEvent } from 'react'
import { addDays, format, parseISO, getISOWeek, isValid } from 'date-fns'
import { useTranslation } from '@/hooks/useTranslation'
import { useUnavailabilityIncidents } from '@/lib/hooks/useUnavailabilityIncidents'
import { useCityNodeLoad } from '@/lib/hooks/useCityNodeLoad'
import { IncidentHeader } from '@/components/incidents/IncidentHeader'
import { CityLoadPanel } from '@/components/incidents/CityLoadPanel'
import type { SelectedCell } from '@/components/incidents/CityLoadPanel'
import { CellSamplesPanel } from '@/components/incidents/CellSamplesPanel'
import { IncidentLinesTable } from '@/components/incidents/IncidentLinesTable'
import { IncidentConversation } from '@/components/incidents/IncidentConversation'
import {
  sampleLabel, planLabel, fmtShort, fmtWeekRange, currentMonday, addWeeksTo, defaultWindowWeeks, toMonday,
  SATURATION_BADGE_CLASS,
} from '@/lib/incidentFormat'
import { startMoveDrag } from '@/lib/incidentDrag'
import type { CellSample, MoveDragPayload, MoveSuggestion, ReassignmentProposal, UnavailabilityHeader } from '@/lib/types'

interface Props {
  unavailabilityId: string
  onBack: () => void
}

interface ActionError {
  message?: string
  failed?: { label: string; message: string }[]
}

interface ConfirmState {
  text: string
  run: () => void
}

// Arrastre soltado en una casilla, a la espera de confirmacion.
interface MoveState {
  seq: number
  payload: MoveDragPayload
  nodeId: string
  nodeCode: string
  weekStart: string
  referenceLoad: number
  deviationPercent: number
  loading: boolean
  suggestion: MoveSuggestion | null
  error: string | null
}

const errMsg = (err: any) => err?.message ?? String(err)

// Linea pendiente -> carga del arrastre (el nodo que se mueve es el del lado afectado).
function linePayload(l: ReassignmentProposal): MoveDragPayload | null {
  const d = l.detail
  if (!d) return null
  const origin = l.affected_role === 'origin'
  return {
    kind: 'line',
    lineId: l.id,
    detailId: d.id,
    fromNodeId: origin ? d.origin_node_id : d.destination_node_id,
    otherEndNodeId: origin ? d.destination_node_id : d.origin_node_id,
    fecha: d.fecha_programada,
    label: sampleLabel(l),
    plan: d.plan ?? null,
  }
}

// Detalle de una incidencia de indisponibilidad: cabecera + resolucion final, balance de la
// ciudad por semanas (arrastrar y soltar para mover muestras), muestras de una casilla,
// lineas pendientes (decision del manager) y resueltas.
// Toda accion recarga cabecera, lineas, balance y casilla (tambien tras un error).
export function IncidentReviewPanel({ unavailabilityId, onBack }: Props) {
  const { t } = useTranslation()
  const {
    fetchHeader, fetchLines, decide, decideMany, saveResolution,
    suggestForCell, applyManagerMove, suggestForSampleMove, applySampleMove, fetchCellSamples,
  } = useUnavailabilityIncidents()

  const [header, setHeader] = useState<UnavailabilityHeader | null>(null)
  const [lines, setLines] = useState<ReassignmentProposal[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [actionError, setActionError] = useState<ActionError | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)
  const busyRef = useRef(false) // guarda sincrona contra el doble clic / doble soltado
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  // Se incrementa en cada recarga: refresca la casilla abierta e invalida propuestas de arrastre.
  const [dataVersion, setDataVersion] = useState(0)
  const reloadSeq = useRef(0)

  // Filtros del panel de carga.
  const [referenceLoad, setReferenceLoad] = useState(6)
  const [deviationPercent, setDeviationPercent] = useState(20)

  // Ventana de semanas: empieza en un lunes (nunca antes de la semana actual) y dura
  // max(8 semanas, hasta fin del mes de la baja + 14 dias desde la semana actual).
  // Se recalcula en cada recarga: una pagina abierta pasado el domingo no deja la semana pasada.
  const [todayMonday, setTodayMonday] = useState(() => currentMonday())
  const [windowStart, setWindowStart] = useState(todayMonday)
  useEffect(() => { setWindowStart(ws => (ws < todayMonday ? todayMonday : ws)) }, [todayMonday])
  const windowWeeks = useMemo(() => defaultWindowWeeks(todayMonday, header?.start_date), [todayMonday, header?.start_date])
  const windowEnd = useMemo(() => {
    const p = parseISO(windowStart)
    return isValid(p) ? format(addDays(p, windowWeeks * 7 - 1), 'yyyy-MM-dd') : windowStart
  }, [windowStart, windowWeeks])
  const shiftWindow = useCallback((delta: number) => {
    setWindowStart(ws => {
      const next = addWeeksTo(ws, delta)
      return next < todayMonday ? todayMonday : next
    })
  }, [todayMonday])

  // Cabecera de semana: filtro de las lineas pendientes.
  const [weekFilter, setWeekFilter] = useState<string | null>(null)

  const reload = useCallback(async () => {
    const seq = ++reloadSeq.current
    const [h, ls] = await Promise.all([fetchHeader(unavailabilityId), fetchLines(unavailabilityId)])
    if (seq !== reloadSeq.current) return
    setTodayMonday(currentMonday())
    setHeader(h)
    setLines(ls)
    setDataVersion(v => v + 1)
    const pendingIds = new Set(ls.filter(l => l.status === 'pending').map(l => l.id))
    setSelectedIds(prev => {
      if ([...prev].every(id => pendingIds.has(id))) return prev
      return new Set([...prev].filter(id => pendingIds.has(id)))
    })
  }, [fetchHeader, fetchLines, unavailabilityId])

  useEffect(() => {
    let cancelled = false
    setLoading(true); setLoadError(null)
    reload()
      .catch(err => { if (!cancelled) setLoadError(errMsg(err)) })
      .finally(() => { if (!cancelled) setLoading(false) })
    return () => { cancelled = true }
  }, [reload])

  const {
    weeks, rows, unavailability, loading: loadLoading, error: loadErrorCity, refetch: refetchLoad,
  } = useCityNodeLoad(header?.city_id, windowStart, windowEnd, referenceLoad, deviationPercent, header?.account_id)

  // Casilla abierta (nodo x semana) y sus muestras. Se recarga con cada recarga de datos.
  const [selectedCell, setSelectedCell] = useState<SelectedCell | null>(null)
  const [cellSamples, setCellSamples] = useState<CellSample[]>([])
  const [cellLoading, setCellLoading] = useState(false)
  const [cellError, setCellError] = useState<string | null>(null)
  const cellSeq = useRef(0)
  const cellNodeId = selectedCell?.nodeId ?? null
  const cellWeek = selectedCell?.weekStart ?? null
  useEffect(() => {
    const seq = ++cellSeq.current
    if (!cellNodeId || !cellWeek) { setCellSamples([]); setCellError(null); setCellLoading(false); return }
    setCellLoading(true); setCellError(null)
    fetchCellSamples(cellNodeId, cellWeek)
      .then(data => { if (seq === cellSeq.current) setCellSamples(data) })
      .catch(err => { if (seq === cellSeq.current) setCellError(errMsg(err)) })
      .finally(() => { if (seq === cellSeq.current) setCellLoading(false) })
  }, [cellNodeId, cellWeek, dataVersion, fetchCellSamples])
  const selectCell = useCallback((cell: SelectedCell) => {
    if (cell.nodeId === cellNodeId && cell.weekStart === cellWeek) return
    setCellSamples([])
    setSelectedCell(cell)
  }, [cellNodeId, cellWeek])

  const pending = lines.filter(l => l.status === 'pending')
  const resolved = lines.filter(l => l.status !== 'pending')
  const filterEnd = weekFilter ? format(addDays(parseISO(weekFilter), 6), 'yyyy-MM-dd') : null
  const visiblePending = weekFilter && filterEnd
    ? pending.filter(l => {
        const d = l.detail?.fecha_programada
        return !!d && d >= weekFilter && d <= filterEnd
      })
    : pending
  // La seleccion solo contiene lineas pendientes visibles: al cambiar el filtro (o al
  // recargar) se quitan las ocultas, y las acciones en bloque usan solo estas.
  const visibleKey = visiblePending.map(l => l.id).join(',')
  useEffect(() => {
    const visible = new Set(visibleKey ? visibleKey.split(',') : [])
    setSelectedIds(prev => {
      if ([...prev].every(id => visible.has(id))) return prev
      return new Set([...prev].filter(id => visible.has(id)))
    })
  }, [visibleKey])
  const selectedLines = visiblePending.filter(l => selectedIds.has(l.id))

  // Paso de confirmacion para lo que anula muestras (no se puede deshacer aqui).
  const [confirmState, setConfirmState] = useState<ConfirmState | null>(null)

  // Arrastre en curso y propuesta tras soltar.
  const [dragging, setDragging] = useState<MoveDragPayload | null>(null)
  const [move, setMove] = useState<MoveState | null>(null)
  const moveSeq = useRef(0)
  // Datos o filtros nuevos: la propuesta mostrada ya no vale.
  useEffect(() => { moveSeq.current++; setMove(null) }, [dataVersion, referenceLoad, deviationPercent])

  // Ejecuta una accion bloqueando los botones; siempre recarga al terminar.
  const runAction = async (id: string, fn: () => Promise<void>) => {
    if (busyRef.current) return
    busyRef.current = true
    setBusyId(id); setActionError(null)
    try {
      await fn()
    } catch (err) {
      setActionError({ message: errMsg(err) })
    } finally {
      try {
        await reload()
      } catch (err) {
        setActionError(prev => prev ?? { message: errMsg(err) })
      }
      refetchLoad()
      busyRef.current = false
      setBusyId(null)
    }
  }

  const doAccept = (l: ReassignmentProposal) => runAction(l.id, async () => { await decide(l.id, 'accept') })
  const doCancel = (l: ReassignmentProposal) => runAction(l.id, async () => { await decide(l.id, 'cancel') })
  // Confirmar una propuesta de anulacion tambien anula la muestra: se pide confirmacion.
  const handleAccept = (l: ReassignmentProposal) => {
    setMove(null)
    if (l.suggested_action === 'cancel') {
      setConfirmState({ text: t('incidents.confirm.cancel_one'), run: () => doAccept(l) })
    } else {
      setConfirmState(null)
      doAccept(l)
    }
  }
  const handleCancel = (l: ReassignmentProposal) => {
    setMove(null)
    setConfirmState({ text: t('incidents.confirm.cancel_one'), run: () => doCancel(l) })
  }

  const doBulk = (decision: 'accept' | 'cancel', targets: ReassignmentProposal[]) => runAction('bulk', async () => {
    const pendingById = new Map(targets.map(l => [l.id, l]))
    const ids = targets.map(l => l.id)
    if (ids.length === 0) return
    const res = await decideMany(ids, decision)
    if (res.failed.length > 0) {
      setActionError({
        failed: res.failed.map(f => {
          const l = pendingById.get(f.id)
          return { label: l ? sampleLabel(l) : f.id.slice(0, 8), message: f.message }
        }),
      })
    }
  })

  const handleBulk = (decision: 'accept' | 'cancel') => {
    // Se congela la seleccion visible en el momento del clic.
    const targets = selectedLines
    if (targets.length === 0) return
    setMove(null)
    if (decision === 'cancel') {
      setConfirmState({
        text: t('incidents.confirm.cancel_many', { n: targets.length }),
        run: () => doBulk('cancel', targets),
      })
      return
    }
    const cancelling = targets.filter(l => l.suggested_action === 'cancel').length
    if (cancelling > 0) {
      setConfirmState({
        text: t('incidents.confirm.accept_with_cancel', { n: cancelling }),
        run: () => doBulk('accept', targets),
      })
      return
    }
    setConfirmState(null)
    doBulk('accept', targets)
  }

  // Confirmar: respeta la guarda de doble clic (runAction ignora si hay otra en curso).
  const runConfirmed = () => {
    if (!confirmState || busyRef.current) return
    const { run } = confirmState
    setConfirmState(null)
    run()
  }

  const handleSaveResolution = async (text: string) => {
    // El error del guardado lo muestra la cabecera; se recarga igualmente.
    try {
      await saveResolution(unavailabilityId, text)
    } finally {
      try { await reload() } catch (err) { setActionError({ message: errMsg(err) }) }
    }
  }

  // ---- Arrastrar y soltar ----
  const dragActive = useRef(false)
  const handleDragStart = (e: DragEvent, payload: MoveDragPayload) => {
    if (busyRef.current) { e.preventDefault(); return }
    startMoveDrag(e, payload)
    dragActive.current = true
    // Diferido: cambiar el DOM dentro de dragstart puede abortar el arrastre en Chrome.
    window.setTimeout(() => { if (dragActive.current) setDragging(payload) }, 0)
  }
  const handleDragEnd = () => { dragActive.current = false; setDragging(null) }
  const handleDragStartLine = (e: DragEvent, l: ReassignmentProposal) => {
    const p = linePayload(l)
    if (!p) { e.preventDefault(); return }
    handleDragStart(e, p)
  }

  // Al soltar: pedir a la BD el dia concreto. Si una muestra resulta tener una linea pendiente
  // de ESTA incidencia en el lado de la casilla, se usa el par de RPC de linea.
  const handleDropCell = (nodeId: string, nodeCode: string, weekStart: string, payload: MoveDragPayload) => {
    dragActive.current = false
    setDragging(null)
    if (busyRef.current) return
    setConfirmState(null)
    const seq = ++moveSeq.current
    const ref = referenceLoad
    const dev = deviationPercent
    setMove({ seq, payload, nodeId, nodeCode, weekStart, referenceLoad: ref, deviationPercent: dev, loading: true, suggestion: null, error: null })
    const ask = async (): Promise<{ payload: MoveDragPayload; suggestion: MoveSuggestion }> => {
      if (payload.kind === 'line' && payload.lineId) {
        return { payload, suggestion: await suggestForCell(payload.lineId, nodeId, weekStart, ref, dev) }
      }
      const s = await suggestForSampleMove(payload.detailId, payload.fromNodeId, nodeId, weekStart, ref, dev)
      if (!s.found && s.reason === 'has_incident_line') {
        const own = lines.find(l => l.status === 'pending' && l.detail?.id === payload.detailId)
        const lp = own ? linePayload(own) : null
        if (lp && lp.fromNodeId === payload.fromNodeId && lp.lineId) {
          return { payload: lp, suggestion: await suggestForCell(lp.lineId, nodeId, weekStart, ref, dev) }
        }
      }
      return { payload, suggestion: s }
    }
    ask()
      .then(r => setMove(prev => (prev?.seq === seq ? { ...prev, payload: r.payload, loading: false, suggestion: r.suggestion } : prev)))
      .catch(err => setMove(prev => (prev?.seq === seq ? { ...prev, loading: false, error: errMsg(err) } : prev)))
  }

  const moveFound = !!move?.suggestion?.found
  const moveNothing = moveFound && !!move?.suggestion?.same_node && move?.suggestion?.date === move?.payload.fecha
  const confirmMove = () => {
    if (!move || !moveFound || moveNothing || busyRef.current) return
    const m = move
    setMove(null)
    const p = m.payload
    runAction(p.lineId ?? p.detailId, async () => {
      if (p.kind === 'line' && p.lineId) {
        await applyManagerMove(p.lineId, m.nodeId, m.weekStart, m.referenceLoad, m.deviationPercent)
      } else {
        await applySampleMove(p.detailId, p.fromNodeId, m.nodeId, m.weekStart, m.referenceLoad, m.deviationPercent)
      }
    })
  }

  const toggleOne = (id: string) => setSelectedIds(prev => {
    const next = new Set(prev)
    if (next.has(id)) next.delete(id); else next.add(id)
    return next
  })
  // Seleccionar/deseleccionar todas: solo afecta a las filas pendientes visibles.
  const toggleAll = (ids: string[]) => setSelectedIds(prev => {
    const next = new Set(prev)
    if (ids.length > 0 && ids.every(id => prev.has(id))) ids.forEach(id => next.delete(id))
    else ids.forEach(id => next.add(id))
    return next
  })

  if (loading) return <div className="p-6">{t('common.loading')}</div>
  if (!header) {
    return (
      <div>
        <button type="button" onClick={onBack} className="text-blue-600 hover:text-blue-800 mb-4">← {t('incidents.detail.back')}</button>
        <div className="text-red-600">{t('common.error')}: {loadError ?? '-'}</div>
      </div>
    )
  }

  const pendingEmptyText = weekFilter && pending.length > 0
    ? t('incidents.balance.week_filter_empty')
    : t('incidents.detail.no_pending')

  // Estrella solo para destinos de reencaminamiento (un nodo distinto del liberado).
  const highlightNodeIds = pending
    .filter(l => l.suggested_action === 'reroute' && !!l.suggested_target_node_id && l.suggested_target_node_id !== header.node_id)
    .map(l => l.suggested_target_node_id as string)
  const sugNode = move?.suggestion?.found ? move.suggestion.node_id : undefined
  if (sugNode && sugNode !== header.node_id) highlightNodeIds.push(sugNode)

  const selectedPendingCount = selectedLines.length
  const cellRow = selectedCell ? rows.find(r => r.node_id === selectedCell.nodeId) : undefined

  // Texto de la barra de confirmacion del arrastre.
  const moveText = (): string => {
    if (!move) return ''
    if (move.loading) return t('incidents.move.checking')
    if (move.error) return `${t('common.error')}: ${move.error}`
    const s = move.suggestion
    if (!s) return ''
    if (!s.found) {
      const code = s.reason ?? 'not_found'
      return t('incidents.move.not_possible', { reason: t(`incidents.move_reason.${code}`, undefined, code) })
    }
    if (moveNothing) return t('incidents.move.nothing_to_change')
    // load_after ya cuenta la muestra en su nuevo sitio (y no la cuenta dos veces). Si no cambia
    // de nodo ni de semana ya estaba contada: la carga no varia.
    const after = Number(s.load_after ?? 0)
    const sameCell = (s.node_id ?? move.nodeId) === move.payload.fromNodeId && toMonday(move.payload.fecha) === move.weekStart
    const before = sameCell ? after : Math.max(0, after - 1)
    const ws = parseISO(move.weekStart)
    return t('incidents.move.proposal', {
      sample: move.payload.label,
      plan: planLabel(move.payload.plan),
      node: s.node_code ?? move.nodeCode,
      date: fmtShort(s.date),
      week: `${t('incidents.balance.week_prefix')}${isValid(ws) ? getISOWeek(ws) : ''} (${fmtWeekRange(move.weekStart)})`,
      before,
      after,
    })
  }

  return (
    <div className="pb-48">
      <div className="flex justify-between items-center mb-6">
        <button type="button" onClick={onBack} className="text-blue-600 hover:text-blue-800">← {t('incidents.detail.back')}</button>
      </div>

      <IncidentHeader header={header} onSaveResolution={handleSaveResolution} />

      {actionError && (
        <div role="alert" className="bg-red-50 border border-red-200 text-red-700 rounded-lg p-4 mb-6 flex items-start justify-between gap-4">
          <div className="text-sm">
            <div className="font-medium">{t('common.error')}{actionError.message ? `: ${actionError.message}` : ''}</div>
            {actionError.failed && actionError.failed.length > 0 && (
              <ul className="mt-1 list-disc ps-5">
                {actionError.failed.map((f, i) => (
                  <li key={i}><span className="font-mono">{f.label}</span>: {f.message}</li>
                ))}
              </ul>
            )}
          </div>
          <button
            type="button"
            onClick={() => setActionError(null)}
            aria-label={t('common.close')}
            className="text-red-700 hover:text-red-900"
          >
            ✕
          </button>
        </div>
      )}

      {header.city_id && (
        <CityLoadPanel
          cityName={header.city_name}
          bajaStart={header.start_date}
          bajaEnd={header.end_date}
          releasedNodeId={header.node_id}
          highlightNodeIds={highlightNodeIds}
          weeks={weeks}
          rows={rows}
          unavailability={unavailability}
          loading={loadLoading}
          error={loadErrorCity}
          referenceLoad={referenceLoad}
          deviationPercent={deviationPercent}
          onChangeParams={(ref, dev) => { setReferenceLoad(ref); setDeviationPercent(dev) }}
          windowStart={windowStart}
          windowEnd={windowEnd}
          minWindowStart={todayMonday}
          onShiftWindow={shiftWindow}
          todayMonday={todayMonday}
          selectedWeekStart={weekFilter}
          onSelectWeek={setWeekFilter}
          selectedCell={selectedCell}
          onSelectCell={selectCell}
          dragging={dragging}
          onDropCell={handleDropCell}
          busy={busyId !== null}
        />
      )}

      {selectedCell && (
        <CellSamplesPanel
          nodeId={selectedCell.nodeId}
          nodeCode={cellRow?.node_code ?? '-'}
          weekStart={selectedCell.weekStart}
          samples={cellSamples}
          loading={cellLoading}
          error={cellError}
          unavailabilityId={unavailabilityId}
          busy={busyId !== null}
          draggingDetailId={dragging?.detailId ?? null}
          onDragStart={handleDragStart}
          onDragEnd={handleDragEnd}
          onClose={() => setSelectedCell(null)}
        />
      )}

      {confirmState && (
        <div
          role="alertdialog"
          aria-labelledby="incident-confirm-text"
          className="bg-amber-50 border border-amber-300 rounded-lg p-4 mb-6 flex flex-wrap items-center justify-between gap-3"
        >
          <span id="incident-confirm-text" className="text-sm font-medium text-amber-900">{confirmState.text}</span>
          <div className="flex gap-2">
            <button
              type="button"
              autoFocus
              onClick={runConfirmed}
              disabled={busyId !== null}
              className="px-3 py-1 bg-red-600 text-white text-sm rounded hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {t('common.confirm')}
            </button>
            <button
              type="button"
              onClick={() => setConfirmState(null)}
              className="px-3 py-1 bg-gray-200 text-gray-700 text-sm rounded hover:bg-gray-300"
            >
              {t('incidents.confirm.back')}
            </button>
          </div>
        </div>
      )}

      {selectedPendingCount > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6 flex flex-wrap items-center justify-between gap-2">
          <span className="text-sm font-medium text-blue-900">
            {t('incidents.action.selected_count', { count: selectedPendingCount })}
          </span>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => handleBulk('accept')}
              disabled={busyId !== null}
              className="px-3 py-1 bg-green-600 text-white text-sm rounded hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {t('incidents.action.accept_selected')}
            </button>
            <button
              type="button"
              onClick={() => handleBulk('cancel')}
              disabled={busyId !== null}
              className="px-3 py-1 bg-red-600 text-white text-sm rounded hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {t('incidents.action.cancel_selected')}
            </button>
          </div>
          {busyId === 'bulk' && <span className="text-xs text-gray-500">{t('common.loading')}</span>}
        </div>
      )}

      <IncidentLinesTable
        lines={[...visiblePending, ...resolved]}
        selectedIds={selectedIds}
        onToggle={toggleOne}
        onToggleAll={toggleAll}
        onAccept={handleAccept}
        onCancel={handleCancel}
        busyId={busyId}
        onDragStartLine={handleDragStartLine}
        onDragEnd={handleDragEnd}
        draggingLineId={dragging?.kind === 'line' ? dragging.lineId ?? null : null}
        pendingEmptyText={pendingEmptyText}
      />

      <IncidentConversation kind="unavailability" incidentId={unavailabilityId} />

      {move && (
        <div
          role="alertdialog"
          aria-labelledby="incident-move-text"
          onKeyDown={e => { if (e.key === 'Escape') { e.stopPropagation(); setMove(null) } }}
          className="fixed bottom-4 inset-x-4 z-40 mx-auto max-w-3xl bg-white border border-blue-300 shadow-2xl rounded-lg p-4 flex flex-wrap items-center justify-between gap-3"
        >
          <div className="flex flex-wrap items-center gap-2 text-start" aria-live="polite">
            <span
              id="incident-move-text"
              className={`text-sm font-medium ${move.error || (move.suggestion && !move.suggestion.found) ? 'text-amber-800' : 'text-gray-900'}`}
            >
              {moveText()}
            </span>
            {moveFound && !moveNothing && move.suggestion?.saturation_level && (
              <span className={`inline-flex px-2 py-0.5 text-xs font-semibold rounded-full ${SATURATION_BADGE_CLASS[move.suggestion.saturation_level] ?? SATURATION_BADGE_CLASS.normal}`}>
                {t(`incidents.balance.saturation_${move.suggestion.saturation_level}`)}
              </span>
            )}
          </div>
          <div className="flex gap-2">
            {moveFound && !moveNothing && (
              <button
                type="button"
                autoFocus
                onClick={confirmMove}
                disabled={busyId !== null || move.loading}
                className="px-3 py-1 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {t('common.confirm')}
              </button>
            )}
            <button
              type="button"
              onClick={() => setMove(null)}
              className="px-3 py-1 bg-gray-200 text-gray-700 text-sm rounded hover:bg-gray-300"
            >
              {t('incidents.confirm.back')}
            </button>
          </div>
        </div>
      )}
    </div>
  )
}
