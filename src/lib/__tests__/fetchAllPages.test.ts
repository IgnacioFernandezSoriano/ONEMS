import { describe, it, expect } from 'vitest'
import { fetchAllPages } from '../fetchAllPages'

describe('fetchAllPages', () => {
  it('recorre paginas de 1000 hasta una pagina corta y conserva el orden', async () => {
    const all = Array.from({ length: 2500 }, (_, i) => i)
    const calls: Array<[number, number]> = []
    const rows = await fetchAllPages<number>(async (from, to) => {
      calls.push([from, to])
      return { data: all.slice(from, to + 1), error: null }
    })
    expect(rows).toEqual(all)
    expect(calls).toEqual([[0, 999], [1000, 1999], [2000, 2999]])
  })

  it('multiplo exacto del tamano: termina con una pagina vacia', async () => {
    const all = Array.from({ length: 2000 }, (_, i) => i)
    let n = 0
    const rows = await fetchAllPages<number>(async (from, to) => {
      n++
      return { data: all.slice(from, to + 1), error: null }
    })
    expect(rows.length).toBe(2000)
    expect(n).toBe(3)
  })

  it('data null cuenta como pagina vacia', async () => {
    expect(await fetchAllPages<number>(async () => ({ data: null, error: null }))).toEqual([])
  })

  it('un error en cualquier pagina se lanza', async () => {
    await expect(
      fetchAllPages<number>(async (from) =>
        from === 0
          ? { data: Array.from({ length: 1000 }, (_, i) => i), error: null }
          : { data: null, error: { message: 'boom' } })
    ).rejects.toMatchObject({ message: 'boom' })
  })
})
