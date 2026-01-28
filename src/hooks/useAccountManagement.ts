import { useState } from 'react'
import { supabase } from '@/lib/supabase'

export interface Account {
  id: string
  name: string
  created_at: string
}

export interface ResetResult {
  success: boolean
  account_id?: string
  account_name?: string
  message: string
  deleted_records?: Record<string, number>
  inserted_records?: Record<string, number>
}

export function useAccountManagement() {
  const [accounts, setAccounts] = useState<Account[]>([])
  const [loading, setLoading] = useState(false)
  const [resetting, setResetting] = useState(false)

  const fetchAccounts = async () => {
    setLoading(true)
    try {
      const { data, error } = await supabase
        .from('accounts')
        .select('id, name, created_at')
        .eq('name', 'DEMO2')
        .single()

      if (error) throw error
      setAccounts(data ? [data] : [])
    } catch (error) {
      console.error('Error fetching DEMO2 account:', error)
    } finally {
      setLoading(false)
    }
  }

  const resetAccountData = async (accountIdentifier: string): Promise<ResetResult> => {
    setResetting(true)
    try {
      const { data, error } = await supabase.rpc('admin_reset_and_seed_demo2')

      if (error) throw error

      return data as ResetResult
    } catch (error: any) {
      console.error('Error resetting account:', error)
      return {
        success: false,
        message: error.message || 'Failed to reset account data'
      }
    } finally {
      setResetting(false)
    }
  }

  return {
    accounts,
    loading,
    resetting,
    fetchAccounts,
    resetAccountData
  }
}
