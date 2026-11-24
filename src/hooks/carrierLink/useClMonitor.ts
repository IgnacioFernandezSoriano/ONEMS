import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import { MONITOR_PAGE_SIZE } from '@/lib/carrierLink/monitorView'

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
    let aq = supabase
      .from('cl_alerts')
      .select('id, alert_type, severity, status, details, created_at, quota:cl_plan_quotas(origin_city_id, destination_city_id)', {
        count: 'exact',
      })
      .eq('account_id', accountId)
    if (alertFilter === 'open') aq = aq.eq('status', 'open')
    const aFrom = alertPage * MONITOR_PAGE_SIZE
    const aRes = await aq.order('created_at', { ascending: false }).order('id').range(aFrom, aFrom + MONITOR_PAGE_SIZE - 1)
    if (isStale()) return

    // 416 / PGRST103 = pagina fuera de rango: no es un error para el usuario.
    setError(aRes.error && aRes.error.code !== 'PGRST103' ? aRes.error : null)
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
  }, [accountId, alertPage, alertFilter, beginLoad])

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

  return { alerts, alertTotal, loading, error, setAlertStatus }
}
