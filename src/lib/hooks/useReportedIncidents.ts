import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type { ReportedIncident, ReportedIncidentDetail, ReportedIncidentStatus } from '@/lib/types'

export function useReportedIncidents() {
  const { effectiveAccountId } = useAccount()
  const [inbox, setInbox] = useState<ReportedIncident[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchInbox = useCallback(async () => {
    try {
      setLoading(true); setError(null)
      let q = supabase
        .from('panelist_incident')
        .select('*, panelist:panelists ( name, panelist_code )')
        .order('reported_at', { ascending: false })
      if (effectiveAccountId) q = q.eq('account_id', effectiveAccountId)
      const { data, error: e } = await q
      if (e) throw e
      setInbox((data || []).map((r: any) => ({
        ...r, panelist_name: r.panelist?.name ?? '-', panelist_code: r.panelist?.panelist_code ?? '-',
      })))
    } catch (err: any) { setError(err.message); console.error('fetchInbox reported', err) }
    finally { setLoading(false) }
  }, [effectiveAccountId])

  useEffect(() => { fetchInbox() }, [fetchInbox])

  const fetchIncident = useCallback(async (id: string): Promise<ReportedIncidentDetail | null> => {
    const { data, error: e } = await supabase
      .from('panelist_incident')
      .select(`*,
        panelist:panelists(id,name,panelist_code,email,mobile,telegram_id,language,address_city,node_id),
        detail:allocation_plan_details(id,fecha_programada,status,tag_id,origin_node_id,destination_node_id,origin_panelist_id,destination_panelist_id,
          origin_node:nodes!allocation_plan_details_origin_node_id_fkey(auto_id),
          destination_node:nodes!allocation_plan_details_destination_node_id_fkey(auto_id),
          plan:allocation_plans(carrier:carriers(name),product:products(description)))`)
      .eq('id', id).single()
    if (e) throw e
    return data as any
  }, [])

  const resolve = useCallback(async (id: string, status: ReportedIncidentStatus, note?: string, reply?: string) => {
    const { error: e } = await supabase.rpc('resolve_panelist_incident', {
      p_incident_id: id, p_status: status, p_resolution_note: note ?? null, p_reply_text: reply ?? null })
    if (e) throw e
  }, [])

  const actCancel = useCallback(async (detailId: string) => {
    const { error: e } = await supabase.rpc('cancel_detail', { p_detail_id: detailId }); if (e) throw e }, [])

  const listNodesForMove = useCallback(async (detailId: string): Promise<
    { node_id: string; auto_id: string; city_name: string; same_city: boolean; panelist_name: string }[]> => {
    const { data, error: e } = await supabase.rpc('list_nodes_for_sample_move', { p_detail_id: detailId })
    if (e) throw e
    return (data || []) as any
  }, [])

  // Vista previa del reenvío de una muestra devuelta (sent/incident); suggest_for_sample_move devolvería sample_not_movable.
  const suggestRerouteReturnedSample = useCallback(async (detailId: string, toNodeId: string, weekStart: string): Promise<Record<string, any>> => {
    const { data, error: e } = await supabase.rpc('suggest_reroute_returned_sample', {
      p_detail_id: detailId, p_to_node_id: toNodeId, p_week_start: weekStart })
    if (e) throw e
    return (data || {}) as Record<string, any>
  }, [])

  const rerouteReturnedSample = useCallback(async (detailId: string, toNodeId: string, weekStart: string): Promise<void> => {
    const { error: e } = await supabase.rpc('reroute_returned_sample', {
      p_detail_id: detailId, p_to_node_id: toNodeId, p_week_start: weekStart }); if (e) throw e }, [])

  const signedPhotoUrl = useCallback(async (path: string): Promise<string | null> => {
    const { data, error: e } = await supabase.storage.from('incident-photos').createSignedUrl(path, 3600)
    if (e) { console.error('signedPhotoUrl', e); return null }
    return data?.signedUrl ?? null
  }, [])

  const openCount = inbox.filter(r => r.status === 'open' || r.status === 'in_progress').length

  return { inbox, loading, error, openCount, fetchInbox, fetchIncident, resolve, actCancel, signedPhotoUrl,
    listNodesForMove, suggestRerouteReturnedSample, rerouteReturnedSample, panelistRole }
}

// Papel del panelista en el envío: emisor/receptor (por panelista asignado o, si no hay, por el nodo).
export function panelistRole(inc: ReportedIncidentDetail): 'sender' | 'receiver' | null {
  const d = inc.detail, p = inc.panelist
  if (!d || !p) return null
  if (d.origin_panelist_id === p.id || (d.origin_panelist_id == null && d.origin_node_id != null && d.origin_node_id === p.node_id)) return 'sender'
  if (d.destination_panelist_id === p.id || (d.destination_panelist_id == null && d.destination_node_id != null && d.destination_node_id === p.node_id)) return 'receiver'
  return null
}
