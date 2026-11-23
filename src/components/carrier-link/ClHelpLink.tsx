import { HelpCircle } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { helpDocUrl } from '@/lib/helpDocs'
import { isCarrierLinkEnabled } from '@/lib/featureFlags'

export type ClHelpSection = 'generator' | 'balancing' | 'records' | 'samples' | 'reading-points' | 'connectors' | 'monitor'

/**
 * Enlace «Ayuda» junto al título de las pantallas con Carrier Link; abre su apartado de la ayuda en otra pestaña.
 * Solo se muestra si Carrier Link está habilitado en este entorno.
 */
export function ClHelpLink({ section }: { section: ClHelpSection }) {
  const { t, locale } = useTranslation()
  if (!isCarrierLinkEnabled()) return null
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
