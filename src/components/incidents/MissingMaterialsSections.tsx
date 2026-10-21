import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { addDays, format, isValid, parseISO } from 'date-fns'
import { useMaterialsTreatment, type NeedLine, type SupplyPlan, type PanelistStockRow, type AffectedSample } from '@/lib/hooks/useMaterialsTreatment'
import { supabase } from '@/lib/supabase'
import type { ReportedIncidentDetail } from '@/lib/types'
import { BTN_PRIMARY, BTN_SECONDARY } from './buttonStyles'

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
async function mergePayload(incidentId: string, patch: Record<string, any>) {
  const { data, error: e0 } = await supabase.from('panelist_incident').select('payload').eq('id', incidentId).single()
  if (e0) throw e0
  const { error: e1 } = await supabase.from('panelist_incident')
    .update({ payload: { ...((data?.payload as Record<string, any> | null) ?? {}), ...patch } }).eq('id', incidentId)
  if (e1) throw e1
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
type Override = 'plan' | 'central' | 'purchase'

// Plan efectivo: por defecto el reparto propuesto por resolveSupply; el override
// solo sustituye las lineas de ESE material por una unica fuente, sin superar
// el stock conocido (el plan original solo incluye central hasta lo disponible).
function buildPlan(needs: NeedLine[], plan: SupplyPlan, override: Record<string, Override>): SupplyPlan {
  const out: SupplyPlan = { fromCentral: [], fromDonor: [], toPurchase: [] }
  needs.filter(n => n.quantity_needed > 0).forEach(n => {
    const id = n.material_id
    const mode = override[id] ?? 'plan'
    if (mode === 'plan') {
      out.fromCentral.push(...plan.fromCentral.filter(x => x.material_id === id))
      out.fromDonor.push(...plan.fromDonor.filter(x => x.material_id === id))
      out.toPurchase.push(...plan.toPurchase.filter(x => x.material_id === id))
    } else if (mode === 'central') {
      const cap = plan.fromCentral.filter(x => x.material_id === id).reduce((sum, x) => sum + x.quantity, 0)
      const q = Math.min(cap, n.quantity_needed)
      if (q > 0) out.fromCentral.push({ material_id: id, quantity: q })
      if (n.quantity_needed - q > 0) out.toPurchase.push({ material_id: id, quantity: n.quantity_needed - q })
    } else {
      out.toPurchase.push({ material_id: id, quantity: n.quantity_needed })
    }
  })
  return out
}

function SupplySection({ tr, accountId, incidentId, panelist, payload, executed, bajaId, stockVersion, expectedDate, setExpectedDate, today, datePast, onExecuted, onChanged, t }: {
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
  onExecuted: (e: Executed) => void
  onChanged: () => Promise<void>
  t: TFn
}) {
  const { recomputeNeed, resolveSupply, executeSupply, linkShipmentToIncident, daysWithoutStock } = tr
  const done: string | null = payload?.supply_executed_at ?? null
  const [needs, setNeeds] = useState<NeedLine[] | null>(null)
  const [plan, setPlan] = useState<SupplyPlan | null>(null)
  const [override, setOverride] = useState<Record<string, Override>>({})
  // Guarda de reintento: ids de envios ya creados (si el payload ya los tiene, p. ej. tras recargar, se reutilizan)
  const [created, setCreated] = useState<{ centralShipmentId: string | null; donorShipmentIds: string[] } | null>(() => {
    if (payload?.supply_executed_at) return null
    const donors: string[] = Array.isArray(payload?.donor_shipment_ids) ? payload.donor_shipment_ids : []
    return payload?.central_shipment_id || donors.length > 0
      ? { centralShipmentId: payload?.central_shipment_id ?? null, donorShipmentIds: donors }
      : null
  })
  const [lead, setLead] = useState<{ ship: number; purchase: number } | null>(null)
  const [touched, setTouched] = useState(false)
  const [dws, setDws] = useState<{ businessDays: number; samples: AffectedSample[] } | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (done) return // confirmado: solo lectura, no se recalcula
    let cancelled = false
    ;(async () => {
      try {
        const lines = await recomputeNeed(panelist.id, today, format(addDays(new Date(), 90), DATE_FMT))
        const p = await resolveSupply(lines, panelist.id)
        if (cancelled) return
        setNeeds(lines); setPlan(p)
      } catch (e: any) { if (!cancelled) setError(errMsg(t, e)) }
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [panelist.id, stockVersion, !!done])

  useEffect(() => {
    if (!accountId) return
    supabase.from('stock_settings').select('purchase_lead_time_days, shipment_lead_time_days').eq('account_id', accountId).maybeSingle()
      .then(({ data, error: e }) => {
        if (e) { setError(errMsg(t, e)); return }
        setLead({ ship: data?.shipment_lead_time_days ?? 7, purchase: data?.purchase_lead_time_days ?? 7 })
      })
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [accountId])

  const effective = useMemo(() => (needs && plan ? buildPlan(needs, plan, override) : null), [needs, plan, override])
  const hasPurchase = (effective?.toPurchase.length ?? 0) > 0
  useEffect(() => {
    if (touched || done || !lead) return
    setExpectedDate(format(addDays(new Date(), hasPurchase ? lead.purchase : lead.ship), DATE_FMT))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lead, hasPurchase, touched, done])

  const blockingIds = useMemo(
    () => (needs ?? []).filter(n => n.is_blocking && n.quantity_needed > 0).map(n => n.material_id), [needs])
  useEffect(() => {
    if (!expectedDate || !panelist.node_id || !needs) return
    daysWithoutStock(panelist.node_id, today, expectedDate, blockingIds).then(setDws).catch(e => setError(errMsg(t, e)))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expectedDate, blockingIds, needs, panelist.node_id])

  const confirmSupply = async () => {
    if (!effective || datePast) return
    setBusy(true); setError(null)
    try {
      // Reintento seguro: si los envios ya se crearon (fallo posterior, otra pestana o sesion), no se vuelven a crear.
      // Los envios quedan `pending`: se despachan en la seccion 3, despues de crear la baja.
      let ids = created
      if (!ids) {
        const { data: fresh, error: e0 } = await supabase.from('panelist_incident').select('payload').eq('id', incidentId).single()
        if (e0) throw e0
        const fp = (fresh?.payload as Record<string, any> | null) ?? {}
        const fd: string[] = Array.isArray(fp.donor_shipment_ids) ? fp.donor_shipment_ids : []
        if (fp.central_shipment_id || fd.length > 0) ids = { centralShipmentId: fp.central_shipment_id ?? null, donorShipmentIds: fd }
      }
      if (!ids) {
        ids = await executeSupply(effective, panelist.id)
        // Persistir los ids YA: si algo falla despues, un reintento (incluso tras recargar) no duplica envios
        await mergePayload(incidentId, { central_shipment_id: ids.centralShipmentId, donor_shipment_ids: ids.donorShipmentIds })
      }
      setCreated(ids)
      if (ids.centralShipmentId) await linkShipmentToIncident(incidentId, ids.centralShipmentId)
      await mergePayload(incidentId, {
        expected_date: expectedDate, days_without_stock: dws?.businessDays ?? 0,
        central_shipment_id: ids.centralShipmentId, donor_shipment_ids: ids.donorShipmentIds,
        supply_executed_at: new Date().toISOString()
      })
      onExecuted({ expectedDate, centralShipmentId: ids.centralShipmentId, donorShipmentIds: ids.donorShipmentIds })
      await onChanged()
    } catch (e: any) { setError(errMsg(t, e)) }
    finally { setBusy(false) }
  }

  const shipIds = executed ? [executed.centralShipmentId, ...executed.donorShipmentIds].filter(Boolean) as string[] : []
  const splitText = (id: string) => {
    if (!plan) return ''
    const parts = [
      ...plan.fromCentral.filter(x => x.material_id === id).map(x => `${t(m('source_central'))} ${x.quantity}`),
      ...plan.fromDonor.filter(x => x.material_id === id).map(x => `${t(m('source_donor'), { name: x.donor_name || x.donor_panelist_id })} ${x.quantity}`),
      ...plan.toPurchase.filter(x => x.material_id === id).map(x => `${t(m('source_purchase'))} ${x.quantity}`)
    ]
    return parts.join(' · ')
  }
  return (
    <Section title={t(m('s2_title'))}>
      {error && <p className="text-sm text-red-600">{error}</p>}
      {done && <p className="text-sm text-gray-600 mb-2">{t(m('supply_done'), { date: fmtDate(done.slice(0, 10)) })}</p>}
      {!done && !needs && !error && <p className="text-sm text-gray-500">{t('common.loading')}</p>}
      {!done && needs && (
        <table className="w-full text-sm">
          <thead>
            <tr className="text-start text-gray-500">
              <th /><th /><th className="font-medium">{t(m('source'))}</th><th className="font-medium">{t(m('change_source'))}</th>
            </tr>
          </thead>
          <tbody>
            {needs.map(n => (
              <tr key={n.material_id} className="border-t">
                <td className="py-1">{n.material_name} {n.is_blocking && <BlockingBadge t={t} />}</td>
                <td className="py-1">{n.quantity_needed} {n.unit_measure}</td>
                <td className="py-1">{splitText(n.material_id)}</td>
                <td className="py-1">
                  <select className="border rounded p-1 text-sm" value={override[n.material_id] ?? 'plan'}
                    onChange={e => setOverride(p => ({ ...p, [n.material_id]: e.target.value as Override }))}>
                    <option value="plan">{t(m('source_plan'))}</option>
                    <option value="central">{t(m('source_central'))}</option>
                    <option value="purchase">{t(m('source_purchase'))}</option>
                  </select>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      <div className="mt-3 flex items-center gap-2 text-sm">
        <label>{t(m('expected_date'))}</label>
        <input type="date" className="border rounded p-1" min={today} disabled={!!bajaId} value={expectedDate}
          onChange={e => { setTouched(true); setExpectedDate(e.target.value) }} />
      </div>
      {datePast && <p className="text-sm text-red-600 mt-1">{t(m('date_in_past'))}</p>}
      {dws && (
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
        <button disabled={busy || !!done || !effective || !expectedDate || datePast} className={BTN_PRIMARY} onClick={confirmSupply}>
          {t(m('confirm_supply'))}
        </button>
        {done && shipIds.length > 0 && (
          <p className="text-sm text-gray-600 mt-2 font-mono">{shipIds.map(i => i.slice(0, 8)).join(', ')}</p>
        )}
      </div>
    </Section>
  )
}

// ---------- Seccion 3: replanificar ----------
function ReplanSection({ tr, incidentId, payload, unavailabilityId, executed, expectedDate, datePast, onBajaCreated, onChanged, t }: {
  tr: Treatment
  incidentId: string
  payload: Record<string, any> | null
  unavailabilityId: string | null
  executed: Executed | null
  expectedDate: string
  datePast: boolean
  onBajaCreated: (id: string) => void
  onChanged: () => Promise<void>
  t: TFn
}) {
  const { createDisplacementBaja, markShipmentSent } = tr
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [sentLocal, setSentLocal] = useState<string[]>([])

  const allIds = executed ? [executed.centralShipmentId, ...executed.donorShipmentIds].filter(Boolean) as string[] : []
  const sent = new Set<string>([...(Array.isArray(payload?.sent_shipment_ids) ? payload.sent_shipment_ids : []), ...sentLocal])
  const pending = allIds.filter(id => !sent.has(id))

  const createBaja = async () => {
    if (!expectedDate || datePast) return
    setBusy(true); setError(null)
    try {
      // La fecha vigente del campo manda: se guarda en el payload y se usa para la baja
      await mergePayload(incidentId, { expected_date: expectedDate })
      onBajaCreated(await createDisplacementBaja(incidentId, expectedDate))
      await onChanged()
    } catch (e: any) { setError(errMsg(t, e)) }
    finally { setBusy(false) }
  }

  // Solo tras crear la baja (receive_material_shipment necesita el enlace para cerrarla).
  // Cada envio se registra como enviado al instante: un fallo deja el resto reintentable.
  const sendPending = async () => {
    setBusy(true); setError(null)
    try {
      const sentIds = [...sent]
      for (const id of pending) {
        await markShipmentSent(id)
        sentIds.push(id)
        setSentLocal(prev => [...prev, id])
        await mergePayload(incidentId, { sent_shipment_ids: sentIds })
      }
      await onChanged()
    } catch (e: any) { setError(errMsg(t, e)) }
    finally { setBusy(false) }
  }

  return (
    <Section title={t(m('s3_title'))}>
      {error && <p className="text-sm text-red-600">{error}</p>}
      {datePast && !unavailabilityId && <p className="text-sm text-red-600 mb-2">{t(m('date_in_past'))}</p>}
      <div className="flex gap-2">
        <button disabled={busy || !executed || !!unavailabilityId || !expectedDate || datePast} className={BTN_PRIMARY} onClick={createBaja}>
          {t(m('create_baja_replan'))}
        </button>
        {unavailabilityId && pending.length > 0 && (
          <button disabled={busy} className={BTN_PRIMARY} onClick={sendPending}>{t(m('send_shipments'))}</button>
        )}
      </div>
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
  return (
    <div className="space-y-5">
      <StockSection accountId={accountId} tr={tr} panelist={panelist} reported={reported} onChanged={onChanged}
        onStockChanged={() => setStockVersion(v => v + 1)} t={t} />
      <SupplySection tr={tr} accountId={accountId} incidentId={incidentId} panelist={panelist} payload={payload} executed={executed}
        bajaId={bajaId} stockVersion={stockVersion} expectedDate={expectedDate} setExpectedDate={setExpectedDate}
        today={today} datePast={datePast} onExecuted={setLocal} onChanged={onChanged} t={t} />
      <ReplanSection tr={tr} incidentId={incidentId} payload={payload} unavailabilityId={bajaId} executed={executed}
        expectedDate={expectedDate} datePast={datePast} onBajaCreated={setCreatedBajaId} onChanged={onChanged} t={t} />
    </div>
  )
}
