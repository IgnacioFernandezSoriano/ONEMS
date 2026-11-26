import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { AlertTriangle } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { ClHelpLink } from '@/components/carrier-link/ClHelpLink'
import { ClBadge } from '@/components/carrier-link/ClBadge'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useAuth } from '@/contexts/AuthContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { SelectAccountNotice } from '@/components/carrier-link/SelectAccountNotice'
import { ClDeliveriesTable, ClPager } from '@/components/carrier-link/ClDeliveries'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import { useClPlans } from '@/hooks/carrierLink/useClPlans'
import { useClFeedOptions } from '@/hooks/carrierLink/useClFeedOptions'
import { useClDeliveries, DELIVERIES_PAGE_SIZE } from '@/hooks/carrierLink/useClDeliveries'
import { useClIncidentCounts } from '@/hooks/carrierLink/useClIncidents'
import { useClMonitor } from '@/hooks/carrierLink/useClMonitor'
import { MONITOR_PAGE_SIZE, alertDetailLines, alertLabelKey } from '@/lib/carrierLink/monitorView'
import { DELIVERY_STATUSES, deliveryPhaseKey, deliveryStatusKey } from '@/lib/carrierLink/deliveryView'
import { INCIDENT_TYPES, incidentTypeKey, incidentsLink } from '@/lib/carrierLink/incidentView'
import { clampPage } from '@/lib/carrierLink/sampleView'
import { ClCsvButton } from '@/components/carrier-link/ClCsvButton'
import { csvDate } from '@/lib/carrierLink/clCsv'

const input = 'border border-gray-300 rounded-lg px-3 py-2 text-sm'
const ALL = ''
const SEVERITY_STYLE: Record<string, string> = {
  high: 'bg-red-100 text-red-800',
  medium: 'bg-amber-100 text-amber-800',
  low: 'bg-gray-100 text-gray-700',
}

function fmt(d: string | null) {
  return d ? new Date(d).toLocaleString() : '-'
}

export function ClMonitor() {
  const { t } = useTranslation()
  const { canEdit, canView } = usePermissions()
  const { profile } = useAuth()
  const accountId = useEffectiveAccountId()
  const readOnly = !canEdit('cl_monitor')
  const seesIncidents = profile?.role === 'superadmin' || canView('cl_incidents')
  const { cityName } = useClPlans(accountId)
  const { feeds } = useClFeedOptions(accountId)

  const [feedId, setFeedId] = useState(ALL)
  const [status, setStatus] = useState(ALL)
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [deliveryPage, setDeliveryPage] = useState(0)
  const [alertPage, setAlertPage] = useState(0)
  const [alertFilter, setAlertFilter] = useState<'open' | 'all'>('open')
  const [actionError, setActionError] = useState<string | null>(null)

  const filters = useMemo(
    () => ({ feedId: feedId || null, status: status || null, from: from || null, to: to || null }),
    [feedId, status, from, to],
  )
  const deliveries = useClDeliveries(accountId, filters, deliveryPage, 15_000)
  const { alerts, alertTotal, loading: alertsLoading, error, setAlertStatus, exportAlerts } = useClMonitor(accountId, { alertPage, alertFilter })
  const incidents = useClIncidentCounts(accountId, feedId || null, seesIncidents)

  const feedName = (id: string) => feeds.find((f) => f.id === id)?.name ?? id.slice(0, 8)
  const yesNo = (v: boolean) => (v ? t('cl.samples.yes') : t('cl.samples.no'))

  const buildDeliveries = async () => {
    const r = await deliveries.exportAll()
    return {
      headers: [
        t('cl.csv.period_start'), t('cl.csv.period_end'), t('cl.connectors.connector'), t('cl.csv.source'), t('cl.csv.test'),
        t('cl.deliveries.col.status'), t('cl.csv.phase'), t('cl.deliveries.col.rows'), t('cl.csv.rows_rejected'),
        t('cl.csv.shipments'), t('cl.deliveries.col.valid'), t('cl.csv.shipments_rejected'), t('cl.deliveries.col.drawn'),
        t('cl.deliveries.col.alerts'), t('cl.csv.received'), t('cl.csv.finished'), t('cl.csv.error_message'),
      ],
      rows: r.rows.map((d) => {
        const phaseKey = deliveryPhaseKey(d.status, d.phase)
        const shipRejected =
          d.shipments_total !== null && d.shipments_valid !== null ? Math.max(0, d.shipments_total - d.shipments_valid) : null
        return [
          d.period_start, d.period_end, feedName(d.feed_id), t(`cl.deliveries.source.${d.source === 'manual' ? 'manual' : 'api'}`),
          yesNo(d.is_test), t(deliveryStatusKey(d.status)), phaseKey ? t(phaseKey) : '', d.rows_total, d.rows_rejected,
          d.shipments_total, d.shipments_valid, shipRejected, d.shipments_drawn, d.alerts, csvDate(d.received_at),
          csvDate(d.finished_at), d.error ?? '',
        ]
      }),
      truncated: r.truncated,
    }
  }

  const buildAlerts = async () => {
    const r = await exportAlerts()
    return {
      headers: [
        t('cl.csv.date'), t('cl.csv.alert'), t('cl.csv.severity'), t('cl.deliveries.col.status'), t('cl.samples.origin'),
        t('cl.samples.destination'), t('cl.csv.details'),
      ],
      rows: r.rows.map((a) => {
        const origin = a.origin_city_id ? cityName(a.origin_city_id) : ''
        const destination = a.destination_city_id ? cityName(a.destination_city_id) : ''
        const route = origin && destination ? { origin, destination } : null
        return [
          csvDate(a.created_at), t(alertLabelKey(a.alert_type)), t(`cl.monitor.severity.${a.severity}`), t(`cl.monitor.alert.${a.status}`),
          origin, destination, alertDetailLines(a.alert_type, a.details, route).map((l) => t(l.key, l.params)).join(' | '),
        ]
      }),
      truncated: r.truncated,
    }
  }

  // Si el total se reduce y la pagina queda fuera de rango, se ajusta y se recarga.
  useEffect(() => {
    if (deliveries.loading) return
    const p = clampPage(deliveryPage, deliveries.total, DELIVERIES_PAGE_SIZE)
    if (p !== deliveryPage) setDeliveryPage(p)
  }, [deliveries.loading, deliveryPage, deliveries.total])
  useEffect(() => {
    if (alertsLoading) return
    const a = clampPage(alertPage, alertTotal, MONITOR_PAGE_SIZE)
    if (a !== alertPage) setAlertPage(a)
  }, [alertsLoading, alertPage, alertTotal])

  const changeAlert = async (id: string, s: 'acknowledged' | 'dismissed') => {
    if (readOnly) return
    setActionError(null)
    const r = await setAlertStatus(id, s)
    if (r.error) setActionError(clErrorKey(r.error))
  }

  const resetPage = () => setDeliveryPage(0)
  const incidentTotal = incidents.counts ? Object.values(incidents.counts).reduce((a, b) => a + b, 0) : 0

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-gray-900">{t('cl.monitor.title')}</h1>
        <ClBadge />
        <ClHelpLink section="monitor" />
        {readOnly && <ReadOnlyBadge />}
      </div>
      <p className="text-sm text-gray-600">{t('cl.monitor.help')}</p>
      {accountId === null && <SelectAccountNotice />}

      {accountId !== null && (
        <>
          {(deliveries.error || error) && (
            <div className="flex items-center gap-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">
              <AlertTriangle className="w-4 h-4" /> {t(clErrorKey(deliveries.error ?? error))}
            </div>
          )}
          {actionError && (
            <div className="flex items-center gap-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">
              <AlertTriangle className="w-4 h-4" /> {t(actionError)}
            </div>
          )}

          {seesIncidents && incidents.counts && (
            <section className="space-y-2">
              <div className="flex flex-wrap items-center justify-between gap-2">
                <h2 className="font-semibold text-gray-900">{t('cl.monitor.incidents', { count: incidentTotal })}</h2>
                <Link className="text-sm text-blue-600 hover:underline" to={incidentsLink({ feedId: feedId || null })}>
                  {t('cl.monitor.incidents_open_all')}
                </Link>
              </div>
              <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                {INCIDENT_TYPES.map((type) => (
                  <Link
                    key={type}
                    to={incidentsLink({ type, feedId: feedId || null })}
                    className="bg-white border border-gray-200 rounded-lg p-4 hover:border-blue-300"
                  >
                    <div className={`text-2xl font-bold ${incidents.counts![type] > 0 ? 'text-red-700' : 'text-gray-900'}`}>
                      {incidents.counts![type]}
                    </div>
                    <div className="text-sm text-gray-600">{t(incidentTypeKey(type))}</div>
                  </Link>
                ))}
              </div>
            </section>
          )}

          <section className="space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="font-semibold text-gray-900">{t('cl.monitor.deliveries')}</h2>
              <ClCsvButton fileBase="cl-deliveries" build={buildDeliveries} disabled={deliveries.loading || deliveries.total === 0} />
            </div>
            <div className="flex flex-wrap items-end gap-3">
              <label className="text-sm">
                <span className="block text-gray-600 mb-1">{t('cl.connectors.connector')}</span>
                <select
                  className={input}
                  value={feedId}
                  onChange={(e) => {
                    setFeedId(e.target.value)
                    resetPage()
                  }}
                >
                  <option value={ALL}>{t('cl.monitor.all_connectors')}</option>
                  {feeds.map((f) => (
                    <option key={f.id} value={f.id}>
                      {f.name}
                    </option>
                  ))}
                </select>
              </label>
              <label className="text-sm">
                <span className="block text-gray-600 mb-1">{t('cl.deliveries.col.status')}</span>
                <select
                  className={input}
                  value={status}
                  onChange={(e) => {
                    setStatus(e.target.value)
                    resetPage()
                  }}
                >
                  <option value={ALL}>{t('cl.monitor.all_statuses')}</option>
                  {DELIVERY_STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {t(deliveryStatusKey(s))}
                    </option>
                  ))}
                </select>
              </label>
              <label className="text-sm">
                <span className="block text-gray-600 mb-1">{t('cl.monitor.period_from')}</span>
                <input
                  type="date"
                  className={input}
                  value={from}
                  onChange={(e) => {
                    setFrom(e.target.value)
                    resetPage()
                  }}
                />
              </label>
              <label className="text-sm">
                <span className="block text-gray-600 mb-1">{t('cl.monitor.period_to')}</span>
                <input
                  type="date"
                  className={input}
                  value={to}
                  onChange={(e) => {
                    setTo(e.target.value)
                    resetPage()
                  }}
                />
              </label>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg">
              <ClDeliveriesTable rows={deliveries.rows} loading={deliveries.loading} feedName={feedName} />
              <ClPager
                page={deliveryPage}
                total={deliveries.total}
                pageSize={DELIVERIES_PAGE_SIZE}
                loading={deliveries.loading}
                onPage={setDeliveryPage}
              />
            </div>
          </section>

          <section className="space-y-2">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="font-semibold text-gray-900">{t('cl.monitor.alerts')}</h2>
              <div className="flex flex-wrap items-center gap-2">
                <ClCsvButton fileBase="cl-alerts" build={buildAlerts} disabled={alertsLoading || alertTotal === 0} />
                <select
                  className={input}
                  value={alertFilter}
                  onChange={(e) => {
                    setAlertFilter(e.target.value as 'open' | 'all')
                    setAlertPage(0)
                  }}
                >
                  <option value="open">{t('cl.monitor.alert_filter_open')}</option>
                  <option value="all">{t('cl.monitor.alert_filter_all')}</option>
                </select>
              </div>
            </div>
            <div className="bg-white border border-gray-200 rounded-lg">
              {!alertsLoading && alerts.length === 0 && (
                <p className="px-3 py-4 text-center text-sm text-gray-500">{t('cl.monitor.alerts_empty')}</p>
              )}
              <ul className="divide-y divide-gray-100">
                {alerts.map((a) => {
                  const route =
                    a.origin_city_id && a.destination_city_id
                      ? { origin: cityName(a.origin_city_id), destination: cityName(a.destination_city_id) }
                      : null
                  const lines = alertDetailLines(a.alert_type, a.details, route)
                  return (
                    <li key={a.id} className="px-3 py-3 flex items-start justify-between gap-3">
                      <div className="space-y-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="font-medium text-gray-900">{t(alertLabelKey(a.alert_type))}</span>
                          <span className={`px-2 py-0.5 rounded-full text-xs ${SEVERITY_STYLE[a.severity] ?? SEVERITY_STYLE.low}`}>
                            {t(`cl.monitor.severity.${a.severity}`)}
                          </span>
                          <span className="text-xs text-gray-500">
                            {t(`cl.monitor.alert.${a.status}`)} - {fmt(a.created_at)}
                          </span>
                        </div>
                        {lines.map((l, i) => (
                          <p key={i} className="text-sm text-gray-700">
                            {t(l.key, l.params)}
                          </p>
                        ))}
                      </div>
                      {!readOnly && a.status === 'open' && (
                        <div className="flex gap-2 shrink-0">
                          <button
                            className="px-3 py-1 text-sm border border-gray-300 rounded-lg hover:bg-gray-50"
                            onClick={() => void changeAlert(a.id, 'acknowledged')}
                          >
                            {t('cl.monitor.acknowledge')}
                          </button>
                          <button
                            className="px-3 py-1 text-sm border border-gray-300 rounded-lg hover:bg-gray-50"
                            onClick={() => void changeAlert(a.id, 'dismissed')}
                          >
                            {t('cl.monitor.dismiss')}
                          </button>
                        </div>
                      )}
                    </li>
                  )
                })}
              </ul>
              <ClPager page={alertPage} total={alertTotal} pageSize={MONITOR_PAGE_SIZE} loading={alertsLoading} onPage={setAlertPage} />
            </div>
          </section>
        </>
      )}
    </div>
  )
}
