// Catálogo de las páginas de ayuda de public/help (una por idioma: <file>.<idioma>.html).
// Para añadir una ayuda nueva: crear los 5 archivos (docs/help/GUIA-DISENO-AYUDA.md) y añadirla aquí.

export const HELP_LANGS = ['en', 'es', 'fr', 'ar', 'pt'] as const
export type HelpLang = typeof HELP_LANGS[number]

export interface HelpDoc {
  id: string
  /** Nombre del archivo sin idioma ni extensión */
  file: string
  titleKey: string
  descKey: string
  audience: 'managers' | 'panelists'
  /** Solo para gestores: la ven superadmin, quien gestiona accesos o quien tiene Edit en alguna opción */
  managersOnly?: boolean
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
    managersOnly: true,
    public: false,
  },
  {
    id: 'receipt-errors',
    file: 'receipt-errors',
    titleKey: 'help_center.doc.receipt_errors.title',
    descKey: 'help_center.doc.receipt_errors.desc',
    audience: 'managers',
    managersOnly: true,
    public: false,
  },
  {
    id: 'case-analysis',
    file: 'case-analysis',
    titleKey: 'help_center.doc.case_analysis.title',
    descKey: 'help_center.doc.case_analysis.desc',
    audience: 'managers',
    managersOnly: true,
    public: false,
  },
  {
    id: 'gps-location',
    file: 'gps-location',
    titleKey: 'help_center.doc.gps_location.title',
    descKey: 'help_center.doc.gps_location.desc',
    audience: 'managers',
    managersOnly: true,
    public: false,
  },
  {
    id: 'load-balancing',
    file: 'load-balancing',
    titleKey: 'help_center.doc.load_balancing.title',
    descKey: 'help_center.doc.load_balancing.desc',
    audience: 'managers',
    managersOnly: true,
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

/** ¿Se muestra la ayuda en el Centro de ayuda? Por derechos de la cuenta, no por el rol legacy. */
export function canSeeHelpDoc(
  doc: Pick<HelpDoc, 'managersOnly'>,
  who: { isSuperadmin: boolean; canManageAccess: boolean; hasAnyEdit: boolean },
): boolean {
  if (!doc.managersOnly) return true
  return who.isSuperadmin || who.canManageAccess || who.hasAnyEdit
}

export function helpLang(language: string | null | undefined): HelpLang {
  return (HELP_LANGS as readonly string[]).includes(language ?? '') ? (language as HelpLang) : 'en'
}

/** Ruta de la ayuda en el idioma dado; con absolute, incluye el dominio de la web actual. */
export function helpDocUrl(file: string, language: string | null | undefined, section?: string, absolute = false): string {
  const path = `/help/${file}.${helpLang(language)}.html${section ? '#' + section : ''}`
  return absolute ? window.location.origin + path : path
}
