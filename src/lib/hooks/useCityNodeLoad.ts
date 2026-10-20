import { useState, useEffect, useCallback, useRef } from 'react'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type { CityLoadWeek, CityNodeLoadRow, NodeUnavailability } from '@/lib/types'

// Carga semanal de los nodos de UNA ciudad, reutilizando el RPC del modulo de load
// balancing (rpc_get_node_load_by_period), y las bajas activas de los panelistas de
// esos nodos que solapan la ventana. Solo lectura.
//
// Ventana: windowStart (lunes) .. windowEnd (domingo), la decide el panel (flechas).
// referenceLoad / deviationPercent son los mismos filtros que Load Balancing y deciden
// el semaforo de saturacion.
//
// Todo se indexa por week_start_date: el numero ISO de semana vuelve a 1 al cambiar de
// anio (enero saldria antes que diciembre).
//
// accountId: cuenta de la incidencia. Si no se pasa, se usa la cuenta efectiva del
// usuario (un superadmin sin cuenta seleccionada no veria nada sin este parametro).
export function useCityNodeLoad(
  cityId: string | null | undefined,
  windowStart: string | null | undefined,
  windowEnd: string | null | undefined,
  referenceLoad: number,
  deviationPercent: number,
  accountId?: string | null,
) {
  const { effectiveAccountId } = useAccount()
  const account = accountId ?? effectiveAccountId
  const [weeks, setWeeks] = useState<CityLoadWeek[]>([])
  const [rows, setRows] = useState<CityNodeLoadRow[]>([])
  const [unavailability, setUnavailability] = useState<NodeUnavailability[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  // Solo se aplica la respuesta de la ultima peticion (los filtros cambian rapido).
  const requestSeq = useRef(0)

  const refetch = useCallback(async () => {
    const seq = ++requestSeq.current
    if (!account || !cityId || !windowStart || !windowEnd || windowEnd < windowStart
        || !Number.isFinite(referenceLoad) || referenceLoad <= 0
        || !Number.isFinite(deviationPercent) || deviationPercent < 0) {
      setWeeks([]); setRows([]); setUnavailability([]); setLoading(false)
      return
    }
    try {
      setLoading(true); setError(null)
      const { data, error: e } = await supabase.rpc('rpc_get_node_load_by_period', {
        p_account_id: account,
        p_start_date: windowStart,
        p_end_date: windowEnd,
        p_reference_load: referenceLoad,
        p_deviation_percent: deviationPercent,
      })
      if (e) throw e
      if (seq !== requestSeq.current) return

      // Semanas distintas (columnas) por lunes.
      const weekMap = new Map<string, CityLoadWeek>()
      // Filas por nodo, con conteo por semana.
      const nodeMap = new Map<string, CityNodeLoadRow>()

      for (const row of (data || []) as any[]) {
        if (row.city_id !== cityId) continue
        const ws: string = row.week_start_date
        if (!weekMap.has(ws)) {
          weekMap.set(ws, {
            week_number: Number(row.week_number),
            week_start_date: ws,
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
        const cell = node.counts[ws] ?? { sent: 0, received: 0 }
        cell.sent += sent
        cell.received += received
        node.counts[ws] = cell
        node.total.sent += sent
        node.total.received += received
      }

      const weekList = Array.from(weekMap.values()).sort((a, b) => a.week_start_date.localeCompare(b.week_start_date))
      const rowList = Array.from(nodeMap.values()).sort(
        (a, b) => (a.total.sent + a.total.received) - (b.total.sent + b.total.received)
      )

      // Bajas activas de los panelistas (activos) de esos nodos que solapan la ventana.
      const nodeIds = rowList.map(r => r.node_id)
      let unavs: NodeUnavailability[] = []
      if (nodeIds.length > 0) {
        const { data: pans, error: pe } = await supabase
          .from('panelists')
          .select('id, node_id')
          .eq('account_id', account)
          .eq('status', 'active')
          .in('node_id', nodeIds)
        if (pe) throw pe
        if (seq !== requestSeq.current) return
        const nodeByPanelist = new Map<string, string>()
        for (const p of (pans || []) as { id: string; node_id: string | null }[]) {
          if (p.node_id) nodeByPanelist.set(p.id, p.node_id)
        }
        if (nodeByPanelist.size > 0) {
          const { data: us, error: ue } = await supabase
            .from('panelist_unavailability')
            .select('id, panelist_id, start_date, end_date')
            .eq('account_id', account)
            .eq('status', 'active')
            .in('panelist_id', Array.from(nodeByPanelist.keys()))
            .lte('start_date', windowEnd)
            .gte('end_date', windowStart)
          if (ue) throw ue
          if (seq !== requestSeq.current) return
          unavs = ((us || []) as { id: string; panelist_id: string; start_date: string; end_date: string }[])
            .map(u => ({ ...u, node_id: nodeByPanelist.get(u.panelist_id) as string }))
        }
      }

      setWeeks(weekList)
      setRows(rowList)
      setUnavailability(unavs)
    } catch (err: any) {
      if (seq !== requestSeq.current) return
      setError(err?.message ?? String(err))
      console.error('useCityNodeLoad', err)
    } finally {
      if (seq === requestSeq.current) setLoading(false)
    }
  }, [account, cityId, windowStart, windowEnd, referenceLoad, deviationPercent])

  useEffect(() => { refetch() }, [refetch])

  return { weeks, rows, unavailability, loading, error, refetch }
}
