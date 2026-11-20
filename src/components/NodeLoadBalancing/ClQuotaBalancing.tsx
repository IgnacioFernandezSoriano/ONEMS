import { useMemo, useState } from 'react'
import { Loader2, Lock } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { ClBadge } from '@/components/carrier-link/ClBadge'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import { localDateKey } from '@/lib/workingDays'
import type { QuotaInput } from '@/lib/carrierLink/planView'
import {
  applyChanges,
  effectiveFence,
  fenceParam,
  originLoads,
  planWeeks,
  proposeBalance,
  type BalanceProposal,
  type LoadLevel,
} from '@/lib/carrierLink/quotaBalancing'
import { useClBalancing } from '@/hooks/carrierLink/useClBalancing'
import type { ClPlan } from '@/hooks/carrierLink/useClPlans'

interface Props {
  plan: ClPlan
  cityName: (id: string) => string
  workingDows: number[]
  nonWorkingDays: string[]
  /** Todas las cuotas del plan (lector paginado de useClPlans). */
  loadAllQuotas: (planId: string) => Promise<QuotaInput[]>
  /** Controles compartidos con el balanceo de panelistas. */
  deviationPercent: number
  onChangeDeviation: (v: number) => void
  fenceUntil: string
  onChangeFence: (v: string) => void
  canEdit: boolean
}

const LEVEL_CELL: Record<LoadLevel, string> = {
  normal: 'bg-green-50 text-green-900',
  high: 'bg-orange-100 text-orange-900',
  saturated: 'bg-red-100 text-red-900',
}
const LEVEL_BADGE: Record<LoadLevel, string> = {
  normal: 'bg-green-100 text-green-800',
  high: 'bg-orange-100 text-orange-800',
  saturated: 'bg-red-100 text-red-800',
}
const LEVEL_KEY: Record<LoadLevel, string> = {
  normal: 'lb2.level.normal',
  high: 'lb2.level.high',
  saturated: 'lb2.level.saturated',
}

const input =
  'block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm disabled:opacity-50'
const btn =
  'px-3 py-1.5 text-sm font-medium rounded-md disabled:opacity-50 disabled:cursor-not-allowed focus:outline-none focus:ring-2 focus:ring-blue-500'

/**
 * Balanceo de Carga de un plan de Carrier Link, dentro de la página de siempre: nodos = ciudades de origen, carga =
 * muestras previstas por semana, sin máximo por panelista. La propuesta se calcula en el navegador y se aplica con
 * cl_plan_rebalance_quotas (solo cuotas que cambian, en valor absoluto; la base vuelve a validar total y fence).
 */
export function ClQuotaBalancing({
  plan,
  cityName,
  workingDows,
  nonWorkingDays,
  loadAllQuotas,
  deviationPercent,
  onChangeDeviation,
  fenceUntil,
  onChangeFence,
  canEdit,
}: Props) {
  const { t } = useTranslation()
  const { quotas, loading, error, reload, apply } = useClBalancing(plan.id, loadAllQuotas)
  const [proposal, setProposal] = useState<BalanceProposal | null>(null)
  const [applying, setApplying] = useState(false)
  const [notice, setNotice] = useState<{ type: 'ok' | 'error' | 'info'; text: string } | null>(null)

  const today = localDateKey(new Date())
  const isActive = plan.status === 'active'
  const fence = effectiveFence(plan.status, fenceUntil, today)
  const weeks = useMemo(
    () => planWeeks(plan, { workingDows, nonWorkingDays }, fence),
    [plan, workingDows, nonWorkingDays, fence],
  )
  const shown = useMemo(() => (proposal ? applyChanges(quotas, proposal.changes) : quotas), [quotas, proposal])
  const loads = useMemo(
    () => originLoads(shown, weeks, fence, cityName, deviationPercent),
    [shown, weeks, fence, cityName, deviationPercent],
  )
  const totals = useMemo(
    () =>
      quotas.reduce((a, q) => ({ planned: a.planned + q.samples_planned, carried: a.carried + q.samples_carried_in }), {
        planned: 0,
        carried: 0,
      }),
    [quotas],
  )
  const saturated = loads.filter((o) => o.level === 'saturated').length
  const high = loads.filter((o) => o.level === 'high').length

  // Cambiar fence o tolerancia invalida la propuesta: se vuelve a pedir.
  const changeFence = (v: string) => {
    setProposal(null)
    onChangeFence(v)
  }
  const changeDeviation = (v: number) => {
    setProposal(null)
    onChangeDeviation(v)
  }

  const propose = (origins?: string[]) => {
    if (applying) return
    const p = proposeBalance(quotas, weeks, { fence, deviationPercent, origins, cityName })
    if (p.changes.length === 0) {
      setProposal(null)
      setNotice({ type: 'info', text: t('cl.balancing.nothing_to_do') })
      return
    }
    setNotice(null)
    setProposal(p)
  }

  const confirm = async () => {
    if (!proposal || applying) return
    setApplying(true)
    try {
      const res = await apply(proposal.changes, isActive ? fenceParam(fenceUntil, today) : null)
      if (res.success) {
        setNotice({ type: 'ok', text: t('cl.balancing.applied', { changed: res.result.changed, created: res.result.created, deleted: res.result.deleted }) })
      } else {
        setNotice({ type: 'error', text: t(clErrorKey(res.error)) })
      }
    } finally {
      setProposal(null)
      setApplying(false)
      await reload()
    }
  }

  const fmt = (n: number) => n.toFixed(1)

  return (
    <div className="space-y-6">
      {notice && (
        <div
          role={notice.type === 'error' ? 'alert' : 'status'}
          className={`flex items-start justify-between gap-3 rounded-lg border p-4 text-sm ${
            notice.type === 'ok'
              ? 'bg-green-50 border-green-200 text-green-800'
              : notice.type === 'error'
                ? 'bg-red-50 border-red-200 text-red-800'
                : 'bg-blue-50 border-blue-200 text-blue-800'
          }`}
        >
          <span>{notice.text}</span>
          <button
            type="button"
            onClick={() => setNotice(null)}
            aria-label={t('common.close')}
            className="text-lg leading-none opacity-60 hover:opacity-100"
          >
            ×
          </button>
        </div>
      )}

      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4 space-y-4">
        <div className="flex flex-wrap items-center gap-2">
          <ClBadge />
          <span className="text-sm text-gray-600">
            {plan.carrier_name ?? ''} · {plan.product_label ?? ''} · {plan.start_date} – {plan.end_date} ·{' '}
            {t(`cl.plans.status.${plan.status}`)}
          </span>
          {!canEdit && <ReadOnlyBadge />}
        </div>
        <p className="text-sm text-gray-600">{t('cl.balancing.no_max_note')}</p>
        <p className="flex items-start gap-2 text-sm text-gray-600">
          <Lock className="w-4 h-4 mt-0.5 shrink-0 text-gray-400" />
          {isActive ? t('cl.balancing.fence_note') : t('cl.balancing.draft_note')}
        </p>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          <div>
            <label htmlFor="cl-balancing-deviation" className="block text-sm font-medium text-gray-700 mb-1">
              {t('node_load_balancing.deviation_tolerance')}
            </label>
            <input
              id="cl-balancing-deviation"
              type="number"
              min="0"
              max="100"
              value={deviationPercent}
              disabled={applying}
              onChange={(e) => changeDeviation(Number(e.target.value))}
              className={input}
            />
            <p className="mt-1 text-xs text-gray-500">{t('cl.balancing.deviation_hint')}</p>
          </div>
          {isActive && (
            <div>
              <label htmlFor="cl-balancing-fence" className="block text-sm font-medium text-gray-700 mb-1">
                {t('node_load_balancing.fence_until')}
              </label>
              <input
                id="cl-balancing-fence"
                type="date"
                value={fenceUntil}
                disabled={applying}
                onChange={(e) => changeFence(e.target.value)}
                className={input}
              />
              <p className="mt-1 text-xs text-gray-500">{t('cl.balancing.fence_hint')}</p>
            </div>
          )}
        </div>
      </div>

      {error ? (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-red-700">{t(clErrorKey(error))}</div>
      ) : loading && quotas.length === 0 ? (
        <p className="flex items-center gap-2 text-sm text-gray-600" role="status">
          <Loader2 className="w-4 h-4 animate-spin" />
          {t('cl.balancing.loading')}
        </p>
      ) : quotas.length === 0 ? (
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-8 text-center text-gray-500">
          {t('cl.balancing.empty')}
        </div>
      ) : (
        <>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div className="bg-gradient-to-br from-red-50 to-white rounded-lg shadow-sm border border-red-100 p-6">
              <p className="text-sm font-medium text-red-600 mb-1">{t('cl.balancing.kpi_saturated')}</p>
              <p className="text-3xl font-bold text-red-700">{saturated}</p>
            </div>
            <div className="bg-gradient-to-br from-orange-50 to-white rounded-lg shadow-sm border border-orange-100 p-6">
              <p className="text-sm font-medium text-orange-600 mb-1">{t('cl.balancing.kpi_high')}</p>
              <p className="text-3xl font-bold text-orange-700">{high}</p>
            </div>
            <div className="bg-gradient-to-br from-blue-50 to-white rounded-lg shadow-sm border border-blue-100 p-6">
              <p className="text-sm font-medium text-blue-600 mb-1">{t('cl.balancing.kpi_total')}</p>
              <p className="text-3xl font-bold text-blue-700">{totals.planned}</p>
              {totals.carried > 0 && (
                <p className="text-xs text-blue-500 mt-1">{t('cl.balancing.carried_in', { count: totals.carried })}</p>
              )}
            </div>
          </div>

          {proposal && (
            <div className="bg-white rounded-lg shadow-sm border-2 border-blue-300 p-4 space-y-3" role="region" aria-live="polite">
              <h2 className="text-lg font-semibold text-gray-900">{t('cl.balancing.preview_title')}</h2>
              <p className="text-sm text-gray-700">
                {t('cl.balancing.preview_summary', {
                  moved: proposal.moved,
                  origins: proposal.origins.length,
                  changes: proposal.changes.length,
                  created: proposal.created,
                  zeroed: proposal.zeroed,
                })}
              </p>
              <ul className="text-sm text-gray-700 max-h-40 overflow-y-auto space-y-1">
                {proposal.origins.map((o) => (
                  <li key={o.origin_city_id}>
                    <span className="font-medium">{o.origin}</span>:{' '}
                    {t('cl.balancing.before_after', {
                      moved: o.moved,
                      before: fmt(o.stddevBefore),
                      after: fmt(o.stddevAfter),
                    })}
                  </li>
                ))}
              </ul>
              <p className="text-xs text-gray-500">{t('cl.balancing.preview_matrix_note')}</p>
              <div className="flex items-center gap-2">
                <button
                  type="button"
                  onClick={confirm}
                  disabled={applying}
                  className={`${btn} text-white bg-blue-600 hover:bg-blue-700`}
                >
                  {applying ? t('cl.balancing.applying') : t('cl.balancing.confirm')}
                </button>
                <button
                  type="button"
                  onClick={() => setProposal(null)}
                  disabled={applying}
                  className={`${btn} text-gray-700 bg-white border border-gray-300 hover:bg-gray-50`}
                >
                  {t('common.cancel')}
                </button>
              </div>
            </div>
          )}

          <div className="bg-white rounded-lg shadow-sm border border-gray-200">
            <div className="flex flex-wrap items-center justify-between gap-3 p-4 border-b border-gray-200">
              <div>
                <h2 className="text-lg font-semibold text-gray-900">{t('cl.balancing.matrix_title')}</h2>
                <p className="text-xs text-gray-500">{t('cl.balancing.legend')}</p>
              </div>
              {canEdit && (
                <button
                  type="button"
                  onClick={() => propose()}
                  disabled={applying || loading}
                  className={`${btn} text-white bg-blue-600 hover:bg-blue-700`}
                >
                  {t('cl.balancing.balance_all')}
                </button>
              )}
            </div>
            <div className={`overflow-x-auto ${loading ? 'opacity-60' : ''}`}>
              <table className="min-w-full text-xs">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="sticky start-0 bg-gray-50 px-3 py-2 text-start font-medium text-gray-500 uppercase">
                      {t('cl.balancing.origin')}
                    </th>
                    <th className="px-2 py-2 text-end font-medium text-gray-500 uppercase">{t('cl.balancing.routes')}</th>
                    <th className="px-2 py-2 text-end font-medium text-gray-500 uppercase">{t('cl.balancing.total')}</th>
                    <th className="px-2 py-2 text-end font-medium text-gray-500 uppercase">{t('cl.balancing.stddev')}</th>
                    {canEdit && <th className="px-2 py-2" />}
                    {weeks.map((w) => (
                      <th key={w.key} className="px-2 py-2 text-center font-medium text-gray-500 whitespace-nowrap">
                        {w.key.slice(5)}
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-100">
                  {loads.map((o) => (
                    <tr key={o.origin_city_id}>
                      <td className="sticky start-0 bg-white px-3 py-2 whitespace-nowrap">
                        <div className="font-medium text-gray-900">{o.origin}</div>
                        <span className={`inline-block mt-0.5 px-1.5 rounded ${LEVEL_BADGE[o.level]}`}>{t(LEVEL_KEY[o.level])}</span>
                      </td>
                      <td className="px-2 py-2 text-end">{o.routes}</td>
                      <td className="px-2 py-2 text-end">
                        {o.total}
                        {o.carried > 0 && <div className="text-gray-400">+{o.carried}</div>}
                      </td>
                      <td className="px-2 py-2 text-end">{fmt(o.stddev)}</td>
                      {canEdit && (
                        <td className="px-2 py-2">
                          <button
                            type="button"
                            onClick={() => propose([o.origin_city_id])}
                            disabled={applying || loading}
                            className={`${btn} text-blue-700 bg-blue-50 hover:bg-blue-100 whitespace-nowrap`}
                          >
                            {t('cl.balancing.balance_origin')}
                          </button>
                        </td>
                      )}
                      {weeks.map((w) => {
                        const c = o.cells[w.key]
                        const frozen = !w.movable || (c && c.planned > 0 && c.locked === c.planned)
                        const tone = frozen ? 'bg-gray-100 text-gray-500' : c ? LEVEL_CELL[c.level] : ''
                        return (
                          <td
                            key={w.key}
                            className={`px-2 py-2 text-center whitespace-nowrap ${tone}`}
                            title={c ? t('cl.balancing.cell_title', { expected: fmt(c.expected), locked: c.locked }) : undefined}
                          >
                            {c && c.planned > 0 ? c.planned : ''}
                            {c && c.carried > 0 && <span className="text-gray-400"> +{c.carried}</span>}
                          </td>
                        )
                      })}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
