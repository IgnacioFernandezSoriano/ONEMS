import { useAuth } from '../contexts/AuthContext'
import { useAccount } from '../contexts/AccountContext'

/**
 * Hook helper que devuelve el account_id efectivo para filtrar datos
 * 
 * Para usuarios normales: devuelve su account_id
 * Para superadmin sin selección: devuelve null (ve todas las cuentas)
 * Para superadmin con selección: devuelve el account_id seleccionado
 */
export function useEffectiveAccountId(): string | null {
  const { profile } = useAuth()
  const { selectedAccountId } = useAccount()

  // Si es superadmin, usar la cuenta seleccionada (puede ser null = todas)
  if (profile?.role === 'superadmin') {
    return selectedAccountId
  }

  // Para usuarios normales, usar su propia cuenta
  return profile?.account_id || null
}
