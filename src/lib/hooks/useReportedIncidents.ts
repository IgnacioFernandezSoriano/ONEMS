import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type { ReportedIncident, ReportedIncidentStatus } from '@/lib/types'

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

  const fetchIncident = useCallback(async (id: string): Promise<ReportedIncident | null> => {
    const { data, error: e } = await supabase
      .from('panelist_incident')
      .select('*, panelist:panelists ( name, panelist_code, telegram_id, mobile, language ), detail:allocation_plan_details ( id, fecha_programada, status, origin_node_id, destination_node_id )')
      .eq('id', id).single()
    if (e) throw e
    return data as any
  }, [])

  const resolve = useCallback(async (id: string, status: ReportedIncidentStatus, note?: string, reply?: string) => {
    const { error: e } = await supabase.rpc('resolve_panelist_incident', {
      p_incident_id: id, p_status: status, p_resolution_note: note ?? null, p_reply_text: reply ?? null })
    if (e) throw e
  }, [])

  const actMarkReceived = useCallback(async (detailId: string) => {
    const { error: e } = await supabase.rpc('mark_detail_received_manual', { p_detail_id: detailId }); if (e) throw e }, [])
  const actInvalidate = useCallback(async (detailId: string, note?: string) => {
    const { error: e } = await supabase.rpc('invalidate_detail', { p_detail_id: detailId, p_note: note ?? null }); if (e) throw e }, [])
  const actReschedule = useCallback(async (detailId: string, newDate: string) => {
    const { error: e } = await supabase.rpc('reschedule_detail', { p_detail_id: detailId, p_new_date: newDate }); if (e) throw e }, [])
  const actCancel = useCallback(async (detailId: string) => {
    const { error: e } = await supabase.rpc('cancel_detail', { p_detail_id: detailId }); if (e) throw e }, [])
  const actUpdateContact = useCallback(async (panelistId: string, telegramId?: string, phone?: string, language?: string) => {
    const { error: e } = await supabase.rpc('update_panelist_contact', {
      p_panelist_id: panelistId, p_telegram_id: telegramId ?? null, p_phone: phone ?? null, p_language: language ?? null }); if (e) throw e }, [])
  const actCreateUnavailability = useCallback(async (incidentId: string, start: string, end: string, reason?: string) => {
    const { error: e } = await supabase.rpc('create_unavailability_from_incident', {
      p_incident_id: incidentId, p_start: start, p_end: end, p_reason: reason ?? null }); if (e) throw e }, [])

  const signedPhotoUrl = useCallback(async (path: string): Promise<string | null> => {
    const { data, error: e } = await supabase.storage.from('incident-photos').createSignedUrl(path, 3600)
    if (e) { console.error('signedPhotoUrl', e); return null }
    return data?.signedUrl ?? null
  }, [])

  const openCount = inbox.filter(r => r.status === 'open' || r.status === 'in_progress').length

  return { inbox, loading, error, openCount, fetchInbox, fetchIncident, resolve,
    actMarkReceived, actInvalidate, actReschedule, actCancel, actUpdateContact, actCreateUnavailability, signedPhotoUrl }
}
