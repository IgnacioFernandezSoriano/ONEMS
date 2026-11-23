import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  carrierLinkCaptureAvailable,
  generatorCarriers,
  resolveCapture,
  clGeneratedPlans,
  clAppliedPlans,
  toQuotaInputs,
  clGeneratorFormError,
} from '../carrierLink/generatorCapture'
import { carriersForCapture, CAPTURE_METHODS } from '../carrierCapture'

type C = { id: string; capture_method?: string | null }
const ids = (l: C[]) => l.map((c) => c.id)
const mixed: C[] = [
  { id: 'p', capture_method: 'panelists' },
  { id: 'cl', capture_method: 'carrier_link' },
  { id: 'b', capture_method: 'both' },
  { id: 'none' },
]
const kenya: C[] = [{ id: 'k1', capture_method: 'panelists' }, { id: 'k2' }]

describe('carrierLinkCaptureAvailable', () => {
  const base = { flagOn: true, canEditPlans: true, accountId: 'acc', carriers: mixed }
  it('true solo con flag, permiso de edición, cuenta y un carrier carrier_link|both', () => {
    expect(carrierLinkCaptureAvailable(base)).toBe(true)
    expect(carrierLinkCaptureAvailable({ ...base, carriers: [{ capture_method: 'both' }] })).toBe(true)
  })
  it('false en producción (flag apagado)', () => {
    expect(carrierLinkCaptureAvailable({ ...base, flagOn: false })).toBe(false)
  })
  it('false sin permiso de edición de cl_plans', () => {
    expect(carrierLinkCaptureAvailable({ ...base, canEditPlans: false })).toBe(false)
  })
  it('false sin cuenta elegida', () => {
    expect(carrierLinkCaptureAvailable({ ...base, accountId: null })).toBe(false)
  })
  it('false en una cuenta solo de panelistas (Kenya/Senegal)', () => {
    expect(carrierLinkCaptureAvailable({ ...base, carriers: kenya })).toBe(false)
  })
})

describe('generatorCarriers (regresión: sin Carrier Link, la lista de siempre)', () => {
  it('flag apagado: todos los carriers, igual que hoy', () => {
    expect(generatorCarriers(mixed, { flagOn: false, clAvailable: false })).toBe(mixed)
  })
  it('flag encendido sin captura Carrier Link: los de panelistas, igual que hoy', () => {
    expect(generatorCarriers(mixed, { flagOn: true, clAvailable: false })).toEqual(carriersForCapture(mixed, 'panelists'))
    expect(ids(generatorCarriers(kenya, { flagOn: true, clAvailable: false }))).toEqual(['k1', 'k2'])
  })
  it('con captura Carrier Link: carriers de cualquier forma de captura', () => {
    expect(ids(generatorCarriers(mixed, { flagOn: true, clAvailable: true }))).toEqual(['p', 'cl', 'b', 'none'])
  })
})

describe('resolveCapture', () => {
  it('sin carrier: Panelistas, fija', () => {
    expect(resolveCapture(null, 'carrier_link')).toEqual({ options: ['panelists'], capture: 'panelists', fixed: true })
  })
  it('carrier de un solo tipo: la fija aunque se hubiera elegido otra', () => {
    expect(resolveCapture({ capture_method: 'carrier_link' }, 'panelists')).toEqual({
      options: ['carrier_link'],
      capture: 'carrier_link',
      fixed: true,
    })
    expect(resolveCapture({ capture_method: 'panelists' }, 'carrier_link').capture).toBe('panelists')
    expect(resolveCapture({}, 'carrier_link').capture).toBe('panelists')
  })
  it('carrier con ambas: elige el usuario (por defecto Panelistas)', () => {
    expect(resolveCapture({ capture_method: 'both' }, 'panelists')).toEqual({
      options: ['panelists', 'carrier_link'],
      capture: 'panelists',
      fixed: false,
    })
    expect(resolveCapture({ capture_method: 'both' }, 'carrier_link').capture).toBe('carrier_link')
  })
})

describe('planes de Carrier Link en las pestañas', () => {
  const plans = [
    { id: 'd', status: 'draft' as const },
    { id: 'a', status: 'active' as const },
    { id: 'c', status: 'closed' as const },
  ]
  it('Planes generados: borradores y activos', () => {
    expect(clGeneratedPlans(plans).map((p) => p.id)).toEqual(['d', 'a'])
  })
  it('Planes aplicados: activos y cerrados', () => {
    expect(clAppliedPlans(plans).map((p) => p.id)).toEqual(['a', 'c'])
  })
})

describe('toQuotaInputs', () => {
  it('convierte cuotas generadas en filas de la tabla de cuotas (previsto, sin arrastre ni obtenido)', () => {
    expect(toQuotaInputs([{ origin_city_id: 'A', destination_city_id: 'B', iso_year: 2026, iso_week: 3, samples: 4 }])).toEqual([
      {
        origin_city_id: 'A',
        destination_city_id: 'B',
        iso_year: 2026,
        iso_week: 3,
        samples_planned: 4,
        samples_carried_in: 0,
        samples_obtained: 0,
        status: 'pending',
      },
    ])
  })
})

describe('traducciones del generador con Carrier Link', () => {
  const files = [
    '../carrierLink/quotaCsv.ts',
    '../carrierLink/generatorCapture.ts',
    '../../hooks/carrierLink/useClGeneratorFlow.ts',
    '../../hooks/carrierLink/useClPlans.ts',
    '../../components/carrier-link/ClGeneratorPanel.tsx',
    '../../components/carrier-link/ClPlanActionPanel.tsx',
    '../../components/allocation-plans/AllocationPlanGeneratorForm.tsx',
    '../../pages/AllocationPlanGenerator.tsx',
  ]
  // Claves con plantilla (`cl.x.${valor}`): cada familia se enumera con su conjunto finito de valores.
  const templateFamilies: Record<string, readonly string[]> = {
    'cl.capture_method': CAPTURE_METHODS,
    'cl.plans.status': ['draft', 'active', 'closed'],
    'cl.plans.missing': ['origin', 'destination'],
    'cl.plans.error': ['no_account', 'bad_period', 'bad_total', 'missing_field'],
  }
  const used = new Set<string>()
  const templatePrefixes = new Set<string>()
  for (const f of files) {
    const src = readFileSync(resolve(__dirname, f), 'utf8')
    for (const m of src.matchAll(/'(cl\.(?:generator|plans|capture_method)\.[a-z_.]+)'/g)) used.add(m[1])
    for (const m of src.matchAll(/`(cl\.[a-z_.]+)\.\$\{/g)) templatePrefixes.add(m[1])
  }
  for (const [prefix, values] of Object.entries(templateFamilies)) for (const v of values) used.add(`${prefix}.${v}`)

  it('cada clave con plantilla usada pertenece a una familia enumerada', () => {
    expect(templatePrefixes.size).toBeGreaterThan(0)
    expect([...templatePrefixes].filter((p) => !(p in templateFamilies))).toEqual([])
  })
  for (const lang of ['en', 'es', 'fr', 'ar', 'pt']) {
    it(`todas las claves cl.* usadas existen en ${lang}.csv`, () => {
      const csv = readFileSync(resolve(__dirname, `../../../public/locales/${lang}.csv`), 'utf8')
      const keys = new Set(csv.split(/\r?\n/).map((l) => l.slice(0, l.indexOf(','))))
      expect(used.size).toBeGreaterThan(20)
      expect([...used].filter((k) => !keys.has(k))).toEqual([])
    })
  }
})

describe('clGeneratorFormError', () => {
  const form = {
    plan_name: 'Plan',
    carrier_id: 'c',
    product_id: 'p',
    feed_id: 'f',
    start_date: '2026-01-01',
    end_date: '2026-03-31',
    total_samples: 100,
    feed_diagnosis: false,
  }
  it('formulario completo con conector: sin error', () => {
    expect(clGeneratorFormError('acc', form)).toBeNull()
  })
  it('el conector es obligatorio', () => {
    expect(clGeneratorFormError('acc', { ...form, feed_id: '' })).toBe('cl.generator.connector_required')
  })
  it('primero los errores del plan (cuenta, campos, periodo, total)', () => {
    expect(clGeneratorFormError(null, form)).toBe('cl.plans.error.no_account')
    expect(clGeneratorFormError('acc', { ...form, plan_name: ' ', feed_id: '' })).toBe('cl.plans.error.missing_field')
    expect(clGeneratorFormError('acc', { ...form, end_date: '2025-12-31' })).toBe('cl.plans.error.bad_period')
    expect(clGeneratorFormError('acc', { ...form, total_samples: 0 })).toBe('cl.plans.error.bad_total')
  })
})
