import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'

const REFRESH_MS = 60000
// Lo emiten el detalle (incidencia abierta) y la conversacion (mensajes leidos) para que el menu se actualice ya.
export const INCIDENT_ATTENTION_EVENT = 'onems:incident-attention-changed'
export const notifyIncidentAttention = () => { window.dispatchEvent(new Event(INCIDENT_ATTENTION_EVENT)) }
// Mismo aviso que emite useUnavailabilityIncidents tras una decision.
const INCIDENTS_CHANGED_EVENT = 'onems:incidents-changed'
let warned = false

// Contador del menu: incidencias en las que el manager tiene que actuar (nuevas sin abrir o con respuestas del
// panelista sin leer; bajas pendientes de decision o con respuestas). Cuenta seleccionada / cuenta del usuario.
export function useIncidentAttention() {
  const { effectiveAccountId } = useAccount()
  const [counts, setCounts] = useState({ reported: 0, unavailability: 0, receipts: 0 })

  const load = useCallback(async (): Promise<void> => {
    // Recepciones: casos abiertos (pendientes o que requieren decision), los mismos del bloque "Decisiones
    // pendientes". RLS limita a las cuentas del usuario; con cuenta seleccionada, solo esa.
    let receipts = 0
    try {
      let q = supabase.from('receipt_case').select('id', { count: 'exact', head: true }).in('status', ['pending', 'needs_decision'])
      if (effectiveAccountId) q = q.eq('account_id', effectiveAccountId)
      const { count, error } = await q
      if (error) throw error
      receipts = count ?? 0
    } catch (err) {
      console.warn('receipt_case: contador del menu no disponible', err)
    }
    try {
      const { data, error } = await supabase.rpc('incident_attention_counts', { p_account_id: effectiveAccountId })
      if (error) throw error
      const r = (data || [])[0] as { reported: number; unavailability: number } | undefined
      setCounts({ reported: Number(r?.reported) || 0, unavailability: Number(r?.unavailability) || 0, receipts })
    } catch (err) {
      if (!warned) { warned = true; console.warn('incident_attention_counts no disponible', err) }
      setCounts({ reported: 0, unavailability: 0, receipts })
    }
  }, [effectiveAccountId])

  useEffect(() => {
    load()
    const id = setInterval(load, REFRESH_MS)
    window.addEventListener(INCIDENT_ATTENTION_EVENT, load)
    window.addEventListener(INCIDENTS_CHANGED_EVENT, load)
    return () => {
      clearInterval(id)
      window.removeEventListener(INCIDENT_ATTENTION_EVENT, load)
      window.removeEventListener(INCIDENTS_CHANGED_EVENT, load)
    }
  }, [load])

  return counts
}
