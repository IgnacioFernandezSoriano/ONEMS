import { describe, expect, it } from 'vitest'
import { CSV_MAX_ROWS, csvCell, csvDate, csvFileName, fetchCapped, toCsv } from '../carrierLink/clCsv'

describe('csvCell', () => {
  it('empties null and undefined', () => {
    expect(csvCell(null)).toBe('')
    expect(csvCell(undefined)).toBe('')
  })
  it('writes numbers and booleans as they are', () => {
    expect(csvCell(-12.5)).toBe('-12.5')
    expect(csvCell(true)).toBe('true')
  })
  it('quotes commas, quotes and line breaks', () => {
    expect(csvCell('a,b')).toBe('"a,b"')
    expect(csvCell('say "hi"')).toBe('"say ""hi"""')
    expect(csvCell('l1\nl2')).toBe('"l1\nl2"')
  })
  it('neutralises spreadsheet formulas in text', () => {
    expect(csvCell('=HYPERLINK("x")')).toBe(`"'=HYPERLINK(""x"")"`)
    expect(csvCell('+34')).toBe("'+34")
    expect(csvCell('-1')).toBe("'-1")
    expect(csvCell('@SUM')).toBe("'@SUM")
    expect(csvCell('\tx')).toBe("'\tx")
  })
  it('keeps Arabic and accents untouched', () => {
    expect(csvCell('مكتب')).toBe('مكتب')
    expect(csvCell('Málaga')).toBe('Málaga')
  })
})

describe('toCsv', () => {
  it('header plus rows with CRLF', () => {
    expect(toCsv(['A', 'B'], [[1, 'x'], [null, 'y,z']])).toBe('A,B\r\n1,x\r\n,"y,z"')
  })
})

describe('csvDate', () => {
  it('local YYYY-MM-DD HH:MM, empty for null', () => {
    const d = new Date(2026, 10, 24, 9, 5)
    expect(csvDate(d.toISOString())).toBe('2026-11-24 09:05')
    expect(csvDate(null)).toBe('')
  })
  it('a plain date stays a date', () => {
    expect(csvDate('2026-11-24')).toBe('2026-11-24')
  })
})

describe('csvFileName', () => {
  it('base plus local timestamp', () => {
    expect(csvFileName('cl-samples', new Date(2026, 10, 25, 7, 3))).toBe('cl-samples_20261125-0703.csv')
  })
  it('unsafe characters of a carrier value become _', () => {
    expect(csvFileName('cl-scans-AB/12 x', new Date(2026, 10, 25, 7, 3))).toBe('cl-scans-AB_12_x_20261125-0703.csv')
  })
})

describe('fetchCapped', () => {
  const source = (n: number) => (from: number, to: number) =>
    Promise.resolve({ data: Array.from({ length: Math.max(0, Math.min(to, n - 1) - from + 1) }, (_, i) => from + i), error: null })

  it('reads every page', async () => {
    const r = await fetchCapped(source(2500))
    expect(r.rows.length).toBe(2500)
    expect(r.truncated).toBe(false)
    expect(r.rows[2499]).toBe(2499)
  })
  it('stops at the cap and says so', async () => {
    const r = await fetchCapped(source(3000), 2000)
    expect(r.rows.length).toBe(2000)
    expect(r.truncated).toBe(true)
  })
  it('exactly the cap is not truncated', async () => {
    const r = await fetchCapped(source(2000), 2000)
    expect(r.truncated).toBe(false)
  })
  it('throws the page error', async () => {
    await expect(fetchCapped(() => Promise.resolve({ data: null, error: { message: 'x' } }))).rejects.toEqual({ message: 'x' })
  })
  it('default cap is 50.000', () => {
    expect(CSV_MAX_ROWS).toBe(50000)
  })
})
