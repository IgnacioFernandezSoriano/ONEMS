import { Fragment, useMemo, useState } from 'react'
import { ChevronDown, ChevronRight, AlertTriangle } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import {
  quotaMatrix,
  groupQuotaMatrix,
  originGroups,
  nextExpandedGroups,
  MAX_EXPANDED_CELLS,
  type QuotaInput,
} from '@/lib/carrierLink/planView'

interface Props {
  quotas: QuotaInput[]
  cityName: (id: string) => string
  /** Plan activo o cerrado: muestra "✓obtenido" en cada celda. */
  showObtained: boolean
  /** Claves de ruta (`origen|destino`) sin estándar de entrega. */
  noStandard?: Set<string>
}

const STATUS_STYLE: Record<string, string> = {
  open: 'bg-blue-50',
  fulfilled: 'bg-green-50',
  carried: 'bg-amber-50',
  unfilled: 'bg-red-50',
}

function cellText(c: { planned: number; carried: number; obtained: number }, showObtained: boolean): string {
  let s = String(c.planned)
  if (c.carried > 0) s += ` (+${c.carried})`
  if (showObtained) s += ` ✓${c.obtained}`
  return s
}

/** Tabla de cuotas agrupada por ciudad de origen: grupos plegados con totales; solo se pinta lo que se despliega. */
export function QuotaMatrix({ quotas, cityName, showObtained, noStandard }: Props) {
  const { t } = useTranslation()
  const [by, setBy] = useState<'week' | 'month'>('week')
  const [filter, setFilter] = useState('')
  const [expanded, setExpanded] = useState<string[]>([])

  const base = useMemo(() => quotaMatrix(quotas, cityName), [quotas, cityName])
  const matrix = useMemo(() => groupQuotaMatrix(base, by), [base, by])
  const groups = useMemo(() => {
    const f = filter.trim().toLowerCase()
    return originGroups(f ? matrix.rows.filter((r) => r.route.toLowerCase().includes(f)) : matrix.rows)
  }, [matrix, filter])

  const cols = matrix.weeks
  const grandTotal = groups.reduce((a, g) => a + g.total, 0)
  const routeCount = groups.reduce((a, g) => a + g.rows.length, 0)
  const groupSize = (id: string) => (groups.find((g) => g.origin_city_id === id)?.rows.length ?? 0) * cols.length
  const toggle = (id: string) => setExpanded((e) => nextExpandedGroups(e, id, groupSize))

  return (
    <div className="space-y-3">
      <div className="flex flex-wrap items-center gap-3">
        <input
          className="border border-gray-300 rounded-lg px-3 py-2 min-w-[16rem]"
          placeholder={t('cl.plans.matrix.filter')}
          value={filter}
          onChange={(e) => setFilter(e.target.value)}
        />
        <div className="inline-flex rounded-lg border border-gray-300 overflow-hidden text-sm">
          {(['week', 'month'] as const).map((k) => (
            <button
              key={k}
              type="button"
              onClick={() => setBy(k)}
              className={`px-3 py-2 ${by === k ? 'bg-blue-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'}`}
            >
              {t(`cl.plans.matrix.by_${k}`)}
            </button>
          ))}
        </div>
        <span className="text-sm text-gray-600">
          {t('cl.plans.matrix.summary', { routes: routeCount, total: grandTotal })}
        </span>
      </div>
      <p className="text-xs text-gray-500">
        {showObtained ? t('cl.plans.matrix.legend_obtained') : t('cl.plans.matrix.legend')}{' '}
        {t('cl.plans.matrix.expand_hint', { cells: MAX_EXPANDED_CELLS })}
      </p>

      {groups.length === 0 ? (
        <p className="text-sm text-gray-500">{t('cl.plans.matrix.no_match')}</p>
      ) : (
        <div className="bg-white rounded-lg border border-gray-200 overflow-auto max-h-[70vh]">
          <table className="min-w-full text-xs">
            <thead className="bg-gray-50 text-gray-600 sticky top-0 z-10">
              <tr>
                <th className="text-start px-3 py-2 sticky start-0 bg-gray-50 min-w-[14rem]">{t('cl.plans.matrix.route')}</th>
                {cols.map((c) => (
                  <th key={c} className="px-2 py-2 text-end whitespace-nowrap">
                    {c}
                  </th>
                ))}
                <th className="px-3 py-2 text-end">{t('cl.plans.matrix.total')}</th>
              </tr>
            </thead>
            <tbody>
              {groups.map((g) => {
                const open = expanded.includes(g.origin_city_id)
                return (
                  <Fragment key={g.origin_city_id}>
                    <tr className="border-t border-gray-200 bg-gray-50/60 font-medium">
                      <td className="px-3 py-2 sticky start-0 bg-gray-50">
                        <button
                          type="button"
                          onClick={() => toggle(g.origin_city_id)}
                          className="inline-flex items-center gap-1 text-gray-900 hover:text-blue-700"
                        >
                          {open ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4 rtl:rotate-180" />}
                          {g.origin}
                          <span className="text-gray-500 font-normal">({t('cl.plans.matrix.routes', { count: g.rows.length })})</span>
                        </button>
                      </td>
                      {cols.map((c) => {
                        const cell = g.cells[c]
                        return (
                          <td key={c} className="px-2 py-2 text-end whitespace-nowrap">
                            {cell ? cellText(cell, showObtained) : ''}
                          </td>
                        )
                      })}
                      <td className="px-3 py-2 text-end">{g.total}</td>
                    </tr>
                    {open &&
                      g.rows.map((r) => (
                        <tr key={r.key} className="border-t border-gray-100">
                          <td className="px-3 py-1 ps-8 sticky start-0 bg-white whitespace-nowrap">
                            {r.route}
                            {noStandard?.has(r.key) && (
                              <span className="ms-2 inline-flex items-center gap-1 text-amber-700" title={t('cl.plans.no_standard')}>
                                <AlertTriangle className="w-3 h-3" />
                                {t('cl.plans.no_standard')}
                              </span>
                            )}
                          </td>
                          {cols.map((c) => {
                            const cell = r.cells[c]
                            return (
                              <td key={c} className={`px-2 py-1 text-end whitespace-nowrap ${cell ? STATUS_STYLE[cell.status] ?? '' : ''}`}>
                                {cell ? cellText(cell, showObtained) : ''}
                              </td>
                            )
                          })}
                          <td className="px-3 py-1 text-end">{r.total}</td>
                        </tr>
                      ))}
                  </Fragment>
                )
              })}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}
