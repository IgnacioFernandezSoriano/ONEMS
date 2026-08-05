import { useState, useEffect, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type { CityNodeLoad } from '@/lib/types'

// Carga de los nodos de UNA ciudad en un rango de fechas, reutilizando el RPC del
// módulo de load balancing (rpc_get_node_load_by_period). Solo lectura.
// El RPC devuelve filas por nodo/semana; saturation_level ya se clasifica por la
// media del periodo del nodo (constante por nodo), así que agregamos por node_id:
// sumamos shipment_count en el rango y tomamos el saturation_level del nodo.
export function useCityNodeLoad(
  cityId: string | null | undefined,
  startDate: string | null | undefined,
  endDate: string | null | undefined,
) {
  const { effectiveAccountId } = useAccount()
  const [nodes, setNodes] = useState<CityNodeLoad[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const refetch = useCallback(async () => {
    if (!effectiveAccountId || !cityId || !startDate || !endDate) {
      setNodes([])
      return
    }
    try {
      setLoading(true); setError(null)
      const { data, error: e } = await supabase.rpc('rpc_get_node_load_by_period', {
        p_account_id: effectiveAccountId,
        p_start_date: startDate,
        p_end_date: endDate,
        p_reference_load: 6,
        p_deviation_percent: 20,
      })
      if (e) throw e

      const byNode = new Map<string, CityNodeLoad>()
      for (const row of (data || []) as any[]) {
        if (row.city_id !== cityId) continue
        const existing = byNode.get(row.node_id)
        if (existing) {
          existing.load_count += Number(row.shipment_count ?? 0)
        } else {
          byNode.set(row.node_id, {
            node_id: row.node_id,
            node_code: row.node_code ?? '-',
            saturation_level: (row.saturation_level ?? 'normal') as CityNodeLoad['saturation_level'],
            load_count: Number(row.shipment_count ?? 0),
          })
        }
      }
      // Menos cargado primero (los mejores destinos arriba).
      const list = Array.from(byNode.values()).sort((a, b) => a.load_count - b.load_count)
      setNodes(list)
    } catch (err: any) {
      setError(err.message)
      console.error('useCityNodeLoad', err)
    } finally {
      setLoading(false)
    }
  }, [effectiveAccountId, cityId, startDate, endDate])

  useEffect(() => { refetch() }, [refetch])

  return { nodes, loading, error, refetch }
}
