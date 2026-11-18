import { useCallback, useEffect, useMemo, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { INCIDENT_ATTENTION_EVENT } from '@/lib/hooks/useIncidentAttention'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { useLatestRequest } from '@/lib/latestRequest'

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
  // Cuenta elegida (superadmin) o la propia; null = todas las cuentas (solo superadmin).
  const effectiveAccountId = useEffectiveAccountId()
  const beginLoad = useLatestRequest()

  const load = useCallback(async (): Promise<void> => {
    const isStale = beginLoad()
    try {
      const { data, error } = await supabase.rpc('unread_incident_conversations', {
        p_account_id: effectiveAccountId,
      })
      if (isStale()) return
      if (error) throw error
      setRows((data || []) as UnreadRow[])
    } catch (err) {
      if (isStale()) return
      if (!warned) { warned = true; console.warn('unread_incident_conversations no disponible', err) }
      setRows([])
    }
  }, [beginLoad, effectiveAccountId])

  useEffect(() => {
    load()
    const id = setInterval(load, REFRESH_MS)
    window.addEventListener(INCIDENT_ATTENTION_EVENT, load)
    return () => { clearInterval(id); window.removeEventListener(INCIDENT_ATTENTION_EVENT, load) }
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
