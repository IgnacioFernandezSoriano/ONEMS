import { describe, it, expect } from 'vitest'
import { isPendingLike, isDeferredStatus, withoutDeferred } from '../planStatus'

describe('isPendingLike', () => {
  it('cuenta pending, notified y deferred como pendientes', () => {
    for (const s of ['pending', 'notified', 'deferred']) expect(isPendingLike(s)).toBe(true)
  })
  it('no cuenta el resto de estados', () => {
    for (const s of ['sent', 'received', 'cancelled', 'invalid', 'transfer_error', '', null, undefined])
      expect(isPendingLike(s)).toBe(false)
  })
  it('isDeferredStatus solo para deferred', () => {
    expect(isDeferredStatus('deferred')).toBe(true)
    expect(isDeferredStatus('pending')).toBe(false)
  })
})

describe('withoutDeferred', () => {
  it('quita solo las filas por compensar (no estan en transito)', () => {
    const rows = [
      { id: 1, status: 'pending' }, { id: 2, status: 'deferred' }, { id: 3, status: 'sent' },
      { id: 4, status: null }, { id: 5, status: 'deferred' },
    ]
    expect(withoutDeferred(rows).map(r => r.id)).toEqual([1, 3, 4])
  })
})
