import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Loader2, Lock } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { TablePagination } from '@/components/common/TablePagination'
import { QuotaMatrix } from '@/components/carrier-link/QuotaMatrix'
import { ClBadge } from '@/components/carrier-link/ClBadge'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import { planWeekKeys } from '@/lib/carrierLink/sampleView'
import type { QuotaInput } from '@/lib/carrierLink/planView'
import {
  clPlanOptionLabel,
  clPlanOptionValue,
  quotaTotals,
  samplesLink,
  EMPTY_QUOTA_FILTERS,
  QUOTA_STATUSES,
  type QuotaFilters,
} from '@/lib/carrierLink/planRecords'
import { useClPlanQuotas, useClPlanQuotaTotals } from '@/hooks/carrierLink/useClPlanRecords'
import type { ClPlan } from '@/hooks/carrierLink/useClPlans'

interface Props {
  plan: ClPlan
  /** Planes de panelistas del selector (como en los filtros de siempre). */
  panelistPlans: { id: string; plan_name: string }[]
  clPlans: ClPlan[]
  /** Valor del selector: id de un plan de panelistas, '' (todos) o clPlanOptionValue(id). */
  onSelectPlan: (value: string) => void
  cities: { id: string; name: string }[]
  cityName: (id: string) => string
  /** Todas las cuotas del plan (paginado de 1.000 en 1.000), solo para la matriz. */
  loadAllQuotas: (planId: string) => Promise<QuotaInput[]>
  canViewSamples: boolean
}

const select = 'w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent'
const th = 'px-4 py-3 text-start text-xs font-medium text-gray-500 uppercase whitespace-nowrap'
const thNum = 'px-4 py-3 text-end text-xs font-medium text-gray-500 uppercase whitespace-nowrap'

const STATUS_STYLE: Record<string, string> = {
  pending: 'bg-gray-100 text-gray-700',
  open: 'bg-blue-100 text-blue-800',
  fulfilled: 'bg-green-100 text-green-800',
  carried: 'bg-amber-100 text-amber-800',
  unfilled: 'bg-red-100 text-red-800',
}

/**
 * Registros de un plan de Carrier Link en Planes de Asignación: cuotas ruta × semana, de solo lectura
 * (las cambian el Generador de Asignaciones y el Balanceo de Carga). Tabla paginada en el servidor o matriz agrupada.
 * Se monta con key={plan.id}: otro plan empieza desde cero (filtros, página y matriz) sin una consulta de más.
 */
export function ClPlanRecords({
  plan,
  panelistPlans,
  clPlans,
  onSelectPlan,
  cities,
  cityName,
  loadAllQuotas,
  canViewSamples,
}: Props) {
  const { t } = useTranslation()
  const [filters, setFilters] = useState<QuotaFilters>(EMPTY_QUOTA_FILTERS)
  const [page, setPage] = useState(1)
  const [pageSize, setPageSize] = useState(100)
  const [view, setView] = useState<'table' | 'matrix'>('table')
  const [matrixQuotas, setMatrixQuotas] = useState<QuotaInput[] | null>(null)
  const [matrixError, setMatrixError] = useState<string | null>(null)

  const { rows, total, loading, error } = useClPlanQuotas(plan.id, filters, page, pageSize)
  const weeks = useMemo(() => planWeekKeys(plan.start_date, plan.end_date), [plan.start_date, plan.end_date])
  const totalPages = Math.max(1, Math.ceil(total / pageSize))
  const totals = quotaTotals(rows)
  // Totales de todas las cuotas con estos filtros (no solo la página), calculados en el servidor.
  const filterTotals = useClPlanQuotaTotals(plan.id, filters)
  // Con una sola página los de la página ya son los de todo el filtro (también si la RPC falla).
  const wholeTotals = filterTotals ?? (totalPages <= 1 ? totals : null)

  // Si el total se reduce y la página queda fuera de rango, se vuelve a la última.
  useEffect(() => {
    if (!loading && page > totalPages) setPage(totalPages)
  }, [loading, page, totalPages])

  // La matriz necesita todas las cuotas: se leen solo al abrirla (y una vez por plan).
  useEffect(() => {
    if (view !== 'matrix' || matrixQuotas) return
    let cancelled = false
    setMatrixError(null)
    loadAllQuotas(plan.id)
      .then((q) => !cancelled && setMatrixQuotas(q))
      .catch((e) => !cancelled && setMatrixError(clErrorKey(e as { message?: string; code?: string })))
    return () => {
      cancelled = true
    }
  }, [view, matrixQuotas, loadAllQuotas, plan.id])

  const setFilter = (key: keyof QuotaFilters, value: string) => {
    setFilters((f) => ({ ...f, [key]: value }))
    setPage(1)
  }
  const hasFilters = Object.values(filters).some((v) => v !== '')
  const route = (o: string, d: string) => `${cityName(o)} → ${cityName(d)}`

  const citySelect = (key: 'origin' | 'destination', label: string) => (
    <div>
      <label className="block text-sm font-medium text-gray-700 mb-2">{label}</label>
      <select className={select} value={filters[key]} onChange={(e) => setFilter(key, e.target.value)}>
        <option value="">{t('allocation_plans.all_cities')}</option>
        {cities.map((c) => (
          <option key={c.id} value={c.id}>
            {c.name}
          </option>
        ))}
      </select>
    </div>
  )

  return (
    <div className="space-y-6">
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6 space-y-4">
        <div className="flex flex-wrap items-end gap-4">
          <div className="min-w-[18rem]">
            <label className="block text-sm font-medium text-gray-700 mb-2">{t('allocation_plans.plan')}</label>
            <select className={select} value={clPlanOptionValue(plan.id)} onChange={(e) => onSelectPlan(e.target.value)}>
              <option value="">{t('allocation_plans.all_plans')}</option>
              {panelistPlans.map((p) => (
                <option key={p.id} value={p.id}>
                  {p.plan_name}
                </option>
              ))}
              <optgroup label={`${t('cl.generator.capture_column')}: ${t('cl.capture_method.carrier_link')}`}>
                {clPlans.map((p) => (
                  <option key={p.id} value={clPlanOptionValue(p.id)}>
                    {clPlanOptionLabel(p, t)}
                  </option>
                ))}
              </optgroup>
            </select>
          </div>
          <div className="flex items-center gap-2 pb-2">
            <ClBadge />
            <span className="text-sm text-gray-600">
              {plan.carrier_name ?? ''} · {plan.product_label ?? ''} · {plan.start_date} – {plan.end_date} ·{' '}
              {t(`cl.plans.status.${plan.status}`)}
            </span>
          </div>
        </div>
        <p className="flex items-start gap-2 text-sm text-gray-600">
          <Lock className="w-4 h-4 mt-0.5 shrink-0 text-gray-400" />
          {t('cl.records.read_only_note')}
        </p>
      </div>

      <div className="bg-white rounded-lg shadow">
        <div className="p-6 space-y-4">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-lg font-medium">{t('cl.records.heading', { count: total })}</h2>
            <div className="inline-flex rounded-lg border border-gray-300 overflow-hidden text-sm">
              {(['table', 'matrix'] as const).map((k) => (
                <button
                  key={k}
                  type="button"
                  onClick={() => setView(k)}
                  className={`px-3 py-2 ${view === k ? 'bg-blue-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'}`}
                >
                  {k === 'table' ? t('cl.records.view_table') : t('cl.records.view_matrix')}
                </button>
              ))}
            </div>
          </div>

          {view === 'table' && (
            <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4 items-end">
              {citySelect('origin', t('allocation_plans.origin_city'))}
              {citySelect('destination', t('allocation_plans.destination_city'))}
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">{t('allocationplans.week')}</label>
                <select className={select} value={filters.week} onChange={(e) => setFilter('week', e.target.value)}>
                  <option value="">{t('cl.samples.all')}</option>
                  {weeks.map((w) => (
                    <option key={w} value={w}>
                      {w}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">{t('allocation_plans.status')}</label>
                <select className={select} value={filters.status} onChange={(e) => setFilter('status', e.target.value)}>
                  <option value="">{t('allocation_plans.all_status')}</option>
                  {QUOTA_STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {t(`cl.records.status.${s}`)}
                    </option>
                  ))}
                </select>
              </div>
              <div>
                {hasFilters && (
                  <button
                    type="button"
                    onClick={() => {
                      setFilters(EMPTY_QUOTA_FILTERS)
                      setPage(1)
                    }}
                    className="px-3 py-2 text-sm text-gray-700 hover:text-gray-900"
                  >
                    {t('common.reset')}
                  </button>
                )}
              </div>
            </div>
          )}
        </div>

        {view === 'matrix' ? (
          <div className="px-6 pb-6 space-y-3">
            <p className="text-xs text-gray-500">{t('cl.records.matrix_scope')}</p>
            {matrixError ? (
              <p className="text-sm text-red-600">{t(matrixError)}</p>
            ) : !matrixQuotas ? (
              <p className="flex items-center gap-2 text-sm text-gray-600">
                <Loader2 className="w-4 h-4 animate-spin" />
                {t('cl.records.matrix_loading')}
              </p>
            ) : (
              <QuotaMatrix quotas={matrixQuotas} cityName={cityName} showObtained={plan.status !== 'draft'} />
            )}
          </div>
        ) : error ? (
          <div className="text-red-600 text-center py-8 px-6">{t(clErrorKey(error))}</div>
        ) : loading && rows.length === 0 ? (
          <div className="text-gray-600 text-center py-8 px-6">{t('common.loading')}</div>
        ) : rows.length === 0 ? (
          <div className="text-gray-500 text-center py-8 px-6">{t('cl.records.empty')}</div>
        ) : (
          <div className="overflow-x-auto">
            <div className={`max-h-[600px] overflow-y-auto ${loading ? 'opacity-60' : ''}`}>
              <table className="min-w-full divide-y divide-gray-200 text-sm">
                <thead className="bg-gray-50 sticky top-0 z-10">
                  <tr>
                    <th className={th}>{t('cl.samples.route')}</th>
                    <th className={th}>{t('allocationplans.week')}</th>
                    <th className={thNum}>{t('cl.records.planned')}</th>
                    <th className={thNum}>{t('cl.records.carried_in')}</th>
                    <th className={thNum}>{t('cl.records.obtained')}</th>
                    <th className={th}>{t('common.status')}</th>
                    <th className={thNum}>{t('cl.records.demands')}</th>
                    {canViewSamples && <th className={th}>{t('cl.samples.title')}</th>}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {rows.map((r) => (
                    <tr key={r.id} className="hover:bg-gray-50">
                      <td className="px-4 py-2 whitespace-nowrap">{route(r.origin_city_id, r.destination_city_id)}</td>
                      <td className="px-4 py-2 whitespace-nowrap">
                        <div className="font-medium">{r.week}</div>
                        <div className="text-xs text-gray-500">
                          {r.period_start} – {r.period_end}
                        </div>
                      </td>
                      <td className="px-4 py-2 text-end">{r.planned}</td>
                      <td className="px-4 py-2 text-end">{r.carried_in}</td>
                      <td className="px-4 py-2 text-end">{r.obtained}</td>
                      <td className="px-4 py-2">
                        <span className={`px-2 py-1 rounded text-xs ${STATUS_STYLE[r.status] ?? ''}`}>
                          {t(`cl.records.status.${r.status}`)}
                        </span>
                      </td>
                      <td className="px-4 py-2 text-end">{r.demands}</td>
                      {canViewSamples && (
                        <td className="px-4 py-2 whitespace-nowrap">
                          <Link to={samplesLink(plan.id, r)} className="text-blue-600 hover:underline">
                            {t('cl.records.view_samples')}
                          </Link>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
                <tfoot className="bg-gray-50 font-medium">
                  {totalPages > 1 && (
                    <tr className="text-gray-500">
                      <td className="px-4 py-2" colSpan={2}>
                        {t('cl.records.page_total')}
                      </td>
                      <td className="px-4 py-2 text-end">{totals.planned}</td>
                      <td className="px-4 py-2 text-end">{totals.carried_in}</td>
                      <td className="px-4 py-2 text-end">{totals.obtained}</td>
                      <td />
                      <td className="px-4 py-2 text-end">{totals.demands}</td>
                      {canViewSamples && <td />}
                    </tr>
                  )}
                  <tr>
                    <td className="px-4 py-2" colSpan={2}>
                      {hasFilters ? t('cl.records.filter_total') : t('cl.records.plan_total')}
                    </td>
                    <td className="px-4 py-2 text-end">{wholeTotals ? wholeTotals.planned : '…'}</td>
                    <td className="px-4 py-2 text-end">{wholeTotals ? wholeTotals.carried_in : '…'}</td>
                    <td className="px-4 py-2 text-end">{wholeTotals ? wholeTotals.obtained : '…'}</td>
                    <td />
                    <td className="px-4 py-2 text-end">{wholeTotals ? wholeTotals.demands : '…'}</td>
                    {canViewSamples && <td />}
                  </tr>
                </tfoot>
              </table>
            </div>
            <TablePagination
              idPrefix="cl-plan-records"
              currentPage={page}
              totalPages={totalPages}
              pageSize={pageSize}
              totalItems={total}
              onPageChange={setPage}
              onPageSizeChange={(s) => {
                setPageSize(s)
                setPage(1)
              }}
            />
          </div>
        )}
      </div>
    </div>
  )
}
