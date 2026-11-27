import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import { fetchCapped } from '@/lib/carrierLink/clCsv'
import {
  INCIDENTS_PAGE_SIZE,
  parseIncident,
  parseIncidentList,
  statusParam,
  type IncidentDetail,
  type IncidentFilters,
  type IncidentListItem,
} from '@/lib/carrierLink/incidentView'

export type ClIncidentError = { message?: string; code?: string }

/** Lista paginada de incidencias (cl_incidents_list; el servidor limita a 1.000 por llamada, aqui 25). */
export function useClIncidents(accountId: string | null, filters: IncidentFilters, page: number) {
  const beginLoad = useLatestRequest()
  const [items, setItems] = useState<IncidentListItem[]>([])
  const [total, setTotal] = useState(0)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<ClIncidentError | null>(null)
  const { status, type, feedId } = filters

  const load = useCallback(async () => {
    const isStale = beginLoad()
    if (!accountId) {
      setItems([])
      setTotal(0)
      setError(null)
      setLoading(false)
      return
    }
    setLoading(true)
    const { data, error: e } = await supabase.rpc('cl_incidents_list', {
      p_account_id: accountId,
      p_status: statusParam(status),
      p_type: type,
      p_feed_id: feedId,
      p_limit: INCIDENTS_PAGE_SIZE,
      p_offset: page * INCIDENTS_PAGE_SIZE,
    })
    if (isStale()) return
    const parsed = parseIncidentList(data)
    setError(e ?? null)
    setItems(e ? [] : parsed.items)
    setTotal(e ? 0 : parsed.total)
    setLoading(false)
  }, [accountId, status, type, feedId, page, beginLoad])

  useEffect(() => {
    void load()
  }, [load])

  /** Descarga CSV: todas las incidencias de los filtros (el servidor da como mucho 1.000 por llamada). */
  const exportAll = useCallback(async (): Promise<{ rows: IncidentListItem[]; truncated: boolean }> => {
    if (!accountId) return { rows: [], truncated: false }
    return fetchCapped<IncidentListItem>(async (from, to) => {
      const { data, error: e } = await supabase.rpc('cl_incidents_list', {
        p_account_id: accountId,
        p_status: statusParam(status),
        p_type: type,
        p_feed_id: feedId,
        p_limit: to - from + 1,
        p_offset: from,
      })
      return { data: e ? null : parseIncidentList(data).items, error: e }
    })
  }, [accountId, status, type, feedId])

  return { items, total, loading, error, refetch: load, exportAll }
}

/** Recuento de incidencias sin resolver por tipo (para el Monitor): una llamada con limite 1 por tipo. */
export function useClIncidentCounts(accountId: string | null, feedId: string | null, enabled: boolean) {
  const beginLoad = useLatestRequest()
  const [counts, setCounts] = useState<Record<string, number> | null>(null)
  const [error, setError] = useState<ClIncidentError | null>(null)

  useEffect(() => {
    const isStale = beginLoad()
    if (!accountId || !enabled) {
      setCounts(null)
      setError(null)
      return
    }
    const types = ['missing_delivery', 'delivery_rejected', 'high_rejection', 'unknown_data', 'quota_unfilled']
    void Promise.all(
      types.map((t) =>
        supabase.rpc('cl_incidents_list', {
          p_account_id: accountId,
          p_status: 'unresolved',
          p_type: t,
          p_feed_id: feedId,
          p_limit: 1,
          p_offset: 0,
        }),
      ),
    ).then((res) => {
      if (isStale()) return
      const e = res.map((r) => r.error).find(Boolean) ?? null
      setError(e)
      setCounts(e ? null : Object.fromEntries(types.map((t, i) => [t, parseIncidentList(res[i].data).total])))
    })
  }, [accountId, feedId, enabled, beginLoad])

  return { counts, error }
}

export interface ClAccountMember {
  user_id: string
  label: string
}

/**
 * Una incidencia con sus cambios (cl_incident_get / _update / _close). Cada escritura va por el id de la incidencia y
 * la base comprueba la cuenta y el derecho Edit (mismo CL_FORBIDDEN si no).
 */
export function useClIncident(incidentId: string | null) {
  const beginLoad = useLatestRequest()
  const [incident, setIncident] = useState<IncidentDetail | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<ClIncidentError | null>(null)

  const load = useCallback(async () => {
    const isStale = beginLoad()
    if (!incidentId) {
      setIncident(null)
      setError(null)
      setLoading(false)
      return
    }
    setLoading(true)
    const { data, error: e } = await supabase.rpc('cl_incident_get', { p_incident_id: incidentId })
    if (isStale()) return
    setError(e ?? null)
    setIncident(e ? null : parseIncident(data))
    setLoading(false)
  }, [incidentId, beginLoad])

  useEffect(() => {
    void load()
  }, [load])

  const apply = async (op: PromiseLike<{ data: unknown; error: ClIncidentError | null }>) => {
    const { data, error: e } = await op
    if (e) return { error: e }
    setIncident(parseIncident(data))
    return { error: null }
  }

  const update = (args: { status?: 'open' | 'in_progress'; assigneeId?: string | null; note?: string }) => {
    if (!incidentId) return Promise.resolve({ error: { message: 'CL_FORBIDDEN' } as ClIncidentError })
    return apply(
      supabase.rpc('cl_incident_update', {
        p_incident_id: incidentId,
        p_status: args.status ?? null,
        p_assignee_id: args.assigneeId ?? null,
        p_note: args.note ?? null,
        p_clear_assignee: args.assigneeId === null,
      }),
    )
  }

  const close = (note: string) => {
    if (!incidentId) return Promise.resolve({ error: { message: 'CL_FORBIDDEN' } as ClIncidentError })
    return apply(supabase.rpc('cl_incident_close', { p_incident_id: incidentId, p_note: note.trim() || null }))
  }

  return { incident, loading, error, refetch: load, update, close }
}

/**
 * Personas que se pueden poner como responsables: miembros de la cuenta (account_members; solo lo devuelve a quien
 * gestiona la cuenta, que son quienes tienen Edit en incidencias). Sin derecho, lista vacia (nunca error).
 */
export function useClAccountMembers(accountId: string | null, enabled: boolean) {
  const [members, setMembers] = useState<ClAccountMember[]>([])
  useEffect(() => {
    let alive = true
    if (!accountId || !enabled) {
      setMembers([])
      return
    }
    void supabase.rpc('account_members', { p_account_id: accountId }).then(({ data, error }) => {
      if (!alive) return
      const rows = (error ? [] : ((data ?? []) as { user_id: string; email: string | null; full_name: string | null }[]))
      setMembers(
        rows
          .map((r) => ({ user_id: r.user_id, label: r.full_name?.trim() || r.email || r.user_id }))
          .sort((a, b) => a.label.localeCompare(b.label)),
      )
    })
    return () => {
      alive = false
    }
  }, [accountId, enabled])
  return members
}
