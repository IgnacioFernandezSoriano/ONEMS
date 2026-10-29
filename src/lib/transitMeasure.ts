// Medida de transito segun la unidad del estandar de la ruta:
// estandar en dias -> se mide en dias laborables; en horas (o sin estandar) -> horas laborables.
import type { TimeUnit } from './accountTime'

export interface TransitShipment {
  business_transit_hours: number | null
  business_transit_days: number | null
}

export interface StandardRef {
  standard_time: number | null
  time_unit: 'hours' | 'days' | null
}

export function measureUnit(std?: StandardRef | null): TimeUnit {
  return std?.time_unit === 'days' ? 'days' : 'hours'
}

export function measureOf(s: TransitShipment, unit: TimeUnit): number | null {
  const v = unit === 'days' ? s.business_transit_days : s.business_transit_hours
  return v === null || v === undefined ? null : Number(v)
}

// La medida expresada en horas (dias * 24), para medias presentables con formatDuration
export function measureHours(s: TransitShipment, unit: TimeUnit): number | null {
  const v = measureOf(s, unit)
  if (v === null) return null
  return unit === 'days' ? v * 24 : v
}

// Horas laborables de un envio sin importar estandar (cae a dias*24 si faltan horas)
export function shipmentHours(s: TransitShipment): number | null {
  if (s.business_transit_hours !== null && s.business_transit_hours !== undefined) {
    return Number(s.business_transit_hours)
  }
  if (s.business_transit_days !== null && s.business_transit_days !== undefined) {
    return Number(s.business_transit_days) * 24
  }
  return null
}

// ---- Helpers de J+K (agregados de rutas con unidades posiblemente distintas) ----

// Unidad comun de un grupo: la de sus elementos si todos coinciden; si mezclan, horas.
export function commonUnit(units: Iterable<TimeUnit>): TimeUnit {
  let found: TimeUnit | null = null
  for (const u of units) {
    if (found === null) found = u
    else if (found !== u) return 'hours'
  }
  return found ?? 'hours'
}

// Convierte un valor entre unidades (dias <-> horas, 1 dia = 24 h)
export function convertUnit(v: number, from: TimeUnit, to: TimeUnit): number {
  if (from === to) return v
  return from === 'days' ? v * 24 : v / 24
}

// Formato de J+K segun la unidad de la fila y el selector global.
// Filas en dias -> J+n (la desviacion conserva signo: +1); filas en horas -> "n.n h" o "n.nn d".
export function formatJK(
  value: number,
  rowUnit: TimeUnit,
  displayUnit: TimeUnit,
  signed = false,
): string {
  const sign = signed && value > 0 ? '+' : ''
  if (rowUnit === 'days') {
    // Rutas: valores enteros -> J+n. Medias de varias rutas: un decimal si no son enteras.
    const txt = Math.abs(value - Math.round(value)) < 0.05 ? String(Math.round(value)) : value.toFixed(1)
    return signed ? `${sign}${txt}` : `J+${txt}`
  }
  return displayUnit === 'hours'
    ? `${sign}${value.toFixed(1)} h`
    : `${sign}${(value / 24).toFixed(2)} d`
}

interface JKItem {
  unit: TimeUnit
  jkStandard: number
  jkActual: number
  totalSamples: number
}

// Acumulador ponderado por muestras: guarda en horas y recuerda las unidades vistas
export function addJK(
  acc: { totalWeightedJKStandard: number; totalWeightedJKActual: number; units?: Set<TimeUnit> },
  item: JKItem,
): void {
  acc.totalWeightedJKStandard += convertUnit(item.jkStandard, item.unit, 'hours') * item.totalSamples
  acc.totalWeightedJKActual += convertUnit(item.jkActual, item.unit, 'hours') * item.totalSamples
  if (!acc.units) acc.units = new Set()
  acc.units.add(item.unit)
}

// Medias ponderadas en la unidad comun del grupo (horas si mezcla)
export function finishJK(acc: {
  totalSamples: number
  totalWeightedJKStandard: number
  totalWeightedJKActual: number
  units?: Set<TimeUnit>
}): { unit: TimeUnit; jkStandard: number; jkActual: number } {
  const unit = commonUnit(acc.units || [])
  const n = acc.totalSamples
  return {
    unit,
    jkStandard: n > 0 ? convertUnit(acc.totalWeightedJKStandard / n, 'hours', unit) : 0,
    jkActual: n > 0 ? convertUnit(acc.totalWeightedJKActual / n, 'hours', unit) : 0,
  }
}

// Media ponderada de J+K de una lista de elementos (p. ej. rutas)
export function aggregateJK(items: JKItem[]): { unit: TimeUnit; jkStandard: number; jkActual: number } {
  const acc = {
    totalSamples: 0,
    totalWeightedJKStandard: 0,
    totalWeightedJKActual: 0,
    units: new Set<TimeUnit>(),
  }
  items.forEach(i => {
    acc.totalSamples += i.totalSamples
    addJK(acc, i)
  })
  return finishJK(acc)
}
