import { useState, useEffect, useCallback, useRef } from 'react'
import { endOfMonth, addDays, format, parseISO, isValid } from 'date-fns'
import { supabase } from '@/lib/supabase'
import { useAccount } from '@/contexts/AccountContext'
import type { CityLoadWeek, CityNodeLoadRow } from '@/lib/types'

// Fin de rango por defecto del panel de carga: fin del mes de la baja + 14 dias
// (las dos primeras semanas del mes siguiente). parseISO evita el desfase de un dia
// que da new Date('YYYY-MM-DD') al oeste de UTC.
export function defaultLoadRangeEnd(bajaStart: string | null | undefined): string {
  if (!bajaStart) return ''
  const d = parseISO(bajaStart)
  if (!isValid(d)) return ''
  return format(addDays(endOfMonth(d), 14), 'yyyy-MM-dd')
}

// Carga semanal de los nodos de UNA ciudad, reutilizando el RPC del modulo de load
// balancing (rpc_get_node_load_by_period). Solo lectura.
//
// Ventana: desde el inicio de la baja hasta rangeEnd (lo elige el manager; por defecto
// defaultLoadRangeEnd). referenceLoad / deviationPercent son los mismos filtros que
// Load Balancing y deciden el semaforo de saturacion.
//
// accountId: cuenta de la incidencia. Si no se pasa, se usa la cuenta efectiva del
// usuario (un superadmin sin cuenta seleccionada no veria nada sin este parametro).
export function useCityNodeLoad(
  cityId: string | null | undefined,
  bajaStart: string | null | undefined,
  rangeEnd: string | null | undefined,
  referenceLoad: number,
  deviationPercent: number,
  accountId?: string | null,
) {
  const { effectiveAccountId } = useAccount()
  const account = accountId ?? effectiveAccountId
  const [weeks, setWeeks] = useState<CityLoadWeek[]>([])
  const [rows, setRows] = useState<CityNodeLoadRow[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  // Solo se aplica la respuesta de la ultima peticion (los filtros cambian rapido).
  const requestSeq = useRef(0)

  const refetch = useCallback(async () => {
    const seq = ++requestSeq.current
    if (!account || !cityId || !bajaStart || !rangeEnd || rangeEnd < bajaStart
        || !Number.isFinite(referenceLoad) || referenceLoad <= 0
        || !Number.isFinite(deviationPercent) || deviationPercent < 0) {
      setWeeks([]); setRows([]); setLoading(false)
      return
    }
    try {
      setLoading(true); setError(null)
      const { data, error: e } = await supabase.rpc('rpc_get_node_load_by_period', {
        p_account_id: account,
        p_start_date: bajaStart,
        p_end_date: rangeEnd,
        p_reference_load: referenceLoad,
        p_deviation_percent: deviationPercent,
      })
      if (e) throw e
      if (seq !== requestSeq.current) return

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

      // Orden por fecha de inicio (el numero ISO de semana vuelve a 1 al cambiar de anio).
      const weekList = Array.from(weekMap.values()).sort((a, b) => a.week_start_date.localeCompare(b.week_start_date))
      const rowList = Array.from(nodeMap.values()).sort(
        (a, b) => (a.total.sent + a.total.received) - (b.total.sent + b.total.received)
      )
      setWeeks(weekList)
      setRows(rowList)
    } catch (err: any) {
      if (seq !== requestSeq.current) return
      setError(err.message)
      console.error('useCityNodeLoad', err)
    } finally {
      if (seq === requestSeq.current) setLoading(false)
    }
  }, [account, cityId, bajaStart, rangeEnd, referenceLoad, deviationPercent])

  useEffect(() => { refetch() }, [refetch])

  return { weeks, rows, loading, error, refetch }
}
