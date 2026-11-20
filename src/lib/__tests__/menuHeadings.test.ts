import { describe, it, expect } from 'vitest'
import { visibleEntries } from '../menuHeadings'

type E = { id: string; heading?: boolean; ok?: boolean }
const vis = (e: E) => e.ok !== false
const ids = (l: E[]) => l.map(e => e.id)

describe('visibleEntries', () => {
  it('muestra el subencabezado si algún enlace de su sección es visible', () => {
    const l: E[] = [{ id: 'a' }, { id: 'H', heading: true }, { id: 'b', ok: false }, { id: 'c' }]
    expect(ids(visibleEntries(l, vis))).toEqual(['a', 'H', 'c'])
  })
  it('oculta el subencabezado si ninguno de sus enlaces es visible', () => {
    const l: E[] = [{ id: 'a' }, { id: 'H', heading: true }, { id: 'b', ok: false }]
    expect(ids(visibleEntries(l, vis))).toEqual(['a'])
  })
  it('cada subencabezado depende solo de su sección', () => {
    const l: E[] = [{ id: 'H1', heading: true }, { id: 'a', ok: false }, { id: 'H2', heading: true }, { id: 'b' }]
    expect(ids(visibleEntries(l, vis))).toEqual(['H2', 'b'])
  })
  it('sin subencabezados devuelve solo los enlaces visibles', () => {
    expect(ids(visibleEntries([{ id: 'a' }, { id: 'b', ok: false }], vis))).toEqual(['a'])
  })
})
