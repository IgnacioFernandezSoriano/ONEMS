import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { Account } from '@/lib/types'

export function useAccounts() {
  const [accounts, setAccounts] = useState<Account[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchAccounts = async () => {
    try {
      setLoading(true)
      const { data, error } = await supabase
        .from('accounts')
        .select('*')
        .order('created_at', { ascending: false })

      if (error) throw error
      setAccounts(data || [])
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchAccounts()
  }, [])

  const createAccount = async (account: { name: string; slug: string }) => {
    const { data, error } = await supabase
      .from('accounts')
      .insert(account as any)
      .select()
      .single()

    if (error) throw error
    await fetchAccounts()
    return data
  }

  const updateAccount = async (id: string, updates: Partial<Account>) => {
    const { error } = await supabase
      .from('accounts')
      .update(updates as any)
      .eq('id', id)

    if (error) throw error
    await fetchAccounts()
  }

  const deleteAccount = async (id: string) => {
    const { error } = await supabase
      .from('accounts')
      .delete()
      .eq('id', id)

    if (error) throw error
    await fetchAccounts()
  }

  return {
    accounts,
    loading,
    error,
    createAccount,
    updateAccount,
    deleteAccount,
    refresh: fetchAccounts,
  }
}
