import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useEffectiveAccountId } from './useEffectiveAccountId'
import { effectivePolicy, type DatePolicy } from '../lib/workingDays'

export interface AccountBalancePolicy {
  date_policy: DatePolicy
  pobox_enabled: boolean
}

export interface CityBalancePolicy {
  id: string
  name: string
  date_policy: DatePolicy | null
  pobox_enabled: boolean | null
}

const DEFAULT_ACCOUNT_POLICY: AccountBalancePolicy = { date_policy: 'daily', pobox_enabled: false }

export function useBalancePolicies() {
  const accountId = useEffectiveAccountId()
  const [account, setAccount] = useState<AccountBalancePolicy | null>(null)
  const [cities, setCities] = useState<CityBalancePolicy[]>([])
  const [loading, setLoading] = useState(true)

  const refetch = useCallback(async () => {
    if (!accountId) {
      setAccount(null)
      setCities([])
      setLoading(false)
      return
    }
    setLoading(true)
    try {
      const [cfg, cts] = await Promise.all([
        supabase.from('account_config').select('date_policy, pobox_enabled').eq('account_id', accountId).maybeSingle(),
        supabase.from('cities').select('id, name, date_policy, pobox_enabled').eq('account_id', accountId).order('name'),
      ])
      if (cfg.error) throw cfg.error
      if (cts.error) throw cts.error
      // Sin fila en account_config se aplican los valores por defecto de la columna
      setAccount((cfg.data as AccountBalancePolicy | null) ?? DEFAULT_ACCOUNT_POLICY)
      setCities((cts.data as CityBalancePolicy[]) ?? [])
    } catch (err) {
      console.error('[useBalancePolicies] Error loading policies:', err)
    } finally {
      setLoading(false)
    }
  }, [accountId])

  useEffect(() => {
    refetch()
  }, [refetch])

  const updateAccountPolicy = async (p: Partial<AccountBalancePolicy>) => {
    if (!accountId) return { success: false, error: 'No account selected' }
    // RPC SECURITY DEFINER (RLS solo deja insertar a admin y deja fuera al superadmin): hace upsert y
    // escribe solo date_policy / pobox_enabled (NULL = no cambiar); nunca pisa calculation_mode.
    const { data, error } = await supabase.rpc('rpc_set_account_balance_policy', {
      p_account_id: accountId,
      p_date_policy: p.date_policy ?? null,
      p_pobox_enabled: p.pobox_enabled ?? null,
    })
    if (error) return { success: false, error: error.message }
    const res = data as { success?: boolean; error?: string } | null
    if (res && res.success === false) return { success: false, error: res.error ?? 'Error' }
    await refetch()
    return { success: true }
  }

  const updateCityPolicy = async (
    cityId: string,
    p: { date_policy?: DatePolicy | null; pobox_enabled?: boolean | null }
  ) => {
    // RPC SECURITY DEFINER (UPDATE de cities por RLS es solo admin). Solo se escriben las claves definidas
    // en p; null = la ciudad hereda de la cuenta.
    const { data, error } = await supabase.rpc('rpc_set_city_balance_policy', {
      p_city_id: cityId,
      p_set_date_policy: p.date_policy !== undefined,
      p_date_policy: p.date_policy ?? null,
      p_set_pobox: p.pobox_enabled !== undefined,
      p_pobox_enabled: p.pobox_enabled ?? null,
    })
    if (error) return { success: false, error: error.message }
    const res = data as { success?: boolean; error?: string } | null
    if (res && res.success === false) return { success: false, error: res.error ?? 'Error' }
    await refetch()
    return { success: true }
  }

  const effectiveFor = (cityId: string): { datePolicy: DatePolicy; pobox: boolean } =>
    effectivePolicy(account ?? DEFAULT_ACCOUNT_POLICY, cities.find((c) => c.id === cityId))

  return { account, cities, updateAccountPolicy, updateCityPolicy, effectiveFor, loading, refetch }
}
