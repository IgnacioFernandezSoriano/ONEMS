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
    // Un upsert con calculation_mode pisaria el valor de una fila existente: se distingue
    // actualizar (fila existente) de insertar (cuenta sin fila; calculation_mode tiene DEFAULT).
    const { data: existing, error: selErr } = await supabase
      .from('account_config').select('id').eq('account_id', accountId).maybeSingle()
    if (selErr) return { success: false, error: selErr.message }
    const { error } = existing
      ? await supabase.from('account_config').update(p).eq('account_id', accountId)
      : await supabase.from('account_config').insert({ account_id: accountId, calculation_mode: 'natural_days', ...p })
    if (error) return { success: false, error: error.message }
    await refetch()
    return { success: true }
  }

  const updateCityPolicy = async (
    cityId: string,
    p: { date_policy?: DatePolicy | null; pobox_enabled?: boolean | null }
  ) => {
    const { error } = await supabase.from('cities').update(p).eq('id', cityId)
    if (error) return { success: false, error: error.message }
    await refetch()
    return { success: true }
  }

  const effectiveFor = (cityId: string): { datePolicy: DatePolicy; pobox: boolean } =>
    effectivePolicy(account ?? DEFAULT_ACCOUNT_POLICY, cities.find((c) => c.id === cityId))

  return { account, cities, updateAccountPolicy, updateCityPolicy, effectiveFor, loading, refetch }
}
