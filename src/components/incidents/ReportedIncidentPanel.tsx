import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { useReportedIncidents } from '@/lib/hooks/useReportedIncidents'
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
        ) : inc.category === 'parcel_returned' || inc.category === 'missing_materials' ? (
          <ReturnedOrMaterialsActions busy={busy} hasDetail={!!detailId}
            onReschedule={(d) => run(() => actReschedule(detailId!, d), 'reported_incidents.done.rescheduled')}
            onCancel={() => run(() => actCancel(detailId!), 'reported_incidents.done.cancelled')} t={t} />
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
