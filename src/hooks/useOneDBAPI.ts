import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'
import { useEffectiveAccountId } from './useEffectiveAccountId'
import { useLatestRequest } from '../lib/latestRequest'

export interface ApiKey {
  id: string
  name: string | null
  key_prefix: string | null
  scope: string
  is_active: boolean
  created_at: string
  last_used_at: string | null
  usage_count: number
  expires_at: string | null
}

/** Resultado de emitir una clave: es la única vez que se conoce el texto completo. */
export interface IssuedApiKey {
  id: string
  api_key: string
}

export interface ApiUsageStats {
  total_calls_this_month: number
  last_call: string | null
  calls_last_hour: number
}

export function useOneDBAPI() {
  const { profile } = useAuth()
  // Cuenta efectiva: un superadmin no tiene account_id en el perfil, usa la cuenta seleccionada
  const effectiveAccountId = useEffectiveAccountId()
  const accountId = effectiveAccountId || profile?.account_id
  const [apiKeys, setApiKeys] = useState<ApiKey[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [usageStats, setUsageStats] = useState<ApiUsageStats | null>(null)
  const beginKeyLoad = useLatestRequest()
  const beginStatsLoad = useLatestRequest()

  useEffect(() => {
    if (accountId) {
      loadApiKey()
      loadUsageStats()
    }
  }, [accountId])

  const loadApiKey = async () => {
    const isStale = beginKeyLoad()
    try {
      setLoading(true)
      const { data, error } = await supabase
        .from('api_keys')
        .select('id, name, key_prefix, scope, is_active, created_at, last_used_at, usage_count, expires_at')
        .eq('account_id', accountId)
        .eq('scope', 'onedb_read')
        .order('created_at', { ascending: false })

      if (isStale()) return
      if (error) throw error

      setApiKeys((data || []) as ApiKey[])
      setError(null)
    } catch (err: any) {
      if (isStale()) return
      console.error('Error loading API key:', err)
      setError(err.message)
    } finally {
      if (!isStale()) setLoading(false)
    }
  }

  const loadUsageStats = async () => {
    const isStale = beginStatsLoad()
    try {
      const { data: keysData } = await supabase
        .from('api_keys')
        .select('id')
        .eq('account_id', accountId)
        .eq('scope', 'onedb_read')

      if (isStale()) return
      const keyIds = (keysData || []).map((k: { id: string }) => k.id)
      if (keyIds.length === 0) { setUsageStats(null); return }

      // Get usage stats for this month
      const startOfMonth = new Date()
      startOfMonth.setDate(1)
      startOfMonth.setHours(0, 0, 0, 0)

      const { data: monthlyData, error: monthlyError } = await supabase
        .from('api_usage_log')
        .select('id', { count: 'exact' })
        .in('api_key_id', keyIds)
        .gte('request_timestamp', startOfMonth.toISOString())

      if (isStale()) return
      // Get last call
      const { data: lastCallData } = await supabase
        .from('api_usage_log')
        .select('request_timestamp')
        .in('api_key_id', keyIds)
        .order('request_timestamp', { ascending: false })
        .limit(1)
        .maybeSingle()

      if (isStale()) return

      // Get calls in last hour
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      const { data: hourlyData } = await supabase
        .from('api_usage_log')
        .select('id', { count: 'exact' })
        .in('api_key_id', keyIds)
        .gte('request_timestamp', oneHourAgo)

      if (isStale()) return

      setUsageStats({
        total_calls_this_month: monthlyData?.length || 0,
        last_call: lastCallData?.request_timestamp || null,
        calls_last_hour: hourlyData?.length || 0
      })
    } catch (err) {
      console.error('Error loading usage stats:', err)
    }
  }

  /** Emite una clave nueva. Devuelve el texto completo, que no se vuelve a poder consultar. */
  const generateApiKey = async (name: string): Promise<IssuedApiKey> => {
    try {
      setError(null)
      const { data, error } = await supabase.rpc('api_key_issue', {
        p_account_id: accountId,
        p_name: name.trim()
      })
      if (error) throw error
      const issued = Array.isArray(data) ? data[0] : data
      if (!issued?.api_key) throw new Error('API key was not returned')
      await loadApiKey()
      loadUsageStats()
      return { id: issued.id, api_key: issued.api_key }
    } catch (err: any) {
      console.error('Error generating API key:', err)
      setError(err.message)
      throw err
    }
  }

  const deactivateApiKey = async (id: string) => {
    try {
      setError(null)
      const { error } = await supabase
        .from('api_keys')
        .update({ is_active: false })
        .eq('id', id)
      if (error) throw error
      await loadApiKey()
    } catch (err: any) {
      console.error('Error deactivating API key:', err)
      setError(err.message)
      throw err
    }
  }

  /** Sustituir = emitir una clave nueva y desactivar la anterior. */
  const replaceApiKey = async (oldId: string, name: string): Promise<IssuedApiKey> => {
    const issued = await generateApiKey(name)
    await deactivateApiKey(oldId)
    return issued
  }

  return {
    apiKeys,
    loading,
    error,
    usageStats,
    generateApiKey,
    replaceApiKey,
    deactivateApiKey,
    refreshStats: loadUsageStats
  }
}
