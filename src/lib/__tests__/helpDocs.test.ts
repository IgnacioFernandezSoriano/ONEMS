import { describe, it, expect } from 'vitest'
import { existsSync, readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { visibleHelpDocs, HELP_DOCS, HELP_LANGS, canSeeHelpDoc, helpDocUrl } from '../helpDocs'

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

describe('ayuda de Carrier Link', () => {
  it('está en el catálogo, solo para gestores', () => {
    const doc = HELP_DOCS.find(d => d.id === 'carrier-link')
    expect(doc).toMatchObject({ file: 'carrier-link', audience: 'managers', managersOnly: true, public: false })
    expect(doc?.titleKey).toBe('help_center.doc.carrier_link.title')
    expect(doc?.descKey).toBe('help_center.doc.carrier_link.desc')
  })
  it('existen los ficheros en los 5 idiomas con las anclas de las pantallas', () => {
    for (const lang of HELP_LANGS) {
      const file = resolve(__dirname, '../../../public/help', `carrier-link.${lang}.html`)
      expect(existsSync(file)).toBe(true)
      const html = readFileSync(file, 'utf-8')
      for (const id of ['generator', 'balancing', 'records', 'samples', 'reading-points', 'connectors', 'monitor']) {
        expect(html).toContain(`<section id="${id}">`)
        expect(html).toContain(`href="#${id}"`)
      }
      expect(html).not.toContain('<section id="plans">')
    }
  })
  it('los enlaces de las pantallas apuntan a la sección correcta', () => {
    expect(helpDocUrl('carrier-link', 'es', 'reading-points')).toBe('/help/carrier-link.es.html#reading-points')
    expect(helpDocUrl('carrier-link', 'en', 'generator')).toBe('/help/carrier-link.en.html#generator')
    expect(helpDocUrl('carrier-link', 'fr', 'balancing')).toBe('/help/carrier-link.fr.html#balancing')
    expect(helpDocUrl('carrier-link', 'ar', 'records')).toBe('/help/carrier-link.ar.html#records')
  })
})


describe('visibleHelpDocs', () => {
  it('oculta la ayuda carrier-link cuando Carrier Link esta deshabilitado', () => {
    expect(visibleHelpDocs(false).some(d => d.id === 'carrier-link')).toBe(false)
    expect(visibleHelpDocs(true).some(d => d.id === 'carrier-link')).toBe(true)
  })
})
