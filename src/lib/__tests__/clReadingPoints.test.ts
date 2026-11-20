import { describe, it, expect } from 'vitest'
import {
  buildReadingPointRow,
  parseUnknownPlaces,
  excludeRegistered,
  reviveReadingPointFields,
  readingPointErrorKey,
} from '../carrierLink/readingPoints'

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

describe('parseUnknownPlaces', () => {
  it('lee las filas de cl_unknown_places: recorta, modo en blanco = null, readings numérico', () => {
    const out = parseUnknownPlaces([
      { place_ref: ' NBO ', mode_ref: 'ADM', readings: 3 },
      { place_ref: 'XYZ', mode_ref: '  ', readings: '2' },
      { place_ref: 'MBA', mode_ref: null, readings: 1 },
    ])
    expect(out).toEqual([
      { place_ref: 'NBO', mode_ref: 'ADM', readings: 3 },
      { place_ref: 'XYZ', mode_ref: null, readings: 2 },
      { place_ref: 'MBA', mode_ref: null, readings: 1 },
    ])
  })
  it('descarta lugares NULL o en blanco y respuestas sin forma', () => {
    expect(parseUnknownPlaces([{ place_ref: null, mode_ref: 'M', readings: 1 }, { place_ref: '  ', readings: 4 }, null])).toEqual([])
    expect(parseUnknownPlaces(null)).toEqual([])
    expect(parseUnknownPlaces({ place_ref: 'X' })).toEqual([])
  })
})

describe('reviveReadingPointFields', () => {
  it('reactiva la fila borrada con los datos del formulario, sin tocar cuenta ni origen', () => {
    const built = buildReadingPointRow('a1', { ...base, carrier_mode_ref: 'ADM', e2e_role: 'both', name: 'Hub' })
    expect(built.ok).toBe(true)
    if (!built.ok) return
    const f = reviveReadingPointFields(built.row, '2026-11-20T10:00:00.000Z')
    expect(f).toEqual({
      carrier_id: 'c1',
      carrier_place_ref: 'NYC-RDC',
      carrier_mode_ref: 'ADM',
      postal_center_id: 'pc1',
      e2e_role: 'both',
      type: 'Mixed',
      name: 'Hub',
      deleted_at: null,
      is_active: true,
      updated_at: '2026-11-20T10:00:00.000Z',
    })
  })
})

describe('readingPointErrorKey', () => {
  it('23505 -> duplicado; 42501 -> forbidden; CL_* y resto como clErrorKey', () => {
    expect(readingPointErrorKey({ code: '23505', message: 'duplicate key value violates unique constraint' })).toBe(
      'cl.reading_points.error.duplicate',
    )
    expect(readingPointErrorKey({ code: '42501', message: 'new row violates row-level security policy' })).toBe('cl.error.forbidden')
    expect(readingPointErrorKey({ message: 'CL_FORBIDDEN' })).toBe('cl.error.cl_forbidden')
    expect(readingPointErrorKey({ message: 'boom' })).toBe('cl.error.generic')
    expect(readingPointErrorKey(null)).toBe('cl.error.generic')
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
