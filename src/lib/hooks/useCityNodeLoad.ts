import { useState, useEffect, useCallback } from 'react'
import { endOfMonth, addDays, format, parseISO } from 'date-fns'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type { CityLoadWeek, CityNodeLoadRow } from '@/lib/types'

// Carga semanal de los nodos de UNA ciudad, reutilizando el RPC del módulo de load
// balancing (rpc_get_node_load_by_period). Solo lectura.
//
// Ventana: desde la fecha de inicio de la baja hasta el fin de su mes + las dos
// primeras semanas del mes siguiente (fin de mes + 14 días). Así se ve la semana
// afectada y cómo queda la carga por semanas hasta bien entrado el mes siguiente.
//
// El RPC devuelve filas por nodo/semana (week_number, week_start_date, week_end_date,
// shipment_count) y un saturation_level ya clasificado a nivel de periodo del nodo.
export function useCityNodeLoad(
  cityId: string | null | undefined,
  bajaStart: string | null | undefined,
  bajaEnd: string | null | undefined,
) {
  const { effectiveAccountId } = useAccount()
  const [weeks, setWeeks] = useState<CityLoadWeek[]>([])
  const [rows, setRows] = useState<CityNodeLoadRow[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const refetch = useCallback(async () => {
    if (!effectiveAccountId || !cityId || !bajaStart || !bajaEnd) {
      setWeeks([]); setRows([])
      return
    }
    try {
      setLoading(true); setError(null)
      // Ventana: inicio de la baja .. fin de mes de la baja + 14 días (2 semanas del mes siguiente).
      const windowStart = bajaStart
      const windowEnd = format(addDays(endOfMonth(parseISO(bajaStart)), 14), 'yyyy-MM-dd')

      const { data, error: e } = await supabase.rpc('rpc_get_node_load_by_period', {
        p_account_id: effectiveAccountId,
        p_start_date: windowStart,
        p_end_date: windowEnd,
        p_reference_load: 6,
        p_deviation_percent: 20,
      })
      if (e) throw e

      // Semanas distintas (columnas), ordenadas.
      const weekMap = new Map<number, CityLoadWeek>()
      // Filas por nodo, con conteo por semana.
      const nodeMap = new Map<string, CityNodeLoadRow>()

      for (const row of (data || []) as any[]) {
        if (row.city_id !== cityId) continue
        const wn = Number(row.week_number)
        if (!weekMap.has(wn)) {
          weekMap.set(wn, {
            week_number: wn,
            week_start_date: row.week_start_date,
            week_end_date: row.week_end_date,
          })
        }
        let node = nodeMap.get(row.node_id)
        if (!node) {
          node = {
            node_id: row.node_id,
            node_code: row.node_code ?? '-',
            saturation_level: (row.saturation_level ?? 'normal') as CityNodeLoadRow['saturation_level'],
            counts: {},
            total: { sent: 0, received: 0 },
          }
          nodeMap.set(row.node_id, node)
        }
        const sent = Number(row.sent_count ?? row.shipment_count ?? 0)
        const received = Number(row.received_count ?? 0)
        const cell = node.counts[wn] ?? { sent: 0, received: 0 }
        cell.sent += sent
        cell.received += received
        node.counts[wn] = cell
        node.total.sent += sent
        node.total.received += received
      }

      const weekList = Array.from(weekMap.values()).sort((a, b) => a.week_number - b.week_number)
      const rowList = Array.from(nodeMap.values()).sort(
        (a, b) => (a.total.sent + a.total.received) - (b.total.sent + b.total.received)
      )
      setWeeks(weekList)
      setRows(rowList)
    } catch (err: any) {
      setError(err.message)
      console.error('useCityNodeLoad', err)
    } finally {
      setLoading(false)
    }
  }, [effectiveAccountId, cityId, bajaStart, bajaEnd])

  useEffect(() => { refetch() }, [refetch])

  return { weeks, rows, loading, error, refetch }
}
