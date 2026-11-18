import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import {
  ACCESS_OPTIONS, ROUTE_OPTION, firstAllowedPath,
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
})
