import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import {
  applyQuotaFilters,
  quotaPageRange,
  toQuotaRecord,
  QUOTA_COLUMNS,
  QUOTA_ORDER,
  quotaTotalsParams,
  toQuotaFilterTotals,
  CL_ALL_ACCOUNTS,
  type QuotaFilters,
  type QuotaFilterTotals,
  type QuotaRecord,
} from '@/lib/carrierLink/planRecords'

export type ClRecordsError = { message?: string; code?: string }

interface QuotaQuery extends PromiseLike<{ data: unknown[] | null; count: number | null; error: ClRecordsError | null }> {
  eq(column: string, value: unknown): QuotaQuery
  order(column: string): QuotaQuery
  range(from: number, to: number): QuotaQuery
}

/**
 * Forma de captura de los carriers de la cuenta, para decidir si Planes de Asignación (o el menú) muestra Carrier Link.
 * Con accountId null no consulta nada (producción, sin permiso o sin cuenta): la página es la de siempre.
 * CL_ALL_ACCOUNTS: los de todas las cuentas que deje ver RLS (superadmin con "todas las cuentas").
 */
type CaptureCarrier = { id: string; capture_method: string | null }
/** Siempre el mismo array vacío: sin cuenta no hay ni consulta ni re-render (producción, la página de siempre). */
const NO_CARRIERS: CaptureCarrier[] = []

export function useClCaptureCarriers(accountId: string | null) {
  const [carriers, setCarriers] = useState<CaptureCarrier[]>(NO_CARRIERS)
  useEffect(() => {
    if (!accountId) {
      setCarriers(NO_CARRIERS)
      return
    }
    let cancelled = false
    let query = supabase.from('carriers').select('id, capture_method').in('capture_method', ['carrier_link', 'both'])
    if (accountId !== CL_ALL_ACCOUNTS) query = query.eq('account_id', accountId)
    query
      .limit(50)
      .then(({ data, error }) => {
        if (cancelled) return
        setCarriers(error ? NO_CARRIERS : ((data ?? []) as CaptureCarrier[]))
      })
    return () => {
      cancelled = true
    }
  }, [accountId])
  return carriers
}

/**
 * Cuotas (registros) de un plan de Carrier Link, paginadas en el servidor (`.range()` + `count: 'exact'`): un plan
 * puede tener decenas de miles. planId null = sin plan elegido, no consulta.
 */
export function useClPlanQuotas(planId: string | null, filters: QuotaFilters, page: number, pageSize: number) {
  const beginLoad = useLatestRequest()
  const [rows, setRows] = useState<QuotaRecord[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<ClRecordsError | null>(null)
  const { origin, destination, week, status } = filters

  useEffect(() => {
    const isStale = beginLoad()
    if (!planId) {
      setRows([])
      setTotal(0)
      setError(null)
      setLoading(false)
      return
    }
    setLoading(true)
    // Tipo mínimo del constructor de PostgREST (el genérico completo es demasiado profundo para TypeScript).
    const base = supabase.from('cl_plan_quotas').select(QUOTA_COLUMNS, { count: 'exact' }) as unknown as QuotaQuery
    let q = applyQuotaFilters(base, planId, { origin, destination, week, status })
    for (const col of QUOTA_ORDER) q = q.order(col)
    const { from, to } = quotaPageRange(page, pageSize)
    q.range(from, to).then(({ data, count, error: e }) => {
      if (isStale()) return
      // 416 / PGRST103 = página fuera de rango: la pantalla ajusta la página, no es un error para el usuario.
      setError(e && e.code !== 'PGRST103' ? e : null)
      setTotal(count ?? 0)
      setRows(((data ?? []) as Record<string, any>[]).map(toQuotaRecord))
      setLoading(false)
    })
  }, [planId, origin, destination, week, status, page, pageSize, beginLoad])

  return { rows, total, loading, error }
}

/**
 * Totales de TODAS las cuotas del plan que cumplen los filtros (cl_plan_quota_totals, en el servidor): la tabla solo
 * trae una página. planId null = sin plan elegido, no consulta.
 */
export function useClPlanQuotaTotals(planId: string | null, filters: QuotaFilters) {
  const beginLoad = useLatestRequest()
  const [totals, setTotals] = useState<QuotaFilterTotals | null>(null)
  const [failed, setFailed] = useState(false)
  const { origin, destination, week, status } = filters

  useEffect(() => {
    const isStale = beginLoad()
    // Mientras llegan los de estos filtros no se muestran los anteriores.
    setTotals(null)
    setFailed(false)
    if (!planId) return
    supabase
      .rpc('cl_plan_quota_totals', quotaTotalsParams(planId, { origin, destination, week, status }))
      .then(
        ({ data, error }) => {
          if (isStale()) return
          // Sin totales (error o sin fila): la pantalla se queda con los de la página y un aviso.
          const read = error ? null : toQuotaFilterTotals(data)
          setTotals(read)
          setFailed(read === null)
        },
        () => {
          if (!isStale()) setFailed(true)
        },
      )
  }, [planId, origin, destination, week, status, beginLoad])

  return { totals, failed }
}
