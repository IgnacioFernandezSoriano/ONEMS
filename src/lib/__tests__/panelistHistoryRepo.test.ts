import { describe, it, expect } from 'vitest'
import { readFileSync, readdirSync } from 'node:fs'
import { resolve } from 'node:path'
import { LEAVE_REASONS, leaveReasonKey } from '../panelistHistory'

const root = resolve(__dirname, '../../..')

describe('historial del panelista: repo', () => {
  it('no hay dos migraciones con la misma versión (la CLI de Supabase saltaría una)', () => {
    const versions = readdirSync(resolve(root, 'supabase/migrations'))
      .filter(f => f.endsWith('.sql')).map(f => f.split('_')[0])
    const dup = versions.filter((v, i) => versions.indexOf(v) !== i)
    expect(dup).toEqual([])
  })

  it('cada motivo de baja tiene su texto en los 5 idiomas', () => {
    for (const lang of ['es', 'en', 'fr', 'ar', 'pt']) {
      const keys = new Set(readFileSync(resolve(root, `public/locales/${lang}.csv`), 'utf-8')
        .split(/\r?\n/).map(l => l.split(',')[0]))
      for (const r of LEAVE_REASONS) expect(keys.has(leaveReasonKey(r)), `${lang}: ${r}`).toBe(true)
    }
  })
})
