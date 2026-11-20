import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import { DEMAND_STATUSES, MONITOR_PAGE_SIZE, type DemandStatus } from '@/lib/carrierLink/monitorView'

export type ClMonitorError = { message?: string; code?: string }
export type AlertStatus = 'open' | 'acknowledged' | 'dismissed'

export interface ClBatchRow {
  id: string
  status: string
  created_at: string
  summary: unknown
  /** Muestras elegidas del lote (suma de cl_sampling_runs.samples_selected). */
  selected: number
}

export interface ClAlertRow {
  id: string
  alert_type: string
  severity: 'low' | 'medium' | 'high'
  status: AlertStatus
  details: unknown
  created_at: string
  origin_city_id: string | null
  destination_city_id: string | null
}

export interface ClUndoResult {
  pending: number
  carried: number
  kept: number
}

export type ClUndoOutcome = { success: true; result: ClUndoResult } | { success: false; error: ClMonitorError }

interface Options {
  batchPage: number
  alertPage: number
  /** 'open' = solo avisos abiertos; 'all' = todos. */
  alertFilter: 'open' | 'all'
}

const len = (v: unknown) => (Array.isArray(v) ? v.length : 0)

/**
 * Monitor de capturas de un plan (o de todos si planId es null). Nada se carga entero: las demandas son 4 recuentos
 * (`head: true`) por estado; lotes y avisos paginan en el servidor (`.range()` + `count: 'exact'`) con el filtro de plan
 * en la consulta (los lotes a traves de su demanda).
 */
export function useClMonitor(accountId: string | null, planId: string | null, opts: Options) {
  const beginLoad = useLatestRequest()
  const { batchPage, alertPage, alertFilter } = opts
  const [demands, setDemands] = useState<Record<DemandStatus, number>>({ open: 0, fulfilled: 0, partial: 0, failed: 0 })
  const [batches, setBatches] = useState<ClBatchRow[]>([])
  const [batchTotal, setBatchTotal] = useState(0)
  const [alerts, setAlerts] = useState<ClAlertRow[]>([])
  const [alertTotal, setAlertTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<ClMonitorError | null>(null)

  const load = useCallback(async () => {
    const isStale = beginLoad()
    if (!accountId) {
      setDemands({ open: 0, fulfilled: 0, partial: 0, failed: 0 })
      setBatches([])
      setBatchTotal(0)
      setAlerts([])
      setAlertTotal(0)
      setError(null)
      setLoading(false)
      return
    }
    setLoading(true)

    const demandQueries = DEMAND_STATUSES.map((s) => {
      let q = supabase
        .from('cl_demands')
        .select('id', { count: 'exact', head: true })
        .eq('account_id', accountId)
        .eq('status', s)
      if (planId) q = q.eq('plan_id', planId)
      return q
    })

    let bq = supabase
      .from('cl_batches')
      .select('id, status, created_at, summary, demand:cl_demands!inner(plan_id)', { count: 'exact' })
      .eq('account_id', accountId)
    if (planId) bq = bq.eq('demand.plan_id', planId)
    const bFrom = batchPage * MONITOR_PAGE_SIZE

    let aq = supabase
      .from('cl_alerts')
      .select('id, alert_type, severity, status, details, created_at, quota:cl_plan_quotas(origin_city_id, destination_city_id)', {
        count: 'exact',
      })
      .eq('account_id', accountId)
    // Con plan elegido tambien se ven los avisos de cuenta (plan_id nulo).
    if (planId) aq = aq.or(`plan_id.eq.${planId},plan_id.is.null`)
    if (alertFilter === 'open') aq = aq.eq('status', 'open')
    const aFrom = alertPage * MONITOR_PAGE_SIZE

    const [dRes, bRes, aRes] = await Promise.all([
      Promise.all(demandQueries),
      bq.order('created_at', { ascending: false }).order('id').range(bFrom, bFrom + MONITOR_PAGE_SIZE - 1),
      aq.order('created_at', { ascending: false }).order('id').range(aFrom, aFrom + MONITOR_PAGE_SIZE - 1),
    ])

    // Elegidos por lote: un recuento (head) por lote de esta pagina, en paralelo; incluye todas las muestras del lote
    // (tambien las de un lote deshecho). Nunca se traen filas: cl_sampling_runs puede pasar del tope de 1.000 de PostgREST.
    const batchRows = (bRes.data ?? []) as any[]
    const selCounts = await Promise.all(
      batchRows.map((b) =>
        supabase.from('cl_samples').select('id', { count: 'exact', head: true }).eq('account_id', accountId).eq('batch_id', b.id),
      ),
    )
    const selectedByBatch = new Map<string, number>(batchRows.map((b, i) => [b.id as string, selCounts[i].count ?? 0]))
    const runsError: ClMonitorError | null = selCounts.map((r) => r.error).find(Boolean) ?? null
    if (isStale()) return

    // 416 / PGRST103 = pagina fuera de rango: no es un error para el usuario.
    const real = (e: ClMonitorError | null) => (e && e.code !== 'PGRST103' ? e : null)
    setError(dRes.map((r) => r.error).find(Boolean) ?? real(bRes.error) ?? real(aRes.error) ?? runsError ?? null)
    const counts: Record<DemandStatus, number> = { open: 0, fulfilled: 0, partial: 0, failed: 0 }
    DEMAND_STATUSES.forEach((s, i) => {
      counts[s] = dRes[i].count ?? 0
    })
    setDemands(counts)
    setBatchTotal(bRes.count ?? 0)
    setBatches(
      batchRows.map((b) => ({
        id: b.id,
        status: b.status,
        created_at: b.created_at,
        summary: b.summary,
        selected: selectedByBatch.get(b.id) ?? 0,
      })),
    )
    setAlertTotal(aRes.count ?? 0)
    setAlerts(
      ((aRes.data ?? []) as any[]).map((a) => {
        const quota = Array.isArray(a.quota) ? a.quota[0] : a.quota
        const d = (a.details && typeof a.details === 'object' ? a.details : {}) as Record<string, unknown>
        return {
          id: a.id,
          alert_type: a.alert_type,
          severity: a.severity,
          status: a.status,
          details: a.details,
          created_at: a.created_at,
          origin_city_id: (quota?.origin_city_id ?? (d.origin_city_id as string | undefined) ?? null) as string | null,
          destination_city_id: (quota?.destination_city_id ?? (d.destination_city_id as string | undefined) ?? null) as
            | string
            | null,
        }
      }),
    )
    setLoading(false)
  }, [accountId, planId, batchPage, alertPage, alertFilter, beginLoad])

  useEffect(() => {
    void load()
  }, [load])

  /** Deshace un lote en la base (la pagina ya ha pedido confirmacion). */
  const undo = async (batchId: string): Promise<ClUndoOutcome> => {
    if (!accountId) return { success: false, error: { message: 'no account' } }
    const { data, error: e } = await supabase.rpc('cl_undo_batch', { p_batch_id: batchId })
    if (e) return { success: false, error: e }
    const r = (data ?? {}) as Record<string, unknown>
    await load()
    return { success: true, result: { pending: len(r.quotas_pending), carried: len(r.quotas_carried), kept: len(r.quotas_kept_open) } }
  }

  /** Solo cambia `status` (la base rellena quien y cuando). */
  const setAlertStatus = async (id: string, status: 'acknowledged' | 'dismissed'): Promise<{ error: ClMonitorError | null }> => {
    if (!accountId) return { error: { message: 'no account' } }
    const { error: e } = await supabase.from('cl_alerts').update({ status }).eq('id', id).eq('account_id', accountId)
    if (e) return { error: e }
    await load()
    return { error: null }
  }

  return { demands, batches, batchTotal, alerts, alertTotal, loading, error, undo, setAlertStatus }
}
