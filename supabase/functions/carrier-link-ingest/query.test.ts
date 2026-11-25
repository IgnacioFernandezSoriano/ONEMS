// deno-lint-ignore-file no-import-prefix
import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts'
import { buildCarrierQuery, type ConnectorConfig } from './query.ts'

// The config of tools/carrier-simulator/examples/01-get-config.json (body).
const CONFIG: ConnectorConfig = {
  connector: { id: 'c1517000-0000-4000-8000-0000000000f1', name: 'SimPost - simulated connector', status: 'active', carrier: 'SIMPOST' },
  date_timezone: 'Africa/Nairobi',
  include_all_scans: false,
  fields: {
    item_id: { field: 'tracking_no' },
    product: { field: 'service' },
    scan_at: { field: 'event_ts', format: 'DD/MM/YYYY HH24:MI:SS', timezone: 'Africa/Nairobi' },
    mode_ref: { field: 'event_code' },
    place_ref: { field: 'site_code' },
  },
  extra_fields: ['weight_g'],
  mapping_complete: true,
  products: [{ code: 'SIM-STD', carrier_codes: ['STD'] }],
  points: [
    { role: 'origin', mode_ref: 'ACC', place_ref: 'EMR-PO' },
    { role: 'destination', mode_ref: 'DLV', place_ref: 'EMR-PO' },
    { role: 'origin', mode_ref: 'ACC', place_ref: 'NPT-PO' },
    { role: 'destination', mode_ref: 'DLV', place_ref: 'NPT-PO' },
    { role: 'origin', mode_ref: 'ACC', place_ref: 'SVL-PO' },
    { role: 'destination', mode_ref: 'DLV', place_ref: 'SVL-PO' },
  ],
  next_period: { due_at: '2026-11-05T01:00:00+01:00', period_end: '2026-11-04', deliverable: true, period_start: '2026-11-02' },
}

const clone = (): ConnectorConfig => structuredClone(CONFIG)

Deno.test('postgresql: tested, period and the carrier names', () => {
  const r = buildCarrierQuery(CONFIG, 'postgresql')
  assertEquals(r.db, 'postgresql')
  assertEquals(r.tested, true)
  assertEquals(r.period_start, '2026-11-02')
  assertEquals(r.period_end, '2026-11-04')
  assertEquals(r.table_placeholder, 'carrier_scans')
  for (const s of ['"tracking_no"', '"event_ts"', '"weight_g"', "AT TIME ZONE 'Africa/Nairobi'", 'ROW_NUMBER()', "'STD'",
    "'EMR-PO'", "'NPT-PO'", "'SVL-PO'", "DATE '2026-11-02'", "DATE '2026-11-04'", 'carrier_scans']) {
    assert(r.sql.includes(s), `missing ${s}`)
  }
  assert(!r.sql.includes('DISTINCT ON'))
  assert(!r.sql.includes('UNTESTED'))
})

Deno.test('oracle: untested, FROM_TZ and dual', () => {
  const r = buildCarrierQuery(CONFIG, 'oracle')
  assertEquals(r.tested, false)
  for (const s of ['SIN PROBAR / UNTESTED', 'FROM_TZ(', 'FROM dual', '"tracking_no"']) assert(r.sql.includes(s), `missing ${s}`)
})

Deno.test('sqlserver: untested, brackets and Windows zone', () => {
  const r = buildCarrierQuery(CONFIG, 'sqlserver')
  assertEquals(r.tested, false)
  for (const s of ['SIN PROBAR / UNTESTED', '[tracking_no]', "'E. Africa Standard Time'"]) assert(r.sql.includes(s), `missing ${s}`)
})

Deno.test('no next_period: placeholders and null period', () => {
  const c = clone()
  c.next_period = null
  const r = buildCarrierQuery(c, 'postgresql')
  assertEquals(r.period_start, null)
  assertEquals(r.period_end, null)
  assert(r.sql.includes('<PERIOD_START>') && r.sql.includes('<PERIOD_END>'))
})

Deno.test('include_all_scans drops the agreed-point filter of the file', () => {
  assert(buildCarrierQuery(CONFIG, 'postgresql').sql.includes('WHERE s.is_agreed'))
  const c = clone()
  c.include_all_scans = true
  assert(!buildCarrierQuery(c, 'postgresql').sql.includes('WHERE s.is_agreed'))
})

Deno.test('without product mapping: no product filter', () => {
  const c = clone()
  delete c.fields.product
  const sql = buildCarrierQuery(c, 'postgresql').sql
  assert(!sql.includes("'STD'"))
  assert(!sql.includes('"service"'))
})

Deno.test('without mode mapping: no mode column', () => {
  const c = clone()
  delete c.fields.mode_ref
  const sql = buildCarrierQuery(c, 'postgresql').sql
  assert(!sql.includes('"event_code"'))
  assert(sql.includes('"site_code"'))
})

Deno.test('literals and identifiers are escaped per dialect', () => {
  const c = clone()
  c.products = [{ code: 'X', carrier_codes: ["O'BRIEN"] }]
  c.extra_fields = ['we"ird', 'a]b']
  const pg = buildCarrierQuery(c, 'postgresql').sql
  assert(pg.includes("'O''BRIEN'"))
  assert(pg.includes('"we""ird"'))
  const ms = buildCarrierQuery(c, 'sqlserver').sql
  assert(ms.includes('[we"ird]'))
  assert(ms.includes('[a]]b]'))
  assert(ms.includes("'O''BRIEN'"))
})

Deno.test('empty products and points still give valid SQL', () => {
  const c = clone()
  c.products = []
  c.points = []
  for (const db of ['postgresql', 'oracle', 'sqlserver'] as const) {
    const sql = buildCarrierQuery(c, db).sql
    assert(!/IN\s*\(\s*\)/.test(sql), `${db}: empty IN`)
    assert(!/VALUES\s*\)/.test(sql), `${db}: empty VALUES`)
    assert(sql.includes('1 = 0'), `${db}: never-matching guard`)
  }
})

Deno.test('sqlserver: unknown IANA zone becomes a visible placeholder', () => {
  const c = clone()
  c.date_timezone = 'Mars/Base'
  assert(buildCarrierQuery(c, 'sqlserver').sql.includes('<WINDOWS_TIME_ZONE_FOR_Mars/Base>'))
})

Deno.test('sqlserver: period as CAST(... AS date), no DATE literal', () => {
  const sql = buildCarrierQuery(CONFIG, 'sqlserver').sql
  assert(sql.includes("CAST('2026-11-02' AS date)"))
  assert(!sql.includes("DATE '"))
})
