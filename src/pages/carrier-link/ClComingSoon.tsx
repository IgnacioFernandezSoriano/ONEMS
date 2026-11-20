import { useTranslation } from '@/hooks/useTranslation'
import { ClBadge } from '@/components/carrier-link/ClBadge'

/** Pantalla temporal de Carrier Link: solo cabecera y aviso "en preparación" (se sustituye por la real). */
export function ClComingSoon({ titleKey }: { titleKey: string }) {
  const { t } = useTranslation()
  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-gray-900">{t(titleKey)}</h1>
        <ClBadge />
      </div>
      <p className="text-gray-600">{t('cl.coming_soon')}</p>
    </div>
  )
}
