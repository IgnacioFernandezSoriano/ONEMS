import { describe, it, expect } from 'vitest'
import { buildReadingPointRow, unknownPlaces, excludeRegistered } from '../carrierLink/readingPoints'

const base = {
  carrier_id: 'c1',
  carrier_place_ref: 'NYC-RDC',
  carrier_mode_ref: '',
  postal_center_id: 'pc1',
  e2e_role: 'origin' as const,
  name: '',
}

describe('buildReadingPointRow', () => {
  it('sin cuenta devuelve no_account', () => {
    expect(buildReadingPointRow(null, base)).toEqual({ ok: false, error: 'no_account' })
  })
  it('recorta el lugar y deja el modo vacío en null', () => {
    const r = buildReadingPointRow('a1', { ...base, carrier_place_ref: '  NYC-RDC ' })
    expect(r.ok).toBe(true)
    if (r.ok) {
      expect(r.row.carrier_place_ref).toBe('NYC-RDC')
      expect(r.row.carrier_mode_ref).toBeNull()
      expect(r.row.capture_source).toBe('carrier_scan')
      expect(r.row.account_id).toBe('a1')
      expect('reader_id' in r.row).toBe(false)
    }
  })
  it('valida lugar, carrier y centro', () => {
    expect(buildReadingPointRow('a1', { ...base, carrier_place_ref: ' ' })).toEqual({ ok: false, error: 'missing_place' })
    expect(buildReadingPointRow('a1', { ...base, carrier_id: '' })).toEqual({ ok: false, error: 'missing_carrier' })
    expect(buildReadingPointRow('a1', { ...base, postal_center_id: '' })).toEqual({ ok: false, error: 'missing_center' })
  })
  it('deriva el tipo del papel', () => {
    const t = (e2e_role: 'origin' | 'destination' | 'both' | 'none') => {
      const r = buildReadingPointRow('a1', { ...base, e2e_role })
      return r.ok ? r.row.type : null
    }
    expect([t('origin'), t('destination'), t('both'), t('none')]).toEqual(['Entry', 'Exit', 'Mixed', 'Exit'])
  })
})

describe('unknownPlaces', () => {
  it('agrupa lecturas del mismo lugar/modo e ignora las resueltas', () => {
    const s = (reader_id: string | null, reject_reason: string | null = null) =>
      ({ place_ref: 'X', mode_ref: 'M', reject_reason, reader_id })
    const out = unknownPlaces([s(null), s(null, 'unknown_reading_point'), s('r1'), s(null)])
    expect(out).toEqual([{ place_ref: 'X', mode_ref: 'M', readings: 3 }])
  })
})

describe('excludeRegistered', () => {
  const u = (place_ref: string, mode_ref: string | null) => ({ place_ref, mode_ref, readings: 1 })
  it('quita lugares con punto activo; modo NULL del punto cubre cualquier modo', () => {
    const pts = [
      { carrier_place_ref: 'A', carrier_mode_ref: null },
      { carrier_place_ref: 'B', carrier_mode_ref: 'M1' },
    ]
    const out = excludeRegistered([u(' A ', 'X'), u('B', 'M1'), u('B', 'M2'), u('C', null)], pts)
    expect(out).toEqual([u('B', 'M2'), u('C', null)])
  })
})

describe('excludeRegistered (inactivos)', () => {
  it('un punto inactivo no excluye su lugar', () => {
    const out = excludeRegistered(
      [{ place_ref: 'A', mode_ref: null, readings: 2 }],
      [{ carrier_place_ref: 'A', carrier_mode_ref: null, is_active: false }],
    )
    expect(out).toHaveLength(1)
  })
})
