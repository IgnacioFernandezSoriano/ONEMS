/** Vista de las entregas de Carrier Link v4 (cl_deliveries): estados, fases, motivos, periodos y calendario. */
import { clErrorKey } from './clErrors'

export const DELIVERY_STATUSES = ['pending_upload', 'received', 'processing', 'processed', 'failed', 'rejected'] as const
export type DeliveryStatus = (typeof DELIVERY_STATUSES)[number]

/** Fases del proceso en segundo plano (progress->>'phase'), en orden; al terminar: done, failed, rejected o abort. */
export const DELIVERY_PHASES = ['load', 'resolve', 'items', 'strata', 'draw', 'transfer', 'finish', 'cleanup'] as const
export type DeliveryPhase = (typeof DELIVERY_PHASES)[number]

/** Estados que ya no cambian solos: la pantalla deja de consultar. failed se reintenta en segundo plano. */
export function isDeliveryFinal(status: string | null): boolean {
  return status === 'processed' || status === 'rejected'
}

/** Estados en los que ONEMS sigue trabajando (la pantalla vuelve a consultar). */
export function isDeliveryInFlight(status: string | null): boolean {
  return status === 'received' || status === 'processing' || status === 'failed'
}

export function deliveryStatusKey(status: string): string {
  return (DELIVERY_STATUSES as readonly string[]).includes(status) ? `cl.delivery.status.${status}` : 'cl.delivery.status.unknown'
}

export const DELIVERY_STATUS_STYLE: Record<string, string> = {
  pending_upload: 'bg-gray-100 text-gray-700',
  received: 'bg-blue-100 text-blue-800',
  processing: 'bg-blue-100 text-blue-800',
  processed: 'bg-green-100 text-green-800',
  failed: 'bg-amber-100 text-amber-800',
  rejected: 'bg-red-100 text-red-800',
}

/** Clave de la fase mostrada; null si no hay nada que mostrar (sin empezar o ya terminada). */
export function deliveryPhaseKey(status: string, phase: string | null): string | null {
  if (status !== 'processing' || !phase) return null
  return (DELIVERY_PHASES as readonly string[]).includes(phase) ? `cl.delivery.phase.${phase}` : null
}

/**
 * Avance aproximado (0..100) de una entrega en proceso: la carga del fichero pesa la mitad (por bytes leidos) y cada
 * fase posterior una parte igual del resto. processed = 100. Fuera de processing: null (no hay barra).
 */
export function deliveryProgressPercent(d: {
  status: string
  phase: string | null
  bytes_loaded: number | null
  file_bytes: number | null
}): number | null {
  if (d.status === 'processed') return 100
  if (d.status !== 'processing') return null
  const idx = (DELIVERY_PHASES as readonly string[]).indexOf(d.phase ?? '')
  if (idx < 0) return 0
  if (idx === 0) {
    if (!d.file_bytes || d.file_bytes <= 0 || d.bytes_loaded === null) return 0
    return Math.max(0, Math.min(50, Math.floor((d.bytes_loaded / d.file_bytes) * 50)))
  }
  const rest = DELIVERY_PHASES.length - 1
  return Math.min(99, 50 + Math.floor((idx / rest) * 50))
}

export interface ReasonCount {
  reason: string
  count: number
}

const num = (v: unknown): number | null => (typeof v === 'number' && Number.isFinite(v) ? v : null)
const isObj = (v: unknown): v is Record<string, unknown> => typeof v === 'object' && v !== null && !Array.isArray(v)

function counts(v: unknown): ReasonCount[] {
  if (!isObj(v)) return []
  return Object.entries(v)
    .map(([reason, n]) => ({ reason, count: num(n) ?? 0 }))
    .filter((r) => r.count > 0)
    .sort((a, b) => b.count - a.count || a.reason.localeCompare(b.reason))
}

/** rejected_reasons = {"rows": {motivo: n}, "shipments": {motivo: n}}, ordenados de mas a menos. */
export function rejectedReasons(v: unknown): { rows: ReasonCount[]; shipments: ReasonCount[] } {
  const o = isObj(v) ? v : {}
  return { rows: counts(o.rows), shipments: counts(o.shipments) }
}

/** Clave i18n de un motivo de rechazo (cl.reason.<motivo>; la pantalla muestra el motivo tal cual si no la hay). */
export function reasonKey(reason: string): string {
  return `cl.reason.${reason}`
}

/** Clave i18n del error guardado en la entrega (CL_*, a veces seguido del SQLSTATE: 'CL_PROCESSING_ERROR 23505'). */
export function deliveryErrorKey(error: string | null): string | null {
  if (!error) return null
  return clErrorKey({ message: error })
}

/** Codigos que el proceso escribe en cl_deliveries.error sin lanzarlos (no los ve el test de migraciones). */
export const DELIVERY_ERROR_CODES = [
  'CL_BAD_CSV_HEADER',
  'CL_BAD_ENCODING',
  'CL_BAD_SHA_STATE',
  'CL_COMPRESSION_UNSUPPORTED',
  'CL_FILE_MISSING',
  'CL_FILE_SIZE_UNKNOWN',
  'CL_FILE_TOO_LARGE',
  'CL_MAPPING_INCOMPLETE',
  'CL_PERIOD_ALREADY_DELIVERED',
  'CL_PROCESSING_ERROR',
  'CL_RECORD_TOO_LONG',
  'CL_RETRIES_EXHAUSTED',
  'CL_SHA256_MISMATCH',
  'CL_STAGING_LOST',
  'CL_STOPPED',
  'CL_STORAGE_ERROR',
  'CL_STORAGE_SHORT_READ',
  'CL_SUPERSEDED',
  'CL_TOO_MANY_ROWS',
  'CL_UPLOAD_EXPIRED',
  'CL_WORKER_ERROR',
  'CL_WORKER_LOST',
] as const

// ---------------------------------------------------------------- periodos y calendario

/** Fecha ISO (YYYY-MM-DD) -> texto corto en el idioma de la pantalla, sin moverla de dia (UTC). */
export function fmtDay(iso: string | null, locale: string): string {
  if (!iso || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return '-'
  const [y, m, d] = iso.split('-').map(Number)
  const dt = new Date(Date.UTC(y, m - 1, d))
  try {
    return new Intl.DateTimeFormat(locale, { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'UTC' }).format(dt)
  } catch {
    return iso
  }
}

/** Periodo de una entrega: un dia ('23 nov 2026') o un rango ('23 nov 2026 – 29 nov 2026'). */
export function periodLabel(start: string | null, end: string | null, locale: string): string {
  if (!start || !end) return '-'
  return start === end ? fmtDay(start, locale) : `${fmtDay(start, locale)} – ${fmtDay(end, locale)}`
}

export type DeliveryFrequency = 'daily' | 'weekly' | 'several_per_week'

/** Igual que cl_connector_config: 7 dias = diaria, 1 = semanal, otro = varias por semana. */
export function deliveryFrequency(days: number[]): DeliveryFrequency {
  const n = new Set(days).size
  if (n === 7) return 'daily'
  if (n === 1) return 'weekly'
  return 'several_per_week'
}

const DAY_MS = 86_400_000
const toUtc = (iso: string) => {
  const [y, m, d] = iso.split('-').map(Number)
  return Date.UTC(y, m - 1, d)
}

/**
 * Comprobacion local del periodo de una subida manual (la base decide el resto: cerrado, calendario, ya entregado):
 * clave i18n del error o null.
 */
export function manualPeriodError(start: string, end: string): string | null {
  const re = /^\d{4}-\d{2}-\d{2}$/
  if (!re.test(start) || !re.test(end)) return 'cl.deliveries.upload.period_required'
  const days = (toUtc(end) - toUtc(start)) / DAY_MS
  if (days < 0) return 'cl.deliveries.upload.period_order'
  if (days >= 7) return 'cl.deliveries.upload.period_too_long'
  return null
}

// ---------------------------------------------------------------- fichero de la subida manual

/** Tope de la subida manual: el del bucket cl-deliveries (500 MB); el conector puede tener uno menor (lo dice la base). */
export const MANUAL_DELIVERY_MAX_BYTES = 524_288_000

export type DeliveryFormat = 'jsonl' | 'csv'

/** Formato por la extension del fichero; un fichero comprimido no se admite (v4 no lleva compresion). */
export function formatFromFileName(name: string): { format: DeliveryFormat } | { errorKey: string } {
  const n = name.trim().toLowerCase()
  if (/\.(gz|gzip|zip|bz2|br|xz|7z|zst)$/.test(n)) return { errorKey: 'cl.error.cl_compression_unsupported' }
  if (/\.(jsonl|ndjson)$/.test(n)) return { format: 'jsonl' }
  if (n.endsWith('.csv')) return { format: 'csv' }
  return { errorKey: 'cl.deliveries.upload.bad_extension' }
}

export const CONTENT_TYPE_BY_FORMAT: Record<DeliveryFormat, string> = { jsonl: 'application/x-ndjson', csv: 'text/csv' }

/** Comprobaciones del fichero antes de calcular la huella: clave i18n del error o el formato. */
export function manualFileCheck(file: { name: string; size: number }, maxBytes: number | null): { format: DeliveryFormat } | { errorKey: string } {
  const f = formatFromFileName(file.name)
  if ('errorKey' in f) return f
  if (file.size <= 0) return { errorKey: 'cl.deliveries.upload.empty_file' }
  const cap = Math.min(MANUAL_DELIVERY_MAX_BYTES, maxBytes && maxBytes > 0 ? maxBytes : MANUAL_DELIVERY_MAX_BYTES)
  if (file.size > cap) return { errorKey: 'cl.error.cl_file_too_large' }
  return f
}

/** Tamano legible (KB, MB) con el separador del idioma. */
export function fmtBytes(n: number | null, locale: string): string {
  if (n === null || !Number.isFinite(n)) return '-'
  const units = ['B', 'KB', 'MB', 'GB']
  let v = n
  let u = 0
  while (v >= 1024 && u < units.length - 1) {
    v /= 1024
    u++
  }
  return `${new Intl.NumberFormat(locale, { maximumFractionDigits: u === 0 ? 0 : 1 }).format(v)} ${units[u]}`
}

// ---------------------------------------------------------------- margen de "no recibido" (config.missing_grace_hours)

export const GRACE_HOURS_DEFAULT = 6
export const GRACE_HOURS_MAX = 168

/** Margen vigente, como lo lee la base (cl_feed_missing_grace_hours): numero 0..168 o, si no, 6. */
export function graceHoursOf(config: unknown): number {
  const v = isObj(config) ? config.missing_grace_hours : undefined
  return typeof v === 'number' && Number.isFinite(v) && v >= 0 && v <= GRACE_HOURS_MAX ? Math.trunc(v) : GRACE_HOURS_DEFAULT
}

/** Valor del formulario -> horas validas, o null si no es un entero entre 0 y 168. */
export function parseGraceHours(text: string): number | null {
  if (!/^\s*\d{1,3}\s*$/.test(text)) return null
  const n = Number(text)
  return n >= 0 && n <= GRACE_HOURS_MAX ? n : null
}

/** El config del conector con el margen cambiado; las demas claves (topes del fichero...) se conservan. */
export function withGraceHours(config: unknown, hours: number): Record<string, unknown> {
  return { ...(isObj(config) ? config : {}), missing_grace_hours: hours }
}

// ---------------------------------------------------------------- subida manual (mismo camino que la API)

export interface DeliverySummary {
  delivery_id: string
  status: string
  file_path: string | null
  existing: boolean
  error: string | null
}

/** Lee lo que devuelven cl_manual_delivery_open / _complete (cl_delivery_summary + existing). */
export function parseDeliverySummary(data: unknown): DeliverySummary {
  const o = isObj(data) ? data : {}
  return {
    delivery_id: typeof o.delivery_id === 'string' ? o.delivery_id : '',
    status: typeof o.status === 'string' ? o.status : '',
    file_path: typeof o.file_path === 'string' ? o.file_path : null,
    existing: o.existing === true,
    error: typeof o.error === 'string' ? o.error : null,
  }
}

export interface ManualDeliveryApi {
  open: (args: { periodStart: string; periodEnd: string; sha256: string; format: DeliveryFormat }) => Promise<unknown>
  upload: (path: string, format: DeliveryFormat) => Promise<{ error: { message?: string; statusCode?: string | number } | null }>
  complete: (deliveryId: string) => Promise<unknown>
}

export type ManualDeliveryStep = 'opening' | 'uploading' | 'completing'

/**
 * Abre la entrega (huella ya calculada), sube el fichero a la ruta que decide la base y la marca recibida. Igual que
 * el conector: si la entrega ya existia y no espera fichero (mismo fichero y periodo), se devuelve tal cual; si el
 * fichero ya estaba subido (reintento), se completa directamente. Un error se lanza.
 */
export async function runManualDelivery(
  api: ManualDeliveryApi,
  args: { periodStart: string; periodEnd: string; sha256: string; format: DeliveryFormat },
  onStep?: (s: ManualDeliveryStep) => void,
): Promise<DeliverySummary> {
  onStep?.('opening')
  const opened = parseDeliverySummary(await api.open(args))
  if (!opened.delivery_id) throw { message: 'CL_DELIVERY_NOT_FOUND' }
  if (opened.status !== 'pending_upload') return opened
  if (!opened.file_path) throw { message: 'CL_DELIVERY_NOT_FOUND' }
  onStep?.('uploading')
  const up = await api.upload(opened.file_path, args.format)
  // 409 / Duplicate = el fichero ya estaba subido (reintento tras un corte): se completa igual.
  if (up.error && !isDuplicateUpload(up.error)) throw up.error
  onStep?.('completing')
  return parseDeliverySummary(await api.complete(opened.delivery_id))
}

export function isDuplicateUpload(e: { message?: string; statusCode?: string | number }): boolean {
  return String(e.statusCode ?? '') === '409' || /duplicate|already exists/i.test(e.message ?? '')
}

// ---------------------------------------------------------------- calendario del conector (cl_feed_delivery_calendar)

export interface ClFeedCalendar {
  frequency: string | null
  deliveries_per_week: number | null
  delivery_days: number[]
  delivery_hour: number | null
  timezone: string | null
  next_period: { period_start: string; period_end: string; due_at: string | null; deliverable: boolean } | null
  last_delivery: { period_start: string; period_end: string; status: string } | null
  missing_grace_hours: number | null
  max_file_bytes: number | null
}

const asObj = (v: unknown): Record<string, unknown> | null =>
  v && typeof v === 'object' && !Array.isArray(v) ? (v as Record<string, unknown>) : null

/** Lee lo que devuelve cl_feed_delivery_calendar sin fiarse de su forma. */
export function parseFeedCalendar(data: unknown): ClFeedCalendar {
  const o = asObj(data) ?? {}
  const cal = asObj(o.calendar) ?? {}
  const np = asObj(o.next_period)
  const ld = asObj(o.last_delivery)
  const n = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null)
  const s = (v: unknown) => (typeof v === 'string' ? v : null)
  return {
    frequency: s(cal.frequency),
    deliveries_per_week: n(cal.deliveries_per_week),
    delivery_days: Array.isArray(cal.delivery_days) ? cal.delivery_days.filter((d): d is number => typeof d === 'number') : [],
    delivery_hour: n(cal.delivery_hour),
    timezone: s(cal.timezone),
    next_period:
      np && s(np.period_start) && s(np.period_end)
        ? { period_start: s(np.period_start)!, period_end: s(np.period_end)!, due_at: s(np.due_at), deliverable: np.deliverable === true }
        : null,
    last_delivery:
      ld && s(ld.period_start) && s(ld.period_end)
        ? { period_start: s(ld.period_start)!, period_end: s(ld.period_end)!, status: s(ld.status) ?? '' }
        : null,
    missing_grace_hours: n(o.missing_grace_hours),
    max_file_bytes: n(o.max_file_bytes),
  }
}
