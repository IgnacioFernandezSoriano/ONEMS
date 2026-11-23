import { describe, it, expect } from 'vitest'
import { isoWeekOf } from '../carrierLink/quotaCalculator'

describe('isoWeekOf', () => {
  it('handles year boundaries', () => {
    expect(isoWeekOf(new Date('2026-12-31T12:00:00'))).toEqual({ iso_year: 2026, iso_week: 53 })
    expect(isoWeekOf(new Date('2027-01-04T12:00:00'))).toEqual({ iso_year: 2027, iso_week: 1 })
  })
})
