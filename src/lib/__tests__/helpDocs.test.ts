import { describe, it, expect } from 'vitest'
import { HELP_DOCS, canSeeHelpDoc } from '../helpDocs'

const none = { isSuperadmin: false, canManageAccess: false, hasAnyEdit: false }

describe('canSeeHelpDoc', () => {
  it('las ayudas públicas las ve cualquiera', () => {
    expect(canSeeHelpDoc({ managersOnly: undefined }, none)).toBe(true)
  })
  it('las de gestores: superadmin, quien gestiona accesos o quien tiene algún Edit', () => {
    const doc = { managersOnly: true }
    expect(canSeeHelpDoc(doc, none)).toBe(false)
    expect(canSeeHelpDoc(doc, { ...none, isSuperadmin: true })).toBe(true)
    expect(canSeeHelpDoc(doc, { ...none, canManageAccess: true })).toBe(true)
    expect(canSeeHelpDoc(doc, { ...none, hasAnyEdit: true })).toBe(true)
  })
  it('el catálogo ya no filtra por rol legacy', () => {
    expect(HELP_DOCS.every(d => !('roles' in d))).toBe(true)
    expect(HELP_DOCS.filter(d => canSeeHelpDoc(d, none)).map(d => d.id)).toEqual(['roles-access', 'panelist-guide'])
  })
})
