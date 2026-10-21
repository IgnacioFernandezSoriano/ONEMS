import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase'

export type ConversationKind = 'reported' | 'unavailability'

export interface IncidentMessage {
  id: string
  incident_kind: ConversationKind
  incident_id: string
  direction: 'outbound' | 'inbound' | 'internal'
  author: 'bot' | 'panelist' | 'manager' | 'system'
  body: string
  meta: Record<string, any> | null
  status: 'pending_send' | 'sent' | 'failed' | 'received'
  sent_at: string | null
  error: string | null
  created_at: string
}

const POLL_MS = 30000

export function useIncidentConversation(kind: ConversationKind, incidentId: string) {
  const [messages, setMessages] = useState<IncidentMessage[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const inFlight = useRef(false)
  const alive = useRef(true)
  // Recarga pedida mientras habia otra en vuelo (p. ej. tras enviar durante un poll): se repite al terminar
  const again = useRef(false)

  const reload = useCallback(async (): Promise<void> => {
    if (inFlight.current) { again.current = true; return }
    inFlight.current = true
    try {
      do {
        again.current = false
        try {
          const { data, error: e } = await supabase
            .from('incident_message')
            .select('*')
            .eq('incident_kind', kind)
            .eq('incident_id', incidentId)
            .order('created_at', { ascending: true })
          if (!alive.current) return
          if (e) throw e
          setMessages((data || []) as IncidentMessage[])
          setError(null)
        } catch (err: any) {
          if (alive.current) setError(err.message ?? String(err))
        }
      } while (again.current && alive.current)
    } finally {
      inFlight.current = false
      again.current = false
      if (alive.current) setLoading(false)
    }
  }, [kind, incidentId])

  useEffect(() => {
    alive.current = true
    setLoading(true)
    reload()
    const id = setInterval(reload, POLL_MS)
    return () => { alive.current = false; clearInterval(id) }
  }, [reload])

  const send = useCallback(async (body: string) => {
    const { error: e } = await supabase.rpc('send_manager_message', {
      p_incident_kind: kind, p_incident_id: incidentId, p_body: body,
    })
    if (e) throw new Error(e.message)
    await reload()
  }, [kind, incidentId, reload])

  return { messages, loading, error, reload, send }
}
