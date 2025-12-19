import { createContext, useContext, useState, useEffect, ReactNode } from 'react'
import { useAuth } from './AuthContext'

interface AccountContextType {
  selectedAccountId: string | null
  setSelectedAccountId: (accountId: string | null) => void
  effectiveAccountId: string | null // La cuenta que se usa para filtrar datos
}

const AccountContext = createContext<AccountContextType | undefined>(undefined)

export function AccountProvider({ children }: { children: ReactNode }) {
  const { profile } = useAuth()
  const [selectedAccountId, setSelectedAccountId] = useState<string | null>(null)

  // Calcular el account_id efectivo para filtrar datos
  const effectiveAccountId = profile?.role === 'superadmin' 
    ? selectedAccountId  // Superadmin usa la cuenta seleccionada (null = todas)
    : profile?.account_id || null  // Usuarios normales usan su propia cuenta

  // Guardar la selección en localStorage para persistencia
  useEffect(() => {
    if (profile?.role === 'superadmin' && selectedAccountId) {
      localStorage.setItem('selectedAccountId', selectedAccountId)
    }
  }, [selectedAccountId, profile?.role])

  // Restaurar la selección al cargar
  useEffect(() => {
    if (profile?.role === 'superadmin') {
      const saved = localStorage.getItem('selectedAccountId')
      if (saved) {
        setSelectedAccountId(saved)
      }
    }
  }, [profile?.role])

  return (
    <AccountContext.Provider value={{ 
      selectedAccountId, 
      setSelectedAccountId,
      effectiveAccountId 
    }}>
      {children}
    </AccountContext.Provider>
  )
}

export function useAccount() {
  const context = useContext(AccountContext)
  if (context === undefined) {
    throw new Error('useAccount must be used within an AccountProvider')
  }
  return context
}
