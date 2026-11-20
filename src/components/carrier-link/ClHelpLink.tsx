import { HelpCircle } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { helpDocUrl } from '@/lib/helpDocs'

/** Enlace «Ayuda» junto al título de cada pantalla de Carrier Link; abre su apartado de la ayuda en otra pestaña. */
export function ClHelpLink({ section }: { section: 'plans' | 'samples' | 'reading-points' | 'connectors' | 'monitor' }) {
  const { t, locale } = useTranslation()
  return (
    <a
      href={helpDocUrl('carrier-link', locale, section)}
      target="_blank"
      rel="noreferrer"
      className="inline-flex items-center gap-1 text-sm text-blue-600 hover:text-blue-800"
    >
      <HelpCircle className="w-4 h-4" />
      {t('cl.help_link')}
    </a>
  )
}
