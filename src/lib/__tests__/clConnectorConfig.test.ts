import { describe, it, expect } from 'vitest'
import {
  STANDARD_FIELDS,
  validateFieldMappings,
  validateCalendar,
  canManageCarrierKeys,
  connectorErrorKey,
} from '../carrierLink/connectorConfig'

const full = [
  { standard_field: 'item_id', carrier_field: 'barcode' },
  { standard_field: 'scan_at', carrier_field: 'event_time' },
  { standard_field: 'place_ref', carrier_field: 'facility' },
]

describe('STANDARD_FIELDS', () => {
  it('lista los cinco campos estándar', () => {
    expect(STANDARD_FIELDS).toEqual(['item_id', 'product', 'scan_at', 'place_ref', 'mode_ref'])
  })
})

describe('validateFieldMappings', () => {
  it('sin scan_at → missing scan_at', () => {
    const r = validateFieldMappings(full.filter((m) => m.standard_field !== 'scan_at'))
    expect(r).toEqual({ ok: false, missing: ['scan_at'], duplicates: [] })
  })
  it('dos item_id → duplicates item_id', () => {
    const r = validateFieldMappings([...full, { standard_field: 'item_id', carrier_field: 'other' }])
    expect(r).toEqual({ ok: false, missing: [], duplicates: ['item_id'] })
  })
  it('completos → ok (product y mode_ref opcionales)', () => {
    expect(validateFieldMappings(full)).toEqual({ ok: true, missing: [], duplicates: [] })
    expect(
      validateFieldMappings([
        ...full,
        { standard_field: 'product', carrier_field: 'svc' },
        { standard_field: 'mode_ref', carrier_field: 'mode' },
      ]).ok,
    ).toBe(true)
  })
  it('carrier_field vacío cuenta como ausente', () => {
    const r = validateFieldMappings([...full.slice(0, 2), { standard_field: 'place_ref', carrier_field: '  ' }])
    expect(r.missing).toEqual(['place_ref'])
    expect(r.ok).toBe(false)
  })
  it('lista vacía → faltan los tres obligatorios', () => {
    expect(validateFieldMappings([]).missing).toEqual(['item_id', 'scan_at', 'place_ref'])
  })
})

describe('validateCalendar', () => {
  const base = { emit_days: [1, 3, 5], emit_hour: 3, emit_timezone: null }
  it('válido', () => {
    expect(validateCalendar(base)).toEqual({ ok: true })
  })
  it('[] → no_days', () => {
    expect(validateCalendar({ ...base, emit_days: [] })).toEqual({ ok: false, error: 'no_days' })
  })
  it('[8] → bad_day', () => {
    expect(validateCalendar({ ...base, emit_days: [8] })).toEqual({ ok: false, error: 'bad_day' })
  })
  it('[1,1] → bad_day', () => {
    expect(validateCalendar({ ...base, emit_days: [1, 1] })).toEqual({ ok: false, error: 'bad_day' })
  })
  it('hora 24 → bad_hour', () => {
    expect(validateCalendar({ ...base, emit_hour: 24 })).toEqual({ ok: false, error: 'bad_hour' })
  })
  it('hora negativa o decimal → bad_hour', () => {
    expect(validateCalendar({ ...base, emit_hour: -1 }).error).toBe('bad_hour')
    expect(validateCalendar({ ...base, emit_hour: 2.5 }).error).toBe('bad_hour')
  })
})

describe('canManageCarrierKeys', () => {
  it('ni superadmin ni UPU AM → false', () => {
    expect(canManageCarrierKeys({ isSuperadmin: false, isUpuAm: false })).toBe(false)
  })
  it('cualquiera de los dos → true', () => {
    expect(canManageCarrierKeys({ isSuperadmin: true, isUpuAm: false })).toBe(true)
    expect(canManageCarrierKeys({ isSuperadmin: false, isUpuAm: true })).toBe(true)
  })
})

describe('connectorErrorKey', () => {
  it('los CL_* usan el mapa común', () => {
    expect(connectorErrorKey({ message: 'CL_FORBIDDEN' })).toBe('cl.error.cl_forbidden')
  })
  it('clave repetida, en uso o valor no válido tienen su mensaje', () => {
    expect(connectorErrorKey({ code: '23505', message: 'dup' })).toBe('cl.connectors.error.duplicate')
    expect(connectorErrorKey({ code: '23503', message: 'fk' })).toBe('cl.connectors.error.in_use')
    expect(connectorErrorKey({ code: '23514', message: 'check' })).toBe('cl.connectors.error.invalid_value')
  })
  it('resto → genérico', () => {
    expect(connectorErrorKey({ message: 'boom' })).toBe('cl.error.generic')
  })
})

