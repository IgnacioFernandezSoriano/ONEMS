import { useTranslation } from '@/hooks/useTranslation'

/** Etiqueta "Carrier Link" para la fila del título de cada pantalla de Carrier Link (color de acento propio). */
export function ClBadge() {
  const { t } = useTranslation()
  return (
    <span className="inline-flex items-center rounded-full bg-teal-50 px-2.5 py-0.5 text-xs font-medium text-teal-700 ring-1 ring-inset ring-teal-200">
      {t('menu.carrier_link')}
    </span>
  )
}
