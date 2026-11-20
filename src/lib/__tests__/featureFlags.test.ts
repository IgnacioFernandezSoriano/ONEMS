import { describe, it, expect } from 'vitest'
import { isCarrierLinkEnabled } from '../featureFlags'

describe('isCarrierLinkEnabled', () => {
  it('activo en localhost, 127.0.0.1 y DEV', () => {
    expect(isCarrierLinkEnabled('localhost', undefined)).toBe(true)
    expect(isCarrierLinkEnabled('127.0.0.1', undefined)).toBe(true)
    expect(isCarrierLinkEnabled('onem-dev.netlify.app', undefined)).toBe(true)
  })
  it('activo en deploy previews / branch deploys de DEV', () => {
    expect(isCarrierLinkEnabled('deploy-preview-12--onem-dev.netlify.app', undefined)).toBe(true)
    expect(isCarrierLinkEnabled('feat-x--onem-dev.netlify.app', undefined)).toBe(true)
  })
  it('inactivo en producción y hosts desconocidos', () => {
    expect(isCarrierLinkEnabled('onems.edgeavs.net', undefined)).toBe(false)
    expect(isCarrierLinkEnabled('example.com', undefined)).toBe(false)
    expect(isCarrierLinkEnabled('onem-dev.netlify.app.evil.com', undefined)).toBe(false)
    expect(isCarrierLinkEnabled('evil-onem-dev.netlify.app', undefined)).toBe(false)
    expect(isCarrierLinkEnabled('', undefined)).toBe(false)
  })
  it('sin navegador ni host: desactivado', () => {
    expect(isCarrierLinkEnabled(undefined, undefined)).toBe(false)
  })
  it('override on/off gana al host', () => {
    expect(isCarrierLinkEnabled('onems.edgeavs.net', 'on')).toBe(true)
    expect(isCarrierLinkEnabled('localhost', 'off')).toBe(false)
  })
  it('override con otro valor se ignora', () => {
    expect(isCarrierLinkEnabled('onems.edgeavs.net', 'yes')).toBe(false)
    expect(isCarrierLinkEnabled('localhost', '')).toBe(true)
  })
})
