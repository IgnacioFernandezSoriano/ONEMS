import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { CL_ALERT_TYPES, alertDetailLines, alertLabelKey } from '../carrierLink/monitorView'

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
  // v4: avisos de las entregas (cl_delivery_alert(delivery, plan, quota, 'tipo', 'gravedad', ...)).
  const v4 = new Set<string>()
  for (const f of readdirSync(dir).filter((x) => x.startsWith('202611242'))) {
    const sql = readFileSync(resolve(dir, f), 'utf8')
    for (const m of sql.matchAll(/cl_delivery_alert\([^;]*?,\s*'([a-z_]+)'\s*,\s*'(?:high|medium|low)'/g)) v4.add(m[1])
  }
  it('CL_ALERT_TYPES cubre los avisos de las entregas v4', () => {
    expect(v4.size).toBeGreaterThan(5)
    expect([...v4].filter((t) => !(CL_ALERT_TYPES as readonly string[]).includes(t))).toEqual([])
  })
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

describe('alertDetailLines (v4)', () => {
  it('lee la forma de los avisos de entrega', () => {
    expect(alertDetailLines('insufficient_candidates', { population: 3, quota_for_delivery: 5 }, null)[0].params).toEqual({ valid: 3, required: 5 })
    expect(alertDetailLines('rejected_ratio', { rejected: 30, shipments: 100, ratio: 0.3 }, null)[0].params).toEqual({
      rejected: 30,
      candidates: 100,
      percent: 30,
    })
    expect(alertDetailLines('possible_misrouting', { samples: [{ sample_id: 's', item_id: 'X1' }] }, null)[0].params).toEqual({ items: 'X1' })
    expect(alertDetailLines('quota_already_settled', { skipped: 4 }, null)[0]).toEqual({
      key: 'cl.alert.detail.quota_already_settled',
      params: { skipped: 4 },
    })
    expect(alertDetailLines('delivery_retries_exhausted', { last_error: 'CL_X', samples_voided: 2 }, null)[0].params).toEqual({ voided: 2 })
  })
})

describe('alertDetailLines (diagnostico, R36)', () => {
  it('puntos sin centro y lecturas que quedan fuera', () => {
    const l = alertDetailLines(
      'diagnosis_point_without_center',
      { points: [{ reader_id: 'r', name: 'HUB2', place_ref: 'HU2', mode_ref: null }], readings: 3, shipments: 2 },
      null,
    )
    expect(l).toEqual([
      { key: 'cl.alert.detail.points', params: { points: 'HU2 / -' } },
      { key: 'cl.alert.detail.diagnosis_skipped', params: { readings: 3, shipments: 2 } },
    ])
  })
})
