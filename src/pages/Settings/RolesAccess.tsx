import { Navigate } from 'react-router-dom'
import { useTranslation } from '@/hooks/useTranslation'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { RolesAccessTab } from '@/components/accounts/RolesAccessTab'

/** "Roles y accesos" de la cuenta elegida. Solo para quien puede editarla (AM, UPU account manager, superadmin). */
export function RolesAccess() {
  const { t } = useTranslation()
  const { canManageAccess, loading } = usePermissions()
  const accountId = useEffectiveAccountId()

  if (loading) return <div className="p-8 text-gray-500">{t('common.loading')}</div>
  if (!canManageAccess) return <Navigate to="/" replace />

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold text-gray-900">{t('roles_access.title')}</h1>
        <p className="mt-1 text-sm text-gray-500">{t('roles_access.description')}</p>
      </div>
      {accountId ? (
        <RolesAccessTab key={accountId} accountId={accountId} canEdit={canManageAccess} />
      ) : (
        <div className="bg-amber-50 text-amber-800 p-3 rounded text-sm">{t('roles_access.select_account')}</div>
      )}
    </div>
  )
}
