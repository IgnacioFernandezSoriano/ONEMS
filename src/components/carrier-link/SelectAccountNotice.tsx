import { useTranslation } from '@/hooks/useTranslation'

/** Aviso para el superadmin sin cuenta elegida: Carrier Link no lee ni escribe sin cuenta. */
export function SelectAccountNotice() {
  const { t } = useTranslation()
  return (
    <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 text-amber-900">
      <p className="font-medium">{t('cl.select_account.title')}</p>
      <p className="text-sm mt-1">{t('cl.select_account.body')}</p>
    </div>
  )
}
