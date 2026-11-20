import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import type { QuotaInput } from '@/lib/carrierLink/planView'
import type { QuotaChange } from '@/lib/carrierLink/quotaBalancing'

export type ClBalancingError = { message?: string; code?: string }

export interface ClRebalanceResult {
  changed: number
  created: number
  deleted: number
  fence: string | null
}

/**
 * Cuotas de un plan de Carrier Link para el Balanceo de Carga (todas: el cálculo se hace en el navegador) y aplicar
 * una propuesta con cl_plan_rebalance_quotas. `loadAll` es el lector paginado de useClPlans (de 1.000 en 1.000).
 */
export function useClBalancing(planId: string, loadAll: (planId: string) => Promise<QuotaInput[]>) {
  const beginLoad = useLatestRequest()
  const [quotas, setQuotas] = useState<QuotaInput[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<ClBalancingError | null>(null)

  const reload = useCallback(async () => {
    const isStale = beginLoad()
    setLoading(true)
    try {
      const rows = await loadAll(planId)
      if (isStale()) return
      setQuotas(rows)
      setError(null)
    } catch (e) {
      if (isStale()) return
      setError(e as ClBalancingError)
    } finally {
      if (!isStale()) setLoading(false)
    }
  }, [planId, loadAll, beginLoad])

  useEffect(() => {
    void reload()
  }, [reload])

  /** Envía solo las cuotas que cambian, con su valor absoluto; la base valida total, estado y fence. */
  const apply = async (
    changes: QuotaChange[],
    fence: string | null,
  ): Promise<{ success: true; result: ClRebalanceResult } | { success: false; error: ClBalancingError }> => {
    const { data, error: e } = await supabase.rpc('cl_plan_rebalance_quotas', {
      p_plan_id: planId,
      p_changes: changes,
      p_fence: fence,
    })
    if (e) return { success: false, error: e }
    return { success: true, result: data as ClRebalanceResult }
  }

  return { quotas, loading, error, reload, apply }
}
