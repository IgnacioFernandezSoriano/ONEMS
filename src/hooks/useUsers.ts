import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/contexts/AuthContext'
import type { ProfileWithAccount } from '@/lib/types'

export function useUsers() {
  const { profile } = useAuth()
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
    role?: string
    account_id?: string
    preferred_language?: string
  }) => {
    // Determinar rol y account_id según permisos del usuario actual
    let finalRole = 'user'
    let finalAccountId = userData.account_id

    if (profile?.role === 'superadmin') {
      // Superadmin puede crear admins o users
      finalRole = userData.role || 'admin'
      finalAccountId = userData.account_id
    } else if (profile?.role === 'admin') {
      // Admin solo puede crear users de su cuenta
      finalRole = 'user'
      finalAccountId = profile.account_id || undefined
    } else {
      throw new Error('Unauthorized to create users')
    }

    // Validar que se proporcione account_id para roles que no sean superadmin
    if (finalRole !== 'superadmin' && !finalAccountId) {
      throw new Error('Account is required for this role')
    }

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
        role: finalRole,
        account_id: finalAccountId || undefined,
        preferred_language: userData.preferred_language || 'en',
      } as any)

    if (profileError) {
      // Si falla la creación del perfil, intentar eliminar el usuario de Auth
      await supabase.auth.admin.deleteUser(authData.user.id)
      throw profileError
    }

    await fetchUsers()
  }

  const updateUser = async (id: string, updates: Partial<ProfileWithAccount>) => {
    // Validar que no se intente cambiar el rol o account_id
    const cleanUpdates: any = { ...updates }
    delete cleanUpdates.role
    delete cleanUpdates.account_id
    delete cleanUpdates.email

    // Si se proporciona una nueva contraseña, actualizarla via resetPassword
    if (cleanUpdates.password) {
      await resetPassword(id, cleanUpdates.password)
      delete cleanUpdates.password
    }

    const { error } = await supabase
      .from('profiles')
      .update(cleanUpdates)
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

  const resetPassword = async (userId: string, newPassword: string) => {
    try {
      // Llamar a Edge Function para resetear contraseña
      const { data, error } = await supabase.functions.invoke('admin-reset-password', {
        body: {
          user_id: userId,
          new_password: newPassword
        }
      })

      if (error) throw error
      
      return data
    } catch (err) {
      console.error('Error resetting password:', err)
      throw err
    }
  }

  return {
    users,
    loading,
    error,
    createUser,
    updateUser,
    deleteUser,
    resetPassword,
    refresh: fetchUsers,
  }
}
