import { describe, it, expect } from 'vitest'
import { carrierLinkUiVisible } from '../carrierLinkUi'
import type { AccessOption } from '../access'

const has = (...keys: AccessOption[]) => (o: AccessOption) => keys.includes(o)

describe('carrierLinkUiVisible', () => {
  it('cuenta sin derechos de Carrier Link: oculto aunque el flag esté activo', () => {
    expect(carrierLinkUiVisible(true, has('carriers', 'panelists'))).toBe(false)
  })
  it('cuenta con algún derecho de Carrier Link y flag activo: visible', () => {
    expect(carrierLinkUiVisible(true, has('carriers', 'cl_connectors'))).toBe(true)
    expect(carrierLinkUiVisible(true, has('cl_monitor'))).toBe(true)
  })
  it('flag inactivo: oculto siempre', () => {
    expect(carrierLinkUiVisible(false, has('cl_connectors', 'cl_plans'))).toBe(false)
  })
})
