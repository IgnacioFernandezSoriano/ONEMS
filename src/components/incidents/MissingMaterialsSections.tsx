import { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { addDays, format } from 'date-fns'
import { useMaterialsTreatment, type NeedLine, type SupplyPlan, type PanelistStockRow, type AffectedSample } from '@/lib/hooks/useMaterialsTreatment'
import { useAuth } from '@/contexts/AuthContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { supabase } from '@/lib/supabase'
import type { ReportedIncidentDetail } from '@/lib/types'
import { BTN_PRIMARY, BTN_SECONDARY } from './buttonStyles'

type TFn = (key: string, params?: Record<string, any>, fallback?: string) => string
type Panelist = NonNullable<ReportedIncidentDetail['panelist']>
interface Executed { expectedDate: string | null; centralShipmentId: string | null; donorShipmentIds: string[] }
interface CatalogEntry { id: string; name: string; code: string; is_blocking: boolean }

const DATE_FMT = 'yyyy-MM-dd'
const m = (k: string) => `reported_incidents.materials.${k}`

function useAccountId() {
  const effective = useEffectiveAccountId()
  const { profile } = useAuth()
  return effective || profile?.account_id
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
function StockSection({ panelist, reported, onChanged, t }: {
  panelist: Panelist
  reported: { name: string; quantity: number }[]
  onChanged: () => Promise<void>
  t: TFn
}) {
  const { fetchPanelistStock, zeroAllStock, reconcileStock } = useMaterialsTreatment()
  const accountId = useAccountId()
  const [rows, setRows] = useState<PanelistStockRow[] | null>(null)
  const [catalog, setCatalog] = useState<Record<string, CatalogEntry>>({})
  const [realQty, setRealQty] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  const [info, setInfo] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)

  const reload = useCallback(async () => { setRows(await fetchPanelistStock(panelist.id)) }, [fetchPanelistStock, panelist.id])
  useEffect(() => { reload().catch(e => setError(e.message)) }, [reload])
  useEffect(() => {
    if (!accountId) return
    supabase.from('material_catalog').select('id, code, name, is_blocking').eq('account_id', accountId)
      .then(({ data }) => {
        const map: Record<string, CatalogEntry> = {}
        ;(data || []).forEach((r: any) => {
          const v = { id: r.id, name: r.name, code: r.code, is_blocking: !!r.is_blocking }
          if (r.name) map[String(r.name).toLowerCase()] = v
          if (r.code) map[String(r.code).toLowerCase()] = v
        })
        setCatalog(map)
      })
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
    try { await fn(); await reload(); await onChanged() }
    catch (e: any) { setError(e.message) }
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
                <td className="py-1 w-16 text-right pr-2">{r.quantity}</td>
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
function SupplySection({ incidentId, panelist, payload, executed, onExecuted, onChanged, t }: {
  incidentId: string
  panelist: Panelist
  payload: Record<string, any> | null
  executed: Executed | null
  onExecuted: (e: Executed) => void
  onChanged: () => Promise<void>
  t: TFn
}) {
  const { recomputeNeed, resolveSupply, executeSupply, linkShipmentToIncident, daysWithoutStock } = useMaterialsTreatment()
  const accountId = useAccountId()
  const done: string | null = payload?.supply_executed_at ?? null
  const [needs, setNeeds] = useState<NeedLine[] | null>(null)
  const [plan, setPlan] = useState<SupplyPlan | null>(null)
  const [sources, setSources] = useState<Record<string, string>>({})
  const [lead, setLead] = useState<{ ship: number; purchase: number } | null>(null)
  const [expectedDate, setExpectedDate] = useState<string>(payload?.expected_date ?? '')
  const [touched, setTouched] = useState(false)
  const [dws, setDws] = useState<{ businessDays: number; samples: AffectedSample[] } | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const today = format(new Date(), DATE_FMT)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const lines = await recomputeNeed(panelist.id, today, format(addDays(new Date(), 90), DATE_FMT))
        const p = await resolveSupply(lines, panelist.id)
        if (cancelled) return
        const sel: Record<string, string> = {}
        lines.forEach(n => {
          if (p.fromCentral.some(c => c.material_id === n.material_id)) sel[n.material_id] = 'central'
          else {
            const d = p.fromDonor.find(x => x.material_id === n.material_id)
            sel[n.material_id] = d ? `donor:${d.donor_panelist_id}` : 'purchase'
          }
        })
        setNeeds(lines); setPlan(p); setSources(sel)
      } catch (e: any) { if (!cancelled) setError(e.message) }
    })()
    return () => { cancelled = true }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [panelist.id])

  useEffect(() => {
    if (!accountId) return
    supabase.from('stock_settings').select('purchase_lead_time_days, shipment_lead_time_days').eq('account_id', accountId).maybeSingle()
      .then(({ data }) => setLead({ ship: data?.shipment_lead_time_days ?? 7, purchase: data?.purchase_lead_time_days ?? 7 }))
  }, [accountId])

  const hasPurchase = Object.values(sources).includes('purchase')
  useEffect(() => {
    if (touched || done || !lead) return
    setExpectedDate(format(addDays(new Date(), hasPurchase ? lead.purchase : lead.ship), DATE_FMT))
  }, [lead, hasPurchase, touched, done])

  const blockingIds = useMemo(
    () => (needs ?? []).filter(n => n.is_blocking && n.quantity_needed > 0).map(n => n.material_id), [needs])
  useEffect(() => {
    if (!expectedDate || !panelist.node_id || !needs) return
    daysWithoutStock(panelist.node_id, today, expectedDate, blockingIds).then(setDws).catch(e => setError(e.message))
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expectedDate, blockingIds, needs, panelist.node_id])

  const confirmSupply = async () => {
    if (!plan || !needs) return
    setBusy(true); setError(null)
    try {
      const chosen: SupplyPlan = { fromCentral: [], fromDonor: [], toPurchase: [] }
      needs.filter(n => n.quantity_needed > 0).forEach(n => {
        const src = sources[n.material_id] ?? 'purchase'
        if (src === 'central') chosen.fromCentral.push({ material_id: n.material_id, quantity: n.quantity_needed })
        else if (src.startsWith('donor:')) {
          const id = src.slice(6)
          const d = plan.fromDonor.find(x => x.donor_panelist_id === id)
          chosen.fromDonor.push({ material_id: n.material_id, quantity: n.quantity_needed, donor_panelist_id: id, donor_name: d?.donor_name ?? '' })
        } else chosen.toPurchase.push({ material_id: n.material_id, quantity: n.quantity_needed })
      })
      // Los envios quedan `pending`: se despachan en la seccion 3, despues de crear la baja.
      const { centralShipmentId, donorShipmentIds } = await executeSupply(chosen, panelist.id)
      if (centralShipmentId) await linkShipmentToIncident(incidentId, centralShipmentId)
      const { error: e } = await supabase.from('panelist_incident').update({
        payload: {
          ...(payload ?? {}), expected_date: expectedDate, days_without_stock: dws?.businessDays ?? 0,
          central_shipment_id: centralShipmentId, donor_shipment_ids: donorShipmentIds,
          supply_executed_at: new Date().toISOString()
        }
      }).eq('id', incidentId)
      if (e) throw e
      onExecuted({ expectedDate, centralShipmentId, donorShipmentIds })
      await onChanged()
    } catch (e: any) { setError(e.message) }
    finally { setBusy(false) }
  }

  const ids = executed ? [executed.centralShipmentId, ...executed.donorShipmentIds].filter(Boolean) as string[] : []
  const donors = Array.from(new Map((plan?.fromDonor ?? []).map(d => [d.donor_panelist_id, d.donor_name])).entries())
  return (
    <Section title={t(m('s2_title'))}>
      {error && <p className="text-sm text-red-600">{error}</p>}
      {!needs && !error && <p className="text-sm text-gray-500">{t('common.loading')}</p>}
      {needs && (
        <table className="w-full text-sm">
          <thead><tr className="text-left text-gray-500"><th /><th /><th className="font-medium">{t(m('source'))}</th></tr></thead>
          <tbody>
            {needs.map(n => (
              <tr key={n.material_id} className="border-t">
                <td className="py-1">{n.material_name} {n.is_blocking && <BlockingBadge t={t} />}</td>
                <td className="py-1">{n.quantity_needed} {n.unit_measure}</td>
                <td className="py-1">
                  <select className="border rounded p-1 text-sm" disabled={!!done} value={sources[n.material_id] ?? 'purchase'}
                    onChange={e => setSources(p => ({ ...p, [n.material_id]: e.target.value }))}>
                    <option value="central">{t(m('source_central'))}</option>
                    {donors.map(([id, name]) => (
                      <option key={id} value={`donor:${id}`}>{t(m('source_donor'), { name })}</option>
                    ))}
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
        <input type="date" className="border rounded p-1" min={today} disabled={!!done} value={expectedDate}
          onChange={e => { setTouched(true); setExpectedDate(e.target.value) }} />
      </div>
      {dws && (
        <div className="mt-2 text-sm">
          <p className="font-medium">{t(m('days_without_stock'), { n: dws.businessDays })}</p>
          {dws.samples.length === 0 ? <p className="text-gray-500">{t(m('no_affected_samples'))}</p> : (
            <>
              <p className="text-gray-600">{t(m('affected_samples'))}</p>
              <ul className="list-disc ml-5">
                {dws.samples.map(s => <li key={s.id}>{s.fecha_programada} - {s.destination_auto_id} - {s.product}</li>)}
              </ul>
            </>
          )}
        </div>
      )}
      <div className="mt-3">
        <button disabled={busy || !!done || !needs || !expectedDate} className={BTN_PRIMARY} onClick={confirmSupply}>
          {t(m('confirm_supply'))}
        </button>
        {done && (
          <p className="text-sm text-gray-600 mt-2">
            {t(m('supply_done'), { date: format(new Date(done), DATE_FMT) })}
            {ids.length > 0 && <span className="font-mono"> ({ids.map(i => i.slice(0, 8)).join(', ')})</span>}
          </p>
        )}
      </div>
    </Section>
  )
}

// ---------- Seccion 3: replanificar ----------
function ReplanSection({ incidentId, linkedUnavailabilityId, executed, onChanged, t }: {
  incidentId: string
  linkedUnavailabilityId: string | null
  executed: Executed | null
  onChanged: () => Promise<void>
  t: TFn
}) {
  const { createDisplacementBaja, markShipmentSent } = useMaterialsTreatment()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [createdId, setCreatedId] = useState<string | null>(null)
  const unavailabilityId = linkedUnavailabilityId ?? createdId

  const createBaja = async () => {
    if (!executed?.expectedDate) return
    setBusy(true); setError(null)
    try {
      // Orden: la baja y el enlace del envio deben existir ANTES de enviar,
      // si no receive_material_shipment no puede cerrar la baja automaticamente.
      const id = await createDisplacementBaja(incidentId, executed.expectedDate)
      setCreatedId(id)
      if (executed.centralShipmentId) await markShipmentSent(executed.centralShipmentId)
      for (const sid of executed.donorShipmentIds) await markShipmentSent(sid)
      await onChanged()
    } catch (e: any) { setError(e.message) }
    finally { setBusy(false) }
  }

  return (
    <Section title={t(m('s3_title'))}>
      {error && <p className="text-sm text-red-600">{error}</p>}
      <button disabled={busy || !executed || !!unavailabilityId} className={BTN_PRIMARY} onClick={createBaja}>
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

export function MissingMaterialsSections({ incidentId, panelist, payload, linkedUnavailabilityId, onChanged, t }: {
  incidentId: string
  panelist: ReportedIncidentDetail['panelist']
  payload: Record<string, any> | null
  linkedUnavailabilityId: string | null
  onChanged: () => Promise<void>
  t: TFn
}) {
  const [local, setLocal] = useState<Executed | null>(null)
  if (!panelist) return null
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
      <StockSection panelist={panelist} reported={reported} onChanged={onChanged} t={t} />
      <SupplySection incidentId={incidentId} panelist={panelist} payload={payload} executed={executed}
        onExecuted={setLocal} onChanged={onChanged} t={t} />
      <ReplanSection incidentId={incidentId} linkedUnavailabilityId={linkedUnavailabilityId} executed={executed}
        onChanged={onChanged} t={t} />
    </div>
  )
}
