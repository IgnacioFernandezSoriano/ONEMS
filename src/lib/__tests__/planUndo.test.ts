import { describe, it, expect, vi } from 'vitest'

// undoLabel es pura: no hace falta el cliente real (necesita window)
vi.mock('@/lib/supabase', () => ({ supabase: {} }))
import { undoLabel, isUndoChangedError, type UndoEntry } from '../planUndo'

const t = (k: string, p?: Record<string, unknown>) => `${k}|${JSON.stringify(p ?? {})}`

const entry = (over: Partial<UndoEntry> = {}): UndoEntry => ({
  id: 1,
  action: 'delete',
  n_rows: 164,
  user_name: 'Ana',
  created_at: '2026-11-18T09:32:00Z',
  ...over,
})

describe('undoLabel', () => {
  it('incluye acción, cantidad y usuario', () => {
    const out = undoLabel(entry(), t)
    expect(out).toContain('allocation_plans.undo_label')
    expect(out).toContain('allocation_plans.undo_action_delete')
    expect(out).toContain('"count":164')
    expect(out).toContain('"user":"Ana"')
  })

  it('usa un guion si no hay nombre de usuario', () => {
    expect(undoLabel(entry({ user_name: null }), t)).toContain('"user":"—"')
  })

  it('formatea la hora local en 24h con ceros', () => {
    const d = new Date('2026-11-18T09:32:00Z')
    const hh = String(d.getHours()).padStart(2, '0')
    const mm = String(d.getMinutes()).padStart(2, '0')
    expect(undoLabel(entry(), t)).toContain(`"time":"${hh}:${mm}"`)
  })
})

describe('isUndoChangedError', () => {
  it('reconoce el error de la BD por código o por mensaje', () => {
    expect(isUndoChangedError({ code: 'PU001', message: 'x' })).toBe(true)
    expect(isUndoChangedError({ message: 'plan_undo_changed: la última acción ya no es la 7' })).toBe(true)
  })

  it('no confunde otros errores', () => {
    expect(isUndoChangedError({ code: '42501', message: 'Sin permiso sobre la cuenta' })).toBe(false)
    expect(isUndoChangedError(null)).toBe(false)
  })
})
