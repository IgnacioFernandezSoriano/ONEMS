import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { addDays, endOfMonth, format, isValid, parseISO } from 'date-fns'
import { useMaterialsTreatment, applySourceMode, toSupplyPlan, readPurchaseLines, type SupplyLine, type SourceMode, type PanelistStockRow, type AffectedSample, type PurchaseLine } from '@/lib/hooks/useMaterialsTreatment'
import { supabase } from '@/lib/supabase'
import type { ReportedIncidentDetail } from '@/lib/types'
import { BTN_PRIMARY, BTN_SECONDARY } from './buttonStyles'
import { SupplyTable } from './SupplyTable'

type TFn = (key: string, params?: Record<string, any>, fallback?: string) => string
type Panelist = NonNullable<ReportedIncidentDetail['panelist']>
interface Executed { expectedDate: string | null; centralShipmentId: string | null; donorShipmentIds: string[] }
interface CatalogEntry { id: string; name: string; code: string; is_blocking: boolean }

const DATE_FMT = 'yyyy-MM-dd'
const m = (k: string) => `reported_incidents.materials.${k}`

type Treatment = ReturnType<typeof useMaterialsTreatment>

const errMsg = (t: TFn, e: any) => `${t('common.error')}: ${e?.message ?? String(e)}`

const fmtDate = (d: string | null | undefined) => {
  if (!d) return '-'
  const p = parseISO(d)
  return isValid(p) ? format(p, 'dd/MM/yyyy') : '-'
}

// Fusiona un parche sobre el payload FRESCO de la BD (evita pisar cambios de otra sesion o pestana).
// Con unlessExecuted no escribe si el suministro ya se confirmo (otra pestana o sesion): devuelve false.
async function mergePayload(incidentId: string, patch: Record<string, any>, opts?: { unlessExecuted?: boolean }): Promise<boolean> {
  const { data, error: e0 } = await supabase.from('panelist_incident').select('payload').eq('id', incidentId).single()
  if (e0) throw e0
  const fresh = (data?.payload as Record<string, any> | null) ?? {}
  if (opts?.unlessExecuted && fresh.supply_executed_at) return false
  const { error: e1 } = await supabase.from('panelist_incident')
    .update({ payload: { ...fresh, ...patch } }).eq('id', incidentId)
  if (e1) throw e1
  return true
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h4 className="font-medium mb-2">{title}</h4>
      {children}
    </div>
  )
}

function BlockingBadge({ t }: { t: TFn }) {
  return <span className="bg-red-100 text-red-700 text-xs px-2 py-0.5 rounded">{t(m('blocking_badge'))}</span>
}

// ---------- Seccion 1: stock teorico ----------
function StockSection({ accountId, tr, panelist, reported, onChanged, onStockChanged, t }: {
  accountId: string | null | undefined
  tr: Treatment
  panelist: Panelist
  reported: { name: string; quantity: number }[]
  onChanged: () => Promise<void>
  onStockChanged: () => void
  t: TFn
}) {
  const { fetchPanelistStock, zeroAllStock, reconcileStock } = tr
  const [rows, setRows] = useState<PanelistStockRow[] | null>(null)
  const [catalog, setCatalog] = useState<Record<string, CatalogEntry>>({})
  const [realQty, setRealQty] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  const [info, setInfo] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const reload = useCallback(async () => { setRows(await fetchPanelistStock(panelist.id)) }, [fetchPanelistStock, panelist.id])
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => { reload().catch(e => setError(errMsg(t, e))) }, [reload])
  useEffect(() => {
    if (!accountId) return
    supabase.from('material_catalog').select('id, code, name, is_blocking').eq('account_id', accountId)
      .then(({ data, error: e }) => {
        if (e) { setError(errMsg(t, e)); return }
        const map: Record<string, CatalogEntry> = {}
        ;(data || []).forEach((r: any) => {
          const v = { id: r.id, name: r.name, code: r.code, is_blocking: !!r.is_blocking }
          if (r.name) map[String(r.name).toLowerCase()] = v
          if (r.code) map[String(r.code).toLowerCase()] = v
        })
        setCatalog(map)
      })
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accountId])

  // Filas = stock del panelista + materiales reportados que aun no tienen fila de stock
  const display = useMemo(() => {
    const list: (PanelistStockRow & { unmatched?: boolean })[] = [...(rows ?? [])]
    reported.forEach(r => {
      const c = catalog[r.name.toLowerCase()]
      if (!c) list.push({ material_id: `unmatched-${r.name}`, name: r.name, code: '', quantity: 0, is_blocking: false, unmatched: true })
      else if (!list.some(x => x.material_id === c.id)) list.push({ material_id: c.id, name: c.name, code: c.code, quantity: 0, is_blocking: c.is_blocking })
    })
    return list
  }, [rows, reported, catalog])

  const act = async (fn: () => Promise<void>) => {
    setBusy(true); setError(null); setInfo(null)
    try { await fn(); onStockChanged(); await reload(); await onChanged() }
    catch (e: any) { setError(errMsg(t, e)) }
    finally { setBusy(false) }
  }
  const canZero = (rows ?? []).some(r => r.quantity > 0)

  return (
    <Section title={t(m('s1_title'))}>
      {error && <p className="text-sm text-red-600">{error}</p>}
      {rows && display.length === 0 && <p className="text-sm text-gray-500">{t(m('no_stock_rows'))}</p>}
      <table className="w-full text-sm">
        <tbody>
          {display.map(r => {
            const key = r.material_id
            const val = realQty[key] ?? ''
            return (
              <tr key={key} className="border-t">
                <td className="py-1">{r.name}</td>
                <td className="py-1 w-16 text-end pe-2">{r.quantity}</td>
                <td className="py-1">{r.is_blocking && <BlockingBadge t={t} />}</td>
                <td className="py-1">
                  {r.unmatched ? <span className="text-xs text-gray-500">{t(m('unmatched'))}</span> : (
                    <div className="flex items-center gap-2">
                      <input type="number" className="border rounded p-1 text-sm w-24" placeholder={t(m('real_qty'))}
                        value={val} onChange={e => setRealQty(p => ({ ...p, [key]: e.target.value }))} />
                      <button disabled={busy || val === '' || Number.isNaN(Number(val))} className={BTN_SECONDARY}
                        onClick={() => act(async () => { await reconcileStock(panelist.id, key, Number(val)); setRealQty(p => ({ ...p, [key]: '' })) })}>
                        {t(m('real_qty'))}
                      </button>
                    </div>
                  )}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
      <div className="mt-2 flex items-center gap-3">
        <button disabled={busy || !canZero} className={BTN_SECONDARY}
          onClick={() => {
            if (!confirm(t(m('zero_confirm')))) return
            act(async () => { const n = await zeroAllStock(panelist.id); setInfo(t(m('zero_done'), { n })) })
          }}>
          {t(m('zero_stock'))}
        </button>
        {info && <span className="text-sm text-green-700">{info}</span>}
      </div>
    </Section>
  )
}

// ---------- Seccion 2: necesidad y suministro ----------
// Horizonte: vacio = hasta el ultimo dia del mes de hoy; N = hoy + N dias.
function horizonFor(days: string): string {
  const n = Number(days)
  if (days.trim() !== '' && Number.isInteger(n) && n > 0) return format(addDays(new Date(), n), DATE_FMT)
  return format(endOfMonth(new Date()), DATE_FMT)
}

function SupplySection({ tr, accountId, incidentId, panelist, payload, executed, bajaId, stockVersion, expectedDate, setExpectedDate, today, datePast, purchase, onPurchaseChange, onExecuted, onChanged, t }: {
  tr: Treatment
  accountId: string | null | undefined
  incidentId: string
  panelist: Panelist
  payload: Record<string, any> | null
  executed: Executed | null
  bajaId: string | null
  stockVersion: number
  expectedDate: string
  setExpectedDate: (d: string) => void
  today: string
  datePast: boolean
  purchase: boolean | null
  onPurchaseChange: (p: boolean, nothingNeeded: boolean) => void
  onExecuted: (e: Executed) => void
  onChanged: () => Promise<void>
  t: TFn
}) {
  const { resolveSupplyV2, executeSupply, fetchIncidentShipments, linkShipmentsToIncident, linkShipmentToIncident, daysWithoutStock } = tr
  const done: string | null = payload?.supply_executed_at ?? null
  const [days, setDays] = useState('')
  const horizonEnd = useMemo(() => horizonFor(days), [days])
  const [lines, setLines] = useState<SupplyLine[] | null>(null)
  const [modes, setModes] = useState<Record<string, SourceMode>>({})
  // Guarda de reintento: ids de envios ya creados (si el payload ya los tiene, p. ej. tras recargar, se reutilizan)
  const [created, setCreated] = useState<{ centralShipmentId: string | null; donorShipmentIds: string[] } | null>(() => {
    if (payload?.supply_executed_at) return null
    const donors: string[] = Array.isArray(payload?.donor_shipment_ids) ? payload.donor_shipment_ids : []
    return payload?.central_shipment_id || donors.length > 0
      ? { centralShipmentId: payload?.central_shipment_id ?? null, donorShipmentIds: donors }
      : null
  })
  const [purchaseLead, setPurchaseLead] = useState<number | null>(null)
  const [shipLead, setShipLead] = useState(7)
  const inFlight = useRef(false) // guarda sincrona de doble clic (busy llega un render tarde)
  const [touched, setTouched] = useState(false)
  const [dws, setDws] = useState<{ businessDays: number; samples: AffectedSample[] } | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (done) return // confirmado: solo lectura, no se recalcula
    let cancelled = false
    setLines(null); setError(null)
    // En camino no cuenta lo ya creado para ESTA incidencia (p. ej. un reintento tras fallo parcial)
    resolveSupplyV2(panelist.id, horizonEnd, { excludeIncidentId: incidentId })
      .then(l => { if (!cancelled) setLines(l) })
      .catch(e => { if (!cancelled) setError(errMsg(t, e)) })
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [panelist.id, stockVersion, !!done, horizonEnd])

  useEffect(() => {
    if (!accountId) return
    supabase.from('stock_settings').select('purchase_lead_time_days, shipment_lead_time_days').eq('account_id', accountId).maybeSingle()
      .then(({ data, error: e }) => {
        if (e) { setError(errMsg(t, e)); return }
        setPurchaseLead(data?.purchase_lead_time_days ?? 7)
        setShipLead(data?.shipment_lead_time_days ?? 7)
      })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accountId])

  const effective = useMemo(
    () => (lines ? lines.map(l => applySourceMode(l, modes[l.material_id] ?? 'proposal')) : null), [lines, modes])
  const hasPurchase = (effective ?? []).some(l => l.toPurchase > 0)
  useEffect(() => {
    if (!done && effective) onPurchaseChange(hasPurchase, effective.length === 0)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hasPurchase, !!effective, done])
  useEffect(() => {
    if (touched || done || purchaseLead === null || !hasPurchase) return
    setExpectedDate(format(addDays(new Date(), purchaseLead), DATE_FMT))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [purchaseLead, hasPurchase, touched, done])

  // Dias sin stock: solo los materiales bloqueantes que quedan a compra
  const blockingKey = useMemo(
    () => (effective ?? []).filter(l => l.is_blocking && l.toPurchase > 0).map(l => l.material_id).join(','), [effective])
  useEffect(() => {
    if (!hasPurchase || !expectedDate || !panelist.node_id || !effective) { setDws(null); return }
    daysWithoutStock(panelist.node_id, today, expectedDate, blockingKey ? blockingKey.split(',') : [])
      .then(setDws).catch(e => setError(errMsg(t, e)))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expectedDate, blockingKey, hasPurchase, !!effective, panelist.node_id])

  const confirmSupply = async () => {
    if (inFlight.current) return
    if (!effective || effective.length === 0 || (hasPurchase && (!expectedDate || datePast))) return
    inFlight.current = true
    setBusy(true); setError(null)
    try {
      // Otra pestana o sesion ya confirmo: no se crea ni se pisa nada, solo se recarga
      const { data: fresh, error: e0 } = await supabase.from('panelist_incident').select('payload').eq('id', incidentId).single()
      if (e0) throw e0
      const fp = (fresh?.payload as Record<string, any> | null) ?? {}
      if (fp.supply_executed_at) { await onChanged(); return }

      // Reintento seguro: la BD manda. Los ids conocidos (memoria de esta sesion o payload) se enlazan
      // primero a la incidencia; despues se leen los envios de la incidencia y SOLO se crean los origenes
      // que faltan (un fallo parcial previo no duplica el central ni los donantes).
      // Quedan `pending`: el donante confirma el envio por Telegram y el central se marca enviado desde la hoja.
      const fd: unknown[] = Array.isArray(fp.donor_shipment_ids) ? fp.donor_shipment_ids : []
      const known = Array.from(new Set([created?.centralShipmentId, ...(created?.donorShipmentIds ?? []), fp.central_shipment_id, ...fd]
        .filter((x): x is string => typeof x === 'string' && x !== '')))
      if (known.length > 0) await linkShipmentsToIncident(incidentId, known)
      const existing = await fetchIncidentShipments(incidentId)
      // Fecha en que debe llegar cada envio (central/vecinos): siempre hoy + plazo habitual de envio.
      // La compra no es un envio: payload.expected_date es solo la llegada de la compra (fin de la baja).
      const shipExpected = format(addDays(new Date(), shipLead), DATE_FMT)
      const ids = await executeSupply(toSupplyPlan(effective), panelist.id, shipExpected, { incidentId, existing })
      setCreated(ids) // guarda en memoria (misma sesion) ANTES de persistir
      await mergePayload(incidentId, { central_shipment_id: ids.centralShipmentId, donor_shipment_ids: ids.donorShipmentIds })
      const allIds = [ids.centralShipmentId, ...ids.donorShipmentIds].filter(Boolean) as string[]
      await linkShipmentsToIncident(incidentId, allIds) // idempotente (ya enlazados en el INSERT)
      // Compatibilidad: linked_material_shipment_id sigue apuntando al envio central
      if (ids.centralShipmentId) await linkShipmentToIncident(incidentId, ids.centralShipmentId)
      const expected = hasPurchase ? expectedDate : null
      const purchaseLines: PurchaseLine[] = effective
        .filter(l => l.toPurchase > 0)
        .map(l => ({ material_id: l.material_id, code: l.code, name: l.name, quantity: l.toPurchase }))
      // Justo antes de la escritura final se relee el payload: si otra pestana ya confirmo, no se pisa
      const written = await mergePayload(incidentId, {
        horizon_end: horizonEnd, expected_date: expected, days_without_stock: hasPurchase ? (dws?.businessDays ?? 0) : 0,
        central_shipment_id: ids.centralShipmentId, donor_shipment_ids: ids.donorShipmentIds,
        purchase_lines: purchaseLines,
        supply_executed_at: new Date().toISOString()
      }, { unlessExecuted: true })
      if (written) onExecuted({ expectedDate: expected, centralShipmentId: ids.centralShipmentId, donorShipmentIds: ids.donorShipmentIds })
      await onChanged()
    } catch (e: any) { setError(errMsg(t, e)) }
    finally { inFlight.current = false; setBusy(false) }
  }

  const shipIds = executed ? [executed.centralShipmentId, ...executed.donorShipmentIds].filter(Boolean) as string[] : []
  const showDate = done ? !!purchase : hasPurchase
  const boughtLines = done ? readPurchaseLines(payload) : []
  return (
    <Section title={t(m('s2_title'))}>
      {error && <p className="text-sm text-red-600">{error}</p>}
      {done && <p className="text-sm text-gray-600 mb-2">{t(m('supply_done'), { date: fmtDate(done.slice(0, 10)) })}</p>}
      {done && boughtLines.length > 0 && (
        <div className="mb-2 text-sm">
          <p className="font-medium">{t(m('to_buy_title'))}</p>
          <ul className="list-disc ms-5">
            {boughtLines.map(l => <li key={l.material_id || l.code}>{t(m('to_buy_line'), { name: l.name, code: l.code, n: l.quantity })}</li>)}
          </ul>
        </div>
      )}
      {!done && (
        <div className="mb-2 flex flex-wrap items-center gap-2 text-sm">
          <label>{t(m('days_to_cover'))}</label>
          <input type="number" min={1} step={1} className="border rounded p-1 w-20" value={days} disabled={busy}
            onChange={e => setDays(e.target.value)} />
          <span className="text-gray-500">{t(m('days_to_cover_hint'), { date: fmtDate(horizonEnd) })}</span>
        </div>
      )}
      {!done && !lines && !error && <p className="text-sm text-gray-500">{t('common.loading')}</p>}
      {!done && effective && (
        <SupplyTable lines={effective} modes={modes} disabled={busy} t={t}
          onModeChange={(id, mode) => setModes(p => ({ ...p, [id]: mode }))} />
      )}
      {showDate && (
        <div className="mt-3 flex items-center gap-2 text-sm">
          <label>{t(m('expected_date'))}</label>
          <input type="date" className="border rounded p-1" min={today} disabled={!!bajaId} value={expectedDate}
            onChange={e => { setTouched(true); setExpectedDate(e.target.value) }} />
        </div>
      )}
      {showDate && datePast && <p className="text-sm text-red-600 mt-1">{t(m('date_in_past'))}</p>}
      {showDate && dws && (
        <div className="mt-2 text-sm">
          <p className="font-medium">{t(m('days_without_stock'), { n: dws.businessDays })}</p>
          {dws.samples.length === 0 ? <p className="text-gray-500">{t(m('no_affected_samples'))}</p> : (
            <>
              <p className="text-gray-600">{t(m('affected_samples'))}</p>
              <ul className="list-disc ms-5">
                {dws.samples.map(s => <li key={s.id}>{fmtDate(s.fecha_programada)} - {s.destination_auto_id} - {s.product}</li>)}
              </ul>
            </>
          )}
        </div>
      )}
      <div className="mt-3">
        <button disabled={busy || !!done || !effective || effective.length === 0 || (hasPurchase && (!expectedDate || datePast))}
          className={BTN_PRIMARY} onClick={confirmSupply}>
          {t(m('confirm_supply'))}
        </button>
        {done && shipIds.length > 0 && (
          <p className="text-sm text-gray-600 mt-2 font-mono">{shipIds.map(i => i.slice(0, 8)).join(', ')}</p>
        )}
      </div>
    </Section>
  )
}

// ---------- Seccion 3: replanificar (solo si queda algo a compra) ----------
function ReplanSection({ tr, incidentId, unavailabilityId, executed, purchase, nothingNeeded, expectedDate, datePast, onBajaCreated, onChanged, t }: {
  tr: Treatment
  incidentId: string
  unavailabilityId: string | null
  executed: Executed | null
  purchase: boolean | null
  nothingNeeded: boolean
  expectedDate: string
  datePast: boolean
  onBajaCreated: (id: string) => void
  onChanged: () => Promise<void>
  t: TFn
}) {
  const { createDisplacementBaja } = tr
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const inFlight = useRef(false)

  const createBaja = async () => {
    if (inFlight.current || !expectedDate || datePast) return
    inFlight.current = true
    setBusy(true); setError(null)
    try {
      // La fecha vigente del campo manda: se guarda en el payload y se usa para la baja
      await mergePayload(incidentId, { expected_date: expectedDate })
      onBajaCreated(await createDisplacementBaja(incidentId, expectedDate))
      await onChanged()
    } catch (e: any) { setError(errMsg(t, e)) }
    finally { inFlight.current = false; setBusy(false) }
  }

  if (purchase === null && !unavailabilityId) return null // calculando: sin cabecera vacia
  if (!purchase && !unavailabilityId) {
    return (
      <Section title={t(m('s3_title'))}>
        <p className="text-sm text-gray-500">{t(m(nothingNeeded ? 'nothing_needed' : 'no_purchase_no_baja'))}</p>
      </Section>
    )
  }
  return (
    <Section title={t(m('s3_title'))}>
      {error && <p className="text-sm text-red-600">{error}</p>}
      {datePast && !unavailabilityId && <p className="text-sm text-red-600 mb-2">{t(m('date_in_past'))}</p>}
      <button disabled={busy || !executed || !!unavailabilityId || !expectedDate || datePast} className={BTN_PRIMARY} onClick={createBaja}>
        {t(m('create_baja_replan'))}
      </button>
      <p className="text-sm text-gray-500 mt-2">{t(m('close_hint'))}</p>
      {unavailabilityId && (
        <Link to={`/incidents/panelist-availability?unavailability=${unavailabilityId}`} className="text-blue-600 hover:text-blue-800 text-sm">
          {t(m('go_to_unavailability'))}
        </Link>
      )}
    </Section>
  )
}

export function MissingMaterialsSections({ incidentId, accountId, panelist, payload, linkedUnavailabilityId, onChanged, t }: {
  incidentId: string
  accountId: string
  panelist: ReportedIncidentDetail['panelist']
  payload: Record<string, any> | null
  linkedUnavailabilityId: string | null
  onChanged: () => Promise<void>
  t: TFn
}) {
  // Una sola instancia (cada una carga el stock completo); siempre con la cuenta DEL INCIDENTE
  const tr = useMaterialsTreatment(accountId)
  const [local, setLocal] = useState<Executed | null>(null)
  const [stockVersion, setStockVersion] = useState(0)
  const [expectedDate, setExpectedDate] = useState<string>(payload?.expected_date ?? '')
  const [createdBajaId, setCreatedBajaId] = useState<string | null>(null)
  const [livePurchase, setLivePurchase] = useState<boolean | null>(null)
  const [liveNothing, setLiveNothing] = useState(false)
  if (!panelist) return null
  const today = format(new Date(), DATE_FMT)
  const datePast = !!expectedDate && expectedDate < today
  const bajaId = linkedUnavailabilityId ?? createdBajaId
  const reported: { name: string; quantity: number }[] = Array.isArray(payload?.materials) ? payload.materials : []
  const executed: Executed | null = payload?.supply_executed_at
    ? {
        expectedDate: payload.expected_date ?? null,
        centralShipmentId: payload.central_shipment_id ?? null,
        donorShipmentIds: Array.isArray(payload.donor_shipment_ids) ? payload.donor_shipment_ids : []
      }
    : local
  // Hay compra: confirmado -> se guardo fecha prevista (solo se guarda si hay compra); si no, calculo en vivo
  const purchase = executed ? !!executed.expectedDate : livePurchase
  return (
    <div className="space-y-5">
      <StockSection accountId={accountId} tr={tr} panelist={panelist} reported={reported} onChanged={onChanged}
        onStockChanged={() => setStockVersion(v => v + 1)} t={t} />
      <SupplySection tr={tr} accountId={accountId} incidentId={incidentId} panelist={panelist} payload={payload} executed={executed}
        bajaId={bajaId} stockVersion={stockVersion} expectedDate={expectedDate} setExpectedDate={setExpectedDate}
        today={today} datePast={datePast} purchase={purchase} onPurchaseChange={(p, none) => { setLivePurchase(p); setLiveNothing(none) }}
        onExecuted={setLocal} onChanged={onChanged} t={t} />
      <ReplanSection tr={tr} incidentId={incidentId} unavailabilityId={bajaId} executed={executed} purchase={purchase}
        nothingNeeded={!executed && liveNothing}
        expectedDate={expectedDate} datePast={datePast} onBajaCreated={setCreatedBajaId} onChanged={onChanged} t={t} />
    </div>
  )
}
