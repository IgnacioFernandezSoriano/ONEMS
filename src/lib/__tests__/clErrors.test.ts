import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
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

describe('traducciones de errores CL_*', () => {
  for (const lang of ['en', 'es', 'fr', 'ar', 'pt']) {
    it(`${lang}.csv traduce todos los CL_ERROR_CODES y las claves genéricas`, () => {
      const csv = readFileSync(resolve(__dirname, `../../../public/locales/${lang}.csv`), 'utf8')
      const keys = new Set(csv.split(/\r?\n/).map(l => l.slice(0, l.indexOf(','))))
      const needed = [...CL_ERROR_CODES.map(c => `cl.error.${c.toLowerCase()}`), 'cl.error.forbidden', 'cl.error.generic']
      expect(needed.filter(k => !keys.has(k))).toEqual([])
    })
  }
})
