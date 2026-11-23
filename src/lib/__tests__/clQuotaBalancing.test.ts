import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import type { QuotaInput } from '../carrierLink/planView'
import {
  addDays,
  applyChanges,
  effectiveFence,
  fenceParam,
  isoWeekMonday,
  isQuotaMovable,
  loadLevel,
  originLoads,
  planWeeks,
  proposeBalance,
  weeklyStddev,
} from '../carrierLink/quotaBalancing'
import { carrierLinkPlansVisible } from '../carrierLink/planRecords'
import { balancingPlanOptions } from '../carrierLink/quotaBalancing'


const q = (o: string, d: string, w: number, n: number, status = 'pending', y = 2027): QuotaInput => ({
  origin_city_id: o,
  destination_city_id: d,
  iso_year: y,
  iso_week: w,
  samples_planned: n,
  samples_carried_in: 0,
  samples_obtained: 0,
  status,
})

const MON_FRI = { workingDows: [1, 2, 3, 4, 5], nonWorkingDays: [] as string[] }
// 2027-W01 empieza el lunes 2027-01-04; cuatro semanas completas: W01..W04.
const draft4 = { start_date: '2027-01-04', end_date: '2027-01-31', status: 'draft' }

const sum = (xs: number[]) => xs.reduce((a, b) => a + b, 0)
const totalsBy = (qs: QuotaInput[], key: (q: QuotaInput) => string) => {
  const m = new Map<string, number>()
  for (const x of qs) m.set(key(x), (m.get(key(x)) ?? 0) + x.samples_planned)
  for (const [k, v] of m) if (v === 0) m.delete(k)
  return m
}

describe('fechas y fence (mismas reglas que cl_plan_rebalance_quotas)', () => {
  it('lunes de una semana ISO', () => {
    expect(isoWeekMonday(2027, 1)).toBe('2027-01-04')
    expect(isoWeekMonday(2026, 53)).toBe('2026-12-28')
    expect(isoWeekMonday(2026, 47)).toBe('2026-11-16')
  })
  it('fence vacío = sin fence (ayer); con fecha se envía tal cual', () => {
    expect(fenceParam('', '2026-11-20')).toBe('2026-11-19')
    expect(fenceParam('2026-11-22', '2026-11-20')).toBe('2026-11-22')
  })
  it('fence efectivo: borrador sin fence; activo nunca antes de ayer', () => {
    expect(effectiveFence('draft', '2026-11-22', '2026-11-20')).toBeNull()
    expect(effectiveFence('active', '2026-11-22', '2026-11-20')).toBe('2026-11-22')
    expect(effectiveFence('active', '2026-11-01', '2026-11-20')).toBe('2026-11-19')
    expect(effectiveFence('active', '', '2026-11-20')).toBe('2026-11-19')
  })
  it('cuota movible: pendiente y lunes posterior al fence', () => {
    // 2026-W48 empieza el lunes 23/11 (> fence 22/11); 2026-W47 el 16/11.
    expect(isQuotaMovable(q('a', 'b', 48, 1, 'pending', 2026), '2026-11-22')).toBe(true)
    expect(isQuotaMovable(q('a', 'b', 47, 1, 'pending', 2026), '2026-11-22')).toBe(false)
    expect(isQuotaMovable(q('a', 'b', 48, 1, 'open', 2026), '2026-11-22')).toBe(false)
    expect(isQuotaMovable(q('a', 'b', 1, 1, 'fulfilled'), null)).toBe(false)
    expect(isQuotaMovable(q('a', 'b', 1, 1), null)).toBe(true)
  })
  it('addDays cruza meses y años', () => {
    expect(addDays('2026-12-31', 1)).toBe('2027-01-01')
    expect(addDays('2026-03-01', -1)).toBe('2026-02-28')
  })
})

describe('planWeeks', () => {
  it('peso = días laborables dentro del plan; semanas parciales pesan menos', () => {
    const ws = planWeeks({ start_date: '2027-01-06', end_date: '2027-01-19', status: 'draft' }, MON_FRI, null)
    expect(ws.map((w) => [w.key, w.weight])).toEqual([
      ['2027-W01', 3],
      ['2027-W02', 5],
      ['2027-W03', 2],
    ])
    expect(ws.every((w) => w.movable)).toBe(true)
  })
  it('festivos restan y el fence bloquea semanas', () => {
    const ws = planWeeks({ ...draft4, status: 'active' }, { workingDows: [1, 2, 3, 4, 5], nonWorkingDays: ['2027-01-05'] }, '2027-01-10')
    expect(ws[0].weight).toBe(4)
    expect(ws.map((w) => w.movable)).toEqual([false, true, true, true])
  })
  it('calendario vacío: todas pesan 1', () => {
    const ws = planWeeks(draft4, { workingDows: [], nonWorkingDays: [] }, null)
    expect(ws.map((w) => w.weight)).toEqual([1, 1, 1, 1])
  })
})

describe('media esperada y desviación (como E2E, sin máximo por panelista)', () => {
  it('niveles con el % de desviación', () => {
    expect(loadLevel(10, 10, 20)).toBe('normal')
    expect(loadLevel(12, 10, 20)).toBe('high')
    expect(loadLevel(13, 10, 20)).toBe('saturated')
    expect(loadLevel(1, 0, 20)).toBe('saturated')
    expect(loadLevel(0, 0, 20)).toBe('normal')
  })
  it('desviación típica respecto a lo esperado', () => {
    expect(weeklyStddev([5, 5], [5, 5])).toBe(0)
    expect(weeklyStddev([8, 2], [5, 5])).toBe(3)
  })
  it('originLoads: un nodo por ciudad de origen, esperado según el calendario', () => {
    const ws = planWeeks(draft4, MON_FRI, null)
    const loads = originLoads([q('a', 'x', 1, 20), q('a', 'y', 1, 20), q('b', 'x', 2, 4)], ws, null, (id) => id.toUpperCase(), 20)
    expect(loads.map((l) => l.origin)).toEqual(['A', 'B'])
    const a = loads[0]
    expect(a.total).toBe(40)
    expect(a.routes).toBe(2)
    expect(a.cells['2027-W01']).toMatchObject({ planned: 40, expected: 10, level: 'saturated' })
    expect(a.cells['2027-W02']).toMatchObject({ planned: 0, expected: 10, level: 'normal' })
    expect(a.saturated).toBe(1)
  })
})

describe('proposeBalance', () => {
  const ws = planWeeks(draft4, MON_FRI, null)

  it('reparte una ciudad cargada en una semana entre todas, conservando totales de plan, origen y ruta', () => {
    const quotas = [q('a', 'x', 1, 30), q('a', 'y', 1, 10), q('b', 'x', 1, 4), q('b', 'x', 2, 4), q('b', 'x', 3, 4), q('b', 'x', 4, 4)]
    const p = proposeBalance(quotas, ws, { fence: null, deviationPercent: 20 })
    const after = applyChanges(quotas, p.changes)
    expect(sum(after.map((x) => x.samples_planned))).toBe(56)
    expect(totalsBy(after, (x) => x.origin_city_id)).toEqual(totalsBy(quotas, (x) => x.origin_city_id))
    expect(totalsBy(after, (x) => `${x.origin_city_id}|${x.destination_city_id}`)).toEqual(
      totalsBy(quotas, (x) => `${x.origin_city_id}|${x.destination_city_id}`),
    )
    const weekA = totalsBy(after.filter((x) => x.origin_city_id === 'a'), (x) => String(x.iso_week))
    expect([...weekA.values()]).toEqual([10, 10, 10, 10])
    expect(p.origins.map((o) => o.origin_city_id)).toEqual(['a']) // b ya está equilibrada
    expect(p.moved).toBe(30)
    expect(p.origins[0].stddevAfter).toBeLessThan(p.origins[0].stddevBefore)
    expect(p.created).toBeGreaterThan(0)
    expect(p.zeroed).toBe(0)
  })

  it('valores absolutos solo de lo que cambia; la suma de deltas es 0', () => {
    const quotas = [q('a', 'x', 1, 8), q('a', 'x', 2, 0), q('a', 'x', 3, 0), q('a', 'x', 4, 0)]
    const p = proposeBalance(quotas, ws, { fence: null, deviationPercent: 20 })
    expect(p.changes).toEqual([
      { origin_city_id: 'a', destination_city_id: 'x', iso_year: 2027, iso_week: 1, samples: 2 },
      { origin_city_id: 'a', destination_city_id: 'x', iso_year: 2027, iso_week: 2, samples: 2 },
      { origin_city_id: 'a', destination_city_id: 'x', iso_year: 2027, iso_week: 3, samples: 2 },
      { origin_city_id: 'a', destination_city_id: 'x', iso_year: 2027, iso_week: 4, samples: 2 },
    ])
    expect(p.created).toBe(0)
  })

  it('nunca toca cuotas bloqueadas (no pendientes o dentro del fence) ni mete carga en semanas bloqueadas', () => {
    const active = planWeeks({ ...draft4, status: 'active' }, MON_FRI, '2027-01-10') // W01 congelada
    const quotas = [
      q('a', 'x', 1, 20), // dentro del fence
      q('a', 'x', 2, 12),
      q('a', 'y', 2, 6, 'open'), // no pendiente
      q('a', 'y', 3, 0),
      q('a', 'x', 4, 0),
    ]
    const p = proposeBalance(quotas, active, { fence: '2027-01-10', deviationPercent: 20, origins: ['a'] })
    const touched = new Set(p.changes.map((c) => `${c.destination_city_id}|${c.iso_week}`))
    expect(touched.has('x|1')).toBe(false)
    expect(touched.has('y|2')).toBe(false)
    for (const c of p.changes) expect(isoWeekMonday(c.iso_year, c.iso_week) > '2027-01-10').toBe(true)
    expect(sum(p.changes.map((c) => c.samples))).toBe(12) // solo se reparten las 12 movibles
    const after = applyChanges(quotas, p.changes)
    expect(totalsBy(after, (x) => x.destination_city_id)).toEqual(totalsBy(quotas, (x) => x.destination_city_id))
  })

  it('una ruta con la cuota destino bloqueada busca otra ruta de la semana cargada', () => {
    const quotas = [q('a', 'x', 1, 10), q('a', 'y', 1, 2), q('a', 'x', 2, 0, 'carried'), q('a', 'y', 2, 0)]
    const two = planWeeks({ start_date: '2027-01-04', end_date: '2027-01-17', status: 'draft' }, MON_FRI, null)
    const p = proposeBalance(quotas, two, { fence: null, deviationPercent: 20, origins: ['a'] })
    expect(p.changes.some((c) => c.destination_city_id === 'x' && c.iso_week === 2)).toBe(false)
    expect(p.moved).toBe(2) // solo las 2 de la ruta y pueden pasar a W02
  })

  it('sin `origins` solo entran las ciudades fuera de tolerancia; con `origins` se fuerza', () => {
    const quotas = [q('a', 'x', 1, 11), q('a', 'x', 2, 9), q('a', 'x', 3, 10), q('a', 'x', 4, 10)]
    expect(proposeBalance(quotas, ws, { fence: null, deviationPercent: 20 }).changes).toEqual([])
    expect(proposeBalance(quotas, ws, { fence: null, deviationPercent: 20, origins: ['a'] }).moved).toBe(1)
  })

  it('ya equilibrado: no propone nada (ni con empates)', () => {
    const three = [q('a', 'x', 1, 1), q('a', 'x', 2, 0), q('a', 'x', 3, 0), q('a', 'x', 4, 0)]
    expect(proposeBalance(three, ws, { fence: null, deviationPercent: 20, origins: ['a'] }).changes).toEqual([])
  })

  it('determinista: el orden de entrada no cambia la propuesta', () => {
    const quotas = [q('a', 'x', 1, 7), q('a', 'y', 1, 9), q('a', 'z', 2, 1), q('c', 'x', 3, 12), q('c', 'y', 1, 1)]
    const a = proposeBalance(quotas, ws, { fence: null, deviationPercent: 10 })
    const b = proposeBalance([...quotas].reverse(), ws, { fence: null, deviationPercent: 10 })
    expect(b).toEqual(a)
  })

  it('escala: 15.000 muestras, 870 rutas, un año, en menos de 2 s y conservando todo', () => {
    const year = planWeeks({ start_date: '2027-01-04', end_date: '2027-12-31', status: 'draft' }, MON_FRI, null)
    const quotas: QuotaInput[] = []
    let left = 15000
    let seed = 7
    const rnd = () => (seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648
    for (let r = 0; r < 870; r++) {
      const o = `o${String(r % 40).padStart(2, '0')}`
      const d = `d${String(r).padStart(3, '0')}`
      const n = r === 869 ? left : Math.min(left, 10 + Math.floor(rnd() * 15))
      left -= n
      // Concentrado en pocas semanas para que haya mucho que mover.
      const w1 = 1 + Math.floor(rnd() * 10)
      quotas.push(q(o, d, w1, Math.ceil(n / 2)), q(o, d, w1 + 20, Math.floor(n / 2)))
    }
    const t0 = performance.now()
    const p = proposeBalance(quotas, year, { fence: null, deviationPercent: 20 })
    const loads = originLoads(applyChanges(quotas, p.changes), year, null, (x) => x, 20)
    const ms = performance.now() - t0
    expect(ms).toBeLessThan(2000)
    const after = applyChanges(quotas, p.changes)
    expect(sum(after.map((x) => x.samples_planned))).toBe(15000)
    expect(totalsBy(after, (x) => `${x.origin_city_id}|${x.destination_city_id}`)).toEqual(
      totalsBy(quotas, (x) => `${x.origin_city_id}|${x.destination_city_id}`),
    )
    expect(p.moved).toBeGreaterThan(0)
    expect(loads.length).toBe(40)
  })
})

describe('regresión: sin Carrier Link el Balanceo de Carga es el de siempre', () => {
  const base = { flagOn: true, canViewPlans: true, accountId: 'acc', carriers: [{ capture_method: 'carrier_link' }] }
  it('la condición falla con el flag apagado, sin permiso, sin cuenta o sin carriers de Carrier Link', () => {
    expect(carrierLinkPlansVisible({ ...base, flagOn: false })).toBe(false)
    expect(carrierLinkPlansVisible({ ...base, canViewPlans: false })).toBe(false)
    expect(carrierLinkPlansVisible({ ...base, accountId: null })).toBe(false)
    expect(carrierLinkPlansVisible({ ...base, carriers: [{ capture_method: 'panelists' }, {}] })).toBe(false)
  })
  it('sin la condición no hay selector de plan: solo borradores y activos cuando sí', () => {
    const plans = [
      { id: '1', status: 'draft' },
      { id: '2', status: 'active' },
      { id: '3', status: 'closed' },
    ]
    expect(balancingPlanOptions(false, plans)).toEqual([])
    expect(balancingPlanOptions(true, plans).map((p) => p.id)).toEqual(['1', '2'])
  })
})

describe('traducciones del balanceo de Carrier Link', () => {
  const files = [
    '../carrierLink/quotaBalancing.ts',
    '../../components/NodeLoadBalancing/ClQuotaBalancing.tsx',
    '../../pages/NodeLoadBalancing.tsx',
    '../../components/carrier-link/ClPlanRecords.tsx',
  ]
  const used = new Set<string>()
  for (const f of files) {
    const src = readFileSync(resolve(__dirname, f), 'utf8')
    for (const m of src.matchAll(/'(cl\.[a-z_]+\.[a-z_.]+)'/g)) used.add(m[1])
  }
  for (const level of ['normal', 'high', 'saturated']) used.add(`lb2.level.${level}`)
  for (const lang of ['en', 'es', 'fr', 'ar', 'pt']) {
    it(`todas las claves usadas existen en ${lang}.csv`, () => {
      const csv = readFileSync(resolve(__dirname, `../../../public/locales/${lang}.csv`), 'utf8')
      const keys = new Set(csv.split(/\r?\n/).map((l) => l.slice(0, l.indexOf(','))))
      expect(used.size).toBeGreaterThan(10)
      expect([...used].filter((k) => !keys.has(k))).toEqual([])
    })
  }
})
