import { useState, useEffect, useCallback, useRef } from 'react'
import { addDays, addWeeks, format, parseISO, isValid } from 'date-fns'
import { useTranslation } from '@/hooks/useTranslation'
import { useUnavailabilityIncidents } from '@/lib/hooks/useUnavailabilityIncidents'
import { useCityNodeLoad, defaultLoadRangeEnd } from '@/lib/hooks/useCityNodeLoad'
import { IncidentHeader } from '@/components/incidents/IncidentHeader'
import { CityLoadPanel } from '@/components/incidents/CityLoadPanel'
import { IncidentLinesTable } from '@/components/incidents/IncidentLinesTable'
import { WeekPickerDialog } from '@/components/incidents/WeekPickerDialog'
import { sampleLabel, toMonday } from '@/lib/incidentFormat'
import type { ReassignmentProposal, UnavailabilityHeader, WeekSuggestion } from '@/lib/types'

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

interface SuggestionState {
  key: string
  data: WeekSuggestion | null
  loading: boolean
}

const errMsg = (err: any) => err?.message ?? String(err)

// Semana por defecto al abrir "Otra semana...": la de la propuesta del sistema o, si no
// hay, la siguiente a la fecha original de la muestra.
function defaultWeekFor(line: ReassignmentProposal): string | null {
  const fromSuggestion = toMonday(line.suggested_date)
  if (fromSuggestion) return fromSuggestion
  const orig = line.detail?.original_fecha_programada ?? line.detail?.fecha_programada
  if (!orig) return null
  const p = parseISO(orig)
  return isValid(p) ? toMonday(format(addWeeks(p, 1), 'yyyy-MM-dd')) : null
}

// Detalle de una incidencia de indisponibilidad: cabecera + resolucion final, carga de
// la ciudad por semanas, lineas pendientes (decision del manager) y resueltas.
// Toda accion recarga cabecera, lineas y carga (tambien tras un error).
export function IncidentReviewPanel({ unavailabilityId, onBack }: Props) {
  const { t } = useTranslation()
  const { fetchHeader, fetchLines, suggestForWeek, decide, decideMany, saveResolution } = useUnavailabilityIncidents()

  const [header, setHeader] = useState<UnavailabilityHeader | null>(null)
  const [lines, setLines] = useState<ReassignmentProposal[]>([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [actionError, setActionError] = useState<ActionError | null>(null)
  const [busyId, setBusyId] = useState<string | null>(null)
  const busyRef = useRef(false) // guarda sincrona contra el doble clic
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  // Se incrementa en cada recarga: invalida propuestas de semana ya calculadas.
  const [dataVersion, setDataVersion] = useState(0)
  const reloadSeq = useRef(0)

  // Filtros del panel de carga.
  const [referenceLoad, setReferenceLoad] = useState(6)
  const [deviationPercent, setDeviationPercent] = useState(20)
  const [rangeEndOverride, setRangeEndOverride] = useState<string | null>(null)
  const rangeEnd = rangeEndOverride ?? defaultLoadRangeEnd(header?.start_date)

  // Semana: filtro de la lista (sin linea en edicion) o semana elegida en el dialogo.
  const [weekFilter, setWeekFilter] = useState<string | null>(null)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [pickedWeek, setPickedWeek] = useState<string | null>(null)
  const [suggestion, setSuggestion] = useState<SuggestionState | null>(null)

  const reload = useCallback(async () => {
    const seq = ++reloadSeq.current
    const [h, ls] = await Promise.all([fetchHeader(unavailabilityId), fetchLines(unavailabilityId)])
    if (seq !== reloadSeq.current) return
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

  const { weeks, rows, loading: loadLoading, error: loadErrorCity, refetch: refetchLoad } = useCityNodeLoad(
    header?.city_id, header?.start_date, rangeEnd, referenceLoad, deviationPercent, header?.account_id,
  )

  // Linea en edicion: solo mientras siga pendiente (otro manager pudo resolverla).
  const editingLine = lines.find(l => l.id === editingId && l.status === 'pending') ?? null
  const hasEditingLine = editingLine !== null
  useEffect(() => {
    if (editingId && !hasEditingLine) { setEditingId(null); setPickedWeek(null) }
  }, [editingId, hasEditingLine])

  // Propuesta para la semana elegida. Se recalcula al cambiar linea, semana, filtros o
  // datos; una respuesta cuya clave ya no es la actual se descarta.
  const requestKey = editingId && pickedWeek
    ? `${editingId}|${pickedWeek}|${referenceLoad}|${deviationPercent}|${dataVersion}`
    : null
  useEffect(() => {
    if (!requestKey || !editingId || !pickedWeek) { setSuggestion(null); return }
    let cancelled = false
    setSuggestion({ key: requestKey, data: null, loading: true })
    suggestForWeek(editingId, pickedWeek, referenceLoad, deviationPercent)
      .then(data => {
        if (cancelled) return
        setSuggestion(prev => (prev?.key === requestKey ? { key: requestKey, data, loading: false } : prev))
      })
      .catch(err => {
        if (cancelled) return
        setSuggestion(prev => (prev?.key === requestKey ? { key: requestKey, data: null, loading: false } : prev))
        setActionError({ message: errMsg(err) })
      })
    return () => { cancelled = true }
  }, [requestKey, editingId, pickedWeek, referenceLoad, deviationPercent, suggestForWeek])

  const currentSuggestion = suggestion && suggestion.key === requestKey ? suggestion : null

  const pending = lines.filter(l => l.status === 'pending')
  const resolved = lines.filter(l => l.status !== 'pending')
  // Filtro de semana sobre las pendientes (solo sin linea en edicion).
  const filterActive = !editingId && !!weekFilter
  const filterEnd = weekFilter ? format(addDays(parseISO(weekFilter), 6), 'yyyy-MM-dd') : null
  const visiblePending = filterActive && weekFilter && filterEnd
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
  // Boton "Otra semana..." que abrio el dialogo: recupera el foco al cerrarlo.
  const returnFocusRef = useRef<HTMLElement | null>(null)
  useEffect(() => {
    if (editingId) return
    const el = returnFocusRef.current
    returnFocusRef.current = null
    if (el && el.isConnected) el.focus()
  }, [editingId])

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

  const closeDialog = useCallback(() => { setEditingId(null); setPickedWeek(null) }, [])

  const doAccept = (l: ReassignmentProposal) => runAction(l.id, async () => { await decide(l.id, 'accept') })
  const doCancel = (l: ReassignmentProposal) => runAction(l.id, async () => { await decide(l.id, 'cancel') })
  // Aceptar una propuesta de anulacion tambien anula la muestra: se pide confirmacion.
  const handleAccept = (l: ReassignmentProposal) => {
    if (l.suggested_action === 'cancel') {
      setConfirmState({ text: t('incidents.confirm.cancel_one'), run: () => doAccept(l) })
    } else {
      setConfirmState(null)
      doAccept(l)
    }
  }
  const handleCancel = (l: ReassignmentProposal) =>
    setConfirmState({ text: t('incidents.confirm.cancel_one'), run: () => doCancel(l) })
  const handleOtherWeek = (l: ReassignmentProposal, trigger: HTMLElement) => {
    setConfirmState(null)
    returnFocusRef.current = trigger
    setEditingId(l.id)
    setPickedWeek(defaultWeekFor(l))
  }
  const handleConfirmWeek = () => {
    if (!editingLine || !pickedWeek || !currentSuggestion?.data?.found) return
    const id = editingLine.id
    const week = pickedWeek
    return runAction(id, async () => {
      await decide(id, 'week', week, referenceLoad, deviationPercent)
      closeDialog()
    })
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

  const onSelectWeek = (weekStart: string | null) => {
    if (editingId) { if (weekStart) setPickedWeek(weekStart) }
    else setWeekFilter(weekStart)
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

  const pendingEmptyText = filterActive && pending.length > 0
    ? t('incidents.balance.week_filter_empty')
    : t('incidents.detail.no_pending')

  // Estrella solo para destinos de reencaminamiento (un nodo distinto del liberado).
  const highlightNodeIds = pending
    .filter(l => l.suggested_action === 'reroute' && !!l.suggested_target_node_id && l.suggested_target_node_id !== header.node_id)
    .map(l => l.suggested_target_node_id as string)
  const sugNode = currentSuggestion?.data?.found ? currentSuggestion.data.node_id : undefined
  if (sugNode && sugNode !== header.node_id) highlightNodeIds.push(sugNode)

  const selectedPendingCount = selectedLines.length

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
          loading={loadLoading}
          error={loadErrorCity}
          referenceLoad={referenceLoad}
          deviationPercent={deviationPercent}
          onChangeParams={(ref, dev) => { setReferenceLoad(ref); setDeviationPercent(dev) }}
          rangeEnd={rangeEnd}
          onChangeRangeEnd={setRangeEndOverride}
          selectedWeekStart={editingId ? pickedWeek : weekFilter}
          onSelectWeek={onSelectWeek}
          pickingWeek={!!editingId}
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
        onOtherWeek={handleOtherWeek}
        onCancel={handleCancel}
        busyId={busyId}
        editingId={editingId}
        pendingEmptyText={pendingEmptyText}
      />

      {editingLine && (
        <WeekPickerDialog
          line={editingLine}
          weekStart={pickedWeek}
          suggestion={currentSuggestion?.data ?? null}
          loading={!!pickedWeek && (!currentSuggestion || currentSuggestion.loading)}
          busy={busyId !== null}
          onPickWeek={setPickedWeek}
          onConfirm={handleConfirmWeek}
          onClose={closeDialog}
        />
      )}
    </div>
  )
}
