import { Fragment, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { AlertTriangle, ChevronDown, ChevronRight, Loader2, CheckCircle2 } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { ClHelpLink } from '@/components/carrier-link/ClHelpLink'
import { ClBadge } from '@/components/carrier-link/ClBadge'
import { ClPager } from '@/components/carrier-link/ClDeliveries'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { SelectAccountNotice } from '@/components/carrier-link/SelectAccountNotice'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import { periodLabel } from '@/lib/carrierLink/deliveryView'
import { clampPage } from '@/lib/carrierLink/sampleView'
import { useClFeedOptions } from '@/hooks/carrierLink/useClFeedOptions'
import { useClAccountMembers, useClIncident, useClIncidents, type ClAccountMember } from '@/hooks/carrierLink/useClIncidents'
import {
  INCIDENTS_PAGE_SIZE,
  INCIDENT_STATUS_FILTERS,
  INCIDENT_STATUS_STYLE,
  INCIDENT_TYPES,
  NOTE_MAX,
  closedHowKey,
  filtersFromSearch,
  incidentStatusKey,
  incidentTypeKey,
  isIncidentEditable,
  isIncidentType,
  notificationCounts,
  periodDetailLines,
  type IncidentDetail,
  type IncidentFilters,
  type IncidentStatusFilter,
} from '@/lib/carrierLink/incidentView'

const input = 'border border-gray-300 rounded-lg px-3 py-2 text-sm'
const btnPrimary = 'inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50'
const btnSecondary = 'px-3 py-2 border border-gray-300 rounded-lg bg-white hover:bg-gray-50 disabled:opacity-50'

const fmt = (d: string | null) => (d ? new Date(d).toLocaleString() : '-')

function StatusBadge({ status }: { status: string }) {
  const { t } = useTranslation()
  return (
    <span className={`px-2 py-0.5 rounded-full text-xs font-medium whitespace-nowrap ${INCIDENT_STATUS_STYLE[status] ?? 'bg-gray-100 text-gray-700'}`}>
      {t(incidentStatusKey(status))}
    </span>
  )
}

/** Incidencias de Carrier Link: lista con filtros y, al desplegar una fila, su detalle con las acciones (con Edit). */
export function ClIncidents() {
  const { t, locale } = useTranslation()
  const { canEdit } = usePermissions()
  const accountId = useEffectiveAccountId()
  const readOnly = !canEdit('cl_incidents')
  const { feeds } = useClFeedOptions(accountId)
  const members = useClAccountMembers(accountId, !readOnly)

  const [searchParams] = useSearchParams()
  const [filters, setFilters] = useState<IncidentFilters>(() => filtersFromSearch(searchParams))
  const [page, setPage] = useState(0)
  const [openId, setOpenId] = useState<string | null>(null)
  const { items, total, loading, error, refetch } = useClIncidents(accountId, filters, page)

  useEffect(() => {
    if (loading) return
    const c = clampPage(page, total, INCIDENTS_PAGE_SIZE)
    if (c !== page) setPage(c)
  }, [loading, page, total])

  const setFilter = (f: Partial<IncidentFilters>) => {
    setFilters((cur) => ({ ...cur, ...f }))
    setPage(0)
    setOpenId(null)
  }

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-gray-900">{t('cl.incidents.title')}</h1>
        <ClBadge />
        <ClHelpLink section="incidents" />
        {readOnly && <ReadOnlyBadge />}
      </div>
      <p className="text-sm text-gray-600">{t('cl.incidents.help')}</p>
      {accountId === null && <SelectAccountNotice />}

      {accountId !== null && (
        <>
          <div className="flex flex-wrap items-end gap-3">
            <label className="text-sm">
              <span className="block text-gray-600 mb-1">{t('cl.incidents.filter.status')}</span>
              <select
                className={input}
                value={filters.status}
                onChange={(e) => setFilter({ status: e.target.value as IncidentStatusFilter })}
              >
                {INCIDENT_STATUS_FILTERS.map((s) => (
                  <option key={s} value={s}>
                    {t(`cl.incidents.filter.status.${s}`)}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              <span className="block text-gray-600 mb-1">{t('cl.incidents.filter.type')}</span>
              <select
                className={input}
                value={filters.type ?? ''}
                onChange={(e) => setFilter({ type: isIncidentType(e.target.value) ? e.target.value : null })}
              >
                <option value="">{t('cl.incidents.filter.all_types')}</option>
                {INCIDENT_TYPES.map((type) => (
                  <option key={type} value={type}>
                    {t(incidentTypeKey(type))}
                  </option>
                ))}
              </select>
            </label>
            <label className="text-sm">
              <span className="block text-gray-600 mb-1">{t('cl.connectors.connector')}</span>
              <select className={input} value={filters.feedId ?? ''} onChange={(e) => setFilter({ feedId: e.target.value || null })}>
                <option value="">{t('cl.monitor.all_connectors')}</option>
                {feeds.map((f) => (
                  <option key={f.id} value={f.id}>
                    {f.name}
                  </option>
                ))}
              </select>
            </label>
          </div>

          {error && (
            <div className="flex items-center gap-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">
              <AlertTriangle className="w-4 h-4" /> {t(clErrorKey(error))}
            </div>
          )}

          <div className="bg-white border border-gray-200 rounded-lg overflow-x-auto">
            <table className="min-w-full text-sm">
              <thead className="bg-gray-50 text-gray-600">
                <tr>
                  <th className="px-2 py-2" />
                  <th className="text-start px-3 py-2">{t('cl.incidents.col.type')}</th>
                  <th className="text-start px-3 py-2">{t('cl.connectors.connector')}</th>
                  <th className="text-start px-3 py-2">{t('cl.incidents.col.status')}</th>
                  <th className="text-start px-3 py-2">{t('cl.incidents.col.periods')}</th>
                  <th className="text-start px-3 py-2">{t('cl.incidents.col.assignee')}</th>
                  <th className="text-start px-3 py-2">{t('cl.incidents.col.updated')}</th>
                </tr>
              </thead>
              <tbody>
                {loading && items.length === 0 && (
                  <tr>
                    <td colSpan={7} className="px-3 py-4 text-center text-gray-500">
                      <Loader2 className="w-4 h-4 animate-spin inline" />
                    </td>
                  </tr>
                )}
                {!loading && items.length === 0 && (
                  <tr>
                    <td colSpan={7} className="px-3 py-4 text-center text-gray-500">
                      {t('cl.incidents.empty')}
                    </td>
                  </tr>
                )}
                {items.map((i) => {
                  const isOpen = openId === i.id
                  const how = closedHowKey(i)
                  return (
                    <Fragment key={i.id}>
                      <tr className="border-t border-gray-100 align-top hover:bg-gray-50 cursor-pointer" onClick={() => setOpenId(isOpen ? null : i.id)}>
                        <td className="px-2 py-2 text-gray-500">
                          {isOpen ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4 rtl:rotate-180" />}
                        </td>
                        <td className="px-3 py-2 font-medium text-gray-900">
                          <button type="button" aria-expanded={isOpen} className="text-start">
                            {t(incidentTypeKey(i.incident_type))}
                          </button>
                        </td>
                        <td className="px-3 py-2">{i.feed_name ?? '-'}</td>
                        <td className="px-3 py-2">
                          <StatusBadge status={i.status} />
                          {how && <div className="text-xs text-gray-500 mt-1">{t(how)}</div>}
                        </td>
                        <td className="px-3 py-2">
                          {i.periods_count}
                          {i.last_period && (
                            <span className="text-gray-500" dir="auto">
                              {' '}
                              · {periodLabel(i.last_period.period_start, i.last_period.period_end, locale)}
                            </span>
                          )}
                        </td>
                        <td className="px-3 py-2">{i.assignee_name ?? <span className="text-gray-400">{t('cl.incidents.unassigned')}</span>}</td>
                        <td className="px-3 py-2 whitespace-nowrap">{fmt(i.updated_at)}</td>
                      </tr>
                      {isOpen && (
                        <tr className="bg-gray-50">
                          <td />
                          <td colSpan={6} className="px-3 py-3">
                            <IncidentPanel id={i.id} readOnly={readOnly} members={members} onChanged={() => void refetch()} />
                          </td>
                        </tr>
                      )}
                    </Fragment>
                  )
                })}
              </tbody>
            </table>
            <ClPager page={page} total={total} pageSize={INCIDENTS_PAGE_SIZE} loading={loading} onPage={setPage} />
          </div>
        </>
      )}
    </div>
  )
}

/** Detalle de una incidencia: periodos, avisos enviados (solo recuentos), responsable, estado, nota y cierre a mano. */
function IncidentPanel(props: { id: string; readOnly: boolean; members: ClAccountMember[]; onChanged: () => void }) {
  const { t } = useTranslation()
  const { incident, loading, error, update, close } = useClIncident(props.id)

  if (loading && !incident) return <Loader2 className="w-4 h-4 animate-spin" />
  if (error) return <p className="text-sm text-red-600">{t(clErrorKey(error))}</p>
  if (!incident) return null
  return <IncidentBody incident={incident} {...props} update={update} close={close} />
}

function IncidentBody(props: {
  incident: IncidentDetail
  readOnly: boolean
  members: ClAccountMember[]
  onChanged: () => void
  update: ReturnType<typeof useClIncident>['update']
  close: ReturnType<typeof useClIncident>['close']
}) {
  const { t, locale } = useTranslation()
  const { incident: inc, readOnly } = props
  const editable = !readOnly && isIncidentEditable(inc.status)
  const [status, setStatus] = useState<'open' | 'in_progress'>(inc.status === 'in_progress' ? 'in_progress' : 'open')
  const [assignee, setAssignee] = useState(inc.assignee_id ?? '')
  const [note, setNote] = useState(inc.notes ?? '')
  const [closing, setClosing] = useState(false)
  const [closeNote, setCloseNote] = useState('')
  const [busy, setBusy] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const [saved, setSaved] = useState(false)

  // Al recargar la incidencia (tras guardar), el formulario muestra lo guardado.
  useEffect(() => {
    setStatus(inc.status === 'in_progress' ? 'in_progress' : 'open')
    setAssignee(inc.assignee_id ?? '')
    setNote(inc.notes ?? '')
  }, [inc.status, inc.assignee_id, inc.notes])

  const dirty =
    status !== (inc.status === 'in_progress' ? 'in_progress' : 'open') || assignee !== (inc.assignee_id ?? '') || note !== (inc.notes ?? '')

  // El responsable actual puede no estar en la lista (lista vacia sin derecho a verla): se ofrece igual.
  const memberOptions =
    inc.assignee_id && !props.members.some((m) => m.user_id === inc.assignee_id)
      ? [{ user_id: inc.assignee_id, label: inc.assignee_name ?? inc.assignee_id }, ...props.members]
      : props.members

  const save = async () => {
    if (note.length > NOTE_MAX) return setErr('cl.incidents.note_too_long')
    setBusy(true)
    setErr(null)
    setSaved(false)
    const r = await props.update({
      status: status !== inc.status ? status : undefined,
      assigneeId: assignee === (inc.assignee_id ?? '') ? undefined : assignee || null,
      note: note !== (inc.notes ?? '') ? note : undefined,
    })
    setBusy(false)
    if (r.error) setErr(clErrorKey(r.error))
    else {
      setSaved(true)
      props.onChanged()
    }
  }

  const confirmClose = async () => {
    if (closeNote.length > NOTE_MAX) return setErr('cl.incidents.note_too_long')
    setBusy(true)
    setErr(null)
    const r = await props.close(closeNote)
    setBusy(false)
    if (r.error) setErr(clErrorKey(r.error))
    else {
      setClosing(false)
      props.onChanged()
    }
  }

  const notices = notificationCounts(inc.notifications)
  const how = closedHowKey(inc)

  return (
    <div className="space-y-4 text-sm">
      <div className="flex flex-wrap items-center gap-3">
        <StatusBadge status={inc.status} />
        <span className="text-gray-600">{t('cl.incidents.opened_at', { date: fmt(inc.opened_at) })}</span>
        {how && (
          <span className="text-gray-600">
            {t(how)} · {fmt(inc.closed_at)}
            {inc.closed_how === 'manual' && inc.closed_by_name ? ` · ${inc.closed_by_name}` : ''}
          </span>
        )}
        {inc.plan_name && <span className="text-gray-600">{t('cl.incidents.plan', { plan: inc.plan_name })}</span>}
      </div>
      <p className="text-gray-700">{t(`cl.incidents.explain.${inc.incident_type}`, undefined, '')}</p>

      <div>
        <h3 className="font-medium text-gray-900 mb-1">{t('cl.incidents.periods', { count: inc.periods.length })}</h3>
        {inc.periods.length === 0 ? (
          <p className="text-gray-500">-</p>
        ) : (
          <ul className="space-y-1">
            {inc.periods.map((p) => (
              <li key={p.key} className="flex flex-wrap gap-x-3">
                <span className="font-medium" dir="auto">
                  {periodLabel(p.period_start, p.period_end, locale)}
                </span>
                {periodDetailLines(inc.incident_type, p, (code) => t(clErrorKey({ message: code }))).map((l, i) => (
                  <span key={i} className="text-gray-700">
                    {t(l.key, l.params)}
                  </span>
                ))}
                <span className="text-gray-500">{t('cl.incidents.detected_at', { date: fmt(p.detected_at) })}</span>
              </li>
            ))}
          </ul>
        )}
        {inc.incident_type === 'unknown_data' && (inc.unknown_products.length > 0 || inc.unknown_points.length > 0) && (
          <div className="mt-2 space-y-1 text-gray-700">
            {inc.unknown_products.length > 0 && <p>{t('cl.incidents.unknown_products', { values: inc.unknown_products.join(', ') })}</p>}
            {inc.unknown_points.length > 0 && (
              <p>
                {t('cl.incidents.unknown_points', {
                  values: inc.unknown_points.map((p) => `${p.place_ref ?? '-'} / ${p.mode_ref ?? '-'}`).join(', '),
                })}
              </p>
            )}
          </div>
        )}
      </div>

      <div>
        <h3 className="font-medium text-gray-900 mb-1">{t('cl.incidents.notices')}</h3>
        {notices.length === 0 ? (
          <p className="text-gray-500">{t('cl.incidents.no_notices')}</p>
        ) : (
          <ul className="space-y-1">
            {notices.map((c) => (
              <li key={c.kind} className="text-gray-700">
                <span className="font-medium">{t(`cl.incidents.recipient.${c.kind === 'carrier' ? 'carrier' : 'account'}`)}</span>
                {': '}
                {t('cl.incidents.notice_counts', { sent: c.sent, pending: c.pending, failed: c.failed, skipped: c.skipped })}
              </li>
            ))}
          </ul>
        )}
        {!inc.carrier_notified && ['missing_delivery', 'delivery_rejected', 'high_rejection'].includes(inc.incident_type) && (
          <p className="text-xs text-gray-500 mt-1">{t('cl.incidents.carrier_without_email')}</p>
        )}
      </div>

      {editable ? (
        <div className="space-y-3 border-t border-gray-200 pt-3">
          <div className="flex flex-wrap items-end gap-3">
            <label>
              <span className="block text-gray-600 mb-1">{t('cl.incidents.col.status')}</span>
              <select className={input} value={status} onChange={(e) => setStatus(e.target.value as 'open' | 'in_progress')}>
                <option value="open">{t('cl.incidents.status.open')}</option>
                <option value="in_progress">{t('cl.incidents.status.in_progress')}</option>
              </select>
            </label>
            <label>
              <span className="block text-gray-600 mb-1">{t('cl.incidents.col.assignee')}</span>
              <select className={`${input} min-w-[14rem]`} value={assignee} onChange={(e) => setAssignee(e.target.value)}>
                <option value="">{t('cl.incidents.unassigned')}</option>
                {memberOptions.map((m) => (
                  <option key={m.user_id} value={m.user_id}>
                    {m.label}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <label className="block">
            <span className="block text-gray-600 mb-1">{t('cl.incidents.note')}</span>
            <textarea
              className={`${input} w-full`}
              rows={3}
              maxLength={NOTE_MAX}
              value={note}
              onChange={(e) => setNote(e.target.value)}
              dir="auto"
            />
          </label>
          <div className="flex flex-wrap items-center gap-2">
            <button type="button" disabled={busy || !dirty} className={btnPrimary} onClick={() => void save()}>
              {busy ? t('common.saving') : t('common.save')}
            </button>
            {!closing && (
              <button
                type="button"
                disabled={busy}
                className={btnSecondary}
                onClick={() => {
                  setErr(null)
                  setClosing(true)
                }}
              >
                {t('cl.incidents.close')}
              </button>
            )}
            {saved && !dirty && (
              <span className="text-green-700 inline-flex items-center gap-1">
                <CheckCircle2 className="w-4 h-4" /> {t('cl.incidents.saved')}
              </span>
            )}
          </div>
          {closing && (
            <div className="max-w-xl space-y-2 bg-amber-50 border border-amber-200 rounded-lg p-3">
              <div className="font-medium text-amber-900">{t('cl.incidents.close_title')}</div>
              <p className="text-amber-900">{t(`cl.incidents.close_effect.${inc.incident_type === 'missing_delivery' ? 'missing' : 'other'}`)}</p>
              <label className="block">
                <span className="block text-amber-900 mb-1">{t('cl.incidents.close_note')}</span>
                <textarea
                  className={`${input} w-full bg-white`}
                  rows={2}
                  maxLength={NOTE_MAX}
                  value={closeNote}
                  onChange={(e) => setCloseNote(e.target.value)}
                  dir="auto"
                />
              </label>
              <div className="flex gap-2">
                <button
                  type="button"
                  className="px-3 py-1 rounded-lg bg-red-600 text-white disabled:opacity-50"
                  disabled={busy}
                  onClick={() => void confirmClose()}
                >
                  {t('cl.incidents.close_confirm')}
                </button>
                <button type="button" className="px-3 py-1 border border-gray-300 rounded-lg bg-white" disabled={busy} onClick={() => setClosing(false)}>
                  {t('common.cancel')}
                </button>
              </div>
            </div>
          )}
          {err && <p className="text-red-600">{t(err)}</p>}
        </div>
      ) : (
        <div className="space-y-1 border-t border-gray-200 pt-3 text-gray-700">
          <p>
            {t('cl.incidents.col.assignee')}: {inc.assignee_name ?? t('cl.incidents.unassigned')}
          </p>
          {inc.notes && (
            <p className="whitespace-pre-wrap" dir="auto">
              {t('cl.incidents.note')}: {inc.notes}
            </p>
          )}
        </div>
      )}
    </div>
  )
}
