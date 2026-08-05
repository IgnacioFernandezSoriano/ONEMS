import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type { ReassignmentProposal, IncidentInboxRow, RerouteCandidate, UnavailabilityHeader } from '@/lib/types'

export function useReassignmentProposals() {
  const { effectiveAccountId } = useAccount()
  const [inbox, setInbox] = useState<IncidentInboxRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // Nivel 1: bajas pending_review con propuestas y contadores.
  const fetchInbox = useCallback(async () => {
    try {
      setLoading(true); setError(null)
      // Traer propuestas de la cuenta activa con joins a baja/panelista/nodo/ciudad,
      // y agregarlas por unavailability_id en JS.
      let q = supabase
        .from('panelist_reassignment_proposal')
        .select(`
          id, unavailability_id, affected_role, status,
          unavailability:panelist_unavailability!inner (
            id, start_date, end_date, review_status,
            panelist:panelists ( name, panelist_code, node:nodes ( auto_id, city:cities ( name ) ) )
          )
        `)
      if (effectiveAccountId) q = q.eq('account_id', effectiveAccountId)
      const { data, error: e } = await q
      if (e) throw e
      // Filtrar a review_status='pending_review' y agregar contadores por baja.
      const byBaja = new Map<string, IncidentInboxRow>()
      for (const row of (data || []) as any[]) {
        const u = row.unavailability
        if (!u || u.review_status !== 'pending_review') continue
        let agg = byBaja.get(u.id)
        if (!agg) {
          agg = {
            unavailability_id: u.id,
            panelist_name: u.panelist?.name ?? '-',
            panelist_code: u.panelist?.panelist_code ?? '-',
            node_label: u.panelist?.node?.auto_id ?? '-',
            city_name: u.panelist?.node?.city?.name ?? '-',
            start_date: u.start_date, end_date: u.end_date,
            affected_count: 0, origin_count: 0, destination_count: 0, pending_count: 0,
          }
          byBaja.set(u.id, agg)
        }
        agg.affected_count++
        if (row.affected_role === 'origin') agg.origin_count++; else agg.destination_count++
        if (row.status === 'pending') agg.pending_count++
      }
      setInbox(Array.from(byBaja.values()))
    } catch (err: any) { setError(err.message); console.error('fetchInbox', err) }
    finally { setLoading(false) }
  }, [effectiveAccountId])

  useEffect(() => { fetchInbox() }, [fetchInbox])

  // Nivel 2: propuestas de una baja concreta.
  const fetchProposals = useCallback(async (unavailabilityId: string): Promise<ReassignmentProposal[]> => {
    const { data, error: e } = await supabase
      .from('panelist_reassignment_proposal')
      .select(`
        *,
        detail:allocation_plan_details ( id, fecha_programada, status, origin_node_id, destination_node_id ),
        suggested_target_node:nodes!prp_target_node_fkey ( id, auto_id )
      `)
      .eq('unavailability_id', unavailabilityId)
      .order('affected_role').order('created_at')
    if (e) throw e
    return (data || []) as any
  }, [])

  const confirmProposal = useCallback(async (p: ReassignmentProposal) => {
    const { error: e } = await supabase.rpc('apply_reassignment_proposal', {
      p_proposal_id: p.id,
      p_final_action: p.suggested_action,
      p_final_target_node_id: p.suggested_target_node_id,
      p_final_date: p.suggested_date,
    })
    if (e) throw e
  }, [])

  const overrideProposal = useCallback(async (
    id: string,
    action: 'reroute' | 'shift_date' | 'cancel',
    nodeId?: string | null,
    date?: string | null,
  ) => {
    // reroute/shift_date/cancel manuales se envían como 'manual' salvo cancel, que va como 'cancel'.
    const finalAction = action === 'cancel' ? 'cancel' : 'manual'
    const { error: e } = await supabase.rpc('apply_reassignment_proposal', {
      p_proposal_id: id,
      p_final_action: finalAction,
      p_final_target_node_id: action === 'reroute' ? (nodeId ?? null) : null,
      p_final_date: action === 'shift_date' ? (date ?? null) : null,
    })
    if (e) throw e
  }, [])

  const dismissProposal = useCallback(async (id: string) => {
    const { error: e } = await supabase.rpc('apply_reassignment_proposal', {
      p_proposal_id: id, p_final_action: 'none', p_final_target_node_id: null, p_final_date: null,
    })
    if (e) throw e
  }, [])

  const confirmMany = useCallback(async (props: ReassignmentProposal[]) => {
    for (const p of props) { if (p.status === 'pending') await confirmProposal(p) }
  }, [confirmProposal])
  const dismissMany = useCallback(async (ids: string[]) => {
    for (const id of ids) await dismissProposal(id)
  }, [dismissProposal])

  const listRerouteCandidates = useCallback(async (detailId: string, role: 'origin' | 'destination'): Promise<RerouteCandidate[]> => {
    const { data, error: e } = await supabase.rpc('list_reroute_candidates', { p_detail_id: detailId, p_role: role })
    if (e) throw e
    return (data || []) as RerouteCandidate[]
  }, [])

  const markReviewed = useCallback(async (unavailabilityId: string) => {
    const { data: { user } } = await supabase.auth.getUser()
    const { error: e } = await supabase
      .from('panelist_unavailability')
      .update({ review_status: 'reviewed', updated_by: user?.id ?? null })
      .eq('id', unavailabilityId)
    if (e) throw e
    await fetchInbox()
  }, [fetchInbox])

  // Cabecera de la baja (panelista, fechas, motivo) para el detalle.
  const fetchUnavailabilityHeader = useCallback(async (unavailabilityId: string): Promise<UnavailabilityHeader | null> => {
    const { data, error: e } = await supabase
      .from('panelist_unavailability')
      .select('id, start_date, end_date, reason, panelist:panelists ( name, panelist_code, node:nodes ( id, auto_id, city:cities ( id, name ) ) )')
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
    }
  }, [])

  // El badge cuenta BAJAS con casos pendientes de resolver (>=1 propuesta pending).
  const pendingCount = inbox.filter(r => r.pending_count > 0).length

  return {
    inbox, loading, error, pendingCount,
    fetchInbox, fetchProposals,
    confirmProposal, overrideProposal, dismissProposal, confirmMany, dismissMany,
    listRerouteCandidates, markReviewed, fetchUnavailabilityHeader,
  }
}
