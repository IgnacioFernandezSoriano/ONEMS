import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase'
import type { ConversationKind } from '@/lib/hooks/useIncidentConversation'

export interface CaseDraft {
  key: string
  panelist_id: string
  code: string
  name: string
  language: string
  text: string
}

export interface CaseAnalysisResult {
  analysis: {
    summary: string
    plan: string
    reality: string
    comparison: string
    causes: { text: string, evidence: string, likelihood: 'alta' | 'media' | 'baja' }[]
    noise: string[]
    contacts: { panelist_id: string, role: 'remitente' | 'receptor' | 'destinatario', why: string }[]
    improvement: string | null
  }
  drafts: CaseDraft[]
  anchor: { kind: string, id: string } | null
  // panelist_id -> "Nombre (CODIGO)" de cada implicado (analisis anteriores pueden no traerlo)
  people?: Record<string, string>
}

export type CaseAnalysisState = 'idle' | 'running' | 'done' | 'failed'

const POLL_MS = 5000

// Puerta por cuenta: el servidor decide segun la cuenta de la incidencia (o la cuenta vista, en recepciones);
// null = aun consultando. Un fallo cuenta como false.
function useServerGate(fn: string, args: Record<string, unknown> | null): boolean | null {
  const [enabled, setEnabled] = useState<boolean | null>(null)
  const key = JSON.stringify(args)
  useEffect(() => {
    setEnabled(null)
    if (!args) { setEnabled(false); return }
    let alive = true
    void (async () => {
      try {
        const { data, error } = await supabase.rpc(fn, args)
        if (alive) setEnabled(error ? false : data === true)
      } catch {
        if (alive) setEnabled(false)
      }
    })()
    return () => { alive = false }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [fn, key])
  return enabled
}

export function useCaseAnalysisEnabled(kind: ConversationKind, incidentId: string): boolean | null {
  return useServerGate('case_analysis_enabled', { p_incident_kind: kind, p_incident_id: incidentId })
}

export function useCaseAnalysisEnabledForAccount(accountId: string | null | undefined): boolean | null {
  return useServerGate('case_analysis_enabled_for_account', accountId ? { p_account: accountId } : null)
}

export function useCaseAnalysis(kind: ConversationKind, incidentId: string) {
  const enabled = useCaseAnalysisEnabled(kind, incidentId)
  const [state, setState] = useState<CaseAnalysisState>('idle')
  const [result, setResult] = useState<CaseAnalysisResult | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [sent, setSent] = useState<Set<string>>(new Set())
  const [requestId, setRequestId] = useState<string | null>(null)
  const alive = useRef(true)

  useEffect(() => {
    alive.current = true
    return () => { alive.current = false }
  }, [])

  // Cambio de incidencia: se parte de cero
  useEffect(() => {
    setState('idle'); setResult(null); setError(null); setSent(new Set()); setRequestId(null)
  }, [kind, incidentId])

  useEffect(() => {
    if (state !== 'running' || !requestId) return
    let stopped = false
    let inFlight = false
    let netErrors = 0
    const poll = async () => {
      if (inFlight) return
      inFlight = true
      try {
        const { data, error: e } = await supabase.rpc('case_analysis_status', { p_request_id: requestId })
        if (stopped || !alive.current) return
        if (e) {
          // Tolera hasta 2 errores seguidos de red antes de dar el analisis por fallido
          netErrors += 1
          if (netErrors > 2) { setError(e.message); setState('failed') }
          return
        }
        netErrors = 0
        const st = data as { status: string, result: CaseAnalysisResult | null, error: string | null } | null
        if (st?.status === 'done') {
          setResult(st.result); setError(null); setState('done')
        } else if (st?.status === 'failed') {
          setError(st.error ?? 'failed'); setState('failed')
        }
      } catch (err: any) {
        if (stopped || !alive.current) return
        netErrors += 1
        if (netErrors > 2) { setError(err?.message ?? String(err)); setState('failed') }
      } finally { inFlight = false }
    }
    poll()
    const id = setInterval(poll, POLL_MS)
    return () => { stopped = true; clearInterval(id) }
  }, [state, requestId])

  const start = useCallback(async () => {
    setError(null); setResult(null); setSent(new Set()); setRequestId(null)
    setState('running')
    const { data, error: e } = await supabase.rpc('request_case_analysis', {
      p_incident_kind: kind, p_incident_id: incidentId,
    })
    if (!alive.current) return
    if (e || !data) { setError(e?.message ?? 'failed'); setState('failed'); return }
    setRequestId(data as string)
  }, [kind, incidentId])

  const send = useCallback(async (draft: CaseDraft, body: string) => {
    const { error: e } = await supabase.rpc('send_case_message', {
      p_incident_kind: kind, p_incident_id: incidentId,
      p_panelist_id: draft.panelist_id, p_body: body, p_draft_key: draft.key,
    })
    // 23505 = clave de borrador repetida: ya se envio
    if (e && e.code !== '23505') throw new Error(e.message)
    if (alive.current) setSent(prev => new Set(prev).add(draft.key))
  }, [kind, incidentId])

  return { state, result, error, start, send, sent, enabled }
}
