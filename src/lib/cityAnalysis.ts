import type { NodeDayLoad } from '../hooks/useNodeLoadBalancing'
import type { DatePolicy } from './workingDays'

export type Severity = 'critical' | 'warning' | 'info' | 'ok'

export interface Finding {
  severity: Severity
  /** clave de traduccion: lb2.rec.<code> */
  code: string
  params: Record<string, string | number>
}

export interface WeekCell {
  node_code: string
  week_number: number
  shipment_count: number
}

export interface CityAnalysisInput {
  weekCells: WeekCell[]
  highThreshold: number
  saturatedThreshold: number
  /** filas nodo x dia (vacio si la RPC diaria no esta disponible) */
  dayRows: NodeDayLoad[]
  datePolicy: DatePolicy
  pobox: boolean
  /** hoy, yyyy-MM-dd */
  today: string
  /** filas del registro de muestras por compensar de esta ciudad que esperan (0 por defecto) */
  deferredPending?: number
  /** muestras que la ultima vista previa de esta ciudad apartaria del plan (0 por defecto) */
  willRemove?: number
}

const SEVERITY_ORDER: Record<Severity, number> = { critical: 0, warning: 1, info: 2, ok: 3 }

function list(items: string[], max = 5): string {
  const shown = items.slice(0, max).join(', ')
  return items.length > max ? `${shown} +${items.length - max}` : shown
}

/**
 * Analisis de una ciudad segun las reglas del balanceador v2: carga semanal por nodo, envios en dias en que el
 * panelista no puede (ausencia / no laborable), nodos sin panelista, envios atrasados, picos diarios y, con
 * POBOX, dias laborables sin ningun envio en la ciudad. Devuelve hallazgos ordenados por gravedad.
 */
export function analyzeCity(input: CityAnalysisInput): Finding[] {
  const { weekCells, highThreshold, saturatedThreshold, dayRows, datePolicy, pobox, today } = input
  const findings: Finding[] = []

  // 1. Carga semanal por nodo (umbrales de referencia + tolerancia)
  if (weekCells.length > 0) {
    const total = weekCells.length
    const saturated = weekCells.filter((c) => c.shipment_count >= saturatedThreshold).length
    const high = weekCells.filter((c) => c.shipment_count >= highThreshold && c.shipment_count < saturatedThreshold).length
    if (saturated > 0) {
      findings.push({ severity: 'critical', code: 'load_critical', params: {
        count: saturated, pct: Math.round((saturated / total) * 100), threshold: saturatedThreshold.toFixed(1) } })
    }
    if (high > 0) {
      findings.push({ severity: 'warning', code: 'load_warning', params: {
        count: high, pct: Math.round((high / total) * 100), threshold: highThreshold.toFixed(1) } })
    }
    if (saturated === 0 && high === 0) {
      findings.push({ severity: 'ok', code: 'load_ok', params: { total, threshold: highThreshold.toFixed(1) } })
    }
  }

  if (dayRows.length > 0) {
    // 2. Envios pendientes (de hoy en adelante) en dias en que el panelista no puede: ausencia o no laborable
    const conflictNodes = new Set<string>()
    let conflictShipments = 0
    // 3. Nodos sin panelista con envios pendientes
    const noPanelistNodes = new Set<string>()
    let noPanelistShipments = 0
    // 4. Atrasados: pendientes con fecha anterior a hoy
    let overdue = 0
    // 5. Picos diarios (solo politica diaria): envios pendientes por nodo y dia
    const availableNodeDays: NodeDayLoad[] = []
    let pendingFuture = 0

    for (const r of dayRows) {
      if (r.pending_count <= 0 && !(r.is_working_day && !r.is_unavailable && r.day >= today)) continue
      if (r.day < today) {
        if (r.pending_count > 0) overdue += r.pending_count
        continue
      }
      if (r.pending_count > 0 && (r.is_unavailable || !r.is_working_day)) {
        conflictShipments += r.pending_count
        conflictNodes.add(r.node_code)
      }
      if (r.pending_count > 0 && !r.panelist_name) {
        noPanelistShipments += r.pending_count
        noPanelistNodes.add(r.node_code)
      }
      if (r.is_working_day && !r.is_unavailable && r.panelist_name) {
        availableNodeDays.push(r)
        pendingFuture += r.pending_count
      }
    }

    if (conflictShipments > 0) {
      findings.push({ severity: 'critical', code: 'conflicts', params: {
        count: conflictShipments, nodes: list([...conflictNodes]) } })
    }
    if (noPanelistShipments > 0) {
      findings.push({ severity: 'critical', code: 'no_panelist', params: {
        count: noPanelistShipments, nodes: list([...noPanelistNodes]) } })
    }
    if (overdue > 0) {
      findings.push({ severity: 'warning', code: 'overdue', params: { count: overdue } })
    }

    if (datePolicy === 'daily' && availableNodeDays.length > 0) {
      const avg = pendingFuture / availableNodeDays.length
      const threshold = Math.max(2, Math.ceil(avg) + 1)
      const peaks = availableNodeDays.filter((r) => r.pending_count > threshold)
      if (peaks.length > 0) {
        const worst = peaks.reduce((a, b) => (b.pending_count > a.pending_count ? b : a))
        findings.push({ severity: 'warning', code: 'daily_peaks', params: {
          count: peaks.length, threshold, max: worst.pending_count, node: worst.node_code, date: worst.day } })
      }
    }

    // 6. POBOX: dia laborable (de hoy en adelante) sin ningun envio en la ciudad
    if (pobox) {
      const byDay = new Map<string, { total: number; working: boolean }>()
      for (const r of dayRows) {
        if (r.day < today) continue
        const cur = byDay.get(r.day) ?? { total: 0, working: false }
        cur.total += r.shipment_count
        cur.working = cur.working || r.is_working_day
        byDay.set(r.day, cur)
      }
      const gaps = [...byDay.entries()].filter(([, v]) => v.working && v.total === 0).map(([d]) => d).sort()
      if (gaps.length > 0) {
        findings.push({ severity: 'critical', code: 'pobox_gap', params: { count: gaps.length, dates: list(gaps) } })
      } else if (byDay.size > 0) {
        findings.push({ severity: 'ok', code: 'pobox_ok', params: {} })
      }
    }
  }

  // 7. Muestras por compensar (registro): esperando / que se apartarian al aplicar la vista previa
  if ((input.deferredPending ?? 0) > 0) {
    findings.push({ severity: 'info', code: 'deferred_waiting', params: { count: input.deferredPending! } })
  }
  if ((input.willRemove ?? 0) > 0) {
    findings.push({ severity: 'critical', code: 'deferred_will_remove', params: { count: input.willRemove! } })
  }

  if (findings.length === 0) findings.push({ severity: 'info', code: 'no_data', params: {} })

  const needsAction = findings.some((f) => f.severity === 'critical' || f.severity === 'warning')
  if (needsAction) findings.push({ severity: 'info', code: 'action_balance', params: {} })

  return findings.sort((a, b) => SEVERITY_ORDER[a.severity] - SEVERITY_ORDER[b.severity])
}
