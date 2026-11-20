import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { CL_ERROR_CODES, clErrorKey } from '../carrierLink/clErrors'

describe('clErrorKey', () => {
  it('extrae el código CL_* del mensaje', () => {
    expect(clErrorKey({ message: 'CL_MISSING_POINTS: 2 city/role…' })).toBe('cl.error.cl_missing_points')
  })
  it('42501 -> forbidden', () => {
    expect(clErrorKey({ code: '42501', message: 'x' })).toBe('cl.error.forbidden')
  })
  it('null o desconocido -> generic', () => {
    expect(clErrorKey(null)).toBe('cl.error.generic')
    expect(clErrorKey({ message: 'boom' })).toBe('cl.error.generic')
  })
})

/** Códigos CL_* que lanza alguna migración (RAISE EXCEPTION 'CL_…), para que ninguno se quede sin traducir. */
function raisedClCodes(): string[] {
  const dir = resolve(__dirname, '../../../supabase/migrations')
  const codes = new Set<string>()
  for (const f of readdirSync(dir).filter((n) => n.endsWith('.sql'))) {
    const sql = readFileSync(resolve(dir, f), 'utf8')
    for (const m of sql.matchAll(/RAISE\s+EXCEPTION\s+'(CL_[A-Z_]+)/gi)) codes.add(m[1])
  }
  return [...codes].sort()
}

describe('CL_ERROR_CODES', () => {
  it('incluye todos los códigos CL_* que lanzan las migraciones', () => {
    const raised = raisedClCodes()
    expect(raised.length).toBeGreaterThan(0)
    expect(raised.filter((c) => !(CL_ERROR_CODES as readonly string[]).includes(c))).toEqual([])
  })
})

describe('traducciones de errores CL_*', () => {
  for (const lang of ['en', 'es', 'fr', 'ar', 'pt']) {
    it(`${lang}.csv traduce todos los CL_ERROR_CODES y las claves genéricas`, () => {
      const csv = readFileSync(resolve(__dirname, `../../../public/locales/${lang}.csv`), 'utf8')
      const keys = new Set(csv.split(/\r?\n/).map(l => l.slice(0, l.indexOf(','))))
      const codes = new Set<string>([...CL_ERROR_CODES, ...raisedClCodes()])
      const needed = [...[...codes].map(c => `cl.error.${c.toLowerCase()}`), 'cl.error.forbidden', 'cl.error.generic']
      expect(needed.filter(k => !keys.has(k))).toEqual([])
    })
  }
})
