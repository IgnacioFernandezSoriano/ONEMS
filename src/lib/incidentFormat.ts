import { format, parseISO, isValid, startOfWeek, addDays, endOfMonth, differenceInCalendarDays } from 'date-fns'
import type { ReassignmentProposal, SamplePlanInfo, NodeUnavailability } from '@/lib/types'

// Utilidades de presentacion del detalle de incidencias de indisponibilidad.
// Las fechas 'YYYY-MM-DD' se leen con parseISO (hora local): new Date('YYYY-MM-DD')
// las toma como UTC y al oeste de UTC muestran el dia anterior.

export const fmtDay = (d: string | null | undefined): string => {
  if (!d) return '-'
  const p = parseISO(d)
  return isValid(p) ? format(p, 'dd/MM/yyyy') : d
}

// Dia y mes (dd/MM) para cabeceras compactas.
export const fmtShort = (d: string | null | undefined): string => {
  if (!d) return '-'
  const p = parseISO(d)
  return isValid(p) ? format(p, 'dd/MM') : d
}

// Rango de una semana: "26/10 – 01/11". Si no se da el fin se toma lunes + 6 dias.
export const fmtWeekRange = (start: string, end?: string | null): string => {
  const s = parseISO(start)
  const e = end ? parseISO(end) : (isValid(s) ? addDays(s, 6) : s)
  if (!isValid(s) || !isValid(e)) return start
  return `${format(s, 'dd/MM')} – ${format(e, 'dd/MM')}`
}

export const fmtDateTime = (d: string | null | undefined): string => {
  if (!d) return '-'
  const p = parseISO(d)
  return isValid(p) ? format(p, 'dd/MM/yyyy HH:mm') : d
}

// Muestra = nodo origen -> nodo destino.
export const sampleLabel = (l: ReassignmentProposal): string =>
  nodesLabel(l.detail?.origin_node?.auto_id, l.detail?.destination_node?.auto_id)

export const nodesLabel = (origin: string | null | undefined, destination: string | null | undefined): string =>
  `${origin ?? '?'} → ${destination ?? '?'}`

// Carrier y producto del plan, compacto: "CARRIER · PRODUCTO" (codigo del producto o, si no hay,
// su descripcion). planTitle da el texto completo para el tooltip.
export const planLabel = (plan: SamplePlanInfo | null | undefined): string => {
  const carrier = plan?.carrier?.name?.trim() || '-'
  const product = plan?.product?.code?.trim() || plan?.product?.description?.trim() || '-'
  return `${carrier} · ${product}`
}

export const planTitle = (plan: SamplePlanInfo | null | undefined): string => {
  const carrier = plan?.carrier?.name?.trim() || '-'
  const code = plan?.product?.code?.trim()
  const desc = plan?.product?.description?.trim()
  const product = code && desc ? `${code} — ${desc}` : code || desc || '-'
  return `${carrier} · ${product}`
}

// Cobertura de las bajas de UN nodo en la semana que empieza el lunes weekStart:
// workdaysCovered = lunes..viernes cubiertos (0..5); ranges = tramos de la semana (lunes..domingo)
// cubiertos, "dd/MM – dd/MM", para el tooltip. Comparacion de cadenas 'yyyy-MM-dd'.
export interface WeekCoverage {
  workdaysCovered: number
  ranges: string[]
}

export function weekCoverage(unavs: NodeUnavailability[], weekStart: string): WeekCoverage {
  const s = parseISO(weekStart)
  if (!isValid(s) || unavs.length === 0) return { workdaysCovered: 0, ranges: [] }
  const sunday = format(addDays(s, 6), 'yyyy-MM-dd')
  let workdaysCovered = 0
  for (let i = 0; i < 5; i++) {
    const day = format(addDays(s, i), 'yyyy-MM-dd')
    if (unavs.some(u => u.start_date <= day && u.end_date >= day)) workdaysCovered++
  }
  const ranges = unavs
    .filter(u => u.start_date <= sunday && u.end_date >= weekStart)
    .map(u => {
      const from = u.start_date > weekStart ? u.start_date : weekStart
      const to = u.end_date < sunday ? u.end_date : sunday
      return from === to ? fmtShort(from) : `${fmtShort(from)} – ${fmtShort(to)}`
    })
  return { workdaysCovered, ranges }
}

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

// Lunes (yyyy-MM-dd) de la semana de hoy (hora local).
export const currentMonday = (): string =>
  format(startOfWeek(new Date(), { weekStartsOn: 1 }), 'yyyy-MM-dd')

// Suma semanas a un lunes 'yyyy-MM-dd'.
export function addWeeksTo(monday: string, n: number): string {
  const p = parseISO(monday)
  return isValid(p) ? format(addDays(p, n * 7), 'yyyy-MM-dd') : monday
}

// Numero de semanas de la ventana del balance: desde el lunes `fromMonday` hasta el fin del mes
// de la baja + 14 dias, con un minimo de 8.
export function defaultWindowWeeks(fromMonday: string, bajaStart: string | null | undefined): number {
  const MIN = 8
  const from = parseISO(fromMonday)
  const b = bajaStart ? parseISO(bajaStart) : null
  if (!isValid(from) || !b || !isValid(b)) return MIN
  const target = addDays(endOfMonth(b), 14)
  const days = differenceInCalendarDays(target, from) + 1
  return Math.max(MIN, Math.ceil(days / 7))
}
