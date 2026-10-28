import { describe, it, expect } from 'vitest'
import {
  workingDowsFromSchedule,
  isWorkingDay,
  localDateKey,
  firstWorkingDayOfWeek,
  unavailabilityKeys,
  effectivePolicy,
  type WorkingCalendar,
} from '../workingDays'

const calOf = (rows: Array<{ day_of_week: number; is_working_day: boolean }>, non: string[] = []): WorkingCalendar => ({
  workingDows: workingDowsFromSchedule(rows),
  nonWorkingDays: new Set(non),
})

describe('workingDays', () => {
  it('sin horario: lunes a viernes', () => {
    const cal = calOf([])
    expect([...cal.workingDows].sort()).toEqual([1, 2, 3, 4, 5])
    expect(isWorkingDay(new Date(2027, 2, 6), cal)).toBe(false)
    expect(isWorkingDay(new Date(2027, 2, 8), cal)).toBe(true)
  })

  it('horario domingo a jueves', () => {
    const cal = calOf([0, 1, 2, 3, 4, 5, 6].map(d => ({ day_of_week: d, is_working_day: d <= 4 })))
    expect(isWorkingDay(new Date(2027, 2, 7), cal)).toBe(true)
    expect(isWorkingDay(new Date(2027, 2, 5), cal)).toBe(false)
  })

  it('filas parciales: cada dia sin fila usa el defecto lunes-viernes', () => {
    expect([...workingDowsFromSchedule([{ day_of_week: 1, is_working_day: false }])].sort()).toEqual([2, 3, 4, 5])
    expect([...workingDowsFromSchedule([{ day_of_week: 6, is_working_day: true }])].sort()).toEqual([1, 2, 3, 4, 5, 6])
  })

  it('ignora filas de centro postal', () => {
    const rows = [
      { day_of_week: 6, is_working_day: true, postal_center_id: 'pc1' },
      { day_of_week: 1, is_working_day: false, postal_center_id: 'pc1' },
    ]
    expect([...workingDowsFromSchedule(rows)].sort()).toEqual([1, 2, 3, 4, 5])
  })

  it('dia no laborable de la cuenta', () => {
    const cal = calOf([], ['2027-03-08'])
    expect(isWorkingDay(new Date(2027, 2, 8), cal)).toBe(false)
  })

  it('localDateKey usa fecha local', () => {
    expect(localDateKey(new Date(2027, 0, 5, 23, 59))).toBe('2027-01-05')
  })

  it('firstWorkingDayOfWeek', () => {
    const cal = calOf([])
    const r = firstWorkingDayOfWeek(new Date(2027, 2, 10), cal, new Date(2027, 2, 9))
    expect(r && localDateKey(r)).toBe('2027-03-09')
    const b = firstWorkingDayOfWeek(new Date(2027, 2, 10), cal, new Date(2027, 2, 9), new Set(['2027-03-09']))
    expect(b && localDateKey(b)).toBe('2027-03-10')
    const all = new Set(['2027-03-08', '2027-03-09', '2027-03-10', '2027-03-11', '2027-03-12'])
    expect(firstWorkingDayOfWeek(new Date(2027, 2, 10), cal, undefined, all)).toBeNull()
  })

  it('unavailabilityKeys: inclusivo, varios periodos, fin antes de inicio ignorado', () => {
    const m = unavailabilityKeys([
      { node_id: 'a', start_date: '2027-03-08', end_date: '2027-03-10' },
      { node_id: 'a', start_date: '2027-03-15', end_date: '2027-03-15' },
      { node_id: 'b', start_date: '2027-03-10', end_date: '2027-03-01' },
    ])
    expect([...(m.get('a') ?? [])].sort()).toEqual(['2027-03-08', '2027-03-09', '2027-03-10', '2027-03-15'])
    expect(m.get('b')?.size ?? 0).toBe(0)
  })

  it('effectivePolicy', () => {
    expect(effectivePolicy({ date_policy: 'weekly', pobox_enabled: false }, { date_policy: null, pobox_enabled: true }))
      .toEqual({ datePolicy: 'daily', pobox: true })
    expect(effectivePolicy({ date_policy: 'weekly', pobox_enabled: false }, null))
      .toEqual({ datePolicy: 'weekly', pobox: false })
    expect(effectivePolicy({ date_policy: 'weekly', pobox_enabled: true }, { date_policy: 'weekly', pobox_enabled: false }))
      .toEqual({ datePolicy: 'weekly', pobox: false })
  })
})
