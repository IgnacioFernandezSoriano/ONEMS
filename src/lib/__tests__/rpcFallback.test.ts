import { describe, it, expect, vi } from 'vitest'

vi.mock('../supabase', () => ({ supabase: { rpc: vi.fn() } }))

import { isMissingFunctionError } from '../rpcFallback'

describe('isMissingFunctionError', () => {
  it('reconoce PGRST202 y 42883', () => {
    expect(isMissingFunctionError({ code: 'PGRST202', message: 'x' })).toBe(true)
    expect(isMissingFunctionError({ code: '42883', message: 'x' })).toBe(true)
  })
  it('reconoce el mensaje sin código', () => {
    expect(isMissingFunctionError({ message: 'Could not find the function public.f(p) in the schema cache' })).toBe(true)
    expect(isMissingFunctionError({ message: 'function public.f(uuid) does not exist' })).toBe(true)
  })
  it('no confunde otros errores (p. ej. permiso denegado)', () => {
    expect(isMissingFunctionError(null)).toBe(false)
    expect(isMissingFunctionError({ code: '42501', message: 'permission denied for function f' })).toBe(false)
    expect(isMissingFunctionError({ code: 'P0001', message: 'Forbidden' })).toBe(false)
  })
})
