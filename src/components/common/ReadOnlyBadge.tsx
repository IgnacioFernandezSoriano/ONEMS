import { useTranslation } from '@/hooks/useTranslation'

export function ReadOnlyBadge() {
  const { t } = useTranslation()
  return (
    <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-amber-100 text-amber-800">
      {t('common.read_only')}
    </span>
  )
}
