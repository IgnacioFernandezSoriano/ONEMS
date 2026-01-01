import { useState, useEffect } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

export interface ApiKey {
  id: string
  account_id: string
  api_key: string
  is_active: boolean
  created_at: string
  last_used_at: string | null
  usage_count: number
}

export interface ApiUsageStats {
  total_calls_this_month: number
  last_call: string | null
  calls_last_hour: number
}

export function useOneDBAPI() {
  const { profile } = useAuth()
  const [apiKey, setApiKey] = useState<ApiKey | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [usageStats, setUsageStats] = useState<ApiUsageStats | null>(null)

  useEffect(() => {
    if (profile?.account_id) {
      loadApiKey()
      loadUsageStats()
    }
  }, [profile?.account_id])

  const loadApiKey = async () => {
    try {
      setLoading(true)
      const { data, error } = await supabase
        .from('api_keys')
        .select('*')
        .eq('account_id', profile?.account_id)
        .eq('is_active', true)
        .order('created_at', { ascending: false })
        .limit(1)
        .single()

      if (error && error.code !== 'PGRST116') { // PGRST116 = no rows returned
        throw error
      }

      setApiKey(data)
      setError(null)
    } catch (err: any) {
      console.error('Error loading API key:', err)
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const loadUsageStats = async () => {
    try {
      // Get API key ID first
      const { data: keyData } = await supabase
        .from('api_keys')
        .select('id')
        .eq('account_id', profile?.account_id)
        .eq('is_active', true)
        .single()

      if (!keyData) return

      // Get usage stats for this month
      const startOfMonth = new Date()
      startOfMonth.setDate(1)
      startOfMonth.setHours(0, 0, 0, 0)

      const { data: monthlyData, error: monthlyError } = await supabase
        .from('api_usage_log')
        .select('id', { count: 'exact' })
        .eq('api_key_id', keyData.id)
        .gte('request_timestamp', startOfMonth.toISOString())

      // Get last call
      const { data: lastCallData } = await supabase
        .from('api_usage_log')
        .select('request_timestamp')
        .eq('api_key_id', keyData.id)
        .order('request_timestamp', { ascending: false })
        .limit(1)
        .single()

      // Get calls in last hour
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString()
      const { data: hourlyData } = await supabase
        .from('api_usage_log')
        .select('id', { count: 'exact' })
        .eq('api_key_id', keyData.id)
        .gte('request_timestamp', oneHourAgo)

      setUsageStats({
        total_calls_this_month: monthlyData?.length || 0,
        last_call: lastCallData?.request_timestamp || null,
        calls_last_hour: hourlyData?.length || 0
      })
    } catch (err) {
      console.error('Error loading usage stats:', err)
    }
  }

  const generateApiKey = async () => {
    try {
      setLoading(true)
      
      // Generate random API key
      const randomString = Array.from(crypto.getRandomValues(new Uint8Array(24)))
        .map(b => b.toString(16).padStart(2, '0'))
        .join('')
      const newApiKey = `onedb_live_${randomString}`

      const { data, error } = await supabase
        .from('api_keys')
        .insert({
          account_id: profile?.account_id,
          api_key: newApiKey,
          is_active: true,
          created_by: profile?.id
        })
        .select()
        .single()

      if (error) throw error

      setApiKey(data)
      setError(null)
      return data
    } catch (err: any) {
      console.error('Error generating API key:', err)
      setError(err.message)
      throw err
    } finally {
      setLoading(false)
    }
  }

  const regenerateApiKey = async () => {
    try {
      setLoading(true)

      // Deactivate old key
      if (apiKey) {
        await supabase
          .from('api_keys')
          .update({ is_active: false })
          .eq('id', apiKey.id)
      }

      // Generate new key
      const newKey = await generateApiKey()
      return newKey
    } catch (err: any) {
      console.error('Error regenerating API key:', err)
      setError(err.message)
      throw err
    } finally {
      setLoading(false)
    }
  }

  const deactivateApiKey = async () => {
    try {
      if (!apiKey) return

      setLoading(true)
      const { error } = await supabase
        .from('api_keys')
        .update({ is_active: false })
        .eq('id', apiKey.id)

      if (error) throw error

      setApiKey(null)
      setError(null)
    } catch (err: any) {
      console.error('Error deactivating API key:', err)
      setError(err.message)
      throw err
    } finally {
      setLoading(false)
    }
  }

  return {
    apiKey,
    loading,
    error,
    usageStats,
    generateApiKey,
    regenerateApiKey,
    deactivateApiKey,
    refreshStats: loadUsageStats
  }
}
