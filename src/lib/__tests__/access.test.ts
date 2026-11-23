import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  ACCESS_OPTIONS, ROUTE_OPTION, OPTION_ROUTE, firstAllowedPath, isPermissionsLoading,
  routeAccess, canAccess, landingPath, deniedRedirect, NO_ACCESS_PATH,
  permissionsRetryDelay, permissionsStatus, PERMISSIONS_RETRY_DELAYS_MS,
  type AccessOption, type AccessLevel,
} from '../access'

describe('access', () => {
  it('cada ruta de App.tsx tiene opción asignada', () => {
    const src = readFileSync(resolve(__dirname, '../../App.tsx'), 'utf8')
    const paths = [...src.matchAll(/path=\s*"([^"]+)"/g)].map(m => m[1]).filter(p => p !== '/*' && p !== '/')
    expect(paths.length).toBeGreaterThan(30)
    const missing = paths.filter(p => !(p in ROUTE_OPTION) && p !== '/carrier-link/*') // comodín = redirección en producción
    expect(missing).toEqual([])
  })

  it('el catálogo tiene 34 opciones únicas y las rutas apuntan a opciones válidas', () => {
    const keys = new Set<string>(ACCESS_OPTIONS.map(o => o.key))
    expect(ACCESS_OPTIONS.length).toBe(34)
    expect(keys.size).toBe(34)
    for (const v of Object.values(ROUTE_OPTION)) {
      expect(v === 'open' || v === 'superadmin' || keys.has(v)).toBe(true)
    }
  })

  it('las 5 opciones cl_* tienen ruta propia', () => {
    const rutas: Record<string, string> = {
      '/carrier-link/plans': 'cl_plans',
      '/carrier-link/allocation-generator': 'cl_plans',
      '/carrier-link/load-balancing': 'cl_plans',
      '/carrier-link/allocation-plans': 'cl_plans',
      '/carrier-link/samples': 'cl_samples',
      '/carrier-link/reading-points': 'cl_reading_points',
      '/carrier-link/connectors': 'cl_connectors',
      '/carrier-link/monitor': 'cl_monitor',
    }
    for (const [path, opt] of Object.entries(rutas)) expect(routeAccess(path)).toBe(opt)
    expect(OPTION_ROUTE.cl_monitor).toBe('/carrier-link/monitor')
    expect(OPTION_ROUTE.cl_plans).toBe('/allocation-plan-generator')
  })

  it('las rutas antiguas de asignación de Carrier Link redirigen a las pantallas E2E en App.tsx', () => {
    const src = readFileSync(resolve(__dirname, '../../App.tsx'), 'utf8')
    const redirects: [string, string][] = [
      ['/carrier-link/plans', '/allocation-plan-generator'],
      ['/carrier-link/allocation-generator', '/allocation-plan-generator'],
      ['/carrier-link/load-balancing', '/node-load-balancing'],
      ['/carrier-link/allocation-plans', '/allocation-plans'],
    ]
    for (const [from, to] of redirects) {
      expect(src).toContain(`<Route path="${from}" element={<Navigate to="${to}" replace />} />`)
    }
    expect(src).not.toMatch(/ClPlans|ClComingSoon/)
  })

  it('landingPath: con cl_plans y el Generador aterriza en el Generador de Asignaciones', () => {
    expect(landingPath(o => o === 'cl_plans' || o === 'allocation_generator', true)).toBe('/allocation-plan-generator')
  })

  it('landingPath: cl_plans sin el Generador no aterriza en una pantalla que le negaría la entrada', () => {
    // El Generador exige allocation_generator: con solo cl_plans + cl_samples se pasa a la siguiente permitida.
    expect(landingPath(o => o === 'cl_plans' || o === 'cl_samples', true)).toBe('/carrier-link/samples')
    expect(landingPath(o => o === 'cl_plans', true)).toBe(NO_ACCESS_PATH)
  })

  it('deniedRedirect: negado en la entrada de cl_plans pasa a la siguiente permitida, no a "sin acceso"', () => {
    const v = (o: AccessOption) => o === 'cl_plans' || o === 'cl_samples'
    expect(deniedRedirect('/allocation-plan-generator', v, true)).toBe('/carrier-link/samples')
    // Con varias permitidas, nunca la propia ruta: la siguiente.
    const w = (o: AccessOption) => o === 'cl_samples' || o === 'cl_monitor'
    expect(deniedRedirect('/carrier-link/samples', w, true)).toBe('/carrier-link/monitor')
  })

  it('landingPath: quien solo ve cl_samples aterriza en /carrier-link/samples', () => {
    expect(landingPath(o => o === 'cl_samples', true)).toBe('/carrier-link/samples')
  })

  it('firstAllowedPath: solo reporting -> territory-equity', () => {
    const m = new Map<AccessOption, AccessLevel>([['territory_equity', 'view'], ['compliance', 'view'], ['help_center', 'view']])
    expect(firstAllowedPath(m)).toBe('/reporting/territory-equity')
  })

  it('firstAllowedPath: dashboard primero y nada -> null', () => {
    const m = new Map<AccessOption, AccessLevel>([['dashboard', 'view'], ['carriers', 'edit']])
    expect(firstAllowedPath(m)).toBe('/dashboard')
    expect(firstAllowedPath(new Map())).toBeNull()
  })

  it('isPermissionsLoading: true si la clave cargada no es la actual', () => {
    expect(isPermissionsLoading('u|a2', 'u|a1')).toBe(true)
    expect(isPermissionsLoading('u|a1', null)).toBe(true)
    expect(isPermissionsLoading('u|a1', 'u|a1')).toBe(false)
    expect(isPermissionsLoading(null, 'u|a1')).toBe(false)
  })

  it('App.tsx: cada ProtectedRoute con option usa la de ROUTE_OPTION y no queda allowedRoles', () => {
    const src = readFileSync(resolve(__dirname, '../../App.tsx'), 'utf8')
    expect(src).not.toMatch(/allowedRoles/)
    const pairs = [...src.matchAll(/path="([^"]+)"\s*element=\{\s*<ProtectedRoute option="([^"]+)"/g)]
    expect(pairs.length).toBeGreaterThan(40)
    for (const [, path, opt] of pairs) expect([path, opt]).toEqual([path, ROUTE_OPTION[path]])
  })

  it('Sidebar: sin roles y cada item enlazado lleva la opción de su ruta', () => {
    const src = readFileSync(resolve(__dirname, '../../components/layout/Sidebar.tsx'), 'utf8')
    expect(src).not.toMatch(/roles: \[/)
    const pairs = [...src.matchAll(/path: '(\/[^']+)',[^{}]*?option: '([^']+)'/g)]
    expect(pairs.length).toBeGreaterThan(25)
    for (const [, path, opt] of pairs) {
      expect([path, opt]).toEqual([path, ROUTE_OPTION[path]])
    }
  })

  it('cada opción entra por una ruta que exige esa misma opción', () => {
    for (const o of ACCESS_OPTIONS.filter(x => !x.key.startsWith('cl_'))) {
      const path = firstAllowedPath(new Map<AccessOption, AccessLevel>([[o.key, 'view']]))!
      expect([o.key, routeAccess(path)]).toEqual([o.key, o.key])
    }
  })

  it('rutas globales (todas las cuentas) solo superadmin; /users por cuenta', () => {
    for (const p of ['/settings', '/settings/accounts', '/settings/users', '/settings/reporting-config', '/admin/translations']) {
      expect([p, routeAccess(p)]).toEqual([p, 'superadmin'])
    }
    expect(routeAccess('/users')).toBe('users')
  })

  it('routeAccess: rutas no mapeadas solo superadmin', () => {
    expect(routeAccess('/no-existe')).toBe('superadmin')
    expect(routeAccess('/carriers')).toBe('carriers')
  })

  it('canAccess: open, superadmin y opciones', () => {
    const only = (k: AccessOption) => (o: AccessOption) => o === k
    expect(canAccess('open', false, () => false)).toBe(true)
    expect(canAccess('superadmin', false, () => true)).toBe(false)
    expect(canAccess('superadmin', true, () => false)).toBe(true)
    expect(canAccess('carriers', false, only('carriers'))).toBe(true)
    expect(canAccess('carriers', false, only('panelists'))).toBe(false)
    expect(canAccess('carriers', true, () => false)).toBe(true)
  })

  it('landingPath / deniedRedirect: sin derechos -> cambiar contraseña y nunca a sí misma', () => {
    expect(landingPath(() => false)).toBe(NO_ACCESS_PATH)
    expect(landingPath(() => true)).toBe('/dashboard')
    expect(landingPath(o => o === 'compliance')).toBe('/reporting/compliance')
    expect(deniedRedirect('/carriers', o => o === 'compliance')).toBe('/reporting/compliance')
    expect(deniedRedirect('/dashboard', o => o === 'dashboard')).toBe(NO_ACCESS_PATH)
    expect(routeAccess(NO_ACCESS_PATH)).toBe('open')
  })

  it('permissionsRetryDelay: 2 reintentos con espera creciente y luego null', () => {
    expect(PERMISSIONS_RETRY_DELAYS_MS.length).toBe(2)
    expect(permissionsRetryDelay(0)).toBe(1000)
    expect(permissionsRetryDelay(1)).toBe(3000)
    expect(permissionsRetryDelay(2)).toBeNull()
    expect(permissionsRetryDelay(-1)).toBeNull()
  })

  it('permissionsStatus: un error no es "cargado y vacío"', () => {
    expect(permissionsStatus(null, null, null)).toBe('ready')
    expect(permissionsStatus('u|a1', 'u|a1', null)).toBe('ready')
    expect(permissionsStatus('u|a1', null, null)).toBe('loading')
    expect(permissionsStatus('u|a1', null, 'u|a1')).toBe('error')
    // error de otra cuenta: la actual sigue cargando
    expect(permissionsStatus('u|a2', 'u|a1', 'u|a1')).toBe('loading')
    // derechos ya cargados ganan a un fallo posterior de recarga
    expect(permissionsStatus('u|a1', 'u|a1', 'u|a1')).toBe('ready')
  })
})

describe('Carrier Link deshabilitado (producción)', () => {
  it('quien solo tiene cl_* no aterriza nunca en /carrier-link: pantalla sin acceso', () => {
    expect(landingPath(o => o.startsWith('cl_'), false)).toBe(NO_ACCESS_PATH)
  })
  it('con otras opciones aterriza en la primera no cl_*', () => {
    expect(landingPath(o => o === 'cl_plans' || o === 'dashboard', false)).toBe('/dashboard')
  })
})
