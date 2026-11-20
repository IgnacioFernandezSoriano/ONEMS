import { captureOptionsFor, carriersForCapture, type Capture } from '../carrierCapture'
import type { ClQuota } from './quotaCalculator'
import type { QuotaInput } from './planView'

/**
 * Reglas del campo "Forma de captura" del Generador de Asignaciones.
 * Sin Carrier Link (producción, sin permiso o sin carriers de Carrier Link) el generador es el de siempre.
 */

/** Se ofrece Carrier Link en el generador: flag (DEV), Edit en cl_plans, cuenta elegida y un carrier carrier_link|both. */
export function carrierLinkCaptureAvailable(p: {
  flagOn: boolean
  canEditPlans: boolean
  accountId: string | null
  carriers: { capture_method?: string | null }[]
}): boolean {
  return p.flagOn && p.canEditPlans && p.accountId !== null && carriersForCapture(p.carriers, 'carrier_link').length > 0
}

/**
 * Carriers del desplegable. Flag apagado: todos (como siempre). Flag encendido sin captura Carrier Link:
 * los de panelistas (como hasta ahora). Con captura Carrier Link: todos (cada uno admite al menos una forma).
 */
export function generatorCarriers<T extends { capture_method?: string | null }>(
  carriers: T[],
  p: { flagOn: boolean; clAvailable: boolean },
): T[] {
  if (!p.flagOn) return carriers
  return p.clAvailable ? carriers : carriersForCapture(carriers, 'panelists')
}

/** Captura efectiva: la del carrier si solo admite una; con 'both', la elegida. Sin carrier, Panelistas. */
export function resolveCapture(
  carrier: { capture_method?: string | null } | null | undefined,
  chosen: Capture,
): { options: Capture[]; capture: Capture; fixed: boolean } {
  const options: Capture[] = carrier ? captureOptionsFor(carrier) : ['panelists']
  return { options, capture: options.includes(chosen) ? chosen : options[0], fixed: options.length < 2 }
}

/** Planes de Carrier Link en "Planes generados" (borradores y activos). */
export function clGeneratedPlans<T extends { status: string }>(plans: T[]): T[] {
  return plans.filter((p) => p.status === 'draft' || p.status === 'active')
}

/** Planes de Carrier Link en "Planes aplicados" (activos y cerrados). */
export function clAppliedPlans<T extends { status: string }>(plans: T[]): T[] {
  return plans.filter((p) => p.status === 'active' || p.status === 'closed')
}

/** Cuotas generadas (o importadas) como filas de la tabla de cuotas: solo previsto. */
export function toQuotaInputs(quotas: ClQuota[]): QuotaInput[] {
  return quotas.map((q) => ({
    origin_city_id: q.origin_city_id,
    destination_city_id: q.destination_city_id,
    iso_year: q.iso_year,
    iso_week: q.iso_week,
    samples_planned: q.samples,
    samples_carried_in: 0,
    samples_obtained: 0,
    status: 'pending',
  }))
}
