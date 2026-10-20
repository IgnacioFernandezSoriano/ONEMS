import { useState, useEffect, useCallback, useMemo } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type {
  ReassignmentProposal, IncidentInboxRow, UnavailabilityHeader, IncidentStatus,
  IncidentStatusFilter, WeekSuggestion,
} from '@/lib/types'

export type IncidentDecision = 'accept' | 'week' | 'cancel'

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
  const fetchInbox = useCallback(async () => {
    try {
      setLoading(true); setError(null)
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
    finally { setLoading(false) }
  }, [effectiveAccountId])

  useEffect(() => { fetchInbox() }, [fetchInbox])

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
        id, start_date, end_date, reason, incident_status, auto_summary, final_resolution, resolved_at,
        panelist:panelists ( name, panelist_code, node:nodes ( id, auto_id, city:cities ( id, name ) ) )
      `)
      .eq('id', unavailabilityId)
      .single()
    if (e) throw e
    if (!data) return null
    const d = data as any
    return {
      unavailability_id: d.id,
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
          destination_node:nodes!allocation_plan_details_destination_node_id_fkey ( auto_id )
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

  const suggestForWeek = useCallback(async (
    proposalId: string, weekStart: string, referenceLoad = 6, deviationPercent = 20,
  ): Promise<WeekSuggestion> => {
    const { data, error: e } = await supabase.rpc('suggest_for_week', {
      p_proposal_id: proposalId,
      p_week_start: weekStart,
      p_reference_load: referenceLoad,
      p_deviation_percent: deviationPercent,
    })
    if (e) throw e
    return (data || { found: false }) as WeekSuggestion
  }, [])

  const decide = useCallback(async (
    proposalId: string,
    decision: IncidentDecision,
    weekStart?: string,
    referenceLoad = 6,
    deviationPercent = 20,
  ): Promise<IncidentStatus> => {
    const { data, error: e } = await supabase.rpc('apply_manager_decision', {
      p_proposal_id: proposalId,
      p_decision: decision,
      p_week_start: weekStart ?? null,
      p_reference_load: referenceLoad,
      p_deviation_percent: deviationPercent,
    })
    if (e) throw e
    return (data as { incident_status: IncidentStatus }).incident_status
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
    if (e) throw e
  }, [])

  return {
    inbox, loading, error, pendingManagerCount,
    statusFilter, setStatusFilter,
    fetchInbox, fetchHeader, fetchLines, suggestForWeek, decide, decideMany, saveResolution,
  }
}
