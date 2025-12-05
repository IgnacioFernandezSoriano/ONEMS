import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import type { ProfileWithAccount } from '@/lib/types'

export function useUsers() {
  const [users, setUsers] = useState<ProfileWithAccount[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const fetchUsers = async () => {
    try {
      setLoading(true)
      const { data, error } = await supabase
        .from('profiles')
        .select('*, account:accounts(*)')
        .order('created_at', { ascending: false })

      if (error) throw error
      setUsers(data || [])
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    fetchUsers()
  }, [])

  const createUser = async (userData: {
    email: string
    password: string
    full_name: string
    role: string
    account_id?: string
  }) => {
    // 1. Crear usuario en Supabase Auth
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email: userData.email,
      password: userData.password,
    })

    if (authError) throw authError
    if (!authData.user) throw new Error('Failed to create user')

    // 2. Crear perfil
    const { error: profileError } = await supabase
      .from('profiles')
      .insert({
        id: authData.user.id,
        email: userData.email,
        full_name: userData.full_name,
        role: userData.role,
        account_id: userData.account_id || null,
      } as any)

    if (profileError) throw profileError
    await fetchUsers()
  }

  const updateUser = async (id: string, updates: Partial<ProfileWithAccount>) => {
    const { error } = await supabase
      .from('profiles')
      .update(updates as any)
      .eq('id', id)

    if (error) throw error
    await fetchUsers()
  }

  const deleteUser = async (id: string) => {
    // Nota: Esto solo desactiva el perfil, no elimina el usuario de Auth
    const { error } = await supabase
      .from('profiles')
      .update({ status: 'inactive' } as any)
      .eq('id', id)

    if (error) throw error
    await fetchUsers()
  }

  return {
    users,
    loading,
    error,
    createUser,
    updateUser,
    deleteUser,
    refresh: fetchUsers,
  }
}
