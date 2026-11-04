import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import { notifyIncidentAttention } from '@/lib/hooks/useIncidentAttention'
import type {
  ReceiptDaySummary, ReceiptTrendPoint, ReceiptRepeatPanelist, ReceiptCase,
  ReceiptCandidateShipment, BroadcastRecipientsByLang, BroadcastHistoryRow,
} from '@/lib/types'

export function useReceiptErrors(date: string) {
  const { effectiveAccountId } = useAccount()
  const [summary, setSummary] = useState<ReceiptDaySummary | null>(null)
  const [trend, setTrend] = useState<ReceiptTrendPoint[]>([])
  const [repeaters, setRepeaters] = useState<ReceiptRepeatPanelist[]>([])
  const [cases, setCases] = useState<ReceiptCase[]>([])
  // Casos abiertos (pending / needs_decision) de cualquier dia: no deben quedar ocultos tras el selector de fecha.
  const [openCases, setOpenCases] = useState<ReceiptCase[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const refresh = useCallback(async () => {
    if (!effectiveAccountId) { setLoading(false); return }
    try {
      setLoading(true); setError(null)
      const [s, tr, rp, cs, op, nd] = await Promise.all([
        supabase.rpc('rpc_receipt_day_summary', { p_account_id: effectiveAccountId, p_date: date }),
        supabase.rpc('rpc_receipt_trend', { p_account_id: effectiveAccountId, p_days: 30 }),
        supabase.rpc('rpc_receipt_repeat_panelists', { p_account_id: effectiveAccountId }),
        supabase.rpc('rpc_receipt_cases', { p_account_id: effectiveAccountId, p_status: null, p_date: date }),
        supabase.rpc('rpc_receipt_cases', { p_account_id: effectiveAccountId, p_status: 'pending', p_date: null }),
        supabase.rpc('rpc_receipt_cases', { p_account_id: effectiveAccountId, p_status: 'needs_decision', p_date: null }),
      ])
      if (s.error) throw s.error
      if (tr.error) throw tr.error
      if (rp.error) throw rp.error
      if (cs.error) throw cs.error
      if (op.error) throw op.error
      if (nd.error) throw nd.error
      setSummary(s.data as ReceiptDaySummary)
      setTrend((tr.data || []) as ReceiptTrendPoint[])
      setRepeaters((rp.data || []) as ReceiptRepeatPanelist[])
      setCases((cs.data || []) as ReceiptCase[])
      setOpenCases(([...(nd.data || []), ...(op.data || [])] as ReceiptCase[])
        .sort((a, b) => b.first_attempt_at.localeCompare(a.first_attempt_at)))
    } catch (err: any) { setError(err.message); console.error('useReceiptErrors', err) }
    finally { setLoading(false) }
  }, [effectiveAccountId, date])

  useEffect(() => { refresh() }, [refresh])

  const fixCase = useCallback(async (caseId: string, detailId: string): Promise<string> => {
    const { data, error: e } = await supabase.rpc('rpc_receipt_case_fix', { p_case_id: caseId, p_detail_id: detailId })
    if (e) throw e
    await refresh()
    notifyIncidentAttention()
    return data as string
  }, [refresh])

  const closeCase = useCallback(async (caseId: string, note: string) => {
    const { error: e } = await supabase.rpc('rpc_receipt_case_close', { p_case_id: caseId, p_note: note })
    if (e) throw e
    await refresh()
    notifyIncidentAttention()
  }, [refresh])

  const sendNotice = useCallback(async (panelistId: string, body: string) => {
    const { error: e } = await supabase.rpc('rpc_send_panelist_notice', { p_panelist_id: panelistId, p_body: body })
    if (e) throw e
    await refresh()
  }, [refresh])

  const broadcast = useCallback(async (bodies: Record<string, string>): Promise<number> => {
    if (!effectiveAccountId) throw new Error('no account')
    const { data, error: e } = await supabase.rpc('rpc_broadcast_notice', { p_account_id: effectiveAccountId, p_bodies: bodies })
    if (e) throw e
    return (data ?? 0) as number
  }, [effectiveAccountId])

  const recipients = useCallback(async (): Promise<BroadcastRecipientsByLang[]> => {
    if (!effectiveAccountId) return []
    const { data, error: e } = await supabase.rpc('rpc_broadcast_recipients', { p_account_id: effectiveAccountId })
    if (e) throw e
    return (data || []) as BroadcastRecipientsByLang[]
  }, [effectiveAccountId])

  const history = useCallback(async (): Promise<BroadcastHistoryRow[]> => {
    if (!effectiveAccountId) return []
    const { data, error: e } = await supabase.rpc('rpc_broadcast_history', { p_account_id: effectiveAccountId })
    if (e) throw e
    return (data || []) as BroadcastHistoryRow[]
  }, [effectiveAccountId])

  // Envios 'sent' cuyo destino esta en la ciudad del panelista que declaro la recepcion, declarados no despues del
  // primer intento del caso (uno declarado despues no puede ser la carta recibida; el servidor lo rechaza).
  const candidates = useCallback(async (caseId: string): Promise<ReceiptCandidateShipment[]> => {
    if (!effectiveAccountId) return []
    const { data: c, error: e1 } = await supabase
      .from('receipt_case')
      .select('first_attempt_at, panelist:panelists(node:nodes(city_id))')
      .eq('id', caseId).single()
    if (e1) throw e1
    const cityId = (c as any)?.panelist?.node?.city_id
    const firstAttemptAt = (c as any)?.first_attempt_at as string | undefined
    if (!cityId || !firstAttemptAt) return []
    const { data, error: e2 } = await supabase
      .from('allocation_plan_details')
      .select('id, tag_id, fecha_programada, origin_panelist_name, dest:nodes!allocation_plan_details_destination_node_id_fkey!inner(city_id)')
      .eq('account_id', effectiveAccountId)
      .eq('status', 'sent')
      .eq('dest.city_id', cityId)
      .lte('sent_at', firstAttemptAt)
      .order('fecha_programada', { ascending: false })
      .limit(200)
    if (e2) throw e2
    return (data || []).map((r: any) => ({
      id: r.id, tag_id: r.tag_id, fecha_programada: r.fecha_programada, origin_panelist_name: r.origin_panelist_name,
    }))
  }, [effectiveAccountId])

  return { summary, trend, repeaters, cases, openCases, loading, error, refresh, fixCase, closeCase, sendNotice,
    broadcast, recipients, history, candidates }
}
