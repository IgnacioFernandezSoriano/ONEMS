import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '@/lib/supabase'

interface UnreadRow {
  incident_kind: 'reported' | 'unavailability'
  incident_id: string
  unread: number
  last_at: string | null
}

const REFRESH_MS = 60000
let warned = false

// Conversaciones con respuestas nuevas del panelista. Si las funciones de BD aun no existen,
// no hay insignias (aviso unico en consola).
export function useUnreadConversations() {
  const [rows, setRows] = useState<UnreadRow[]>([])

  const load = useCallback(async (): Promise<void> => {
    try {
      const { data, error } = await supabase.rpc('unread_incident_conversations')
      if (error) throw error
      setRows((data || []) as UnreadRow[])
    } catch (err) {
      if (!warned) { warned = true; console.warn('unread_incident_conversations no disponible', err) }
      setRows([])
    }
  }, [])

  useEffect(() => {
    load()
    const id = setInterval(load, REFRESH_MS)
    return () => clearInterval(id)
  }, [load])

  return useMemo(() => {
    const unreadByKey: Record<string, number> = {}
    let totalReported = 0
    let totalUnavailability = 0
    for (const r of rows) {
      const n = Number(r.unread) || 0
      if (n <= 0) continue
      unreadByKey[`${r.incident_kind}:${r.incident_id}`] = n
      if (r.incident_kind === 'reported') totalReported++
      else totalUnavailability++
    }
    return { unreadByKey, totalReported, totalUnavailability }
  }, [rows])
}
