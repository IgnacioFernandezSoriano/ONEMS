import { useEffect, useState } from 'react'
import { Loader2, AlertTriangle, CheckCircle2 } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { ClHelpLink } from '@/components/carrier-link/ClHelpLink'
import { ClBadge } from '@/components/carrier-link/ClBadge'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { SelectAccountNotice } from '@/components/carrier-link/SelectAccountNotice'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import { useClPlans } from '@/hooks/carrierLink/useClPlans'
import { useClMonitor, type ClUndoResult } from '@/hooks/carrierLink/useClMonitor'
import {
  DEMAND_STATUSES,
  MONITOR_PAGE_SIZE,
  alertDetailLines,
  alertLabelKey,
  batchSummary,
} from '@/lib/carrierLink/monitorView'
import { clampPage } from '@/lib/carrierLink/sampleView'

const input = 'border border-gray-300 rounded-lg px-3 py-2 text-sm'
const ALL = 'all'
const UNDOABLE = ['validated', 'sampled', 'expired']
const KNOWN_BATCH = ['received', 'validated', 'sampled', 'rejected', 'undone', 'expired']
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
  const { canEdit } = usePermissions()
  const accountId = useEffectiveAccountId()
  const readOnly = !canEdit('cl_monitor')
  const { plans, cityName, loading: plansLoading } = useClPlans(accountId)

  const [planSel, setPlanSel] = useState<string | null>(null) // null = aun sin elegir; ALL = todos los planes
  const [batchPage, setBatchPage] = useState(0)
  const [alertPage, setAlertPage] = useState(0)
  const [alertFilter, setAlertFilter] = useState<'open' | 'all'>('open')
  const [confirmId, setConfirmId] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [undoDone, setUndoDone] = useState<ClUndoResult | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)

  // Por defecto: el plan activo mas reciente (la lista ya viene de mas reciente a mas antiguo).
  useEffect(() => {
    if (planSel === ALL || (planSel && plans.some((p) => p.id === planSel))) return
    const def = plans.find((p) => p.status === 'active') ?? plans[0]
    setPlanSel(def?.id ?? (plans.length === 0 ? null : ALL))
  }, [plans, planSel])

  const planId = planSel && planSel !== ALL ? planSel : null
  // Se espera a la lista de planes antes de la primera carga (sin pasar por "todos los planes" ni consultar dos veces).
  // Sin planes visibles (p. ej. sin View en cl_plans) se carga todo lo de la cuenta.
  const ready =
    !plansLoading &&
    (planSel === null ? plans.length === 0 : planSel === ALL || plans.some((p) => p.id === planSel))
  const {
    demands,
    batches,
    batchTotal,
    alerts,
    alertTotal,
    loading: monitorLoading,
    error,
    undo,
    setAlertStatus,
  } = useClMonitor(ready ? accountId : null, planId, { batchPage, alertPage, alertFilter })
  const loading = monitorLoading || !ready

  const batchLast = Math.max(0, Math.ceil(batchTotal / MONITOR_PAGE_SIZE) - 1)
  const alertLast = Math.max(0, Math.ceil(alertTotal / MONITOR_PAGE_SIZE) - 1)

  // Si el total se reduce y la pagina queda fuera de rango, se ajusta y se recarga.
  useEffect(() => {
    if (loading) return
    const b = clampPage(batchPage, batchTotal, MONITOR_PAGE_SIZE)
    if (b !== batchPage) setBatchPage(b)
    const a = clampPage(alertPage, alertTotal, MONITOR_PAGE_SIZE)
    if (a !== alertPage) setAlertPage(a)
  }, [loading, batchPage, batchTotal, alertPage, alertTotal])

  const confirmUndo = async () => {
    if (!confirmId || busy || readOnly) return
    setBusy(true)
    setActionError(null)
    const r = await undo(confirmId)
    setBusy(false)
    setConfirmId(null)
    if (r.success) setUndoDone(r.result)
    else {
      setUndoDone(null)
      setActionError(clErrorKey(r.error))
    }
  }

  const changeAlert = async (id: string, status: 'acknowledged' | 'dismissed') => {
    if (readOnly) return
    setActionError(null)
    const r = await setAlertStatus(id, status)
    if (r.error) setActionError(clErrorKey(r.error))
  }

  const pager = (page: number, last: number, total: number, setPage: (fn: (p: number) => number) => void) => (
    <div className="flex items-center justify-between px-3 py-2 border-t border-gray-100 text-sm text-gray-600">
      <span>{t('cl.monitor.total', { count: total })}</span>
      <div className="flex items-center gap-2">
        <button
          className="px-3 py-1 border border-gray-300 rounded-lg disabled:opacity-50"
          disabled={page === 0 || loading}
          onClick={() => setPage((p) => Math.max(0, p - 1))}
        >
          {t('cl.samples.prev')}
        </button>
        <span>{t('cl.samples.page', { page: page + 1, pages: last + 1 })}</span>
        <button
          className="px-3 py-1 border border-gray-300 rounded-lg disabled:opacity-50"
          disabled={page >= last || loading}
          onClick={() => setPage((p) => p + 1)}
        >
          {t('cl.samples.next')}
        </button>
      </div>
    </div>
  )

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
          <label className="text-sm block">
            <span className="block text-gray-600 mb-1">{t('cl.monitor.plan')}</span>
            <select
              className={input}
              value={planSel ?? ''}
              onChange={(e) => {
                setPlanSel(e.target.value || null)
                setBatchPage(0)
                setAlertPage(0)
                setConfirmId(null)
              }}
            >
              <option value={ALL}>{t('cl.monitor.all_plans')}</option>
              {plans.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.plan_name}
                  {p.product_label ? ` (${p.product_label})` : ''}
                </option>
              ))}
            </select>
          </label>

          {error && (
            <div className="flex items-center gap-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">
              <AlertTriangle className="w-4 h-4" /> {t(clErrorKey(error))}
            </div>
          )}
          {actionError && (
            <div className="flex items-center gap-2 text-sm text-red-700 bg-red-50 border border-red-200 rounded-lg p-3">
              <AlertTriangle className="w-4 h-4" /> {t(actionError)}
            </div>
          )}
          {undoDone && (
            <div className="flex items-center gap-2 text-sm text-green-800 bg-green-50 border border-green-200 rounded-lg p-3">
              <CheckCircle2 className="w-4 h-4" />
              {t('cl.monitor.undo_done', { pending: undoDone.pending, carried: undoDone.carried, kept: undoDone.kept })}
            </div>
          )}

          <section className="space-y-2">
            <h2 className="font-semibold text-gray-900">{t('cl.monitor.demands')}</h2>
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
              {DEMAND_STATUSES.map((s) => (
                <div key={s} className="bg-white border border-gray-200 rounded-lg p-4">
                  <div className="text-2xl font-bold text-gray-900">{demands[s]}</div>
                  <div className="text-sm text-gray-600">{t(`cl.monitor.demand.${s}`)}</div>
                </div>
              ))}
            </div>
          </section>

          <section className="space-y-2">
            <h2 className="font-semibold text-gray-900">{t('cl.monitor.batches')}</h2>
            <div className="overflow-x-auto bg-white border border-gray-200 rounded-lg">
              <table className="w-full text-sm">
                <thead className="bg-gray-50 text-left text-gray-600">
                  <tr>
                    <th className="px-3 py-2">{t('cl.monitor.col.date')}</th>
                    <th className="px-3 py-2">{t('cl.monitor.col.status')}</th>
                    <th className="px-3 py-2">{t('cl.monitor.col.shipments')}</th>
                    <th className="px-3 py-2">{t('cl.monitor.col.rejected')}</th>
                    <th className="px-3 py-2">{t('cl.monitor.col.selected')}</th>
                    <th className="px-3 py-2" />
                  </tr>
                </thead>
                <tbody>
                  {loading && (
                    <tr>
                      <td colSpan={6} className="px-3 py-4 text-center text-gray-500">
                        <Loader2 className="w-4 h-4 animate-spin inline" />
                      </td>
                    </tr>
                  )}
                  {!loading && batches.length === 0 && (
                    <tr>
                      <td colSpan={6} className="px-3 py-4 text-center text-gray-500">
                        {t('cl.monitor.batches_empty')}
                      </td>
                    </tr>
                  )}
                  {!loading &&
                    batches.map((b) => {
                      const s = batchSummary(b)
                      return (
                        <tr key={b.id} className="border-t border-gray-100 align-top">
                          <td className="px-3 py-2">{fmt(b.created_at)}</td>
                          <td className="px-3 py-2">
                            {KNOWN_BATCH.includes(b.status) ? t(`cl.monitor.batch.${b.status}`) : b.status}
                          </td>
                          <td className="px-3 py-2">{s.shipments}</td>
                          <td className="px-3 py-2">{s.rejected}</td>
                          <td className="px-3 py-2">{s.selected}</td>
                          <td className="px-3 py-2">
                            {!readOnly && UNDOABLE.includes(b.status) && confirmId !== b.id && (
                              <button
                                className="px-3 py-1 border border-gray-300 rounded-lg hover:bg-gray-50"
                                onClick={() => {
                                  setConfirmId(b.id)
                                  setUndoDone(null)
                                  setActionError(null)
                                }}
                              >
                                {t('cl.monitor.undo')}
                              </button>
                            )}
                            {confirmId === b.id && (
                              <div className="max-w-sm space-y-2 bg-amber-50 border border-amber-200 rounded-lg p-3">
                                <div className="font-medium text-amber-900">{t('cl.monitor.undo_title')}</div>
                                <p className="text-amber-900">{t('cl.monitor.undo_effect')}</p>
                                <div className="flex gap-2">
                                  <button
                                    className="px-3 py-1 rounded-lg bg-red-600 text-white disabled:opacity-50"
                                    disabled={busy}
                                    onClick={() => void confirmUndo()}
                                  >
                                    {t('cl.monitor.undo_confirm')}
                                  </button>
                                  <button
                                    className="px-3 py-1 border border-gray-300 rounded-lg bg-white"
                                    disabled={busy}
                                    onClick={() => setConfirmId(null)}
                                  >
                                    {t('cl.monitor.undo_cancel')}
                                  </button>
                                </div>
                              </div>
                            )}
                          </td>
                        </tr>
                      )
                    })}
                </tbody>
              </table>
              {pager(batchPage, batchLast, batchTotal, setBatchPage)}
            </div>
          </section>

          <section className="space-y-2">
            <div className="flex items-center justify-between">
              <h2 className="font-semibold text-gray-900">{t('cl.monitor.alerts')}</h2>
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
            <div className="bg-white border border-gray-200 rounded-lg">
              {!loading && alerts.length === 0 && (
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
              {pager(alertPage, alertLast, alertTotal, setAlertPage)}
            </div>
          </section>
        </>
      )}
    </div>
  )
}
