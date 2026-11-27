import type { QuotaInput } from './planView'
import { weekKey } from './sampleView'

/**
 * Balanceo de Carga de un plan de Carrier Link (misma pantalla que E2E). Los "nodos" son las ciudades de origen y la
 * carga es samples_planned por semana ISO. No hay máximo por panelista: la referencia es la media esperada de cada
 * origen según el calendario del plan (días laborables de cada semana).
 *
 * La propuesta solo cambia CUÁNDO se capturan las muestras: mueve muestras de semanas cargadas a semanas con hueco
 * dentro de la misma ciudad de origen y de la misma ruta (el total del plan, el de cada origen y el de cada ruta no
 * cambian). Solo se tocan cuotas movibles: pendientes y, en un plan activo, de semanas posteriores al fence (igual
 * que cl_plan_rebalance_quotas, que vuelve a comprobarlo todo).
 */

export type LoadLevel = 'normal' | 'high' | 'saturated'

export interface PlanWeek {
  /** 'YYYY-Www' */
  key: string
  iso_year: number
  iso_week: number
  /** Lunes de la semana (period_start de la cuota), 'YYYY-MM-DD'. */
  start: string
  /** Días laborables de la semana dentro de las fechas del plan (peso de la media esperada). */
  weight: number
  /** Se puede mover carga a o desde esta semana (borrador: todas; activo: lunes posterior al fence). */
  movable: boolean
}

export interface QuotaChange {
  origin_city_id: string
  destination_city_id: string
  iso_year: number
  iso_week: number
  samples: number
}

export interface OriginWeekCell {
  planned: number
  carried: number
  /** Parte de lo previsto que no se puede mover (cuotas no pendientes o dentro del fence). */
  locked: number
  expected: number
  level: LoadLevel
}

export interface OriginLoad {
  origin_city_id: string
  origin: string
  total: number
  carried: number
  routes: number
  cells: Record<string, OriginWeekCell>
  /** Desviación típica de la carga semanal respecto a la esperada. */
  stddev: number
  high: number
  saturated: number
  level: LoadLevel
}

export interface OriginProposal {
  origin_city_id: string
  origin: string
  moved: number
  stddevBefore: number
  stddevAfter: number
}

export interface BalanceProposal {
  changes: QuotaChange[]
  moved: number
  created: number
  zeroed: number
  origins: OriginProposal[]
}

const DAY = 86400000

function parseDate(d: string): number {
  const [y, m, dd] = d.split('-').map(Number)
  return Date.UTC(y, m - 1, dd)
}

function fmt(ms: number): string {
  return new Date(ms).toISOString().slice(0, 10)
}

export function addDays(date: string, n: number): string {
  return fmt(parseDate(date) + n * DAY)
}

/** Lunes de una semana ISO, 'YYYY-MM-DD'. */
export function isoWeekMonday(isoYear: number, isoWeek: number): string {
  const jan4 = Date.UTC(isoYear, 0, 4)
  const jan4Dow = (new Date(jan4).getUTCDay() + 6) % 7 // 0 = lunes
  return fmt(jan4 + ((isoWeek - 1) * 7 - jan4Dow) * DAY)
}

function isoWeekOfUtc(ms: number): { iso_year: number; iso_week: number } {
  const d = new Date(ms)
  const dow = d.getUTCDay() || 7
  const thu = ms + (4 - dow) * DAY
  const iso_year = new Date(thu).getUTCFullYear()
  const iso_week = Math.ceil(((thu - Date.UTC(iso_year, 0, 1)) / DAY + 1) / 7)
  return { iso_year, iso_week }
}

/**
 * Fence que se envía a cl_plan_rebalance_quotas: el de la pantalla; vacío = "sin fence", que en la base es un fence
 * anterior a hoy (ayer). Sin enviar nada la base usaría el domingo de la semana actual.
 */
export function fenceParam(fenceInput: string, today: string): string {
  return fenceInput || addDays(today, -1)
}

/** Último día congelado efectivo (como la base): borrador = sin fence; activo = el fence, nunca antes de ayer. */
export function effectiveFence(status: string, fenceInput: string, today: string): string | null {
  if (status !== 'active') return null
  const f = fenceParam(fenceInput, today)
  const yesterday = addDays(today, -1)
  return f > yesterday ? f : yesterday
}

/** Una cuota es movible si está pendiente y (sin fence) o su lunes es posterior al fence. Plan cerrado: nada. */
export function isQuotaMovable(q: Pick<QuotaInput, 'status' | 'iso_year' | 'iso_week'>, fence: string | null): boolean {
  if (q.status !== 'pending') return false
  return fence === null || isoWeekMonday(q.iso_year, q.iso_week) > fence
}

/**
 * Semanas ISO del plan con su peso (días laborables dentro de las fechas del plan) y si son movibles.
 * Sin ningún día laborable en todo el plan (calendario vacío), todas pesan 1.
 */
export function planWeeks(
  plan: { start_date: string; end_date: string; status: string },
  calendar: { workingDows: number[]; nonWorkingDays: string[] },
  fence: string | null,
): PlanWeek[] {
  const out: PlanWeek[] = []
  if (!plan.start_date || !plan.end_date || plan.end_date < plan.start_date) return out
  const dows = new Set(calendar.workingDows)
  const holidays = new Set(calendar.nonWorkingDays)
  const end = parseDate(plan.end_date)
  for (let ms = parseDate(plan.start_date); ms <= end; ms += DAY) {
    const { iso_year, iso_week } = isoWeekOfUtc(ms)
    const key = weekKey(iso_year, iso_week)
    let w = out[out.length - 1]
    if (!w || w.key !== key) {
      const start = isoWeekMonday(iso_year, iso_week)
      w = { key, iso_year, iso_week, start, weight: 0, movable: plan.status !== 'closed' && (fence === null || start > fence) }
      out.push(w)
    }
    const day = fmt(ms)
    if (dows.has(new Date(ms).getUTCDay()) && !holidays.has(day)) w.weight++
  }
  if (out.every((w) => w.weight === 0)) for (const w of out) w.weight = 1
  return out
}

/** Nivel como en E2E: Alta ≥ esperado × (1 + %), Saturada ≥ esperado × (1 + % × 1,5). Sin esperado y con carga: Saturada. */
export function loadLevel(load: number, expected: number, deviationPercent: number): LoadLevel {
  if (load <= 0) return 'normal'
  if (expected <= 0) return 'saturated'
  const p = Math.max(0, deviationPercent) / 100
  if (load >= expected * (1 + p * 1.5)) return 'saturated'
  if (load >= expected * (1 + p)) return 'high'
  return 'normal'
}

/** Desviación típica de la carga semanal respecto a la esperada (0 = reparto perfecto según el calendario). */
export function weeklyStddev(loads: number[], expected: number[]): number {
  if (loads.length === 0) return 0
  let s = 0
  for (let i = 0; i < loads.length; i++) s += (loads[i] - expected[i]) ** 2
  return Math.sqrt(s / loads.length)
}

function expectedShares(total: number, weeks: PlanWeek[]): number[] {
  const sum = weeks.reduce((a, w) => a + w.weight, 0)
  return weeks.map((w) => (sum > 0 ? (total * w.weight) / sum : 0))
}

const LEVEL_RANK: Record<LoadLevel, number> = { normal: 0, high: 1, saturated: 2 }

/** Carga por ciudad de origen y semana, con la media esperada y el nivel de cada semana. Orden: peor nivel, más desviación, nombre. */
export function originLoads(
  quotas: QuotaInput[],
  weeks: PlanWeek[],
  fence: string | null,
  cityName: (id: string) => string,
  deviationPercent: number,
): OriginLoad[] {
  const byOrigin = new Map<string, QuotaInput[]>()
  for (const q of quotas) {
    const arr = byOrigin.get(q.origin_city_id)
    if (arr) arr.push(q)
    else byOrigin.set(q.origin_city_id, [q])
  }
  const out: OriginLoad[] = []
  for (const [origin_city_id, qs] of byOrigin) {
    const ws = weeksWithExtra(weeks, qs, fence)
    const planned = new Map<string, number>()
    const carried = new Map<string, number>()
    const locked = new Map<string, number>()
    const routes = new Set<string>()
    let total = 0
    let carriedTotal = 0
    for (const q of qs) {
      const k = weekKey(q.iso_year, q.iso_week)
      planned.set(k, (planned.get(k) ?? 0) + q.samples_planned)
      carried.set(k, (carried.get(k) ?? 0) + q.samples_carried_in)
      if (!isQuotaMovable(q, fence)) locked.set(k, (locked.get(k) ?? 0) + q.samples_planned)
      routes.add(q.destination_city_id)
      total += q.samples_planned
      carriedTotal += q.samples_carried_in
    }
    const exp = expectedShares(total, ws)
    const cells: Record<string, OriginWeekCell> = {}
    let high = 0
    let saturated = 0
    let level: LoadLevel = 'normal'
    ws.forEach((w, i) => {
      const p = planned.get(w.key) ?? 0
      const lv = loadLevel(p, exp[i], deviationPercent)
      if (lv === 'high') high++
      if (lv === 'saturated') saturated++
      if (LEVEL_RANK[lv] > LEVEL_RANK[level]) level = lv
      cells[w.key] = { planned: p, carried: carried.get(w.key) ?? 0, locked: locked.get(w.key) ?? 0, expected: exp[i], level: lv }
    })
    out.push({
      origin_city_id,
      origin: cityName(origin_city_id),
      total,
      carried: carriedTotal,
      routes: routes.size,
      cells,
      stddev: weeklyStddev(ws.map((w) => planned.get(w.key) ?? 0), exp),
      high,
      saturated,
      level,
    })
  }
  return out.sort(
    (a, b) =>
      LEVEL_RANK[b.level] - LEVEL_RANK[a.level] ||
      b.stddev - a.stddev ||
      a.origin.localeCompare(b.origin) ||
      a.origin_city_id.localeCompare(b.origin_city_id),
  )
}

/** Semanas del plan más las de cuotas que caigan fuera (peso 0, para que su carga cuente y pueda salir). */
function weeksWithExtra(weeks: PlanWeek[], qs: QuotaInput[], fence: string | null): PlanWeek[] {
  const known = new Set(weeks.map((w) => w.key))
  const extra: PlanWeek[] = []
  for (const q of qs) {
    const key = weekKey(q.iso_year, q.iso_week)
    if (known.has(key)) continue
    known.add(key)
    const start = isoWeekMonday(q.iso_year, q.iso_week)
    extra.push({ key, iso_year: q.iso_year, iso_week: q.iso_week, start, weight: 0, movable: fence === null || start > fence })
  }
  if (extra.length === 0) return weeks
  return [...weeks, ...extra].sort((a, b) => a.start.localeCompare(b.start))
}

interface Cell {
  dest: string
  week: number // índice en ws
  value: number
  original: number
  movable: boolean
  exists: boolean
}

/**
 * Objetivo de lo movible por semana: llenado por niveles (cada muestra va a la semana movible con menor carga relativa
 * a su peso; empate: la más temprana). Las semanas de peso 0 no reciben.
 */
function targets(pool: number, lockedLoad: number[], ws: PlanWeek[]): number[] {
  const t = ws.map(() => 0)
  const idx = ws.map((w, i) => i).filter((i) => ws[i].movable && ws[i].weight > 0)
  if (idx.length === 0) return t
  for (let n = 0; n < pool; n++) {
    let best = -1
    let bestRatio = Infinity
    for (const i of idx) {
      const r = (lockedLoad[i] + t[i] + 1) / ws[i].weight
      if (r < bestRatio) {
        bestRatio = r
        best = i
      }
    }
    t[best]++
  }
  return t
}

/**
 * Reparte `total` entero en proporción a `weights` (resto mayor; empate: el primero). Si total <= suma de pesos,
 * nadie recibe más que su peso.
 */
export function apportion(total: number, weights: number[]): number[] {
  const W = weights.reduce((a, b) => a + b, 0)
  if (total <= 0 || W <= 0) return weights.map(() => 0)
  const raw = weights.map((w) => (total * w) / W)
  const out = raw.map((x) => Math.floor(x))
  let left = total - out.reduce((a, b) => a + b, 0)
  const order = raw.map((x, i) => i).sort((a, b) => raw[b] - out[b] - (raw[a] - out[a]) || a - b)
  for (const i of order) {
    if (left <= 0) break
    out[i]++
    left--
  }
  return out
}

function balanceOrigin(
  qs: QuotaInput[],
  weeks: PlanWeek[],
  fence: string | null,
): { cells: Cell[]; ws: PlanWeek[]; moved: number; before: number; after: number } | null {
  const ws = weeksWithExtra(weeks, qs, fence)
  const pos = new Map(ws.map((w, i) => [w.key, i]))
  const cells = new Map<string, Cell>()
  const cellKey = (dest: string, week: number) => `${dest}|${week}`
  const lockedLoad = ws.map(() => 0)
  const movableLoad = ws.map(() => 0)
  let pool = 0
  let total = 0
  for (const q of qs) {
    const week = pos.get(weekKey(q.iso_year, q.iso_week))!
    const movable = isQuotaMovable(q, fence)
    cells.set(cellKey(q.destination_city_id, week), {
      dest: q.destination_city_id,
      week,
      value: q.samples_planned,
      original: q.samples_planned,
      movable,
      exists: true,
    })
    total += q.samples_planned
    if (movable) {
      movableLoad[week] += q.samples_planned
      pool += q.samples_planned
    } else lockedLoad[week] += q.samples_planned
  }
  if (pool === 0) return null
  const t = targets(pool, lockedLoad, ws)
  if (t.every((x) => x === 0)) return null // ninguna semana puede recibir
  const exp = expectedShares(total, ws)
  const load = (mov: number[]) => ws.map((_, i) => lockedLoad[i] + mov[i])
  const before = weeklyStddev(load(movableLoad), exp)
  const after = weeklyStddev(load(t), exp)
  if (after >= before - 1e-9) return null // ya está tan equilibrado como se puede

  const surplus = ws.map((_, i) => Math.max(0, movableLoad[i] - t[i]))
  const deficit = ws.map((_, i) => Math.max(0, t[i] - movableLoad[i]))
  const byWeek = ws.map(() => [] as Cell[])
  for (const c of cells.values()) if (c.movable && c.value > 0) byWeek[c.week].push(c)
  for (const list of byWeek) list.sort((a, b) => a.dest.localeCompare(b.dest))

  let moved = 0
  const blocked = (dest: string, d: number) => {
    const c = cells.get(cellKey(dest, d))
    return !!c && !c.movable
  }
  const move = (from: Cell, d: number, n: number) => {
    from.value -= n
    let target = cells.get(cellKey(from.dest, d))
    if (!target) {
      target = { dest: from.dest, week: d, value: 0, original: 0, movable: true, exists: false }
      cells.set(cellKey(from.dest, d), target)
    }
    target.value += n
    surplus[from.week] -= n
    deficit[d] -= n
    moved += n
  }

  // 1) Cada semana cargada cede de cada ruta en proporción a lo que tiene (se conserva la mezcla de rutas) y cada
  //    semana con hueco recibe de esas cesiones en proporción, saltando rutas cuya cuota destino está bloqueada.
  const gives: { cell: Cell; amount: number }[] = []
  for (let s = 0; s < ws.length; s++) {
    if (surplus[s] <= 0) continue
    const list = byWeek[s]
    const parts = apportion(surplus[s], list.map((c) => c.value))
    list.forEach((c, i) => parts[i] > 0 && gives.push({ cell: c, amount: parts[i] }))
  }
  for (let d = 0; d < ws.length; d++) {
    if (deficit[d] <= 0) continue
    const eligible = gives.filter((g) => g.amount > 0 && !blocked(g.cell.dest, d))
    const avail = eligible.reduce((a, g) => a + g.amount, 0)
    const parts = apportion(Math.min(deficit[d], avail), eligible.map((g) => g.amount))
    eligible.forEach((g, i) => {
      if (parts[i] <= 0) return
      g.amount -= parts[i]
      move(g.cell, d, parts[i])
    })
  }
  // 2) Lo que no encontró sitio por bloqueos: de la ruta con más muestras que sí pueda ir a esa semana.
  for (let d = 0; d < ws.length; d++) {
    for (let s = 0; s < ws.length && deficit[d] > 0; s++) {
      while (surplus[s] > 0 && deficit[d] > 0) {
        let pick: Cell | null = null
        for (const c of byWeek[s]) if (c.value > 0 && !blocked(c.dest, d) && (!pick || c.value > pick.value)) pick = c
        if (!pick) break
        move(pick, d, Math.min(surplus[s], deficit[d], pick.value))
      }
    }
  }
  if (moved === 0) return null
  const finalMov = ws.map(() => 0)
  for (const c of cells.values()) if (c.movable) finalMov[c.week] += c.value
  return { cells: [...cells.values()], ws, moved, before, after: weeklyStddev(load(finalMov), exp) }
}

/**
 * Propuesta de balanceo. `origins` limita a esas ciudades de origen (botón de una ciudad: se balancea aunque esté dentro
 * de la tolerancia); sin `origins` se balancean las que tienen alguna semana Alta o Saturada.
 * Devuelve solo las cuotas que cambian, con su valor ABSOLUTO (lo que espera cl_plan_rebalance_quotas).
 */
export function proposeBalance(
  quotas: QuotaInput[],
  weeks: PlanWeek[],
  opts: { fence: string | null; deviationPercent: number; origins?: string[]; cityName?: (id: string) => string },
): BalanceProposal {
  const name = opts.cityName ?? ((id: string) => id)
  const byOrigin = new Map<string, QuotaInput[]>()
  for (const q of quotas) {
    const arr = byOrigin.get(q.origin_city_id)
    if (arr) arr.push(q)
    else byOrigin.set(q.origin_city_id, [q])
  }
  let candidates: string[]
  if (opts.origins) candidates = opts.origins.filter((o) => byOrigin.has(o))
  else {
    const out = new Set(
      originLoads(quotas, weeks, opts.fence, name, opts.deviationPercent)
        .filter((o) => o.level !== 'normal')
        .map((o) => o.origin_city_id),
    )
    candidates = [...byOrigin.keys()].filter((o) => out.has(o))
  }
  candidates.sort()

  const result: BalanceProposal = { changes: [], moved: 0, created: 0, zeroed: 0, origins: [] }
  for (const o of candidates) {
    const r = balanceOrigin(byOrigin.get(o)!, weeks, opts.fence)
    if (!r) continue
    const changed = r.cells
      .filter((c) => c.value !== c.original)
      .sort((a, b) => a.week - b.week || a.dest.localeCompare(b.dest))
    for (const c of changed) {
      const w = r.ws[c.week]
      result.changes.push({ origin_city_id: o, destination_city_id: c.dest, iso_year: w.iso_year, iso_week: w.iso_week, samples: c.value })
      if (!c.exists) result.created++
      if (c.value === 0) result.zeroed++
    }
    result.moved += r.moved
    result.origins.push({ origin_city_id: o, origin: name(o), moved: r.moved, stddevBefore: r.before, stddevAfter: r.after })
  }
  return result
}

/** Cuotas tras aplicar una propuesta (para mostrar el "después" sin volver a leer). */
export function applyChanges(quotas: QuotaInput[], changes: QuotaChange[]): QuotaInput[] {
  const key = (o: string, d: string, y: number, w: number) => `${o}|${d}|${y}|${w}`
  const byKey = new Map(changes.map((c) => [key(c.origin_city_id, c.destination_city_id, c.iso_year, c.iso_week), c]))
  const seen = new Set<string>()
  const out = quotas.map((q) => {
    const k = key(q.origin_city_id, q.destination_city_id, q.iso_year, q.iso_week)
    const c = byKey.get(k)
    if (!c) return q
    seen.add(k)
    return { ...q, samples_planned: c.samples }
  })
  for (const [k, c] of byKey) {
    if (seen.has(k)) continue
    out.push({
      origin_city_id: c.origin_city_id,
      destination_city_id: c.destination_city_id,
      iso_year: c.iso_year,
      iso_week: c.iso_week,
      samples_planned: c.samples,
      samples_carried_in: 0,
      samples_obtained: 0,
      status: 'pending',
    })
  }
  return out
}

/**
 * Planes de Carrier Link que ofrece el selector del Balanceo de Carga: borradores y activos. Sin la condición de
 * Carrier Link (producción, sin permiso o sin carriers de Carrier Link) ninguno: la página es la de siempre.
 */
export function balancingPlanOptions<T extends { status: string }>(clOn: boolean, plans: T[]): T[] {
  return clOn ? plans.filter((p) => p.status === 'draft' || p.status === 'active') : []
}
