import { useCallback, useEffect, useRef, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useEffectiveAccountId } from './useEffectiveAccountId'

export interface DeferredCityRow {
  city_id: string
  city_name: string
  count: number
  waiting_reason: string | null
}

export interface DeferredPlanRow {
  plan_id: string
  plan_name: string
  total_samples: number
  scheduled: number
  done: number
  deferred: number
  pobox_extra: number
}

/** Resultado de rpc_deferred_samples_summary */
export interface DeferredSummary {
  pending_total: number
  by_city: DeferredCityRow[]
  by_plan: DeferredPlanRow[]
}

/** Evento de ventana: la pantalla de balanceo lo lanza tras aplicar; el hook (menu) vuelve a consultar. */
export const DEFERRED_SAMPLES_CHANGED = 'deferred-samples-changed'

export function notifyDeferredSamplesChanged(): void {
  window.dispatchEvent(new CustomEvent(DEFERRED_SAMPLES_CHANGED))
}

/**
 * Resumen de muestras por compensar de la cuenta efectiva. Sin cuenta (superadmin sin seleccionar) no consulta y
 * devuelve null. Si la RPC falla (p. ej. aun no desplegada) deja summary en null y registra el error: sin romper.
 */
export function useDeferredSamples() {
  const accountId = useEffectiveAccountId()
  const [summary, setSummary] = useState<DeferredSummary | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const seq = useRef(0)

  const refetch = useCallback(async () => {
    const id = ++seq.current
    if (!accountId) {
      setSummary(null)
      setError(null)
      setLoading(false)
      return
    }
    setLoading(true)
    try {
      const { data, error: rpcError } = await supabase.rpc('rpc_deferred_samples_summary', {
        p_account_id: accountId,
      })
      if (rpcError) throw rpcError
      if (id !== seq.current) return
      const d = data as Partial<DeferredSummary> | null
      setSummary(
        d && typeof d.pending_total === 'number'
          ? { pending_total: d.pending_total, by_city: d.by_city ?? [], by_plan: d.by_plan ?? [] }
          : null
      )
      setError(null)
    } catch (err) {
      if (id !== seq.current) return
      console.error('[useDeferredSamples] Error fetching deferred samples summary:', err)
      setSummary(null)
      setError(err instanceof Error ? err.message : String((err as { message?: unknown })?.message ?? err))
    } finally {
      if (id === seq.current) setLoading(false)
    }
  }, [accountId])

  useEffect(() => {
    refetch()
  }, [refetch])

  useEffect(() => {
    const handler = () => {
      refetch()
    }
    window.addEventListener(DEFERRED_SAMPLES_CHANGED, handler)
    return () => window.removeEventListener(DEFERRED_SAMPLES_CHANGED, handler)
  }, [refetch])

  return { summary, loading, error, refetch }
}
