import { describe, it, expect } from 'vitest'
import {
  quotaMatrix,
  groupQuotaMatrix,
  originGroups,
  buildPlanRow,
  nextExpandedGroups,
  type QuotaInput,
} from '../carrierLink/planView'

const names: Record<string, string> = { A: 'Alpha', B: 'Beta', C: 'Gamma' }
const cityName = (id: string) => names[id] ?? id

const q = (o: string, d: string, y: number, w: number, planned: number, carried = 0, obtained = 0, status = 'pending'): QuotaInput => ({
  origin_city_id: o,
  destination_city_id: d,
  iso_year: y,
  iso_week: w,
  samples_planned: planned,
  samples_carried_in: carried,
  samples_obtained: obtained,
  status,
})

const sumTotals = (rows: { total: number }[]) => rows.reduce((a, r) => a + r.total, 0)

describe('quotaMatrix', () => {
  it('2 routes x 2 weeks: sorted weeks, carried kept, total = planned + carried, missing week = null', () => {
    const m = quotaMatrix(
      [q('A', 'B', 2026, 46, 2), q('A', 'B', 2026, 45, 3, 1, 2, 'fulfilled'), q('A', 'C', 2026, 45, 4)],
      cityName,
    )
    expect(m.weeks).toEqual(['2026-W45', '2026-W46'])
    expect(m.rows.map((r) => r.route)).toEqual(['Alpha → Beta', 'Alpha → Gamma'])
    const ab = m.rows[0]
    expect(ab.cells['2026-W45']).toEqual({ planned: 3, carried: 1, obtained: 2, status: 'fulfilled' })
    expect(ab.total).toBe(3 + 1 + 2)
    expect(m.rows[1].cells['2026-W46']).toBeNull()
    expect(m.rows[1].total).toBe(4)
  })

  it('orders 2026-W53 before 2027-W01', () => {
    const m = quotaMatrix([q('A', 'B', 2027, 1, 1), q('A', 'B', 2026, 53, 1), q('A', 'B', 2026, 52, 1)], cityName)
    expect(m.weeks).toEqual(['2026-W52', '2026-W53', '2027-W01'])
  })
})

describe('groupQuotaMatrix', () => {
  const m = quotaMatrix(
    [
      q('A', 'B', 2026, 53, 2), // lunes 28/12/2026 -> 2026-12
      q('A', 'B', 2027, 1, 3, 1), // lunes 04/01/2027 -> 2027-01
      q('A', 'B', 2027, 2, 4, 0, 1), // lunes 11/01/2027 -> 2027-01
      q('A', 'C', 2027, 5, 5), // lunes 01/02/2027 -> 2027-02
    ],
    cityName,
  )

  it('by week returns the same matrix', () => {
    expect(groupQuotaMatrix(m, 'week')).toEqual(m)
  })

  it('by month sums the weeks whose Monday falls in that month and keeps the total', () => {
    const g = groupQuotaMatrix(m, 'month')
    expect(g.weeks).toEqual(['2026-12', '2027-01', '2027-02'])
    const ab = g.rows.find((r) => r.route === 'Alpha → Beta')!
    expect(ab.cells['2027-01']).toEqual({ planned: 7, carried: 1, obtained: 1, status: 'pending' })
    expect(ab.cells['2027-02']).toBeNull()
    expect(sumTotals(g.rows)).toBe(sumTotals(m.rows))
    expect(ab.total).toBe(m.rows.find((r) => r.route === 'Alpha → Beta')!.total)
  })

  it('mixed statuses in a month become "mixed"', () => {
    const mm = quotaMatrix([q('A', 'B', 2027, 1, 1, 0, 1, 'fulfilled'), q('A', 'B', 2027, 2, 1, 0, 0, 'open')], cityName)
    expect(groupQuotaMatrix(mm, 'month').rows[0].cells['2027-01']!.status).toBe('mixed')
  })
})

describe('originGroups', () => {
  it('870 routes over 30 cities give 30 groups whose totals add up to the matrix total', () => {
    const cities = Array.from({ length: 30 }, (_, i) => `c${String(i).padStart(2, '0')}`)
    const quotas: QuotaInput[] = []
    let n = 0
    for (const o of cities) for (const d of cities) if (o !== d) quotas.push(q(o, d, 2027, 1 + (n++ % 52), 1 + (n % 3)))
    const m = quotaMatrix(quotas, (id) => id)
    expect(m.rows).toHaveLength(870)
    const groups = originGroups(m.rows)
    expect(groups).toHaveLength(30)
    expect(groups.every((g) => g.rows.length === 29)).toBe(true)
    expect(groups.reduce((a, g) => a + g.total, 0)).toBe(sumTotals(m.rows))
  })

  it('group totals per column add the planned + carried of its routes', () => {
    const m = quotaMatrix([q('A', 'B', 2026, 45, 2, 1), q('A', 'C', 2026, 45, 3), q('B', 'C', 2026, 45, 1)], cityName)
    const [alpha, beta] = originGroups(m.rows)
    expect(alpha.origin).toBe('Alpha')
    expect(alpha.cells['2026-W45']).toEqual({ planned: 5, carried: 1, obtained: 0 })
    expect(beta.total).toBe(1)
  })
})

describe('nextExpandedGroups', () => {
  const size = (g: string) => ({ a: 1500, b: 1500, c: 100 })[g] ?? 0
  it('opens several groups while they fit in 2,000 cells', () => {
    expect(nextExpandedGroups(['c'], 'a', size)).toEqual(['c', 'a'])
  })
  it('keeps only the new group when the total would exceed 2,000 cells', () => {
    expect(nextExpandedGroups(['a'], 'b', size)).toEqual(['b'])
  })
  it('closes an open group', () => {
    expect(nextExpandedGroups(['a', 'c'], 'a', size)).toEqual(['c'])
  })
})

describe('buildPlanRow', () => {
  const f = {
    plan_name: '  Plan 2027 ',
    carrier_id: 'car',
    product_id: 'prod',
    feed_id: 'feed',
    start_date: '2027-01-01',
    end_date: '2027-12-31',
    total_samples: 15000,
    feed_diagnosis: false,
  }
  it('no account -> no_account', () => {
    expect(buildPlanRow(null, f)).toEqual({ ok: false, error: 'no_account' })
  })
  it('end before start -> bad_period', () => {
    expect(buildPlanRow('acc', { ...f, end_date: '2026-12-31' })).toEqual({ ok: false, error: 'bad_period' })
  })
  it('total 0 -> bad_total', () => {
    expect(buildPlanRow('acc', { ...f, total_samples: 0 })).toEqual({ ok: false, error: 'bad_total' })
  })
  it('missing name or product -> missing_field', () => {
    expect(buildPlanRow('acc', { ...f, plan_name: '  ' })).toEqual({ ok: false, error: 'missing_field' })
    expect(buildPlanRow('acc', { ...f, product_id: '' })).toEqual({ ok: false, error: 'missing_field' })
  })
  it('valid form -> row with account and trimmed name; empty connector is null', () => {
    const r = buildPlanRow('acc', { ...f, feed_id: '' })
    expect(r).toEqual({
      ok: true,
      row: {
        account_id: 'acc',
        plan_name: 'Plan 2027',
        carrier_id: 'car',
        product_id: 'prod',
        feed_id: null,
        start_date: '2027-01-01',
        end_date: '2027-12-31',
        total_samples: 15000,
        feed_diagnosis: false,
      },
    })
  })
})
