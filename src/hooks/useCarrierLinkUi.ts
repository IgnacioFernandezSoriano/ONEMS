import { usePermissions } from '@/contexts/PermissionsContext'
import { isCarrierLinkEnabled } from '@/lib/featureFlags'
import { carrierLinkUiVisible } from '@/lib/carrierLinkUi'

const flagOn = isCarrierLinkEnabled()

/** True si esta cuenta debe ver los detalles de Carrier Link en las pantallas comunes. */
export function useCarrierLinkUi(): boolean {
  const { canView } = usePermissions()
  return carrierLinkUiVisible(flagOn, canView)
}
