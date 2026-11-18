import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  ACCESS_OPTIONS, ROUTE_OPTION, firstAllowedPath, isPermissionsLoading,
  routeAccess, canAccess, landingPath, deniedRedirect, NO_ACCESS_PATH,
  permissionsRetryDelay, permissionsStatus, PERMISSIONS_RETRY_DELAYS_MS,
  type AccessOption, type AccessLevel,
} from '../access'

describe('access', () => {
  it('cada ruta de App.tsx tiene opción asignada', () => {
    const src = readFileSync(resolve(__dirname, '../../App.tsx'), 'utf8')
    const paths = [...src.matchAll(/path=\s*"([^"]+)"/g)].map(m => m[1]).filter(p => p !== '/*' && p !== '/')
    expect(paths.length).toBeGreaterThan(30)
    const missing = paths.filter(p => !(p in ROUTE_OPTION))
    expect(missing).toEqual([])
  })

  it('el catálogo tiene 28 opciones únicas y las rutas apuntan a opciones válidas', () => {
    const keys = new Set<string>(ACCESS_OPTIONS.map(o => o.key))
    expect(ACCESS_OPTIONS.length).toBe(28)
    expect(keys.size).toBe(28)
    for (const v of Object.values(ROUTE_OPTION)) {
      expect(v === 'open' || v === 'superadmin' || keys.has(v)).toBe(true)
    }
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
    for (const o of ACCESS_OPTIONS) {
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
