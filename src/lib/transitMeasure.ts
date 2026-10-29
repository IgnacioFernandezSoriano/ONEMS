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
