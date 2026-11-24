import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'

export type ClDeliveryError = { message?: string; code?: string }

export interface ClDeliveryRow {
  id: string
  feed_id: string
  period_start: string
  period_end: string
  source: string
  is_test: boolean
  format: string
  status: string
  phase: string | null
  bytes_loaded: number | null
  attempts: number
  file_bytes: number | null
  rows_total: number | null
  rows_rejected: number | null
  shipments_total: number | null
  shipments_valid: number | null
  shipments_drawn: number | null
  rejected_reasons: unknown
  error: string | null
  created_at: string
  received_at: string | null
  finished_at: string | null
  /** Alertas de esta entrega (recuento en el servidor). */
  alerts: number
}

export interface ClDeliveryFilters {
  feedId: string | null
  status: string | null
  /** Periodos que tocan [from, to] (fechas YYYY-MM-DD; null = sin limite). */
  from: string | null
  to: string | null
}

/** Filas por pagina (muy por debajo del tope de 1.000 de PostgREST). */
export const DELIVERIES_PAGE_SIZE = 25

// Del cursor (progress) solo se traen la fase, los bytes leidos y los intentos: nunca el testigo del proceso.
const COLUMNS =
  'id, feed_id, period_start, period_end, source, is_test, format, status, phase:progress->>phase, ' +
  'bytes_loaded:progress->load->>offset, attempts:progress->>attempts, file_bytes, rows_total, rows_rejected, ' +
  'shipments_total, shipments_valid, shipments_drawn, rejected_reasons, error, created_at, received_at, finished_at'

const toNum = (v: unknown): number | null => {
  if (v === null || v === undefined || v === '') return null
  const n = Number(v)
  return Number.isFinite(n) ? n : null
}

/**
 * Entregas de la cuenta (lectura: RLS de cl_deliveries con View en cl_monitor o cl_connectors), paginadas en el
 * servidor con recuento exacto. `pollMs` vuelve a cargar mientras alguna entrega de la pagina siga en curso.
 */
export function useClDeliveries(accountId: string | null, filters: ClDeliveryFilters, page: number, pollMs = 0) {
  const beginLoad = useLatestRequest()
  const [rows, setRows] = useState<ClDeliveryRow[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<ClDeliveryError | null>(null)
  const { feedId, status, from, to } = filters

  const load = useCallback(
    async (quiet = false) => {
      const isStale = beginLoad()
      if (!accountId) {
        setRows([])
        setTotal(0)
        setError(null)
        setLoading(false)
        return
      }
      if (!quiet) setLoading(true)
      let q = supabase.from('cl_deliveries').select(COLUMNS, { count: 'exact' }).eq('account_id', accountId)
      if (feedId) q = q.eq('feed_id', feedId)
      if (status) q = q.eq('status', status)
      if (from) q = q.gte('period_end', from)
      if (to) q = q.lte('period_start', to)
      const fromRow = page * DELIVERIES_PAGE_SIZE
      const res = await q
        .order('period_end', { ascending: false })
        .order('created_at', { ascending: false })
        .order('id')
        .range(fromRow, fromRow + DELIVERIES_PAGE_SIZE - 1)
      const data = (res.data ?? []) as unknown as Record<string, unknown>[]
      // Alertas por entrega: un recuento (head) por fila de esta pagina; nunca se traen filas.
      const alertCounts = await Promise.all(
        data.map((d) =>
          supabase
            .from('cl_alerts')
            .select('id', { count: 'exact', head: true })
            .eq('account_id', accountId)
            .eq('delivery_id', d.id as string),
        ),
      )
      if (isStale()) return
      // 416 / PGRST103 = pagina fuera de rango: no es un error para el usuario.
      const real = res.error && res.error.code !== 'PGRST103' ? res.error : null
      setError(real ?? alertCounts.map((r) => r.error).find(Boolean) ?? null)
      setTotal(res.count ?? 0)
      setRows(
        data.map((d, i) => ({
          id: d.id as string,
          feed_id: d.feed_id as string,
          period_start: d.period_start as string,
          period_end: d.period_end as string,
          source: d.source as string,
          is_test: d.is_test === true,
          format: d.format as string,
          status: d.status as string,
          phase: (d.phase as string | null) ?? null,
          bytes_loaded: toNum(d.bytes_loaded),
          attempts: toNum(d.attempts) ?? 0,
          file_bytes: toNum(d.file_bytes),
          rows_total: toNum(d.rows_total),
          rows_rejected: toNum(d.rows_rejected),
          shipments_total: toNum(d.shipments_total),
          shipments_valid: toNum(d.shipments_valid),
          shipments_drawn: toNum(d.shipments_drawn),
          rejected_reasons: d.rejected_reasons ?? null,
          error: (d.error as string | null) ?? null,
          created_at: d.created_at as string,
          received_at: (d.received_at as string | null) ?? null,
          finished_at: (d.finished_at as string | null) ?? null,
          alerts: alertCounts[i].count ?? 0,
        })),
      )
      setLoading(false)
    },
    [accountId, feedId, status, from, to, page, beginLoad],
  )

  useEffect(() => {
    void load()
  }, [load])

  const inFlight = rows.some((r) => r.status === 'received' || r.status === 'processing')
  useEffect(() => {
    if (!pollMs || !inFlight) return
    const id = window.setInterval(() => void load(true), pollMs)
    return () => window.clearInterval(id)
  }, [pollMs, inFlight, load])

  return { rows, total, loading, error, refetch: load }
}
