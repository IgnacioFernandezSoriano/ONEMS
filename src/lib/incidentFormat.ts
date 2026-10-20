import { format, parseISO, isValid, startOfWeek } from 'date-fns'
import type { ReassignmentProposal } from '@/lib/types'

// Utilidades de presentacion del detalle de incidencias de indisponibilidad.
// Las fechas 'YYYY-MM-DD' se leen con parseISO (hora local): new Date('YYYY-MM-DD')
// las toma como UTC y al oeste de UTC muestran el dia anterior.

export const fmtDay = (d: string | null | undefined): string => {
  if (!d) return '-'
  const p = parseISO(d)
  return isValid(p) ? format(p, 'dd/MM/yyyy') : d
}

export const fmtDateTime = (d: string | null | undefined): string => {
  if (!d) return '-'
  const p = parseISO(d)
  return isValid(p) ? format(p, 'dd/MM/yyyy HH:mm') : d
}

// Muestra = nodo origen -> nodo destino.
export const sampleLabel = (l: ReassignmentProposal): string =>
  `${l.detail?.origin_node?.auto_id ?? '?'} → ${l.detail?.destination_node?.auto_id ?? '?'}`

// Semaforo de saturacion de un nodo (mismos colores que Load Balancing).
export const SATURATION_BADGE_CLASS: Record<string, string> = {
  normal: 'bg-green-100 text-green-800',
  high: 'bg-yellow-100 text-yellow-800',
  saturated: 'bg-red-100 text-red-800',
}

// Lunes (yyyy-MM-dd) de la semana de una fecha 'yyyy-MM-dd'; null si no es valida.
export function toMonday(d: string | null | undefined): string | null {
  if (!d) return null
  const p = parseISO(d)
  if (!isValid(p)) return null
  return format(startOfWeek(p, { weekStartsOn: 1 }), 'yyyy-MM-dd')
}
