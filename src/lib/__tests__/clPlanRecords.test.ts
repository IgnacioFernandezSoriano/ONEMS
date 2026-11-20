import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  clPlanOptionValue,
  parseClPlanOption,
  carrierLinkPlansVisible,
  applyQuotaFilters,
  EMPTY_QUOTA_FILTERS,
  QUOTA_STATUSES,
  quotaPageRange,
  toQuotaRecord,
  quotaTotals,
  quotaTotalsParams,
  toQuotaFilterTotals,
  samplesLink,
  samplesParams,
  clPlanOptionLabel,
} from '../carrierLink/planRecords'

type C = { id: string; capture_method?: string | null }
const mixed: C[] = [
  { id: 'p', capture_method: 'panelists' },
  { id: 'cl', capture_method: 'carrier_link' },
]
const kenya: C[] = [{ id: 'k1', capture_method: 'panelists' }, { id: 'k2' }]

describe('carrierLinkPlansVisible (regresión: sin Carrier Link, la página de siempre)', () => {
  const base = { flagOn: true, canViewPlans: true, accountId: 'acc', carriers: mixed }
  it('true con flag, View en cl_plans, cuenta y un carrier carrier_link|both', () => {
    expect(carrierLinkPlansVisible(base)).toBe(true)
    expect(carrierLinkPlansVisible({ ...base, carriers: [{ capture_method: 'both' }] })).toBe(true)
  })
  it('false en producción (flag apagado)', () => {
    expect(carrierLinkPlansVisible({ ...base, flagOn: false })).toBe(false)
  })
  it('false sin permiso de ver cl_plans', () => {
    expect(carrierLinkPlansVisible({ ...base, canViewPlans: false })).toBe(false)
  })
  it('false sin cuenta elegida', () => {
    expect(carrierLinkPlansVisible({ ...base, accountId: null })).toBe(false)
  })
  it('false en una cuenta solo de panelistas (Kenya/Senegal) o sin carriers', () => {
    expect(carrierLinkPlansVisible({ ...base, carriers: kenya })).toBe(false)
    expect(carrierLinkPlansVisible({ ...base, carriers: [] })).toBe(false)
  })
})

describe('valor del selector de plan', () => {
  it('los planes de Carrier Link llevan prefijo; los de panelistas no se tocan', () => {
    expect(clPlanOptionValue('abc')).toBe('cl:abc')
    expect(parseClPlanOption('cl:abc')).toBe('abc')
    expect(parseClPlanOption('abc')).toBeNull()
    expect(parseClPlanOption('')).toBeNull()
    expect(parseClPlanOption('cl:')).toBeNull()
  })
  it('etiqueta con la marca de captura y el estado', () => {
    const t = (k: string) => ({ 'cl.capture_method.carrier_link': 'Carrier Link', 'cl.plans.status.active': 'Activo' })[k] ?? k
    expect(clPlanOptionLabel({ plan_name: 'Plan A', status: 'active' }, t)).toBe('Plan A · Carrier Link · Activo')
  })
})

/** Constructor falso que registra las llamadas .eq() como lo haría PostgREST. */
function fakeBuilder() {
  const calls: [string, unknown][] = []
  const b = {
    calls,
    eq(col: string, v: unknown) {
      calls.push([col, v])
      return b
    },
  }
  return b
}

describe('applyQuotaFilters (filtros → consulta)', () => {
  it('sin filtros: solo el plan', () => {
    const b = applyQuotaFilters(fakeBuilder(), 'plan1', EMPTY_QUOTA_FILTERS)
    expect(b.calls).toEqual([['plan_id', 'plan1']])
  })
  it('origen, destino, semana y estado van a la consulta', () => {
    const b = applyQuotaFilters(fakeBuilder(), 'plan1', {
      origin: 'o',
      destination: 'd',
      week: '2026-W07',
      status: 'unfilled',
    })
    expect(b.calls).toEqual([
      ['plan_id', 'plan1'],
      ['origin_city_id', 'o'],
      ['destination_city_id', 'd'],
      ['iso_year', 2026],
      ['iso_week', 7],
      ['status', 'unfilled'],
    ])
  })
  it('semana o estado no válidos se ignoran (nunca rompen la consulta)', () => {
    const b = applyQuotaFilters(fakeBuilder(), 'plan1', { ...EMPTY_QUOTA_FILTERS, week: 'xx', status: 'nope' })
    expect(b.calls).toEqual([['plan_id', 'plan1']])
  })
  it('los estados son los del CHECK de cl_plan_quotas', () => {
    expect([...QUOTA_STATUSES]).toEqual(['pending', 'open', 'fulfilled', 'carried', 'unfilled'])
  })
})

describe('quotaPageRange', () => {
  it('página 1-based a rango inclusivo de .range()', () => {
    expect(quotaPageRange(1, 100)).toEqual({ from: 0, to: 99 })
    expect(quotaPageRange(3, 50)).toEqual({ from: 100, to: 149 })
    expect(quotaPageRange(0, 50)).toEqual({ from: 0, to: 49 })
  })
})

describe('toQuotaRecord y totales', () => {
  const row = {
    id: 'q1',
    origin_city_id: 'o',
    destination_city_id: 'd',
    iso_year: 2026,
    iso_week: 3,
    period_start: '2026-01-12',
    period_end: '2026-01-18',
    samples_planned: 5,
    samples_carried_in: 2,
    samples_obtained: 4,
    demands_count: 1,
    status: 'open',
  }
  it('mapea la fila con la semana YYYY-Www', () => {
    expect(toQuotaRecord(row)).toEqual({
      id: 'q1',
      origin_city_id: 'o',
      destination_city_id: 'd',
      week: '2026-W03',
      period_start: '2026-01-12',
      period_end: '2026-01-18',
      planned: 5,
      carried_in: 2,
      obtained: 4,
      demands: 1,
      status: 'open',
    })
  })
  it('valores nulos cuentan como 0', () => {
    const r = toQuotaRecord({ ...row, samples_obtained: null, demands_count: null })
    expect(r.obtained).toBe(0)
    expect(r.demands).toBe(0)
  })
  it('suma previsto, arrastrado, obtenido y peticiones', () => {
    const a = toQuotaRecord(row)
    const b = toQuotaRecord({ ...row, id: 'q2', samples_planned: 1, samples_carried_in: 0, samples_obtained: 1, demands_count: 3 })
    expect(quotaTotals([a, b])).toEqual({ planned: 6, carried_in: 2, obtained: 5, demands: 4 })
    expect(quotaTotals([])).toEqual({ planned: 0, carried_in: 0, obtained: 0, demands: 0 })
  })
})

describe('enlace a Muestras (parámetros de URL)', () => {
  it('plan, semana y ruta', () => {
    expect(samplesLink('p1', { week: '2026-W03', origin_city_id: 'o', destination_city_id: 'd' })).toBe(
      '/carrier-link/samples?plan=p1&week=2026-W03&origin=o&destination=d',
    )
    expect(samplesLink('p1')).toBe('/carrier-link/samples?plan=p1')
  })
  it('ida y vuelta: Muestras lee los mismos parámetros', () => {
    const url = samplesLink('p 1', { week: '2026-W03', origin_city_id: 'o', destination_city_id: 'd' })
    expect(samplesParams(new URLSearchParams(url.split('?')[1]))).toEqual({
      plan: 'p 1',
      week: '2026-W03',
      origin: 'o',
      destination: 'd',
    })
  })
  it('sin parámetros (o semana no válida): Muestras como siempre', () => {
    expect(samplesParams(new URLSearchParams(''))).toEqual({ plan: null, week: null, origin: '', destination: '' })
    expect(samplesParams(new URLSearchParams('week=bad')).week).toBeNull()
  })
})

describe('totales de todo el filtro (cl_plan_quota_totals)', () => {
  it('mismos filtros que la tabla; vacíos o no válidos = sin filtro', () => {
    expect(quotaTotalsParams('p1', EMPTY_QUOTA_FILTERS)).toEqual({
      p_plan_id: 'p1',
      p_origin: null,
      p_destination: null,
      p_iso_year: null,
      p_iso_week: null,
      p_status: null,
    })
    expect(quotaTotalsParams('p1', { origin: 'o', destination: 'd', week: '2027-W05', status: 'open' })).toEqual({
      p_plan_id: 'p1',
      p_origin: 'o',
      p_destination: 'd',
      p_iso_year: 2027,
      p_iso_week: 5,
      p_status: 'open',
    })
    expect(quotaTotalsParams('p1', { ...EMPTY_QUOTA_FILTERS, week: 'bad', status: 'x' })).toMatchObject({
      p_iso_year: null,
      p_iso_week: null,
      p_status: null,
    })
  })
  it('lee la fila (bigint como texto o número); sin fila, null', () => {
    expect(toQuotaFilterTotals([{ quotas: '3', planned: '40', carried: 2, obtained: '7', demands: 1 }])).toEqual({
      quotas: 3,
      planned: 40,
      carried_in: 2,
      obtained: 7,
      demands: 1,
    })
    expect(toQuotaFilterTotals([])).toBeNull()
    expect(toQuotaFilterTotals(null)).toBeNull()
  })
})

describe('traducciones de los registros de Carrier Link', () => {
  const files = [
    '../carrierLink/planRecords.ts',
    '../../components/carrier-link/ClPlanRecords.tsx',
    '../../components/allocation-plans/AllocationPlanFilters.tsx',
    '../../pages/AllocationPlans.tsx',
  ]
  const templateFamilies: Record<string, readonly string[]> = {
    'cl.records.status': QUOTA_STATUSES,
    'cl.plans.status': ['draft', 'active', 'closed'],
  }
  const used = new Set<string>(['cl.capture_method.carrier_link'])
  const templatePrefixes = new Set<string>()
  for (const f of files) {
    const src = readFileSync(resolve(__dirname, f), 'utf8')
    for (const m of src.matchAll(/'(cl\.[a-z_]+\.[a-z_.]+)'/g)) used.add(m[1])
    for (const m of src.matchAll(/`(cl\.[a-z_.]+)\.\$\{/g)) templatePrefixes.add(m[1])
  }
  for (const [prefix, values] of Object.entries(templateFamilies)) for (const v of values) used.add(`${prefix}.${v}`)

  it('cada clave con plantilla usada pertenece a una familia enumerada', () => {
    expect([...templatePrefixes].filter((p) => !(p in templateFamilies))).toEqual([])
  })
  for (const lang of ['en', 'es', 'fr', 'ar', 'pt']) {
    it(`todas las claves cl.* usadas existen en ${lang}.csv`, () => {
      const csv = readFileSync(resolve(__dirname, `../../../public/locales/${lang}.csv`), 'utf8')
      const keys = new Set(csv.split(/\r?\n/).map((l) => l.slice(0, l.indexOf(','))))
      expect(used.size).toBeGreaterThan(10)
      expect([...used].filter((k) => !keys.has(k))).toEqual([])
    })
  }
})
