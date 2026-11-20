import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { CL_ALERT_TYPES, alertDetailLines, alertLabelKey, batchSummary, demandCounts } from '../carrierLink/monitorView'

describe('demandCounts', () => {
  it('cuenta por estado e ignora desconocidos', () => {
    const r = demandCounts([{ status: 'open' }, { status: 'open' }, { status: 'fulfilled' }, { status: 'raro' }])
    expect(r).toEqual({ open: 2, fulfilled: 1, partial: 0, failed: 0 })
  })
})

describe('batchSummary', () => {
  it('resumen vacio -> ceros', () => {
    expect(batchSummary({ summary: {} })).toEqual({ shipments: 0, rejected: 0, selected: 0 })
    expect(batchSummary({ summary: null })).toEqual({ shipments: 0, rejected: 0, selected: 0 })
  })
  it('lote real de DEMO2: 36 envios, 2 rechazados, 18 elegidos (cl_sampling_runs)', () => {
    const st = (id: string, candidates: number, valid: number, rejected: Record<string, number>) => ({
      stratum_id: id,
      population_size: 40,
      rows: candidates * 2,
      candidates,
      candidates_valid: valid,
      rejected,
      rows_rejected: {},
    })
    const summary = {
      batch: 'b1',
      status: 'validated',
      strata: [
        st('a', 6, 6, {}),
        st('b', 6, 6, {}),
        st('c', 6, 6, {}),
        st('d', 6, 6, {}),
        st('e', 7, 6, { start_after_end: 1 }),
        st('f', 5, 4, { unknown_product: 1 }),
      ],
    }
    expect(batchSummary({ summary, selected: 18 })).toEqual({ shipments: 36, rejected: 2, selected: 18 })
  })
  it('lote rechazado (estratos sin recuentos) -> ceros', () => {
    const summary = { status: 'rejected', strata: [{ stratum_id: 'a', selection_method: 'x' }] }
    expect(batchSummary({ summary })).toEqual({ shipments: 0, rejected: 0, selected: 0 })
  })
})

describe('alertLabelKey y traducciones', () => {
  it('forma de la clave', () => {
    expect(alertLabelKey('missing_standard')).toBe('cl.alert.missing_standard')
  })

  // Union: los 13 de la spec + todos los tipos que el codigo de la base lanza realmente (migraciones).
  const spec = [
    'insufficient_candidates', 'empty_stratum', 'population_drop', 'population_incoherent', 'suspicious_distribution',
    'late_batch', 'unknown_product', 'unknown_reading_point', 'possible_misrouting', 'missing_standard',
    'rejected_ratio', 'quota_unfilled', 'feed_silent',
  ]
  const dir = resolve(__dirname, '../../../supabase/migrations')
  const raised = new Set<string>()
  for (const f of readdirSync(dir).filter((x) => x.startsWith('2026112011'))) {
    const sql = readFileSync(resolve(dir, f), 'utf8')
    for (const m of sql.matchAll(/cl_raise_alert\([^;]*?,\s*'([a-z_]+)'\s*,\s*'(?:high|medium|low)'/g)) raised.add(m[1])
    for (const m of sql.matchAll(/VALUES\s*\([^;]*?,\s*'([a-z_]+)'\s*,\s*'(?:high|medium|low)'/g)) raised.add(m[1])
  }
  it('CL_ALERT_TYPES cubre la spec y todo lo que lanzan las migraciones', () => {
    expect(raised.size).toBeGreaterThan(10)
    expect(spec.filter((t) => !(CL_ALERT_TYPES as readonly string[]).includes(t))).toEqual([])
    expect([...raised].filter((t) => !(CL_ALERT_TYPES as readonly string[]).includes(t))).toEqual([])
  })
  for (const lang of ['en', 'es', 'fr', 'ar', 'pt']) {
    it(`${lang}.csv traduce todos los tipos de aviso`, () => {
      const csv = readFileSync(resolve(__dirname, `../../../public/locales/${lang}.csv`), 'utf8')
      const keys = new Set(csv.split(/\r?\n/).map((l) => l.slice(0, l.indexOf(','))))
      expect(CL_ALERT_TYPES.map(alertLabelKey).filter((k) => !keys.has(k))).toEqual([])
    })
  }
})

describe('alertDetailLines', () => {
  it('ruta y datos en lenguaje claro, sin JSON', () => {
    const l = alertDetailLines('possible_misrouting', { item_ids: ['A1', 'B2'] }, { origin: 'Lyon', destination: 'Paris' })
    expect(l[0]).toEqual({ key: 'cl.alert.route', params: { origin: 'Lyon', destination: 'Paris' } })
    expect(l[1]).toEqual({ key: 'cl.alert.detail.items', params: { items: 'A1, B2' } })
  })
  it('recorta listas largas y tolera details nulo', () => {
    const l = alertDetailLines('reader_without_city', { item_ids: ['1', '2', '3', '4', '5', '6', '7'] }, null)
    expect(l[0].params).toEqual({ items: '1, 2, 3, 4, 5 (+2)' })
    expect(alertDetailLines('emit_failed', { sqlstate: 'X', error: 'boom' }, null)).toEqual([])
    expect(alertDetailLines('quota_unfilled', null, null)[0].params).toEqual({ missing: 0, planned: 0 })
  })
})
