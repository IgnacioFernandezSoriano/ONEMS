// Catálogo de las páginas de ayuda de public/help (una por idioma: <file>.<idioma>.html).
// Para añadir una ayuda nueva: crear los 4 archivos (docs/help/GUIA-DISENO-AYUDA.md) y añadirla aquí.

export const HELP_LANGS = ['en', 'es', 'fr', 'ar'] as const
export type HelpLang = typeof HELP_LANGS[number]

export interface HelpDoc {
  id: string
  /** Nombre del archivo sin idioma ni extensión */
  file: string
  titleKey: string
  descKey: string
  audience: 'managers' | 'panelists'
  /** Roles que la ven en el Centro de ayuda; sin roles = todos */
  roles?: string[]
  /** Se puede abrir sin iniciar sesión y enviar al panelista */
  public: boolean
}

export const HELP_DOCS: HelpDoc[] = [
  {
    id: 'incidents',
    file: 'incidents-and-availability',
    titleKey: 'help_center.doc.incidents.title',
    descKey: 'help_center.doc.incidents.desc',
    audience: 'managers',
    roles: ['admin', 'superadmin'],
    public: false,
  },
  {
    id: 'panelist-guide',
    file: 'panelist-guide',
    titleKey: 'help_center.doc.panelist_guide.title',
    descKey: 'help_center.doc.panelist_guide.desc',
    audience: 'panelists',
    public: true,
  },
]

export function helpLang(language: string | null | undefined): HelpLang {
  return (HELP_LANGS as readonly string[]).includes(language ?? '') ? (language as HelpLang) : 'en'
}

/** Ruta de la ayuda en el idioma dado; con absolute, incluye el dominio de la web actual. */
export function helpDocUrl(file: string, language: string | null | undefined, section?: string, absolute = false): string {
  const path = `/help/${file}.${helpLang(language)}.html${section ? '#' + section : ''}`
  return absolute ? window.location.origin + path : path
}
