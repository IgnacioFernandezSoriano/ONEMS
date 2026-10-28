import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { notifyIncidentAttention } from '@/lib/hooks/useIncidentAttention'

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
  read_at?: string | null
}

const POLL_MS = 30000
const PHOTO_BUCKET = 'incident-photos'
const PHOTO_TTL = 3600
let warnedRead = false

export function useIncidentConversation(kind: ConversationKind, incidentId: string) {
  const [messages, setMessages] = useState<IncidentMessage[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const inFlight = useRef(false)
  const alive = useRef(true)
  // Recarga pedida mientras habia otra en vuelo (p. ej. tras enviar durante un poll): se repite al terminar
  const again = useRef(false)
  const [photoUrls, setPhotoUrls] = useState<Record<string, string>>({})
  const photoRequested = useRef<Set<string>>(new Set())
  const markedFor = useRef('')

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
          const list = (data || []) as IncidentMessage[]
          setMessages(list)
          setError(null)
          // Marca como leidos los inbound nuevos (una vez por lote, sin bucles)
          const unreadIds = list.filter(m => m.direction === 'inbound' && m.read_at == null).map(m => m.id).sort().join(',')
          if (unreadIds && unreadIds !== markedFor.current) {
            markedFor.current = unreadIds
            const { error: re } = await supabase.rpc('mark_incident_conversation_read', {
              p_incident_kind: kind, p_incident_id: incidentId,
            })
            if (re && !warnedRead) { warnedRead = true; console.warn('mark_incident_conversation_read no disponible', re) }
            if (!re) notifyIncidentAttention()
          }
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

  // URLs firmadas de las fotos (cache por ruta, 1 hora)
  useEffect(() => {
    for (const m of messages) {
      const path = m.meta && typeof m.meta === 'object' ? m.meta.photo_path : null
      if (typeof path !== 'string' || !path || photoRequested.current.has(path)) continue
      photoRequested.current.add(path)
      supabase.storage.from(PHOTO_BUCKET).createSignedUrl(path, PHOTO_TTL).then(({ data, error: e }) => {
        if (e || !data?.signedUrl) { photoRequested.current.delete(path); return }
        if (alive.current) setPhotoUrls(prev => ({ ...prev, [path]: data.signedUrl }))
      })
    }
  }, [messages])

  const send = useCallback(async (body: string) => {
    const { error: e } = await supabase.rpc('send_manager_message', {
      p_incident_kind: kind, p_incident_id: incidentId, p_body: body,
    })
    if (e) throw new Error(e.message)
    await reload()
  }, [kind, incidentId, reload])

  return { messages, loading, error, reload, send, photoUrls }
}
