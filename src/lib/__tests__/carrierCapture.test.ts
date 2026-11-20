import { describe, it, expect } from 'vitest'
import { captureMethodOf, carriersForCapture } from '../carrierCapture'

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
