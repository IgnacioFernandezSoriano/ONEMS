import { useCallback, useEffect, useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { useReportedIncidents, panelistRole } from '@/lib/hooks/useReportedIncidents'
import type { ReportedIncidentDetail } from '@/lib/types'
import { BTN_PRIMARY, BTN_SECONDARY } from './buttonStyles'
import { ReportedIncidentHeader } from './ReportedIncidentHeader'
import { ReturnedSampleActions } from './ReturnedSampleActions'
import { MissingMaterialsSections } from './MissingMaterialsSections'

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
          <MissingMaterialsSections incidentId={incidentId} panelist={inc.panelist} payload={inc.payload}
            linkedUnavailabilityId={inc.linked_unavailability_id} t={t}
            onChanged={async () => { await resolve(incidentId, 'in_progress'); await load() }} />
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
