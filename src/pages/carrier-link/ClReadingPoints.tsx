import { useTranslation } from '@/hooks/useTranslation'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { SelectAccountNotice } from '@/components/carrier-link/SelectAccountNotice'

export function ClReadingPoints() {
  const { t } = useTranslation()
  const { canEdit } = usePermissions()
  const accountId = useEffectiveAccountId()
  const readOnly = !canEdit('cl_reading_points')

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-gray-900">{t('cl.reading_points.title')}</h1>
        {readOnly && <ReadOnlyBadge />}
      </div>
      <p className="text-sm text-gray-600">{t('cl.reading_points.help')}</p>
      {accountId === null && <SelectAccountNotice />}
    </div>
  )
}
