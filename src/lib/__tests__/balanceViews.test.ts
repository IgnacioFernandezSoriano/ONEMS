import { describe, it, expect } from 'vitest'
import { cityHasChanges, cityIdsToApply, totalsForAllCities, groupMatrixByWeek, isCityFailed, type AllCitiesRow } from '../balanceViews'
import type { BalanceResult } from '../../hooks/useNodeLoadBalancing'

const dfr = (removed: number, reassigned_dest: number, reintroduced: number, waiting: number, blocked = 0) => ({
  removed, reassigned_dest, reintroduced, waiting, blocked,
  by_reason: { origin_no_panelist: 0, dest_no_panelist: 0, no_valid_day: 0 },
})

const res = (o: Partial<BalanceResult>): BalanceResult => ({
  success: true, movements_count: 0, stddev_before: 0, stddev_after: 0, improvement_percentage: 0,
  movements: [], message: '', error: null, ...o,
})

describe('totalsForAllCities', () => {
  const rows: AllCitiesRow[] = [
    { cityId: 'a', cityName: 'A', result: res({ movements_count: 5, deferred: dfr(2, 1, 3, 4), pobox: { days_missing: 3, days_moved: 1, days_created: 2, days_uncovered: 0 }, warnings: [{ code: 'x', count: 1, detail: null }] }) },
    { cityId: 'b', cityName: 'B', result: res({ movements_count: 7, deferred: dfr(1, 0, 0, 5), pobox: { days_missing: 2, days_moved: 2, days_created: 0, days_uncovered: 1 } }) },
    { cityId: 'c', cityName: 'C', error: 'boom' },
    { cityId: 'd', cityName: 'D', result: res({ success: false, error: 'bad', movements_count: 99, deferred: dfr(50, 50, 50, 50) }) },
  ]
  it('suma solo ciudades correctas y cuenta fallidas', () => {
    expect(totalsForAllCities(rows)).toEqual({
      cities: 4, failed: 2, movements: 12, poboxMoved: 3, poboxCreated: 2, poboxUncovered: 1, warnings: 1,
      deferredRemoved: 3, deferredReassignedDest: 1, deferredReintroduced: 3, deferredWaiting: 9,
    })
  })
  it('isCityFailed', () => {
    expect(isCityFailed(rows[0])).toBe(false)
    expect(isCityFailed(rows[2])).toBe(true)
    expect(isCityFailed(rows[3])).toBe(true)
  })
})

describe('cityHasChanges con muestras por compensar', () => {
  it('apartar, reasignar o reintroducir cuentan como cambios aunque no haya movimientos', () => {
    expect(cityHasChanges(res({ deferred: dfr(1, 0, 0, 0) }))).toBe(true)
    expect(cityHasChanges(res({ deferred: dfr(0, 2, 0, 0) }))).toBe(true)
    expect(cityHasChanges(res({ deferred: dfr(0, 0, 3, 0) }))).toBe(true)
    expect(cityHasChanges(res({ deferred: dfr(0, 0, 0, 7, 2) }))).toBe(false)
  })
})

describe('cityIdsToApply', () => {
  it('solo ciudades no fallidas y con cambios', () => {
    const rows: AllCitiesRow[] = [
      { cityId: 'a', cityName: 'A', result: res({ movements_count: 2 }) },
      { cityId: 'b', cityName: 'B', result: res({ movements_count: 0 }) },
      { cityId: 'c', cityName: 'C', result: res({ movements_count: 0, pobox: { days_missing: 1, days_moved: 0, days_created: 1, days_uncovered: 0 } }) },
      { cityId: 'd', cityName: 'D', error: 'x' },
      { cityId: 'e', cityName: 'E', result: res({ success: false, error: 'bad', movements_count: 5 }) },
    ]
    expect(cityIdsToApply(rows)).toEqual(['a', 'c'])
  })
})

describe('groupMatrixByWeek', () => {
  it('suma dias por semana y ordena', () => {
    const m = groupMatrixByWeek([
      { node_code: 'N2', week_num: 6, week_start: '2027-02-08', day: '2027-02-08', load_count: 4 },
      { node_code: 'N1', week_num: 5, week_start: '2027-02-01', day: '2027-02-01', load_count: 1 },
      { node_code: 'N1', week_num: 5, week_start: '2027-02-01', day: '2027-02-02', load_count: 2 },
      { node_code: 'N1', week_num: 6, week_start: '2027-02-08', day: null, load_count: 3 },
    ])
    expect(m.nodes).toEqual(['N1', 'N2'])
    expect(m.weeks).toEqual([{ key: '2027-02-01', weekNum: 5 }, { key: '2027-02-08', weekNum: 6 }])
    expect(m.lookup['N1|2027-02-01']).toBe(3)
    expect(m.lookup['N1|2027-02-08']).toBe(3)
    expect(m.lookup['N2|2027-02-08']).toBe(4)
  })
})
