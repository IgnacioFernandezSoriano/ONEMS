import { createContext, useContext, useState, useEffect, ReactNode } from 'react'
import { useAuth } from './AuthContext'
import { supabase } from '../lib/supabase'

interface AccountContextType {
  selectedAccountId: string | null
  setSelectedAccountId: (accountId: string | null) => void
  effectiveAccountId: string | null // La cuenta que se usa para filtrar datos
  accountTimezone: string // Zona horaria IANA de la cuenta efectiva ('UTC' si no hay)
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

  // Zona horaria de la cuenta efectiva
  const [accountTimezone, setAccountTimezone] = useState<string>('UTC')
  useEffect(() => {
    if (!effectiveAccountId) {
      setAccountTimezone('UTC')
      return
    }
    let cancelled = false
    supabase
      .from('accounts')
      .select('timezone')
      .eq('id', effectiveAccountId)
      .maybeSingle()
      .then(({ data, error }) => {
        if (cancelled) return
        setAccountTimezone(error ? 'UTC' : data?.timezone || 'UTC')
      })
    return () => {
      cancelled = true
    }
  }, [effectiveAccountId])

  return (
    <AccountContext.Provider value={{
      selectedAccountId,
      setSelectedAccountId,
      effectiveAccountId,
      accountTimezone
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
