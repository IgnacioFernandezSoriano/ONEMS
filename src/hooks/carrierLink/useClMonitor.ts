import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import { MONITOR_PAGE_SIZE } from '@/lib/carrierLink/monitorView'
import { fetchCapped } from '@/lib/carrierLink/clCsv'

export type ClMonitorError = { message?: string; code?: string }
export type AlertStatus = 'open' | 'acknowledged' | 'dismissed'

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

function mapAlert(a: any): ClAlertRow {
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
    destination_city_id: (quota?.destination_city_id ?? (d.destination_city_id as string | undefined) ?? null) as string | null,
  }
}

interface Options {
  alertPage: number
  /** 'open' = solo avisos abiertos; 'all' = todos. */
  alertFilter: 'open' | 'all'
}

/**
 * Avisos de Carrier Link de la cuenta, paginados en el servidor (`.range()` + `count: 'exact'`). Las entregas se
 * cargan aparte (useClDeliveries).
 */
export function useClMonitor(accountId: string | null, opts: Options) {
  const beginLoad = useLatestRequest()
  const { alertPage, alertFilter } = opts
  const [alerts, setAlerts] = useState<ClAlertRow[]>([])
  const [alertTotal, setAlertTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<ClMonitorError | null>(null)

  /** Consulta de avisos con el filtro (abiertos / todos), ordenada (la pagina o la descarga ponen el rango). */
  const query = useCallback(
    (acc: string, withCount: boolean) => {
      let aq = supabase
        .from('cl_alerts')
        .select(
          'id, alert_type, severity, status, details, created_at, quota:cl_plan_quotas(origin_city_id, destination_city_id)',
          withCount ? { count: 'exact' } : undefined,
        )
        .eq('account_id', acc)
      if (alertFilter === 'open') aq = aq.eq('status', 'open')
      return aq.order('created_at', { ascending: false }).order('id')
    },
    [alertFilter],
  )

  const load = useCallback(async () => {
    const isStale = beginLoad()
    if (!accountId) {
      setAlerts([])
      setAlertTotal(0)
      setError(null)
      setLoading(false)
      return
    }
    setLoading(true)
    const aFrom = alertPage * MONITOR_PAGE_SIZE
    const aRes = await query(accountId, true).range(aFrom, aFrom + MONITOR_PAGE_SIZE - 1)
    if (isStale()) return

    // 416 / PGRST103 = pagina fuera de rango: no es un error para el usuario.
    setError(aRes.error && aRes.error.code !== 'PGRST103' ? aRes.error : null)
    setAlertTotal(aRes.count ?? 0)
    setAlerts(((aRes.data ?? []) as any[]).map(mapAlert))
    setLoading(false)
  }, [accountId, alertPage, beginLoad, query])

  useEffect(() => {
    void load()
  }, [load])

  /** Solo cambia `status` (la base rellena quien y cuando). */
  const setAlertStatus = async (id: string, status: 'acknowledged' | 'dismissed'): Promise<{ error: ClMonitorError | null }> => {
    if (!accountId) return { error: { message: 'no account' } }
    const { error: e } = await supabase.from('cl_alerts').update({ status }).eq('id', id).eq('account_id', accountId)
    if (e) return { error: e }
    await load()
    return { error: null }
  }

  /** Descarga CSV: todos los avisos del filtro (hasta CSV_MAX_ROWS). */
  const exportAlerts = useCallback(async (): Promise<{ rows: ClAlertRow[]; truncated: boolean }> => {
    if (!accountId) return { rows: [], truncated: false }
    const r = await fetchCapped<any>((a, b) => query(accountId, false).range(a, b))
    return { rows: r.rows.map(mapAlert), truncated: r.truncated }
  }, [accountId, query])

  return { alerts, alertTotal, loading, error, setAlertStatus, exportAlerts }
}
