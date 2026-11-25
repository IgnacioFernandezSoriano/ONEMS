import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import { fetchAllPages } from '@/lib/fetchAllPages'
import { CSV_MAX_ROWS, ID_CHUNK, fetchCapped } from '@/lib/carrierLink/clCsv'
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

/** Lectura de una muestra en la descarga CSV: con el envio al que pertenece. */
export interface ClSampleScanExport extends ClSampleScan {
  item_id: string
}

export type ClSamplesError = { message?: string; code?: string }

/** planId para listar las muestras de todos los planes de la cuenta (p. ej. sin View en cl_plans no hay lista de planes). */
export const CL_ALL_PLANS = 'all'

const SCAN_COLUMNS = 'id, sample_id, scan_at, role, place_ref, mode_ref, reader:readers(carrier_place_ref, carrier_mode_ref)'

function mapSample(r: any): ClSampleRow {
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
}

/** El punto se resuelve con el lector (carrier_scan) si la lectura no trae place/mode. */
function mapScan(r: any): ClSampleScan {
  return {
    id: r.id,
    scan_at: r.scan_at,
    role: r.role,
    place: r.place_ref ?? r.reader?.carrier_place_ref ?? null,
    mode: r.mode_ref ?? r.reader?.carrier_mode_ref ?? null,
  }
}

/**
 * Muestras activas de un plan (o de todos con CL_ALL_PLANS; null = aun sin decidir, no consulta), paginadas en el
 * servidor (50 por pagina, `.range()` + `count: 'exact'`).
 * Los filtros se aplican en la consulta: ruta con `.eq` sobre origen/destino; semana con un filtro sobre la cuota
 * incrustada (`cl_plan_quotas!inner`, iso_year + iso_week); mal encaminadas con `.eq('possible_misrouting', true)`.
 * La descarga CSV (exportSamples / exportScans) usa la misma consulta sin paginar (hasta CSV_MAX_ROWS).
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

  /** Consulta de las muestras con los filtros de la pantalla, ordenada (la pagina o la descarga ponen el rango). */
  const query = useCallback(
    (acc: string, plan: string, withCount: boolean) => {
      const wk = week ? parseWeekKey(week) : null
      const { origin, destination } = parseRouteFilter(route)
      const quotaEmbed = wk ? 'quota:cl_plan_quotas!inner(iso_year, iso_week)' : 'quota:cl_plan_quotas(iso_year, iso_week)'
      let q = supabase
        .from('cl_samples')
        .select(
          `id, item_id, origin_city_id, destination_city_id, start_at, end_at, possible_misrouting, ${quotaEmbed}, one_db(on_time_delivery)`,
          withCount ? { count: 'exact' } : undefined,
        )
        .eq('account_id', acc)
        .eq('status', 'active')
      if (plan !== CL_ALL_PLANS) q = q.eq('plan_id', plan)
      if (wk) q = q.eq('quota.iso_year', wk.iso_year).eq('quota.iso_week', wk.iso_week)
      if (origin) q = q.eq('origin_city_id', origin)
      if (destination) q = q.eq('destination_city_id', destination)
      if (misroutedOnly) q = q.eq('possible_misrouting', true)
      return q.order('start_at', { ascending: false, nullsFirst: false }).order('id')
    },
    [week, route, misroutedOnly],
  )

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
    const from = page * SAMPLES_PAGE_SIZE
    query(accountId, planId, true)
      .range(from, from + SAMPLES_PAGE_SIZE - 1)
      .then(({ data, count, error: e }) => {
        if (isStale()) return
        // 416 / PGRST103 = página fuera de rango: no es un error para el usuario, la pantalla ajusta la página.
        setError(e && e.code !== 'PGRST103' ? e : null)
        setTotal(count ?? 0)
        setSamples(((data ?? []) as any[]).map(mapSample))
        setLoading(false)
      })
  }, [accountId, planId, page, beginLoad, query])

  /** Lecturas de una muestra por fecha. */
  const scans = useCallback(async (sampleId: string): Promise<ClSampleScan[]> => {
    const { data, error: e } = await supabase
      .from('cl_sample_scans')
      .select(SCAN_COLUMNS)
      .eq('sample_id', sampleId)
      .order('scan_at', { ascending: true, nullsFirst: false })
      .limit(200)
    if (e) throw e
    return ((data ?? []) as any[]).map(mapScan)
  }, [])

  /** Descarga: todas las muestras de los filtros (hasta CSV_MAX_ROWS). */
  const exportSamples = useCallback(async (): Promise<{ rows: ClSampleRow[]; truncated: boolean }> => {
    if (!accountId || !planId) return { rows: [], truncated: false }
    const r = await fetchCapped<any>((from, to) => query(accountId, planId, false).range(from, to))
    return { rows: r.rows.map(mapSample), truncated: r.truncated }
  }, [accountId, planId, query])

  /** Descarga: las lecturas de todas las muestras de los filtros, en el orden de la lista (hasta CSV_MAX_ROWS lecturas). */
  const exportScans = useCallback(async (): Promise<{ rows: ClSampleScanExport[]; truncated: boolean }> => {
    const s = await exportSamples()
    const out: ClSampleScanExport[] = []
    let truncated = s.truncated
    for (let i = 0; i < s.rows.length && out.length < CSV_MAX_ROWS; i += ID_CHUNK) {
      const chunk = s.rows.slice(i, i + ID_CHUNK)
      const items = new Map(chunk.map((x) => [x.id, x.item_id]))
      const r = await fetchCapped<any>(
        (from, to) =>
          supabase
            .from('cl_sample_scans')
            .select(SCAN_COLUMNS)
            .in(
              'sample_id',
              chunk.map((x) => x.id),
            )
            .order('sample_id')
            .order('scan_at', { ascending: true, nullsFirst: false })
            .order('id')
            .range(from, to),
        CSV_MAX_ROWS - out.length,
      )
      out.push(...r.rows.map((x) => ({ ...mapScan(x), item_id: items.get(x.sample_id) ?? '' })))
      if (r.truncated) truncated = true
      if (out.length >= CSV_MAX_ROWS && i + ID_CHUNK < s.rows.length) truncated = true
    }
    const order = new Map(s.rows.map((x, i) => [x.item_id, i]))
    out.sort((a, b) => (order.get(a.item_id) ?? 0) - (order.get(b.item_id) ?? 0))
    return { rows: out, truncated }
  }, [exportSamples])

  return { samples, total, scans, exportSamples, exportScans, cities, loading, error }
}
