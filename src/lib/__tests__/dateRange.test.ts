import { describe, expect, it } from 'vitest'
import { isUsablePeriod } from '../dateRange'

describe('isUsablePeriod', () => {
  it('acepta un periodo completo y ordenado', () => {
    expect(isUsablePeriod('2026-07-01', '2026-09-30')).toBe(true)
    expect(isUsablePeriod('2026-07-01', '2026-07-01')).toBe(true)
  })

  it('rechaza fechas vacias o incompletas', () => {
    expect(isUsablePeriod('', '')).toBe(false)
    expect(isUsablePeriod('2026-07-01', '')).toBe(false)
    expect(isUsablePeriod('2026-07', '2026-09-30')).toBe(false)
  })

  it('rechaza anyos intermedios al teclear (0002, 0202)', () => {
    expect(isUsablePeriod('0002-07-01', '2026-09-30')).toBe(false)
    expect(isUsablePeriod('0202-07-01', '2026-09-30')).toBe(false)
    expect(isUsablePeriod('2026-07-01', '0002-09-30')).toBe(false)
  })

  it('rechaza inicio posterior al fin (pasa mientras se cambia de julio a septiembre)', () => {
    expect(isUsablePeriod('2026-09-01', '2026-07-31')).toBe(false)
  })
})
