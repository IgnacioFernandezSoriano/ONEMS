import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import {
  buildReadingPointRow,
  unknownPlaces,
  excludeRegistered,
  readerTypeForRole,
  type E2eRole,
  type ReadingPointForm,
  type UnknownPlace,
} from '@/lib/carrierLink/readingPoints'

export interface ClReadingPoint {
  id: string
  reader_id: string
  name: string
  carrier_id: string
  carrier_place_ref: string
  carrier_mode_ref: string | null
  e2e_role: E2eRole
  postal_center_id: string | null
  postal_center_name: string | null
  city_id: string | null
  city_name: string | null
  is_active: boolean
}

export interface ClCenterOption {
  id: string
  name: string
  city_id: string | null
  city_name: string | null
}

export interface ClCarrierOption {
  id: string
  code: string
  name: string
}

export type ClWriteResult = { success: true } | { success: false; error: string; key?: string }

const SCAN_WINDOW_DAYS = 90
const SCAN_LIMIT = 5000

/** Transportistas activos y centros postales (con ciudad) de la cuenta, para los desplegables. */
export function useClCarriersAndCenters(accountId: string | null) {
  const [carriers, setCarriers] = useState<ClCarrierOption[]>([])
  const [centers, setCenters] = useState<ClCenterOption[]>([])
  const [error, setError] = useState<{ message?: string; code?: string } | null>(null)

  useEffect(() => {
    if (!accountId) {
      setCarriers([])
      setCenters([])
      setError(null)
      return
    }
    let cancelled = false
    void (async () => {
      const [c, p] = await Promise.all([
        supabase.from('carriers').select('id, code, name').eq('account_id', accountId).eq('status', 'active').order('name'),
        supabase
          .from('postal_centers')
          .select('id, name, city_id, city:cities(name)')
          .eq('account_id', accountId)
          .is('deleted_at', null)
          .order('name'),
      ])
      if (cancelled) return
      setError(c.error ?? p.error ?? null)
      setCarriers((c.data ?? []) as ClCarrierOption[])
      setCenters(
        ((p.data ?? []) as any[]).map((r) => ({
          id: r.id,
          name: r.name,
          city_id: r.city_id ?? null,
          city_name: r.city?.name ?? null,
        })),
      )
    })()
    return () => {
      cancelled = true
    }
  }, [accountId])

  return { carriers, centers, error }
}

export function useClReadingPoints(accountId: string | null, carrierId: string | null) {
  const beginLoad = useLatestRequest()
  const [points, setPoints] = useState<ClReadingPoint[]>([])
  const [unknown, setUnknown] = useState<UnknownPlace[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<{ message?: string; code?: string } | null>(null)

  const refetch = useCallback(async () => {
    const isStale = beginLoad()
    if (!accountId || !carrierId) {
      setPoints([])
      setUnknown([])
      setLoading(false)
      return
    }
    setLoading(true)
    const since = new Date(Date.now() - SCAN_WINDOW_DAYS * 86400000).toISOString()
    const [pts, scans] = await Promise.all([
      supabase
        .from('readers')
        .select(
          'id, reader_id, name, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role, postal_center_id, is_active, postal_center:postal_centers(name, city_id, city:cities(name))',
        )
        .eq('account_id', accountId)
        .eq('capture_source', 'carrier_scan')
        .eq('carrier_id', carrierId)
        .is('deleted_at', null)
        .order('carrier_place_ref'),
      supabase
        .from('cl_batch_scans')
        .select('place_ref, mode_ref, reject_reason, reader_id')
        .eq('account_id', accountId)
        .is('reader_id', null)
        .gte('scan_at', since)
        .order('scan_at', { ascending: false })
        .limit(SCAN_LIMIT),
    ])
    if (isStale()) return
    if (pts.error) {
      setError(pts.error)
      setPoints([])
    } else {
      setError(null)
      setPoints(
        ((pts.data ?? []) as any[]).map((r) => ({
          id: r.id,
          reader_id: r.reader_id,
          name: r.name,
          carrier_id: r.carrier_id,
          carrier_place_ref: r.carrier_place_ref,
          carrier_mode_ref: r.carrier_mode_ref ?? null,
          e2e_role: r.e2e_role,
          postal_center_id: r.postal_center_id ?? null,
          postal_center_name: r.postal_center?.name ?? null,
          city_id: r.postal_center?.city_id ?? null,
          city_name: r.postal_center?.city?.name ?? null,
          is_active: r.is_active,
        })),
      )
    }
    // Sin permiso cl_monitor la consulta falla: lista vacía, sin error visible.
    const registered = ((pts.data ?? []) as any[]).map((r) => ({
      carrier_place_ref: r.carrier_place_ref as string,
      carrier_mode_ref: (r.carrier_mode_ref ?? null) as string | null,
      is_active: r.is_active as boolean,
    }))
    setUnknown(scans.error ? [] : excludeRegistered(unknownPlaces((scans.data ?? []) as any[]), registered))
    setLoading(false)
  }, [accountId, carrierId, beginLoad])

  useEffect(() => {
    void refetch()
  }, [refetch])

  const fail = (err: { message?: string; code?: string }): ClWriteResult => {
    return { success: false, error: err.message ?? '' }
  }

  const create = async (f: ReadingPointForm): Promise<ClWriteResult> => {
    const built = buildReadingPointRow(accountId, f)
    if (!built.ok) return { success: false, error: built.error, key: `cl.reading_points.error.${built.error}` }
    const { error: e } = await supabase.from('readers').insert(built.row)
    if (e) return fail(e)
    await refetch()
    return { success: true }
  }

  const update = async (id: string, f: ReadingPointForm): Promise<ClWriteResult> => {
    const built = buildReadingPointRow(accountId, f)
    if (!built.ok) return { success: false, error: built.error, key: `cl.reading_points.error.${built.error}` }
    const { account_id: _a, capture_source: _c, ...fields } = built.row
    void _a
    void _c
    const { error: e } = await supabase
      .from('readers')
      .update({ ...fields, type: readerTypeForRole(f.e2e_role), updated_at: new Date().toISOString() })
      .eq('id', id)
      .eq('capture_source', 'carrier_scan')
    if (e) return fail(e)
    await refetch()
    return { success: true }
  }

  /** Baja lógica: las tablas cl_* referencian a readers por FK. */
  const remove = async (id: string): Promise<ClWriteResult> => {
    const now = new Date().toISOString()
    const { error: e } = await supabase
      .from('readers')
      .update({ deleted_at: now, is_active: false, updated_at: now })
      .eq('id', id)
      .eq('capture_source', 'carrier_scan')
    if (e) return fail(e)
    await refetch()
    return { success: true }
  }

  return { points, unknown, loading, error, create, update, remove, refetch }
}
