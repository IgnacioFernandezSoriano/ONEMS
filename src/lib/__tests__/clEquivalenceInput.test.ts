import { describe, it, expect } from 'vitest'
import { parseEquivalenceInput } from '../carrierLink/equivalenceInput'

describe('parseEquivalenceInput', () => {
  it('vacío es 0', () => {
    expect(parseEquivalenceInput('')).toBe(0)
    expect(parseEquivalenceInput('  ')).toBe(0)
  })
  it('acepta punto y coma decimal', () => {
    expect(parseEquivalenceInput('1,5')).toBe(1.5)
    expect(parseEquivalenceInput('2.25')).toBe(2.25)
    expect(parseEquivalenceInput('0')).toBe(0)
  })
  it('rechaza negativos y no numéricos', () => {
    expect(parseEquivalenceInput('-1')).toBeNull()
    expect(parseEquivalenceInput('abc')).toBeNull()
    expect(parseEquivalenceInput('1,2,3')).toBeNull()
    expect(parseEquivalenceInput('1e3')).toBeNull()
  })
})
