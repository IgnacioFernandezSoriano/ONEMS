// GET /query: the extraction SQL of the next delivery, built from the same object GET /config returns
// (cl_connector_config). Same rule as the manual §5.1 and the simulator's complete_shipments: a shipment of a plan
// product whose latest arrival (destination/both point) falls inside the period, with an earlier departure
// (origin/both point); the file carries all its scans at agreed points (or all its scans with include_all_scans).
// Pure function: no I/O. PostgreSQL is checked against the simulator (tools/carrier-simulator/e2e/query_pg_check.py);
// Oracle and SQL Server are published untested.

export type QueryDb = 'postgresql' | 'oracle' | 'sqlserver'
export const QUERY_DBS: readonly QueryDb[] = ['postgresql', 'oracle', 'sqlserver']
export const TABLE_PLACEHOLDER = 'carrier_scans'

/** IANA zone -> Windows zone name (SQL Server AT TIME ZONE only knows Windows names). */
export const IANA_TO_WINDOWS: Record<string, string> = {
  'UTC': 'UTC',
  'Etc/UTC': 'UTC',
  'Africa/Nairobi': 'E. Africa Standard Time',
  'Africa/Dakar': 'Greenwich Standard Time',
  'Africa/Abidjan': 'Greenwich Standard Time',
  'Africa/Lagos': 'W. Central Africa Standard Time',
  'Africa/Johannesburg': 'South Africa Standard Time',
  'Africa/Cairo': 'Egypt Standard Time',
  'Africa/Casablanca': 'Morocco Standard Time',
  'Europe/Madrid': 'Romance Standard Time',
  'Europe/Paris': 'Romance Standard Time',
  'Europe/Zurich': 'W. Europe Standard Time',
  'Europe/Berlin': 'W. Europe Standard Time',
  'Europe/London': 'GMT Standard Time',
  'Europe/Lisbon': 'GMT Standard Time',
  'America/New_York': 'Eastern Standard Time',
  'America/Chicago': 'Central Standard Time',
  'America/Denver': 'Mountain Standard Time',
  'America/Los_Angeles': 'Pacific Standard Time',
  'America/Sao_Paulo': 'E. South America Standard Time',
  'America/Mexico_City': 'Central Standard Time (Mexico)',
  'Asia/Dubai': 'Arabian Standard Time',
  'Asia/Riyadh': 'Arab Standard Time',
  'Asia/Kolkata': 'India Standard Time',
  'Asia/Shanghai': 'China Standard Time',
  'Asia/Tokyo': 'Tokyo Standard Time',
  'Australia/Sydney': 'AUS Eastern Standard Time',
}

interface FieldRef { field: string; format?: string | null; timezone?: string | null }

export interface ConnectorConfig {
  connector?: { id?: string; name?: string; status?: string; carrier?: string | null }
  date_timezone: string
  include_all_scans?: boolean
  fields: { item_id?: FieldRef | null; product?: FieldRef | null; scan_at?: FieldRef | null; place_ref?: FieldRef | null; mode_ref?: FieldRef | null }
  extra_fields?: string[] | null
  mapping_complete?: boolean
  products?: { code?: string; carrier_codes?: (string | null)[] | null }[] | null
  points?: { place_ref?: string | null; mode_ref?: string | null; role?: string | null; city?: string | null; city_id?: string | null }[] | null
  next_period?: { period_start?: string; period_end?: string; due_at?: string; deliverable?: boolean } | null
}

export interface CarrierQuery {
  db: QueryDb
  tested: boolean
  period_start: string | null
  period_end: string | null
  table_placeholder: string
  sql: string
}

const STANDARD_ORDER = ['item_id', 'product', 'scan_at', 'place_ref', 'mode_ref'] as const

const lit = (v: string) => `'${v.replace(/'/g, "''")}'`
const norm = (v: unknown): string | null => (typeof v === 'string' && v.trim() !== '' ? v.trim() : null)
// Comment text never carries a line break (a value could otherwise end the comment).
const commentSafe = (v: string) => v.replace(/[\r\n]+/g, ' ')

function ident(db: QueryDb, name: string): string {
  return db === 'sqlserver' ? `[${name.replace(/]/g, ']]')}]` : `"${name.replace(/"/g, '""')}"`
}

function text(db: QueryDb, expr: string): string {
  const t = db === 'oracle' ? 'VARCHAR2(400)' : db === 'sqlserver' ? 'NVARCHAR(400)' : 'VARCHAR(400)'
  return `NULLIF(TRIM(CAST(${expr} AS ${t})), '')`
}

function nullText(db: QueryDb): string {
  const t = db === 'oracle' ? 'VARCHAR2(400)' : db === 'sqlserver' ? 'NVARCHAR(400)' : 'VARCHAR(400)'
  return `CAST(NULL AS ${t})`
}

function localDate(db: QueryDb, col: string, scanTz: string, dateTz: string): { expr: string; notes: string[] } {
  if (db === 'postgresql') {
    return { expr: `CAST((${col} AT TIME ZONE ${lit(scanTz)}) AT TIME ZONE ${lit(dateTz)} AS DATE)`, notes: [] }
  }
  if (db === 'oracle') {
    return {
      expr: `TRUNC(CAST(FROM_TZ(CAST(${col} AS TIMESTAMP), ${lit(scanTz)}) AT TIME ZONE ${lit(dateTz)} AS DATE))`,
      notes: [],
    }
  }
  const notes: string[] = []
  const win = (z: string) => {
    const w = IANA_TO_WINDOWS[z]
    if (w) return w
    notes.push(`-- Replace <WINDOWS_TIME_ZONE_FOR_${commentSafe(z)}> with the Windows name of that zone (sys.time_zone_info).`)
    return `<WINDOWS_TIME_ZONE_FOR_${z}>`
  }
  return { expr: `CAST((${col} AT TIME ZONE ${lit(win(scanTz))}) AT TIME ZONE ${lit(win(dateTz))} AS date)`, notes }
}

/** Rows of an inline table as UNION ALL of SELECTs (portable; no VALUES constructor). Empty -> a never-matching row. */
function inlineRows(db: QueryDb, cols: string[], rows: (string | null)[][]): string {
  const from = db === 'oracle' ? ' FROM dual' : ''
  const cell = (v: string | null) => (v === null ? nullText(db) : `CAST(${lit(v)} AS ${db === 'oracle' ? 'VARCHAR2(400)' : db === 'sqlserver' ? 'NVARCHAR(400)' : 'VARCHAR(400)'})`)
  if (rows.length === 0) {
    return `SELECT ${cols.map((c) => `${nullText(db)} AS ${c}`).join(', ')}${from} WHERE 1 = 0`
  }
  return rows.map((r) => `SELECT ${r.map((v, i) => `${cell(v)} AS ${cols[i]}`).join(', ')}${from}`).join('\n    UNION ALL ')
}

export function buildCarrierQuery(config: ConnectorConfig, db: QueryDb): CarrierQuery {
  const f = config.fields ?? {}
  const name = (k: keyof ConnectorConfig['fields']) => norm(f[k]?.field ?? null)
  const itemF = name('item_id')!, scanF = name('scan_at')!, placeF = name('place_ref')!
  const prodF = name('product'), modeF = name('mode_ref')
  const scanTz = norm(f.scan_at?.timezone ?? null) ?? 'UTC'
  const dateTz = norm(config.date_timezone) ?? 'UTC'
  const allScans = config.include_all_scans === true
  const ps = norm(config.next_period?.period_start ?? null)
  const pe = norm(config.next_period?.period_end ?? null)
  const fromDual = db === 'oracle' ? ' FROM dual' : ''
  const C = (n: string) => `c.${ident(db, n)}`

  // Output columns: the mapped standard fields in the manual's order, then the extra fields; no duplicates.
  const out: string[] = []
  for (const k of STANDARD_ORDER) {
    const n = name(k)
    if (n && !out.includes(n)) out.push(n)
  }
  for (const x of config.extra_fields ?? []) {
    const n = norm(x)
    if (n && !out.includes(n)) out.push(n)
  }

  const points: (string | null)[][] = []
  for (const p of config.points ?? []) {
    const place = norm(p.place_ref)
    if (place === null) continue
    const role = p.role === 'origin' || p.role === 'destination' || p.role === 'both' ? p.role : 'intermediate'
    points.push([place, norm(p.mode_ref), role])
  }
  const codes: string[] = []
  for (const p of config.products ?? []) {
    for (const c of p.carrier_codes ?? []) if (typeof c === 'string' && !codes.includes(c.trim())) codes.push(c.trim())
  }

  const ld = localDate(db, C(scanF), scanTz, dateTz)
  const modeMatch = modeF ? `(p.mode_ref IS NULL OR p.mode_ref = ${text(db, C(modeF))})` : 'p.mode_ref IS NULL'
  const atPoint = (roles: string | null) =>
    `CASE WHEN EXISTS (SELECT 1 FROM agreed_points p WHERE p.place_ref = ${text(db, C(placeF))} AND ${modeMatch}` +
    `${roles ? ` AND p.role IN (${roles})` : ''}) THEN 1 ELSE 0 END`
  // SQL Server has no DATE '...' literal.
  const dateLit = (v: string | null, ph: string) =>
    db === 'sqlserver' ? `CAST(${lit(v ?? ph)} AS date)` : `DATE ${lit(v ?? ph)}`

  const header = [
    `-- ONEMS Carrier Link: extraction query of one delivery (${db}).`,
    ...(db === 'postgresql' ? [] : ['-- SIN PROBAR / UNTESTED: this dialect has not been run by ONEMS yet. Check it before use.']),
    `-- Connector: ${commentSafe(config.connector?.name ?? '')} (carrier ${commentSafe(config.connector?.carrier ?? '')}).`,
    `-- Built from GET /config: products, agreed points, field names and period. Ask GET /query again before each`,
    `-- delivery: the period changes every time and the configuration may change.`,
    `-- 1. Replace ${TABLE_PLACEHOLDER} with your table (or view) of scans: one row per scan.`,
    `-- 2. The column ${commentSafe(scanF)} is assumed a date/time WITHOUT time zone, in ${commentSafe(scanTz)}. If it already`,
    `--    carries a time zone, drop the first time-zone conversion in local_date; if it is text, convert it first.`,
    `-- 3. Period: ${ps && pe ? `${ps} to ${pe} (next_period).` : 'no period is pending now: replace <PERIOD_START> and <PERIOD_END> (YYYY-MM-DD).'}`,
    `-- Statement 1 gives the file rows (all the scans of the complete shipments); statement 2 the control totals.`,
    ...ld.notes,
  ].join('\n')

  const ctes = [
    `params AS (\n  SELECT ${dateLit(ps, '<PERIOD_START>')} AS p_start, ${dateLit(pe, '<PERIOD_END>')} AS p_end${fromDual}\n)`,
    `agreed_points AS (\n  ${inlineRows(db, ['place_ref', 'mode_ref', 'role'], points)}\n)`,
    ...(prodF ? [`plan_products AS (\n  ${inlineRows(db, ['code'], codes.map((c) => [c]))}\n)`] : []),
    `s AS (\n  SELECT c.*,\n         c.${ident(db, itemF)} AS cl_item,\n         c.${ident(db, scanF)} AS cl_ts,\n` +
      `         ${ld.expr} AS cl_local_date,\n` +
      `         ${prodF ? text(db, C(prodF)) : nullText(db)} AS cl_product,\n` +
      `         ${atPoint("'destination', 'both'")} AS is_arrival,\n` +
      `         ${atPoint("'origin', 'both'")} AS is_departure,\n` +
      `         ${atPoint(null)} AS is_agreed\n    FROM ${TABLE_PLACEHOLDER} c\n)`,
    `arrival AS (            -- the final arrival: the latest arrival scan of each shipment\n` +
      `  SELECT x.* FROM (SELECT s.*, ROW_NUMBER() OVER (PARTITION BY s.cl_item ORDER BY s.cl_ts DESC) AS cl_rn\n` +
      `                    FROM s WHERE s.is_arrival = 1 AND s.cl_ts IS NOT NULL) x\n   WHERE x.cl_rn = 1\n)`,
    ...(prodF
      ? [`product AS (            -- the shipment's product: the one on its earliest scan with a time\n` +
        `  SELECT x.cl_item, x.cl_product FROM (SELECT s.cl_item, s.cl_product,\n` +
        `                                     ROW_NUMBER() OVER (PARTITION BY s.cl_item ORDER BY s.cl_ts) AS cl_rn\n` +
        `                                FROM s WHERE s.cl_ts IS NOT NULL) x\n   WHERE x.cl_rn = 1\n)`]
      : []),
    `complete AS (           -- complete shipments of the period\n` +
      `  SELECT a.cl_item, a.cl_ts AS cl_arrival_ts,\n` +
      `         a.${ident(db, placeF)} AS cl_arrival_place, ${modeF ? `a.${ident(db, modeF)}` : nullText(db)} AS cl_arrival_mode,\n` +
      `         ${prodF ? 'pr.cl_product' : nullText(db)} AS cl_shipment_product\n` +
      `    FROM arrival a\n` +
      (prodF ? `    JOIN product pr ON pr.cl_item = a.cl_item\n` : '') +
      `    CROSS JOIN params\n` +
      `   WHERE a.cl_local_date BETWEEN params.p_start AND params.p_end\n` +
      (prodF ? `     AND pr.cl_product IN (SELECT code FROM plan_products)\n` : '') +
      `     AND EXISTS (SELECT 1 FROM s d WHERE d.cl_item = a.cl_item AND d.is_departure = 1 AND d.cl_ts < a.cl_ts)\n)`,
  ]
  const withBlock = `WITH ${ctes.join(',\n')}`

  const file = `${withBlock}\nSELECT ${out.map((n) => `s.${ident(db, n)}`).join(', ')}\n  FROM s JOIN complete k ON k.cl_item = s.cl_item\n` +
    (allScans ? '' : ` WHERE s.is_agreed = 1\n`) +
    ` ORDER BY s.cl_item, s.cl_ts;`

  const totals = `${withBlock}\nSELECT k.cl_arrival_place AS place_ref, k.cl_arrival_mode AS mode_ref, k.cl_shipment_product AS product,\n` +
    `       COUNT(*) AS delivered\n  FROM complete k\n GROUP BY k.cl_arrival_place, k.cl_arrival_mode, k.cl_shipment_product\n` +
    ` ORDER BY 1, 2, 3;`

  return {
    db,
    tested: db === 'postgresql',
    period_start: ps && pe ? ps : null,
    period_end: ps && pe ? pe : null,
    table_placeholder: TABLE_PLACEHOLDER,
    sql: `${header}\n\n-- Statement 1: the delivery file\n${file}\n\n-- Statement 2: control totals\n${totals}\n`,
  }
}
