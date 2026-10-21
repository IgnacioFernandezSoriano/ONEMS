import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useTranslation } from '@/hooks/useTranslation'
import { useReportedIncidents, panelistRole } from '@/lib/hooks/useReportedIncidents'
import { useMaterialsTreatment, type NeedLine, type SupplyPlan } from '@/lib/hooks/useMaterialsTreatment'
import { useAuth } from '@/contexts/AuthContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { supabase } from '@/lib/supabase'
import type { ReportedIncidentDetail } from '@/lib/types'
import { BTN_PRIMARY, BTN_SECONDARY } from './buttonStyles'
import { ReportedIncidentHeader } from './ReportedIncidentHeader'
import { ReturnedSampleActions } from './ReturnedSampleActions'

interface TFn {
  (key: string, params?: Record<string, any>, fallback?: string): string
}

export function ReportedIncidentPanel({ incidentId, onBack }: { incidentId: string; onBack: () => void }) {
  const { t } = useTranslation()
  const { fetchIncident, resolve, actCancel, rerouteReturnedSample, signedPhotoUrl } = useReportedIncidents()
  const [inc, setInc] = useState<ReportedIncidentDetail | null>(null)
  const [photo, setPhoto] = useState<string | null>(null)
  const [note, setNote] = useState('')
  const [reply, setReply] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)

  const load = useCallback(async () => {
    const d = await fetchIncident(incidentId)
    setInc(d)
  }, [fetchIncident, incidentId])
  useEffect(() => { load() }, [load])
  useEffect(() => {
    const p = inc?.photo_url
    if (p && !/^https?:\/\//.test(p)) signedPhotoUrl(p).then(setPhoto)
    else setPhoto(p ?? null)
  }, [inc, signedPhotoUrl])

  const run = async (fn: () => Promise<void>, okKey: string) => {
    setBusy(true); setMsg(null)
    try { await fn(); await resolve(incidentId, 'in_progress'); await load(); setMsg(t(okKey)) }
    catch (e: any) { setMsg(t('common.error') + ': ' + e.message) }
    finally { setBusy(false) }
  }

  const doResolve = async (status: 'resolved' | 'dismissed') => {
    setBusy(true); setMsg(null)
    try { await resolve(incidentId, status, note || undefined, reply || undefined); onBack() }
    catch (e: any) { setMsg(t('common.error') + ': ' + e.message); setBusy(false) }
  }

  if (!inc) return <div>{t('common.loading')}</div>
  const detailId = inc.allocation_plan_detail_id

  return (
    <div className="max-w-3xl">
      <button onClick={onBack} className="text-blue-600 hover:text-blue-800 mb-4">← {t('reported_incidents.back')}</button>
      <h3 className="text-lg font-bold mb-2">{t(`reported_incidents.category.${inc.category}`)}</h3>
      <ReportedIncidentHeader inc={inc} role={panelistRole(inc)} />
      {detailId && <div className="text-sm text-gray-600 mb-4">{t('reported_incidents.linked_shipment')}: <span className="font-mono">{detailId.slice(0, 8)}</span></div>}
      {inc.description && <p className="bg-gray-50 rounded p-3 text-sm mb-3">{inc.description}</p>}
      {photo && <img src={photo} alt="" className="max-w-xs rounded border mb-3" />}

      {/* Bloque de acción por categoría (playbook) */}
      <div className="border rounded p-4 mb-4">
        {inc.category === 'parcel_returned' ? (
          <ReturnedSampleActions detail={inc.detail} busy={busy} t={t}
            onCancel={() => run(() => actCancel(detailId!), 'reported_incidents.done.cancelled')}
            onReroute={(toNode, week) => run(() => rerouteReturnedSample(detailId!, toNode, week), 'reported_incidents.done.rerouted')} />
        ) : inc.category === 'missing_materials' ? (
          <MissingMaterialsActions incidentId={incidentId} panelistId={inc.panelist_id} payload={inc.payload} t={t} />
        ) : inc.category === 'contact_data_change' ? (
          <ReadonlyPayload payload={inc.payload} kind="contact" t={t} />
        ) : inc.category === 'unreadable_label_receipt' ? (
          <ReadonlyPayload payload={inc.payload} kind="receipt" t={t} />
        ) : (
          <p className="text-sm text-gray-500">{t('reported_incidents.action.support_only')}</p>
        )}
        {msg && <p className="text-sm mt-2">{msg}</p>}
      </div>

      {/* Resolver + respuesta al panelista */}
      {inc.status !== 'auto_resolved' && (
      <div className="border rounded p-4">
        <label className="block text-sm font-medium mb-1">{t('reported_incidents.resolution_note')}</label>
        <textarea className="w-full border rounded p-2 text-sm mb-3" rows={2} value={note} onChange={e => setNote(e.target.value)} />
        <label className="block text-sm font-medium mb-1">{t('reported_incidents.reply_to_panelist')}</label>
        <textarea className="w-full border rounded p-2 text-sm mb-3" rows={2} value={reply} onChange={e => setReply(e.target.value)} />
        <div className="flex gap-2">
          <button disabled={busy} className={BTN_PRIMARY} onClick={() => doResolve('resolved')}>{t('reported_incidents.resolve')}</button>
          <button disabled={busy} className={BTN_SECONDARY} onClick={() => doResolve('dismissed')}>{t('reported_incidents.dismiss')}</button>
        </div>
      </div>
      )}
    </div>
  )
}

const CONTACT_FIELDS = ['mobile', 'email', 'language', 'address_line1', 'address_line2', 'address_city', 'address_country'] as const

function ReadonlyPayload({ payload, kind, t }: { payload: Record<string, any> | null; kind: 'contact' | 'receipt'; t: TFn }) {
  const isObj = payload != null && typeof payload === 'object'
  const body = (() => {
    if (!isObj) return <p className="text-sm text-gray-500">{t('reported_incidents.readonly.no_data')}</p>
    if (kind === 'receipt') {
      if (payload.no_candidates) return <p className="text-sm text-gray-500">{t('reported_incidents.readonly.no_candidates')}</p>
      if (payload.chosen_detail_id) {
        return (
          <p className="text-sm">
            {t('reported_incidents.readonly.chosen_shipment')}: <span className="font-mono">{String(payload.chosen_detail_id).slice(0, 8)}</span>
          </p>
        )
      }
      return <p className="text-sm text-gray-500">{t('reported_incidents.readonly.no_data')}</p>
    }
    const before = payload.before && typeof payload.before === 'object' ? payload.before : {}
    const after = payload.after && typeof payload.after === 'object' ? payload.after : {}
    const fields = CONTACT_FIELDS.filter(f => before[f] != null || after[f] != null)
    if (fields.length === 0) return <p className="text-sm text-gray-500">{t('reported_incidents.readonly.no_data')}</p>
    return (
      <table className="w-full text-sm">
        <thead>
          <tr className="text-left text-gray-500">
            <th className="py-1 font-medium" />
            <th className="py-1 font-medium">{t('reported_incidents.contact.before')}</th>
            <th className="py-1 font-medium">{t('reported_incidents.contact.after')}</th>
          </tr>
        </thead>
        <tbody>
          {fields.map(f => (
            <tr key={f} className="border-t">
              <td className="py-1 pr-2 text-gray-600">{t(`reported_incidents.contact.field.${f}`)}</td>
              <td className="py-1 pr-2">{before[f] != null ? String(before[f]) : '-'}</td>
              <td className="py-1">{after[f] != null ? String(after[f]) : '-'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    )
  })()
  return (
    <div>
      <p className="text-xs font-medium text-gray-500 mb-2">{t('reported_incidents.readonly.title')}</p>
      {body}
    </div>
  )
}

function MissingMaterialsActions({ incidentId, panelistId, payload, t }: {
  incidentId: string
  panelistId: string
  payload: Record<string, any> | null
  t: TFn
}) {
  const { reconcileStock, recomputeNeed, resolveSupply, executeSupply, createDisplacementBaja, linkShipmentToIncident, markShipmentSent } = useMaterialsTreatment()
  const effectiveAccountId = useEffectiveAccountId()
  const { profile } = useAuth()
  const accountId = effectiveAccountId || profile?.account_id

  const reportedMaterials: { name: string; quantity: number }[] = Array.isArray(payload?.materials) ? payload.materials : []
  const [catalogByKey, setCatalogByKey] = useState<Record<string, string>>({})
  const [realQty, setRealQty] = useState<Record<string, string>>({})
  const [reconciled, setReconciled] = useState<Record<string, boolean>>({})
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!accountId) return
    supabase.from('material_catalog').select('id, code, name').eq('account_id', accountId)
      .then(({ data }) => {
        const map: Record<string, string> = {}
        ;(data || []).forEach((row: any) => {
          if (row.name) map[String(row.name).toLowerCase()] = row.id
          if (row.code) map[String(row.code).toLowerCase()] = row.id
        })
        setCatalogByKey(map)
      })
  }, [accountId])

  const resolveMaterialId = (name: string): string | undefined => catalogByKey[name.toLowerCase()]

  const [needLines, setNeedLines] = useState<NeedLine[] | null>(null)
  const [supplyPlan, setSupplyPlan] = useState<SupplyPlan | null>(null)
  const [centralShipmentId, setCentralShipmentId] = useState<string | null>(null)
  const [donorShipmentIds, setDonorShipmentIds] = useState<string[]>([])
  const [supplyPrepared, setSupplyPrepared] = useState(false)
  const [displaced, setDisplaced] = useState(false)

  const handleReconcile = async (materialId: string) => {
    const qty = Number(realQty[materialId])
    if (Number.isNaN(qty)) return
    setBusy(true); setError(null)
    try {
      await reconcileStock(panelistId, materialId, qty)
      setReconciled(prev => ({ ...prev, [materialId]: true }))
    } catch (e: any) { setError(e.message) }
    finally { setBusy(false) }
  }

  const handleRecompute = async () => {
    setBusy(true); setError(null)
    try {
      const today = new Date().toISOString().slice(0, 10)
      const horizon = new Date()
      horizon.setDate(horizon.getDate() + 90)
      const lines = await recomputeNeed(panelistId, today, horizon.toISOString().slice(0, 10))
      setNeedLines(lines)
    } catch (e: any) { setError(e.message) }
    finally { setBusy(false) }
  }

  const handleResolveSupply = async () => {
    if (!needLines) return
    setBusy(true); setError(null)
    try {
      const plan = await resolveSupply(needLines, panelistId)
      setSupplyPlan(plan)
    } catch (e: any) { setError(e.message) }
    finally { setBusy(false) }
  }

  const handleExecuteSupply = async () => {
    if (!supplyPlan) return
    setBusy(true); setError(null)
    try {
      // Prepares the shipment(s) as `pending` only. They are NOT dispatched
      // here: dispatch happens after the baja is created and the incident is
      // linked (handleCreateBaja), so receive_material_shipment can always
      // find the link and auto-close the displacement.
      const { centralShipmentId: shipmentId, donorShipmentIds: donorIds } = await executeSupply(supplyPlan, panelistId)
      setCentralShipmentId(shipmentId)
      setDonorShipmentIds(donorIds)
      setSupplyPrepared(true)
    } catch (e: any) { setError(e.message) }
    finally { setBusy(false) }
  }

  const handleCreateBaja = async () => {
    setBusy(true); setError(null)
    try {
      let leadDays = 7
      if (accountId) {
        const { data } = await supabase.from('stock_settings')
          .select('purchase_lead_time_days, shipment_lead_time_days')
          .eq('account_id', accountId)
          .single()
        const hasPurchase = (supplyPlan?.toPurchase.length ?? 0) > 0
        const fromData = hasPurchase ? data?.purchase_lead_time_days : data?.shipment_lead_time_days
        leadDays = fromData ?? 7
      }
      const expected = new Date()
      expected.setDate(expected.getDate() + leadDays)
      const expectedDate = expected.toISOString().slice(0, 10)

      // Order matters: baja + link must exist BEFORE the shipment is sent,
      // otherwise receive_material_shipment can't find the incident to
      // auto-close it.
      const unavailabilityId = await createDisplacementBaja(incidentId, expectedDate)
      if (centralShipmentId) await linkShipmentToIncident(incidentId, centralShipmentId)

      if (centralShipmentId) await markShipmentSent(centralShipmentId)
      for (const donorShipmentId of donorShipmentIds) {
        await markShipmentSent(donorShipmentId)
      }

      if (unavailabilityId) setDisplaced(true)
    } catch (e: any) { setError(e.message) }
    finally { setBusy(false) }
  }

  return (
    <div className="space-y-5">
      {error && <p className="text-sm text-red-600">{error}</p>}

      <div>
        <h4 className="font-medium mb-2">{t('reported_incidents.materials.step1_title')}</h4>
        <div className="space-y-2">
          {reportedMaterials.map((m, idx) => {
            const materialId = resolveMaterialId(m.name)
            const rowKey = materialId ?? `unmatched-${idx}-${m.name}`
            const qtyKey = materialId ?? rowKey
            return (
              <div key={rowKey} className="flex items-center gap-2">
                <span className="text-sm w-40 truncate">{m.name}</span>
                <input type="number" className="border rounded p-2 text-sm w-28" disabled={!materialId}
                  value={realQty[qtyKey] ?? String(m.quantity)}
                  onChange={e => setRealQty(prev => ({ ...prev, [qtyKey]: e.target.value }))}
                  placeholder={t('reported_incidents.materials.real_qty')} />
                <button disabled={busy || !materialId || reconciled[qtyKey]} className={BTN_SECONDARY}
                  onClick={() => materialId && handleReconcile(materialId)}>
                  {t('reported_incidents.materials.real_qty')}
                </button>
                {materialId && reconciled[qtyKey] && <span className="text-green-600 text-sm">✓</span>}
                {!materialId && <span className="text-xs text-gray-500">{t('reported_incidents.materials.unmatched')}</span>}
              </div>
            )
          })}
        </div>
      </div>

      <div>
        <h4 className="font-medium mb-2">{t('reported_incidents.materials.step2_title')}</h4>
        <button disabled={busy} className={BTN_SECONDARY} onClick={handleRecompute}>
          {t('reported_incidents.materials.step2_title')}
        </button>
        {needLines && (
          <table className="w-full text-sm mt-2">
            <tbody>
              {needLines.map(n => (
                <tr key={n.material_id} className="border-t">
                  <td className="py-1">{n.material_name}</td>
                  <td className="py-1">{n.quantity_needed} {n.unit_measure}</td>
                  <td className="py-1">
                    {n.is_blocking && (
                      <span className="bg-red-100 text-red-700 text-xs px-2 py-0.5 rounded">
                        {t('reported_incidents.materials.blocking_badge')}
                      </span>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      <div>
        <h4 className="font-medium mb-2">{t('reported_incidents.materials.step3_title')}</h4>
        <button disabled={busy || !needLines} className={BTN_SECONDARY} onClick={handleResolveSupply}>
          {t('reported_incidents.materials.step3_title')}
        </button>
        {supplyPlan && (
          <div className="text-sm mt-2 space-y-1">
            {supplyPlan.fromCentral.length > 0 && (
              <div>{t('reported_incidents.materials.from_central')}: {supplyPlan.fromCentral.map(c => `${c.material_id} (${c.quantity})`).join(', ')}</div>
            )}
            {supplyPlan.fromDonor.map((d, i) => (
              <div key={i}>{t('reported_incidents.materials.from_donor', { name: d.donor_name })}: {d.material_id} ({d.quantity})</div>
            ))}
            {supplyPlan.toPurchase.length > 0 && (
              <div>{t('reported_incidents.materials.to_purchase')}: {supplyPlan.toPurchase.map(p => `${p.material_id} (${p.quantity})`).join(', ')}</div>
            )}
            <button disabled={busy || supplyPrepared} className={BTN_PRIMARY} onClick={handleExecuteSupply}>
              {t('reported_incidents.materials.execute_supply')}
            </button>
          </div>
        )}
      </div>

      <div>
        <h4 className="font-medium mb-2">{t('reported_incidents.materials.step4_title')}</h4>
        <button disabled={busy || !supplyPrepared || displaced} className={BTN_PRIMARY} onClick={handleCreateBaja}>
          {t('reported_incidents.materials.create_baja')}
        </button>
      </div>

      <div>
        <h4 className="font-medium mb-2">{t('reported_incidents.materials.step5_title')}</h4>
        <p className="text-sm text-gray-500 mb-2">{t('reported_incidents.materials.close_hint')}</p>
        <Link to="/incidents/panelist-availability" className="text-blue-600 hover:text-blue-800 text-sm">
          {t('reported_incidents.materials.go_to_availability')}
        </Link>
      </div>
    </div>
  )
}
