import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import { fetchAllPages } from '@/lib/fetchAllPages'
import {
  SAMPLES_PAGE_SIZE,
  parseRouteFilter,
  parseWeekKey,
  sampleRouteKey,
  weekKey,
  type SampleFilters,
} from '@/lib/carrierLink/sampleView'

export interface ClSampleRow {
  id: string
  item_id: string
  origin_city_id: string | null
  destination_city_id: string | null
  route_key: string
  start_at: string | null
  end_at: string | null
  possible_misrouting: boolean
  on_time_delivery: boolean | null
  quota_week?: string
}

export interface ClSampleScan {
  id: string
  scan_at: string | null
  role: 'start' | 'end' | 'intermediate'
  place: string | null
  mode: string | null
}

export type ClSamplesError = { message?: string; code?: string }

/**
 * Muestras activas de un plan, paginadas en el servidor (50 por pagina, `.range()` + `count: 'exact'`).
 * Los filtros se aplican en la consulta: ruta con `.eq` sobre origen/destino; semana con un filtro sobre la cuota
 * incrustada (`cl_plan_quotas!inner`, iso_year + iso_week); mal encaminadas con `.eq('possible_misrouting', true)`.
 */
export function useClSamples(accountId: string | null, planId: string | null, filters: SampleFilters, page: number) {
  const beginLoad = useLatestRequest()
  const [samples, setSamples] = useState<ClSampleRow[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<ClSamplesError | null>(null)
  const [cities, setCities] = useState<{ id: string; name: string }[]>([])

  const { week, route, misroutedOnly } = filters

  useEffect(() => {
    if (!accountId) {
      setCities([])
      return
    }
    let cancelled = false
    fetchAllPages<{ id: string; name: string }>((from, to) =>
      supabase.from('cities').select('id, name').eq('account_id', accountId).order('name').order('id').range(from, to),
    )
      .then((c) => !cancelled && setCities(c))
      .catch(() => !cancelled && setCities([]))
    return () => {
      cancelled = true
    }
  }, [accountId])

  useEffect(() => {
    const isStale = beginLoad()
    if (!accountId || !planId) {
      setSamples([])
      setTotal(0)
      setError(null)
      setLoading(false)
      return
    }
    setLoading(true)
    const wk = week ? parseWeekKey(week) : null
    const { origin, destination } = parseRouteFilter(route)
    const quotaEmbed = wk ? 'quota:cl_plan_quotas!inner(iso_year, iso_week)' : 'quota:cl_plan_quotas(iso_year, iso_week)'
    let q = supabase
      .from('cl_samples')
      .select(
        `id, item_id, origin_city_id, destination_city_id, start_at, end_at, possible_misrouting, ${quotaEmbed}, one_db(on_time_delivery)`,
        { count: 'exact' },
      )
      .eq('account_id', accountId)
      .eq('plan_id', planId)
      .eq('status', 'active')
    if (wk) q = q.eq('quota.iso_year', wk.iso_year).eq('quota.iso_week', wk.iso_week)
    if (origin) q = q.eq('origin_city_id', origin)
    if (destination) q = q.eq('destination_city_id', destination)
    if (misroutedOnly) q = q.eq('possible_misrouting', true)
    const from = page * SAMPLES_PAGE_SIZE
    q.order('start_at', { ascending: false, nullsFirst: false })
      .order('id')
      .range(from, from + SAMPLES_PAGE_SIZE - 1)
      .then(({ data, count, error: e }) => {
        if (isStale()) return
        setError(e ?? null)
        setTotal(count ?? 0)
        setSamples(
          ((data ?? []) as any[]).map((r) => {
            const od = Array.isArray(r.one_db) ? r.one_db[0] : r.one_db
            return {
              id: r.id,
              item_id: r.item_id,
              origin_city_id: r.origin_city_id,
              destination_city_id: r.destination_city_id,
              route_key: sampleRouteKey(r.origin_city_id, r.destination_city_id),
              start_at: r.start_at,
              end_at: r.end_at,
              possible_misrouting: r.possible_misrouting,
              on_time_delivery: od?.on_time_delivery ?? null,
              quota_week: r.quota ? weekKey(r.quota.iso_year, r.quota.iso_week) : undefined,
            }
          }),
        )
        setLoading(false)
      })
  }, [accountId, planId, week, route, misroutedOnly, page, beginLoad])

  /** Lecturas de una muestra por fecha; el punto se resuelve con el lector (carrier_scan) si la lectura no trae place/mode. */
  const scans = useCallback(async (sampleId: string): Promise<ClSampleScan[]> => {
    const { data, error: e } = await supabase
      .from('cl_sample_scans')
      .select('id, scan_at, role, place_ref, mode_ref, reader:readers(carrier_place_ref, carrier_mode_ref)')
      .eq('sample_id', sampleId)
      .order('scan_at', { ascending: true, nullsFirst: false })
      .limit(200)
    if (e) throw e
    return ((data ?? []) as any[]).map((r) => ({
      id: r.id,
      scan_at: r.scan_at,
      role: r.role,
      place: r.place_ref ?? r.reader?.carrier_place_ref ?? null,
      mode: r.mode_ref ?? r.reader?.carrier_mode_ref ?? null,
    }))
  }, [])

  return { samples, total, scans, cities, loading, error }
}
