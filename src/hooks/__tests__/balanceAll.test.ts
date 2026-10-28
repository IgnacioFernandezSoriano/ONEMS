import { describe, it, expect, vi } from 'vitest'
import { runForCities } from '../../lib/balanceAll'

describe('runForCities', () => {
  it('continua tras un error, nunca lanza y notifica el progreso', async () => {
    const run = vi.fn(async (id: string) => {
      if (id === 'b') throw new Error('boom')
      return `ok-${id}`
    })
    const onProgress = vi.fn()

    const out = await runForCities(['a', 'b', 'c'], run, onProgress)

    expect(out).toHaveLength(3)
    expect(out[0].result).toBe('ok-a')
    expect(out[1].error).toBe('boom')
    expect(out[1].result).toBeUndefined()
    expect(out[2].result).toBe('ok-c')
    expect(onProgress.mock.calls).toEqual([[1, 3], [2, 3], [3, 3]])
  })
})
