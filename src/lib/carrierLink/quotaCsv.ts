import { isoWeekOf, type ClQuota } from './quotaCalculator'

/**
 * CSV de cuotas de Carrier Link (importación al generador y descarga de un plan).
 * Columnas: origin_city, destination_city (código o nombre), week (YYYY-Www o una fecha YYYY-MM-DD), samples.
 */
export const QUOTA_CSV_COLUMNS = ['origin_city', 'destination_city', 'week', 'samples'] as const
export const QUOTA_CSV_TEMPLATE = QUOTA_CSV_COLUMNS.join(',')

export interface QuotaCsvContext {
  cities: { id: string; code?: string | null; name?: string | null }[]
  /** Fechas del plan (yyyy-MM-dd): una semana vale si algún día suyo cae dentro. */
  startDate: string
  endDate: string
  /** Ciudades con punto activo de inicio (origin|both) y de fin (destination|both) del carrier. */
  originCityIds: string[]
  destinationCityIds: string[]
}

/** row = línea del fichero (la cabecera es la 1). La clave i18n recibe vars. */
export type QuotaCsvError = { row: number; key: string; vars?: Record<string, string | number> }

const pad2 = (n: number) => String(n).padStart(2, '0')

/** Divide una línea CSV respetando comillas ("" = comilla literal). */
function splitLine(line: string, sep: string): string[] {
  const out: string[] = []
  let cur = ''
  let quoted = false
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (quoted) {
      if (ch === '"' && line[i + 1] === '"') {
        cur += '"'
        i++
      } else if (ch === '"') quoted = false
      else cur += ch
    } else if (ch === '"') quoted = true
    else if (ch === sep) {
      out.push(cur.trim())
      cur = ''
    } else cur += ch
  }
  out.push(cur.trim())
  return out
}

function weeksInIsoYear(y: number): number {
  // Un año ISO tiene 53 semanas si el 28 de diciembre cae en la semana 53.
  return isoWeekOf(new Date(y, 11, 28)).iso_week
}

/** Lunes (yyyy-MM-dd) de una semana ISO. */
function isoMonday(y: number, w: number): string {
  const jan4 = Date.UTC(y, 0, 4)
  const jan4Dow = (new Date(jan4).getUTCDay() + 6) % 7
  const d = new Date(jan4 + ((w - 1) * 7 - jan4Dow) * 86400000)
  return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`
}

function addDays(ymd: string, n: number): string {
  const [y, m, d] = ymd.split('-').map(Number)
  const t = new Date(Date.UTC(y, m - 1, d + n))
  return `${t.getUTCFullYear()}-${pad2(t.getUTCMonth() + 1)}-${pad2(t.getUTCDate())}`
}

/** Semana ISO de 'YYYY-Www' o de una fecha 'YYYY-MM-DD'; null si no es válida. */
function parseWeek(s: string): { iso_year: number; iso_week: number } | null {
  const w = /^(\d{4})-?W(\d{1,2})$/i.exec(s)
  if (w) {
    const y = Number(w[1])
    const n = Number(w[2])
    return n >= 1 && n <= weeksInIsoYear(y) ? { iso_year: y, iso_week: n } : null
  }
  const d = /^(\d{4})-(\d{2})-(\d{2})$/.exec(s)
  if (d) {
    const [y, m, day] = [Number(d[1]), Number(d[2]), Number(d[3])]
    const date = new Date(y, m - 1, day)
    if (date.getFullYear() !== y || date.getMonth() !== m - 1 || date.getDate() !== day) return null
    return isoWeekOf(date)
  }
  return null
}

const weekLabel = (y: number, w: number) => `${y}-W${pad2(w)}`

/** Lee y valida un CSV de cuotas. Con cualquier error no devuelve cuotas (todo o nada). Filas con 0 muestras se omiten. */
export function parseQuotaCsv(text: string, ctx: QuotaCsvContext): { quotas: ClQuota[]; errors: QuotaCsvError[] } {
  const lines = (text.charCodeAt(0) === 0xfeff ? text.slice(1) : text).split(/\r?\n/)
  const header = lines[0] ?? ''
  const sep = header.includes(';') && !header.includes(',') ? ';' : ','
  const cols = splitLine(header, sep).map((c) => c.toLowerCase())
  const missing = QUOTA_CSV_COLUMNS.filter((c) => !cols.includes(c))
  if (missing.length > 0) {
    return { quotas: [], errors: [{ row: 1, key: 'cl.generator.csv.missing_columns', vars: { columns: missing.join(', ') } }] }
  }
  const idx = Object.fromEntries(QUOTA_CSV_COLUMNS.map((c) => [c, cols.indexOf(c)])) as Record<(typeof QUOTA_CSV_COLUMNS)[number], number>

  const byCode = new Map<string, string>()
  const byName = new Map<string, string | null>() // null = nombre repetido (ambiguo)
  for (const c of ctx.cities) {
    if (c.code) byCode.set(c.code.trim().toLowerCase(), c.id)
    if (c.name) {
      const k = c.name.trim().toLowerCase()
      byName.set(k, byName.has(k) ? null : c.id)
    }
  }
  const cityId = (s: string): string | null => {
    const k = s.toLowerCase()
    return byCode.get(k) ?? byName.get(k) ?? null
  }
  const origins = new Set(ctx.originCityIds)
  const destinations = new Set(ctx.destinationCityIds)

  const errors: QuotaCsvError[] = []
  const quotas: ClQuota[] = []
  const firstRow = new Map<string, number>()
  let dataRows = 0

  for (let i = 1; i < lines.length; i++) {
    if (lines[i].trim() === '') continue
    dataRows++
    const row = i + 1
    const f = splitLine(lines[i], sep)
    const originRaw = f[idx.origin_city] ?? ''
    const destRaw = f[idx.destination_city] ?? ''
    const weekRaw = f[idx.week] ?? ''
    const samplesRaw = f[idx.samples] ?? ''

    const o = cityId(originRaw)
    const d = cityId(destRaw)
    if (!o || !d) {
      errors.push({ row, key: 'cl.generator.csv.unknown_city', vars: { row, city: !o ? originRaw : destRaw } })
      continue
    }
    if (o === d) {
      errors.push({ row, key: 'cl.generator.csv.same_city', vars: { row } })
      continue
    }
    const wk = parseWeek(weekRaw)
    if (!wk) {
      errors.push({ row, key: 'cl.generator.csv.bad_week', vars: { row, week: weekRaw } })
      continue
    }
    const monday = isoMonday(wk.iso_year, wk.iso_week)
    if (addDays(monday, 6) < ctx.startDate || monday > ctx.endDate) {
      errors.push({ row, key: 'cl.generator.csv.week_outside', vars: { row, week: weekLabel(wk.iso_year, wk.iso_week) } })
      continue
    }
    if (!/^\d+$/.test(samplesRaw)) {
      errors.push({ row, key: 'cl.generator.csv.bad_samples', vars: { row, value: samplesRaw } })
      continue
    }
    const key = `${o}|${d}|${wk.iso_year}|${wk.iso_week}`
    const first = firstRow.get(key)
    if (first !== undefined) {
      errors.push({ row, key: 'cl.generator.csv.duplicate', vars: { row, first } })
      continue
    }
    if (!origins.has(o) || !destinations.has(d)) {
      errors.push({ row, key: 'cl.generator.csv.no_points', vars: { row, origin: originRaw, destination: destRaw } })
      continue
    }
    firstRow.set(key, row)
    const samples = Number(samplesRaw)
    if (samples > 0) quotas.push({ origin_city_id: o, destination_city_id: d, iso_year: wk.iso_year, iso_week: wk.iso_week, samples })
  }

  if (errors.length > 0) return { quotas: [], errors }
  if (dataRows === 0 || quotas.length === 0) return { quotas: [], errors: [{ row: 1, key: 'cl.generator.csv.empty' }] }
  return { quotas, errors: [] }
}

const csvCell = (v: string) => (/[",;\n]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v)

/** CSV de las cuotas de un plan con el mismo formato que la plantilla de importación. */
export function quotasToCsv(
  quotas: { origin_city_id: string; destination_city_id: string; iso_year: number; iso_week: number; samples_planned: number }[],
  cityLabel: (id: string) => string,
): string {
  const rows = quotas.map((q) =>
    [csvCell(cityLabel(q.origin_city_id)), csvCell(cityLabel(q.destination_city_id)), weekLabel(q.iso_year, q.iso_week), String(q.samples_planned)].join(','),
  )
  return [QUOTA_CSV_TEMPLATE, ...rows].join('\n')
}
