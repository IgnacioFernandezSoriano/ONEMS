import { useTranslation } from '@/hooks/useTranslation'
import { usePermissions } from '@/contexts/PermissionsContext'

/** Aviso visible cuando los derechos no se pudieron cargar: nunca redirigir, ofrecer reintentar. */
export function PermissionsError() {
  const { t } = useTranslation()
  const { reload } = usePermissions()
  return (
    <div className="min-h-[50vh] flex flex-col items-center justify-center gap-4 p-8 text-center">
      <p className="text-gray-700 max-w-md">{t('roles_access.rights_load_error')}</p>
      <button
        type="button"
        onClick={reload}
        className="px-4 py-2 rounded-md bg-blue-600 text-white hover:bg-blue-700"
      >
        {t('roles_access.rights_retry')}
      </button>
    </div>
  )
}
