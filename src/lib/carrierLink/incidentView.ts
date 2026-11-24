/** Vista de las incidencias de Carrier Link (cl_incidents_list / cl_incident_get): tipos, estados, filtros y textos. */

export const INCIDENT_TYPES = ['missing_delivery', 'delivery_rejected', 'high_rejection', 'unknown_data', 'quota_unfilled'] as const
export type IncidentType = (typeof INCIDENT_TYPES)[number]

export const INCIDENT_STATUSES = ['open', 'in_progress', 'resolved'] as const
export type IncidentStatus = (typeof INCIDENT_STATUSES)[number]

/** Filtro de estado de la lista: 'unresolved' (abiertas + en curso, por defecto), un estado concreto o todas. */
export const INCIDENT_STATUS_FILTERS = ['unresolved', 'open', 'in_progress', 'resolved', 'all'] as const
export type IncidentStatusFilter = (typeof INCIDENT_STATUS_FILTERS)[number]

export const INCIDENTS_PAGE_SIZE = 25

/** Tipos que se avisan tambien al transportista (si su ficha tiene correo de avisos). */
export const CARRIER_SIDE_TYPES: readonly IncidentType[] = ['missing_delivery', 'delivery_rejected', 'high_rejection']

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)
const str = (v: unknown): string | null => (typeof v === 'string' ? v : null)
const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)

export function isIncidentType(v: string | null): v is IncidentType {
  return v !== null && (INCIDENT_TYPES as readonly string[]).includes(v)
}

export function incidentTypeKey(type: string): string {
  return isIncidentType(type) ? `cl.incidents.type.${type}` : 'cl.incidents.type.unknown'
}

export function incidentStatusKey(status: string): string {
  return (INCIDENT_STATUSES as readonly string[]).includes(status) ? `cl.incidents.status.${status}` : 'cl.incidents.status.unknown'
}

export const INCIDENT_STATUS_STYLE: Record<string, string> = {
  open: 'bg-red-100 text-red-800',
  in_progress: 'bg-amber-100 text-amber-800',
  resolved: 'bg-green-100 text-green-800',
}

/** Como se cerro: a mano (por una persona) o solo (ONEMS vio que se arreglo). null si sigue abierta. */
export function closedHowKey(i: { status: string; closed_how: string | null }): string | null {
  if (i.status !== 'resolved') return null
  return i.closed_how === 'manual' ? 'cl.incidents.closed.manual' : 'cl.incidents.closed.auto'
}

/** Solo una incidencia sin resolver se edita o se cierra a mano. */
export function isIncidentEditable(status: string): boolean {
  return status === 'open' || status === 'in_progress'
}

/** Parametro p_status de cl_incidents_list para un filtro de la pantalla ('all' = sin filtro). */
export function statusParam(f: IncidentStatusFilter): string | null {
  return f === 'all' ? null : f
}

export interface IncidentFilters {
  status: IncidentStatusFilter
  type: IncidentType | null
  feedId: string | null
}

export const DEFAULT_INCIDENT_FILTERS: IncidentFilters = { status: 'unresolved', type: null, feedId: null }

/** Filtros iniciales desde la URL (?status=&type=&feed=), p. ej. al llegar desde el Monitor. Valores raros se ignoran. */
export function filtersFromSearch(search: URLSearchParams): IncidentFilters {
  const s = search.get('status')
  const t = search.get('type')
  const f = search.get('feed')
  return {
    status: s && (INCIDENT_STATUS_FILTERS as readonly string[]).includes(s) ? (s as IncidentStatusFilter) : 'unresolved',
    type: isIncidentType(t) ? t : null,
    feedId: f && /^[0-9a-f-]{36}$/i.test(f) ? f : null,
  }
}

/** Enlace a Incidencias con un filtro (lo usa el Monitor). */
export function incidentsLink(f: Partial<IncidentFilters>): string {
  const p = new URLSearchParams()
  if (f.status && f.status !== 'unresolved') p.set('status', f.status)
  if (f.type) p.set('type', f.type)
  if (f.feedId) p.set('feed', f.feedId)
  const q = p.toString()
  return `/carrier-link/incidents${q ? `?${q}` : ''}`
}

export interface IncidentPeriodRef {
  period_start: string | null
  period_end: string | null
}

export interface IncidentListItem {
  id: string
  incident_type: string
  status: string
  feed_id: string
  feed_name: string | null
  plan_id: string | null
  periods_count: number
  last_period: IncidentPeriodRef | null
  assignee_id: string | null
  assignee_name: string | null
  opened_at: string | null
  updated_at: string | null
  closed_at: string | null
  closed_how: string | null
}

function periodRef(v: unknown): IncidentPeriodRef | null {
  if (!isObj(v)) return null
  return { period_start: str(v.period_start), period_end: str(v.period_end) }
}

export function parseIncidentList(data: unknown): { total: number; items: IncidentListItem[] } {
  const o = isObj(data) ? data : {}
  const items = Array.isArray(o.items) ? o.items.filter(isObj) : []
  return {
    total: num(o.total) ?? 0,
    items: items.map((i) => ({
      id: str(i.id) ?? '',
      incident_type: str(i.incident_type) ?? '',
      status: str(i.status) ?? '',
      feed_id: str(i.feed_id) ?? '',
      feed_name: str(i.feed_name),
      plan_id: str(i.plan_id),
      periods_count: num(i.periods_count) ?? 0,
      last_period: periodRef(i.last_period),
      assignee_id: str(i.assignee_id),
      assignee_name: str(i.assignee_name),
      opened_at: str(i.opened_at),
      updated_at: str(i.updated_at),
      closed_at: str(i.closed_at),
      closed_how: str(i.closed_how),
    })),
  }
}

export interface IncidentPeriod extends IncidentPeriodRef {
  key: string
  detected_at: string | null
  /** delivery_rejected: codigo CL_* del rechazo. */
  error: string | null
  /** high_rejection. */
  rejected: number | null
  shipments: number | null
  ratio: number | null
  /** unknown_data: cuantos valores nuevos trajo ese periodo. */
  products: number | null
  points: number | null
  /** quota_unfilled. */
  missing: number | null
}

export interface IncidentNotification {
  recipient_kind: string
  event: string
  status: string
  attempts: number
  periods_count: number
  created_at: string | null
  sent_at: string | null
}

export interface IncidentDetail extends Omit<IncidentListItem, 'periods_count' | 'last_period'> {
  carrier_notified: boolean
  plan_name: string | null
  periods: IncidentPeriod[]
  /** unknown_data: valores sin registrar (productos y puntos del transportista). */
  unknown_products: string[]
  unknown_points: { place_ref: string | null; mode_ref: string | null }[]
  notes: string | null
  closed_by_name: string | null
  notifications: IncidentNotification[]
}

const countOf = (v: unknown): number | null => (Array.isArray(v) ? v.length : num(v))

export function parseIncident(data: unknown): IncidentDetail {
  const o = isObj(data) ? data : {}
  const details = isObj(o.details) ? o.details : {}
  const periods = Array.isArray(o.periods) ? o.periods.filter(isObj) : []
  const notes = Array.isArray(o.notifications) ? o.notifications.filter(isObj) : []
  return {
    id: str(o.id) ?? '',
    incident_type: str(o.incident_type) ?? '',
    status: str(o.status) ?? '',
    feed_id: str(o.feed_id) ?? '',
    feed_name: str(o.feed_name),
    plan_id: str(o.plan_id),
    plan_name: str(o.plan_name),
    carrier_notified: o.carrier_notified === true,
    assignee_id: str(o.assignee_id),
    assignee_name: str(o.assignee_name),
    opened_at: str(o.opened_at),
    updated_at: str(o.updated_at),
    closed_at: str(o.closed_at),
    closed_how: str(o.closed_how),
    closed_by_name: str(o.closed_by_name),
    notes: str(o.notes),
    periods: periods.map((p) => ({
      key: str(p.key) ?? `${str(p.period_start) ?? ''}:${str(p.period_end) ?? ''}`,
      period_start: str(p.period_start),
      period_end: str(p.period_end),
      detected_at: str(p.detected_at),
      error: str(p.error),
      rejected: num(p.rejected),
      shipments: num(p.shipments),
      ratio: num(p.ratio),
      products: countOf(p.products),
      points: countOf(p.points),
      missing: num(p.missing),
    })),
    unknown_products: Array.isArray(details.products) ? details.products.map(str).filter((s): s is string => !!s) : [],
    unknown_points: Array.isArray(details.points)
      ? details.points.filter(isObj).map((p) => ({ place_ref: str(p.place_ref), mode_ref: str(p.mode_ref) }))
      : [],
    notifications: notes.map((n) => ({
      recipient_kind: str(n.recipient_kind) ?? '',
      event: str(n.event) ?? '',
      status: str(n.status) ?? '',
      attempts: num(n.attempts) ?? 0,
      periods_count: num(n.periods_count) ?? 0,
      created_at: str(n.created_at),
      sent_at: str(n.sent_at),
    })),
  }
}

export interface DetailLine {
  key: string
  params?: Record<string, string | number>
}

/** Datos de un periodo de la incidencia en lineas legibles (nunca JSON crudo). */
export function periodDetailLines(type: string, p: IncidentPeriod, errorKey: (code: string) => string): DetailLine[] {
  switch (type) {
    case 'delivery_rejected':
      return p.error ? [{ key: 'cl.incidents.detail.rejected_error', params: { error: errorKey(p.error) } }] : []
    case 'high_rejection':
      return [
        {
          key: 'cl.incidents.detail.high_rejection',
          params: { rejected: p.rejected ?? 0, shipments: p.shipments ?? 0, percent: Math.round((p.ratio ?? 0) * 100) },
        },
      ]
    case 'unknown_data':
      return [{ key: 'cl.incidents.detail.unknown_data', params: { products: p.products ?? 0, points: p.points ?? 0 } }]
    case 'quota_unfilled':
      return [{ key: 'cl.incidents.detail.quota_unfilled', params: { missing: p.missing ?? 0 } }]
    default:
      return []
  }
}

export interface NotificationCounts {
  kind: string
  sent: number
  pending: number
  failed: number
  skipped: number
}

/** Avisos por destinatario (cuenta / transportista): solo recuentos por estado, nunca direcciones. */
export function notificationCounts(list: IncidentNotification[]): NotificationCounts[] {
  const by = new Map<string, NotificationCounts>()
  for (const n of list) {
    const c = by.get(n.recipient_kind) ?? { kind: n.recipient_kind, sent: 0, pending: 0, failed: 0, skipped: 0 }
    if (n.status === 'sent') c.sent++
    else if (n.status === 'failed') c.failed++
    else if (n.status === 'skipped') c.skipped++
    else c.pending++
    by.set(n.recipient_kind, c)
  }
  const order = ['account_manager', 'carrier']
  return [...by.values()].sort((a, b) => order.indexOf(a.kind) - order.indexOf(b.kind))
}

export const NOTE_MAX = 4000
