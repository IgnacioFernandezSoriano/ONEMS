import { useState, useEffect, useCallback, useMemo } from 'react'
import { addDays, format, parseISO, isValid } from 'date-fns'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type {
  ReassignmentProposal, IncidentInboxRow, UnavailabilityHeader, IncidentStatus,
  IncidentStatusFilter, MoveSuggestion, CellSample,
} from '@/lib/types'

// Aviso entre instancias del hook: tras una accion que cambia incidencias, el menu y la bandeja se refrescan.
const INCIDENTS_CHANGED_EVENT = 'onems:incidents-changed'
const notifyIncidentsChanged = () => { window.dispatchEvent(new Event(INCIDENTS_CHANGED_EVENT)) }

export type IncidentDecision = 'accept' | 'cancel'

// Carrier y producto del plan de una muestra. FKs explicitas: allocation_plans tiene FK a
// carriers y a products (y products otra a carriers); sin hint PostgREST puede dar PGRST201.
const PLAN_EMBED = `plan:allocation_plans!allocation_plan_details_plan_id_fkey (
  carrier:carriers!allocation_plans_carrier_id_fkey ( name ),
  product:products!allocation_plans_product_id_fkey ( code, description )
)`

export interface DecideManyResult {
  ok: string[]
  failed: { id: string; message: string }[]
}

export function useUnavailabilityIncidents() {
  const { effectiveAccountId } = useAccount()
  const [allRows, setAllRows] = useState<IncidentInboxRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [statusFilter, setStatusFilter] = useState<IncidentStatusFilter>('open')

  // Bandeja: bajas de la cuenta con contadores de lineas calculados en JS.
  // silent: recarga en segundo plano (sin pasar por "cargando"), p. ej. tras una decision en el detalle;
  // asi el contador del menu se actualiza sin desmontar la pantalla abierta.
  const fetchInbox = useCallback(async (silent = false) => {
    try {
      if (!silent) setLoading(true)
      setError(null)
      let q = supabase
        .from('panelist_unavailability')
        .select(`
          id, start_date, end_date, reason, incident_status, auto_summary, created_at,
          panelist:panelists ( name, panelist_code, node:nodes ( auto_id, city:cities ( name ) ) ),
          lines:panelist_reassignment_proposal!prp_unavailability_fkey ( affected_role, status )
        `)
        .order('created_at', { ascending: false })
      if (effectiveAccountId) q = q.eq('account_id', effectiveAccountId)
      const { data, error: e } = await q
      if (e) throw e
      const rows: IncidentInboxRow[] = ((data || []) as any[]).map(u => {
        const lines: { affected_role: string; status: string }[] = u.lines || []
        return {
          unavailability_id: u.id,
          panelist_name: u.panelist?.name ?? '-',
          panelist_code: u.panelist?.panelist_code ?? '-',
          node_label: u.panelist?.node?.auto_id ?? '-',
          city_name: u.panelist?.node?.city?.name ?? '-',
          start_date: u.start_date,
          end_date: u.end_date,
          reason: u.reason ?? null,
          incident_status: u.incident_status as IncidentStatus,
          auto_summary: u.auto_summary ?? null,
          created_at: u.created_at,
          affected_count: lines.length,
          origin_count: lines.filter(l => l.affected_role === 'origin').length,
          destination_count: lines.filter(l => l.affected_role === 'destination').length,
          pending_count: lines.filter(l => l.status === 'pending').length,
        }
      })
      setAllRows(rows)
    } catch (err: any) { setError(err.message); console.error('fetchInbox', err) }
    finally { if (!silent) setLoading(false) }
  }, [effectiveAccountId])

  useEffect(() => { fetchInbox() }, [fetchInbox])

  // Cualquier instancia del hook (menu lateral, bandeja, detalle) se refresca en silencio cuando otra avisa de un
  // cambio (decision, movimiento, resolucion). Se agrupan los avisos seguidos (acciones en bloque).
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | null = null
    const onChanged = () => {
      if (timer) clearTimeout(timer)
      timer = setTimeout(() => { fetchInbox(true) }, 300)
    }
    window.addEventListener(INCIDENTS_CHANGED_EVENT, onChanged)
    return () => {
      window.removeEventListener(INCIDENTS_CHANGED_EVENT, onChanged)
      if (timer) clearTimeout(timer)
    }
  }, [fetchInbox])

  const inbox = useMemo(() => allRows.filter(r => {
    if (statusFilter === 'all') return true
    if (statusFilter === 'open') return r.incident_status === 'new' || r.incident_status === 'pending_manager'
    return r.incident_status === statusFilter
  }), [allRows, statusFilter])

  // Siempre sobre todas las incidencias de la cuenta, sin aplicar el filtro de UI.
  const pendingManagerCount = useMemo(
    () => allRows.filter(r => r.incident_status === 'pending_manager').length,
    [allRows],
  )

  const fetchHeader = useCallback(async (unavailabilityId: string): Promise<UnavailabilityHeader | null> => {
    const { data, error: e } = await supabase
      .from('panelist_unavailability')
      .select(`
        id, account_id, start_date, end_date, reason, incident_status, auto_summary, final_resolution, resolved_at,
        panelist:panelists ( name, panelist_code, node:nodes ( id, auto_id, city:cities ( id, name ) ) )
      `)
      .eq('id', unavailabilityId)
      .single()
    if (e) throw e
    if (!data) return null
    const d = data as any
    return {
      unavailability_id: d.id,
      account_id: d.account_id ?? null,
      panelist_name: d.panelist?.name ?? '-',
      panelist_code: d.panelist?.panelist_code ?? '-',
      start_date: d.start_date,
      end_date: d.end_date,
      reason: d.reason,
      node_id: d.panelist?.node?.id ?? null,
      node_code: d.panelist?.node?.auto_id ?? null,
      city_id: d.panelist?.node?.city?.id ?? null,
      city_name: d.panelist?.node?.city?.name ?? null,
      incident_status: d.incident_status as IncidentStatus,
      auto_summary: d.auto_summary ?? null,
      final_resolution: d.final_resolution ?? null,
      resolved_at: d.resolved_at ?? null,
    }
  }, [])

  // Lineas de una baja. Ordenar por status en SQL no deja 'pending' primero
  // (alfabeticamente auto_resolved < pending), asi que se reordena en JS con un
  // sort estable que conserva el orden por rol y fecha de creacion.
  const fetchLines = useCallback(async (unavailabilityId: string): Promise<ReassignmentProposal[]> => {
    const { data, error: e } = await supabase
      .from('panelist_reassignment_proposal')
      .select(`
        *,
        detail:allocation_plan_details!prp_detail_fkey (
          id, fecha_programada, original_fecha_programada, status, origin_node_id, destination_node_id,
          origin_node:nodes!allocation_plan_details_origin_node_id_fkey ( auto_id ),
          destination_node:nodes!allocation_plan_details_destination_node_id_fkey ( auto_id ),
          ${PLAN_EMBED}
        ),
        suggested_target_node:nodes!prp_target_node_fkey ( id, auto_id ),
        final_target_node:nodes!prp_final_node_fkey ( id, auto_id )
      `)
      .eq('unavailability_id', unavailabilityId)
      .order('affected_role')
      .order('created_at')
    if (e) throw e
    const lines = (data || []) as unknown as ReassignmentProposal[]
    const rank = (s: string) => (s === 'pending' ? 0 : 1)
    return [...lines].sort((a, b) => rank(a.status) - rank(b.status))
  }, [])

  // Decision sobre una linea pendiente: aceptar la propuesta del sistema o anular la muestra.
  const decide = useCallback(async (proposalId: string, decision: IncidentDecision): Promise<IncidentStatus> => {
    const { data, error: e } = await supabase.rpc('apply_manager_decision', {
      p_proposal_id: proposalId,
      p_decision: decision,
      p_week_start: null,
      p_reference_load: 6,
      p_deviation_percent: 20,
    })
    notifyIncidentsChanged()
    if (e) throw e
    return (data as { incident_status: IncidentStatus }).incident_status
  }, [])

  // Arrastrar una linea pendiente a una casilla (nodo x semana): propuesta (solo lectura) y aplicar.
  const suggestForCell = useCallback(async (
    proposalId: string, nodeId: string, weekStart: string, referenceLoad: number, deviationPercent: number,
  ): Promise<MoveSuggestion> => {
    const { data, error: e } = await supabase.rpc('suggest_for_cell', {
      p_proposal_id: proposalId,
      p_node_id: nodeId,
      p_week_start: weekStart,
      p_reference_load: referenceLoad,
      p_deviation_percent: deviationPercent,
    })
    if (e) throw e
    return (data || { found: false }) as MoveSuggestion
  }, [])

  const applyManagerMove = useCallback(async (
    proposalId: string, nodeId: string, weekStart: string, referenceLoad: number, deviationPercent: number,
  ): Promise<void> => {
    const { error: e } = await supabase.rpc('apply_manager_move', {
      p_proposal_id: proposalId,
      p_node_id: nodeId,
      p_week_start: weekStart,
      p_reference_load: referenceLoad,
      p_deviation_percent: deviationPercent,
    })
    notifyIncidentsChanged()
    if (e) throw e
  }, [])

  // Arrastrar cualquier muestra de una casilla (fromNodeId x semana) a otra.
  const suggestForSampleMove = useCallback(async (
    detailId: string, fromNodeId: string, toNodeId: string, weekStart: string,
    referenceLoad: number, deviationPercent: number,
  ): Promise<MoveSuggestion> => {
    const { data, error: e } = await supabase.rpc('suggest_for_sample_move', {
      p_detail_id: detailId,
      p_from_node_id: fromNodeId,
      p_to_node_id: toNodeId,
      p_week_start: weekStart,
      p_reference_load: referenceLoad,
      p_deviation_percent: deviationPercent,
    })
    if (e) throw e
    return (data || { found: false }) as MoveSuggestion
  }, [])

  const applySampleMove = useCallback(async (
    detailId: string, fromNodeId: string, toNodeId: string, weekStart: string,
    referenceLoad: number, deviationPercent: number,
  ): Promise<void> => {
    const { error: e } = await supabase.rpc('apply_sample_move', {
      p_detail_id: detailId,
      p_from_node_id: fromNodeId,
      p_to_node_id: toNodeId,
      p_week_start: weekStart,
      p_reference_load: referenceLoad,
      p_deviation_percent: deviationPercent,
    })
    notifyIncidentsChanged()
    if (e) throw e
  }, [])

  // Muestras no canceladas de un nodo (como origen o destino) en la semana que empieza weekStart.
  const fetchCellSamples = useCallback(async (nodeId: string, weekStart: string): Promise<CellSample[]> => {
    const s = parseISO(weekStart)
    if (!isValid(s)) return []
    const sunday = format(addDays(s, 6), 'yyyy-MM-dd')
    const { data, error: e } = await supabase
      .from('allocation_plan_details')
      .select(`
        id, fecha_programada, status, origin_node_id, destination_node_id,
        origin_node:nodes!allocation_plan_details_origin_node_id_fkey ( auto_id ),
        destination_node:nodes!allocation_plan_details_destination_node_id_fkey ( auto_id ),
        ${PLAN_EMBED},
        lines:panelist_reassignment_proposal!prp_detail_fkey ( id, unavailability_id, status, affected_role )
      `)
      .or(`origin_node_id.eq.${nodeId},destination_node_id.eq.${nodeId}`)
      .gte('fecha_programada', weekStart)
      .lte('fecha_programada', sunday)
      .neq('status', 'cancelled')
      .order('fecha_programada')
    if (e) throw e
    return (data || []) as unknown as CellSample[]
  }, [])

  // Secuencial; un error en una linea no corta las demas.
  const decideMany = useCallback(async (
    proposalIds: string[], decision: 'accept' | 'cancel',
  ): Promise<DecideManyResult> => {
    const result: DecideManyResult = { ok: [], failed: [] }
    for (const id of proposalIds) {
      try {
        await decide(id, decision)
        result.ok.push(id)
      } catch (err: any) {
        result.failed.push({ id, message: err?.message ?? String(err) })
      }
    }
    return result
  }, [decide])

  const saveResolution = useCallback(async (unavailabilityId: string, text: string): Promise<void> => {
    const { error: e } = await supabase.rpc('set_incident_resolution', {
      p_unavailability_id: unavailabilityId, p_text: text,
    })
    notifyIncidentsChanged()
    if (e) throw e
  }, [])

  return {
    inbox, loading, error, pendingManagerCount,
    statusFilter, setStatusFilter,
    fetchInbox, fetchHeader, fetchLines, decide, decideMany, saveResolution,
    suggestForCell, applyManagerMove, suggestForSampleMove, applySampleMove, fetchCellSamples,
  }
}
