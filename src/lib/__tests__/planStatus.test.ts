import { describe, it, expect } from 'vitest'
import { isPendingLike, isDeferredStatus } from '../planStatus'

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
