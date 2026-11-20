import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

/**
 * ¿Es el usuario UPU Account Manager de la cuenta? (rpc is_upu_account_manager).
 * Para un superadmin no se consulta y devuelve false: el superadmin ya tiene su propio derecho.
 * La base vuelve a comprobarlo en cada operación protegida.
 * La respuesta va ligada a la cuenta consultada: al cambiar de cuenta vale false desde el mismo render.
 */
export function useIsUpuAccountManager(accountId: string | null): { isUpuAm: boolean; loading: boolean } {
  const { profile } = useAuth()
  const role = profile?.role
  const [result, setResult] = useState<{ accountId: string; isUpuAm: boolean } | null>(null)

  const skip = !accountId || role === 'superadmin'

  useEffect(() => {
    if (!accountId || role === 'superadmin') return
    let cancelled = false
    supabase.rpc('is_upu_account_manager', { p_account_id: accountId }).then(({ data, error }) => {
      if (cancelled) return
      setResult({ accountId, isUpuAm: !error && data === true })
    })
    return () => {
      cancelled = true
    }
  }, [accountId, role])

  const current = !skip && result?.accountId === accountId ? result : null
  return { isUpuAm: current?.isUpuAm ?? false, loading: !skip && current === null }
}
