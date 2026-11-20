import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

/**
 * ¿Es el usuario UPU Account Manager de la cuenta? (rpc is_upu_account_manager).
 * Para un superadmin no se consulta y devuelve false: el superadmin ya tiene su propio derecho.
 * La base vuelve a comprobarlo en cada operación protegida.
 */
export function useIsUpuAccountManager(accountId: string | null): { isUpuAm: boolean; loading: boolean } {
  const { profile } = useAuth()
  const role = profile?.role
  const [isUpuAm, setIsUpuAm] = useState(false)
  const [loading, setLoading] = useState(false)

  useEffect(() => {
    setIsUpuAm(false)
    if (!accountId || role === 'superadmin') {
      setLoading(false)
      return
    }
    let cancelled = false
    setLoading(true)
    supabase.rpc('is_upu_account_manager', { p_account_id: accountId }).then(({ data, error }) => {
      if (cancelled) return
      if (!error) setIsUpuAm(data === true)
      setLoading(false)
    })
    return () => {
      cancelled = true
    }
  }, [accountId, role])

  return { isUpuAm, loading }
}
