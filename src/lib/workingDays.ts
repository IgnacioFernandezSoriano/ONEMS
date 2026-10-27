export type DatePolicy = 'weekly' | 'daily'

export interface WorkingCalendar {
  /** 0..6, convencion de getDay() (0 = domingo) */
  workingDows: Set<number>
  /** yyyy-MM-dd */
  nonWorkingDays: Set<string>
}

export function localDateKey(d: Date): string {
  const m = String(d.getMonth() + 1).padStart(2, '0')
  const day = String(d.getDate()).padStart(2, '0')
  return `${d.getFullYear()}-${m}-${day}`
}

export function workingDowsFromSchedule(
  rows: Array<{ day_of_week: number; is_working_day: boolean }>
): Set<number> {
  if (!rows || rows.length === 0) return new Set([1, 2, 3, 4, 5])
  return new Set(rows.filter(r => r.is_working_day).map(r => r.day_of_week))
}

export function isWorkingDay(d: Date, cal: WorkingCalendar): boolean {
  return cal.workingDows.has(d.getDay()) && !cal.nonWorkingDays.has(localDateKey(d))
}

/**
 * Primer dia laborable de la semana ISO (lunes a domingo) que contiene `anyDayOfWeek`,
 * >= notBefore (por fecha de calendario) y no bloqueado. null si no hay ninguno.
 */
export function firstWorkingDayOfWeek(
  anyDayOfWeek: Date,
  cal: WorkingCalendar,
  notBefore?: Date,
  blocked?: Set<string>
): Date | null {
  const base = new Date(anyDayOfWeek.getFullYear(), anyDayOfWeek.getMonth(), anyDayOfWeek.getDate())
  const sinceMonday = (base.getDay() + 6) % 7
  const floor = notBefore
    ? new Date(notBefore.getFullYear(), notBefore.getMonth(), notBefore.getDate()).getTime()
    : null
  for (let i = 0; i < 7; i++) {
    const d = new Date(base.getFullYear(), base.getMonth(), base.getDate() - sinceMonday + i)
    if (floor !== null && d.getTime() < floor) continue
    if (!isWorkingDay(d, cal)) continue
    if (blocked && blocked.has(localDateKey(d))) continue
    return d
  }
  return null
}

function parseKey(s: string): Date {
  const [y, m, d] = s.slice(0, 10).split('-').map(Number)
  return new Date(y, m - 1, d)
}

export function unavailabilityKeys(
  periods: Array<{ node_id: string; start_date: string; end_date: string }>
): Map<string, Set<string>> {
  const out = new Map<string, Set<string>>()
  for (const p of periods) {
    let set = out.get(p.node_id)
    if (!set) {
      set = new Set()
      out.set(p.node_id, set)
    }
    const start = parseKey(p.start_date)
    const end = parseKey(p.end_date)
    for (let d = start; d.getTime() <= end.getTime(); d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
      set.add(localDateKey(d))
    }
  }
  return out
}

export function effectivePolicy(
  account: { date_policy: DatePolicy; pobox_enabled: boolean },
  city?: { date_policy: DatePolicy | null; pobox_enabled: boolean | null } | null
): { datePolicy: DatePolicy; pobox: boolean } {
  const pobox = city?.pobox_enabled ?? account.pobox_enabled
  const base = city?.date_policy ?? account.date_policy
  return { datePolicy: pobox ? 'daily' : base, pobox }
}
