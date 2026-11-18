import { describe, it, expect } from 'vitest'
import { createLatestRequest } from '../latestRequest'
import { scopeToAccount } from '../accountScope'

describe('createLatestRequest', () => {
  it('only the most recent load is current', () => {
    const t = createLatestRequest()
    const firstStale = t.begin()
    expect(firstStale()).toBe(false)
    const secondStale = t.begin()
    expect(firstStale()).toBe(true)
    expect(secondStale()).toBe(false)
  })

  it('cancel makes every started load stale', () => {
    const t = createLatestRequest()
    const stale = t.begin()
    t.cancel()
    expect(stale()).toBe(true)
  })

  it('a slow earlier load cannot overwrite a newer one', async () => {
    const t = createLatestRequest()
    let state = ''
    const load = async (value: string, ms: number) => {
      const isStale = t.begin()
      await new Promise((r) => setTimeout(r, ms))
      if (isStale()) return
      state = value
    }
    await Promise.all([load('all-accounts', 30), load('KENYA', 5)])
    expect(state).toBe('KENYA')
  })
})

describe('scopeToAccount', () => {
  const fakeQuery = () => {
    const calls: Array<[string, unknown]> = []
    const q = { calls, eq: (c: string, v: unknown) => { calls.push([c, v]); return q } }
    return q
  }
  it('adds the account filter when an account is selected', () => {
    const q = fakeQuery()
    scopeToAccount(q, 'acc-1')
    expect(q.calls).toEqual([['account_id', 'acc-1']])
  })
  it('leaves the query unchanged without an account', () => {
    const q = fakeQuery()
    scopeToAccount(q, null)
    expect(q.calls).toEqual([])
  })
})
