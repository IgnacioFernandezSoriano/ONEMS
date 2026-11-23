import { describe, it, expect } from 'vitest'
import { captureMethodOf, carriersForCapture, captureOptionsFor, carrierWritePayload } from '../carrierCapture'

type C = { id: string; capture_method?: string | null }
const ids = (l: C[]) => l.map((c) => c.id)

const list: C[] = [
  { id: 'p', capture_method: 'panelists' },
  { id: 'cl', capture_method: 'carrier_link' },
  { id: 'b', capture_method: 'both' },
  { id: 'none' },
  { id: 'null', capture_method: null },
]

describe('captureMethodOf', () => {
  it('devuelve el valor conocido', () => {
    expect(captureMethodOf({ capture_method: 'carrier_link' })).toBe('carrier_link')
    expect(captureMethodOf({ capture_method: 'both' })).toBe('both')
  })
  it('sin valor o desconocido cuenta como panelists', () => {
    expect(captureMethodOf({})).toBe('panelists')
    expect(captureMethodOf({ capture_method: null })).toBe('panelists')
    expect(captureMethodOf({ capture_method: 'otro' })).toBe('panelists')
  })
})

describe('carriersForCapture', () => {
  it('el generador E2E ofrece panelistas y ambos (sin valor = panelistas)', () => {
    expect(ids(carriersForCapture(list, 'panelists'))).toEqual(['p', 'b', 'none', 'null'])
  })
  it('Carrier Link ofrece carrier_link y ambos', () => {
    expect(ids(carriersForCapture(list, 'carrier_link'))).toEqual(['cl', 'b'])
  })
  it('cuenta solo de panelistas (Kenya/Senegal): el E2E ve todos, Carrier Link ninguno', () => {
    const k: C[] = [{ id: 'a', capture_method: 'panelists' }, { id: 'b', capture_method: 'panelists' }]
    expect(ids(carriersForCapture(k, 'panelists'))).toEqual(['a', 'b'])
    expect(carriersForCapture(k, 'carrier_link')).toEqual([])
  })
})

describe('captureOptionsFor', () => {
  it('both -> las dos capturas', () => {
    expect(captureOptionsFor({ capture_method: 'both' })).toEqual(['panelists', 'carrier_link'])
  })
  it('un solo valor -> solo esa captura (sin valor = panelists)', () => {
    expect(captureOptionsFor({ capture_method: 'carrier_link' })).toEqual(['carrier_link'])
    expect(captureOptionsFor({ capture_method: 'panelists' })).toEqual(['panelists'])
    expect(captureOptionsFor({})).toEqual(['panelists'])
  })
})

describe('carrierWritePayload', () => {
  const data = { code: 'C', name: 'N', status: 'active', capture_method: 'both' as const }
  it('con Carrier Link envía capture_method', () => {
    expect(carrierWritePayload(data, true)).toEqual(data)
  })
  it('sin Carrier Link no envía capture_method (producción como siempre)', () => {
    const out = carrierWritePayload(data, false)
    expect(out).toEqual({ code: 'C', name: 'N', status: 'active' })
    expect('capture_method' in out).toBe(false)
    expect(data.capture_method).toBe('both')
  })
})
