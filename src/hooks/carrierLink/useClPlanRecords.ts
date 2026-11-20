import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import {
  applyQuotaFilters,
  quotaPageRange,
  toQuotaRecord,
  QUOTA_COLUMNS,
  QUOTA_ORDER,
  type QuotaFilters,
  type QuotaRecord,
} from '@/lib/carrierLink/planRecords'

export type ClRecordsError = { message?: string; code?: string }

interface QuotaQuery extends PromiseLike<{ data: unknown[] | null; count: number | null; error: ClRecordsError | null }> {
  eq(column: string, value: unknown): QuotaQuery
  order(column: string): QuotaQuery
  range(from: number, to: number): QuotaQuery
}

/**
 * Forma de captura de los carriers de la cuenta, para decidir si Planes de Asignación muestra Carrier Link.
 * Con accountId null no consulta nada (producción, sin permiso o sin cuenta): la página es la de siempre.
 */
export function useClCaptureCarriers(accountId: string | null) {
  const [carriers, setCarriers] = useState<{ id: string; capture_method: string | null }[]>([])
  useEffect(() => {
    if (!accountId) {
      setCarriers([])
      return
    }
    let cancelled = false
    supabase
      .from('carriers')
      .select('id, capture_method')
      .eq('account_id', accountId)
      .in('capture_method', ['carrier_link', 'both'])
      .limit(50)
      .then(({ data, error }) => {
        if (cancelled) return
        setCarriers(error ? [] : ((data ?? []) as { id: string; capture_method: string | null }[]))
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
