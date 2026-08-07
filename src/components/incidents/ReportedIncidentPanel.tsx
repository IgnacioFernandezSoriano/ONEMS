import { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useTranslation } from '@/hooks/useTranslation'
import { useReportedIncidents } from '@/lib/hooks/useReportedIncidents'
import { useMaterialsTreatment, type NeedLine, type SupplyPlan } from '@/lib/hooks/useMaterialsTreatment'
import { useAuth } from '@/contexts/AuthContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { supabase } from '@/lib/supabase'
import type { ReportedIncident } from '@/lib/types'

// Estilos de botón: no hay clases globales `btn-primary`/`btn-secondary` en el proyecto;
// se reutiliza el patrón de utilidades Tailwind usado en ProposalReviewPanel.tsx.
const BTN_PRIMARY = 'bg-blue-600 text-white px-4 py-2 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed'
const BTN_SECONDARY = 'bg-gray-200 text-gray-700 px-4 py-2 rounded-lg hover:bg-gray-300 disabled:opacity-50 disabled:cursor-not-allowed'

type FetchedIncident = ReportedIncident & {
  panelist?: { name: string; panelist_code: string; telegram_id: string | null; mobile: string | null; language: string | null } | null
  detail?: { id: string; fecha_programada: string | null; status: string; origin_node_id: string | null; destination_node_id: string | null } | null
}

interface TFn {
  (key: string, params?: Record<string, any>, fallback?: string): string
}

export function ReportedIncidentPanel({ incidentId, onBack }: { incidentId: string; onBack: () => void }) {
  const { t } = useTranslation()
  const { fetchIncident, resolve, actMarkReceived, actInvalidate, actReschedule, actCancel,
          actUpdateContact, actCreateUnavailability, signedPhotoUrl } = useReportedIncidents()
  const [inc, setInc] = useState<FetchedIncident | null>(null)
  const [photo, setPhoto] = useState<string | null>(null)
  const [note, setNote] = useState('')
  const [reply, setReply] = useState('')
  const [busy, setBusy] = useState(false)
  const [msg, setMsg] = useState<string | null>(null)

  const load = useCallback(async () => {
    const d = await fetchIncident(incidentId)
    setInc(d as FetchedIncident | null)
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
  const panelistName = inc.panelist_name ?? inc.panelist?.name ?? '-'
  const panelistCode = inc.panelist_code ?? inc.panelist?.panelist_code ?? '-'

  return (
    <div className="max-w-3xl">
      <button onClick={onBack} className="text-blue-600 hover:text-blue-800 mb-4">← {t('reported_incidents.back')}</button>
      <h3 className="text-lg font-bold mb-2">{t(`reported_incidents.category.${inc.category}`)}</h3>
      <div className="text-sm text-gray-600 mb-4">
        <div>{panelistName} · <span className="font-mono">{panelistCode}</span></div>
        {detailId && <div>{t('reported_incidents.linked_shipment')}: <span className="font-mono">{detailId.slice(0, 8)}</span></div>}
      </div>
      {inc.description && <p className="bg-gray-50 rounded p-3 text-sm mb-3">{inc.description}</p>}
      {photo && <img src={photo} alt="" className="max-w-xs rounded border mb-3" />}

      {/* Bloque de acción por categoría (playbook) */}
      <div className="border rounded p-4 mb-4">
        {inc.category === 'unreadable_label_receipt' || inc.category === 'tag_photo_problem' ? (
          <button disabled={busy || !detailId} className={BTN_PRIMARY}
            onClick={() => run(() => actMarkReceived(detailId!), 'reported_incidents.done.received')}>
            {t('reported_incidents.action.mark_received')}
          </button>
        ) : inc.category === 'parcel_damaged' ? (
          <button disabled={busy || !detailId} className={BTN_PRIMARY}
            onClick={() => run(() => actInvalidate(detailId!, note), 'reported_incidents.done.invalidated')}>
            {t('reported_incidents.action.invalidate')}
          </button>
        ) : inc.category === 'parcel_returned' ? (
          <ReturnedOrMaterialsActions busy={busy} hasDetail={!!detailId}
            onReschedule={(d) => run(() => actReschedule(detailId!, d), 'reported_incidents.done.rescheduled')}
            onCancel={() => run(() => actCancel(detailId!), 'reported_incidents.done.cancelled')} t={t} />
        ) : inc.category === 'missing_materials' ? (
          <MissingMaterialsActions incidentId={incidentId} panelistId={inc.panelist_id} payload={inc.payload} t={t} />
        ) : inc.category === 'unavailability_request' ? (
          <UnavailabilityAction busy={busy}
            onCreate={(s, e, r) => run(() => actCreateUnavailability(incidentId, s, e, r), 'reported_incidents.done.baja')} t={t} />
        ) : inc.category === 'contact_data_change' ? (
          <ContactAction busy={busy} payload={inc.payload} currentMobile={inc.panelist?.mobile ?? null}
            onApply={(tg, ph, lang) => run(() => actUpdateContact(inc.panelist_id, tg, ph, lang), 'reported_incidents.done.contact')} t={t} />
        ) : (
          <p className="text-sm text-gray-500">{t('reported_incidents.action.support_only')}</p>
        )}
        {msg && <p className="text-sm mt-2">{msg}</p>}
      </div>

      {/* Resolver + respuesta al panelista */}
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
    </div>
  )
}

function ReturnedOrMaterialsActions({ busy, hasDetail, onReschedule, onCancel, t }: {
  busy: boolean; hasDetail: boolean
  onReschedule: (newDate: string) => void
  onCancel: () => void
  t: TFn
}) {
  const [newDate, setNewDate] = useState('')
  return (
    <div className="space-y-3">
      <div>
        <label className="block text-sm font-medium mb-1">{t('reported_incidents.action.new_date')}</label>
        <div className="flex gap-2">
          <input type="date" className="border rounded p-2 text-sm" value={newDate} onChange={e => setNewDate(e.target.value)} />
          <button disabled={busy || !hasDetail || !newDate} className={BTN_PRIMARY}
            onClick={() => onReschedule(newDate)}>
            {t('reported_incidents.action.reschedule')}
          </button>
        </div>
      </div>
      <button disabled={busy || !hasDetail} className={BTN_SECONDARY} onClick={onCancel}>
        {t('reported_incidents.action.cancel_shipment')}
      </button>
    </div>
  )
}

function UnavailabilityAction({ busy, onCreate, t }: {
  busy: boolean
  onCreate: (start: string, end: string, reason?: string) => void
  t: TFn
}) {
  const [start, setStart] = useState('')
  const [end, setEnd] = useState('')
  const [reason, setReason] = useState('')
  return (
    <div className="space-y-3">
      <div className="flex gap-2">
        <div>
          <label className="block text-sm font-medium mb-1">{t('reported_incidents.action.start_date')}</label>
          <input type="date" className="border rounded p-2 text-sm" value={start} onChange={e => setStart(e.target.value)} />
        </div>
        <div>
          <label className="block text-sm font-medium mb-1">{t('reported_incidents.action.end_date')}</label>
          <input type="date" className="border rounded p-2 text-sm" value={end} onChange={e => setEnd(e.target.value)} />
        </div>
      </div>
      <div>
        <label className="block text-sm font-medium mb-1">{t('reported_incidents.action.reason')}</label>
        <input type="text" className="w-full border rounded p-2 text-sm" value={reason} onChange={e => setReason(e.target.value)} />
      </div>
      <button disabled={busy || !start || !end} className={BTN_PRIMARY}
        onClick={() => onCreate(start, end, reason || undefined)}>
        {t('reported_incidents.action.create_unavailability')}
      </button>
    </div>
  )
}

function ContactAction({ busy, payload, currentMobile, onApply, t }: {
  busy: boolean
  payload: Record<string, any> | null
  currentMobile: string | null
  onApply: (telegramId: string | undefined, phone: string | undefined, language: string | undefined) => void
  t: TFn
}) {
  const [telegramId, setTelegramId] = useState(payload?.telegram_id ?? '')
  const [phone, setPhone] = useState(payload?.mobile ?? currentMobile ?? '')
  const [language, setLanguage] = useState(payload?.language ?? '')
  return (
    <div className="space-y-3">
      {payload && (
        <div className="bg-gray-50 rounded p-3 text-xs text-gray-600">
          <div className="font-medium mb-1">{t('reported_incidents.action.requested_data')}</div>
          <pre className="whitespace-pre-wrap break-all">{JSON.stringify(payload, null, 2)}</pre>
        </div>
      )}
      <div>
        <label className="block text-sm font-medium mb-1">{t('reported_incidents.action.telegram_id')}</label>
        <input type="text" className="w-full border rounded p-2 text-sm" value={telegramId} onChange={e => setTelegramId(e.target.value)} />
      </div>
      <div>
        <label className="block text-sm font-medium mb-1">{t('reported_incidents.action.phone')}</label>
        <input type="text" className="w-full border rounded p-2 text-sm" value={phone} onChange={e => setPhone(e.target.value)} />
      </div>
      <div>
        <label className="block text-sm font-medium mb-1">{t('reported_incidents.action.language')}</label>
        <input type="text" className="w-full border rounded p-2 text-sm" value={language} onChange={e => setLanguage(e.target.value)} />
      </div>
      <button disabled={busy} className={BTN_PRIMARY}
        onClick={() => onApply(telegramId || undefined, phone || undefined, language || undefined)}>
        {t('reported_incidents.action.apply_contact')}
      </button>
    </div>
  )
}

function MissingMaterialsActions({ incidentId, panelistId, payload, t }: {
  incidentId: string
  panelistId: string
  payload: Record<string, any> | null
  t: TFn
}) {
  const { reconcileStock, recomputeNeed, resolveSupply, executeSupply, createDisplacementBaja, linkShipmentToIncident } = useMaterialsTreatment()
  const effectiveAccountId = useEffectiveAccountId()
  const { profile } = useAuth()
  const accountId = effectiveAccountId || profile?.account_id

  const reportedMaterials: { material_id: string; material_name?: string }[] = Array.isArray(payload?.materials) ? payload.materials : []
  const [realQty, setRealQty] = useState<Record<string, string>>({})
  const [reconciled, setReconciled] = useState<Record<string, boolean>>({})
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const [needLines, setNeedLines] = useState<NeedLine[] | null>(null)
  const [supplyPlan, setSupplyPlan] = useState<SupplyPlan | null>(null)
  const [centralShipmentId, setCentralShipmentId] = useState<string | null>(null)
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
      const { centralShipmentId: shipmentId } = await executeSupply(supplyPlan, panelistId)
      setCentralShipmentId(shipmentId)
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

      const unavailabilityId = await createDisplacementBaja(incidentId, expectedDate)
      if (centralShipmentId) await linkShipmentToIncident(incidentId, centralShipmentId)
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
          {reportedMaterials.map(m => (
            <div key={m.material_id} className="flex items-center gap-2">
              <span className="text-sm w-40 truncate">{m.material_name || m.material_id}</span>
              <input type="number" className="border rounded p-2 text-sm w-28"
                value={realQty[m.material_id] ?? ''}
                onChange={e => setRealQty(prev => ({ ...prev, [m.material_id]: e.target.value }))}
                placeholder={t('reported_incidents.materials.real_qty')} />
              <button disabled={busy || reconciled[m.material_id]} className={BTN_SECONDARY}
                onClick={() => handleReconcile(m.material_id)}>
                {t('reported_incidents.materials.real_qty')}
              </button>
              {reconciled[m.material_id] && <span className="text-green-600 text-sm">✓</span>}
            </div>
          ))}
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
            <button disabled={busy || !!centralShipmentId} className={BTN_PRIMARY} onClick={handleExecuteSupply}>
              {t('reported_incidents.materials.execute_supply')}
            </button>
          </div>
        )}
      </div>

      <div>
        <h4 className="font-medium mb-2">{t('reported_incidents.materials.step4_title')}</h4>
        <button disabled={busy || !supplyPlan || displaced} className={BTN_PRIMARY} onClick={handleCreateBaja}>
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
