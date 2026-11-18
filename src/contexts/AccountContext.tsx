import { createContext, useCallback, useContext, useState, useEffect, ReactNode } from 'react'
import { useAuth } from './AuthContext'
import { supabase } from '../lib/supabase'
import { useLatestRequest } from '../lib/latestRequest'

export interface MyAccount {
  account_id: string
  name: string
}

interface AccountContextType {
  selectedAccountId: string | null
  setSelectedAccountId: (accountId: string | null) => void
  effectiveAccountId: string | null // La cuenta que se usa para filtrar datos
  accountTimezone: string // Zona horaria IANA de la cuenta efectiva ('UTC' si no hay)
  /** Cuentas en las que el usuario (no superadmin) puede trabajar: la activa + donde tiene rol. */
  myAccounts: MyAccount[]
  /** Cambia la cuenta activa (profiles.account_id). Si va bien recarga la página entera; devuelve false si falla. */
  switchActiveAccount: (accountId: string) => Promise<boolean>
}

const AccountContext = createContext<AccountContextType | undefined>(undefined)

export function AccountProvider({ children }: { children: ReactNode }) {
  const { user, profile } = useAuth()
  // Start from the saved selection so a superadmin's first load is already scoped to it (only
  // superadmins use selectedAccountId; for everyone else effectiveAccountId ignores it).
  const [selectedAccountId, setSelectedAccountId] = useState<string | null>(() => {
    try {
      return localStorage.getItem('selectedAccountId')
    } catch {
      return null
    }
  })

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

  // Cuentas disponibles para el selector de los usuarios no superadmin (el superadmin usa selectedAccountId).
  const beginMyAccounts = useLatestRequest()
  const [myAccounts, setMyAccounts] = useState<MyAccount[]>([])
  const isSuperadmin = profile?.role === 'superadmin'
  const userId = user?.id ?? null
  const hasProfile = !!profile
  // Recargar cuando cambia la cuenta activa (la lista incluye la activa).
  const activeAccountId = profile?.account_id ?? null
  useEffect(() => {
    const isStale = beginMyAccounts()
    setMyAccounts([])
    if (!userId || !hasProfile || isSuperadmin) return
    supabase.rpc('my_accounts').then(({ data, error }) => {
      if (isStale()) return
      if (error) {
        console.error('my_accounts', error)
        return
      }
      setMyAccounts(((data ?? []) as MyAccount[]).slice().sort((a, b) => a.name.localeCompare(b.name)))
    })
  }, [userId, hasProfile, isSuperadmin, activeAccountId, beginMyAccounts])

  const switchActiveAccount = useCallback(async (accountId: string): Promise<boolean> => {
    const { error } = await supabase.rpc('set_active_account', { p_account_id: accountId })
    if (error) {
      console.error('set_active_account', error)
      return false
    }
    // Recarga completa: vuelve a leer el perfil y los derechos, y ninguna pantalla conserva datos de la cuenta anterior.
    window.location.reload()
    return true
  }, [])

  return (
    <AccountContext.Provider value={{
      selectedAccountId,
      setSelectedAccountId,
      effectiveAccountId,
      accountTimezone,
      myAccounts,
      switchActiveAccount
    }}>
      {children}
    </AccountContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAccount() {
  const context = useContext(AccountContext)
  if (context === undefined) {
    throw new Error('useAccount must be used within an AccountProvider')
  }
  return context
}
