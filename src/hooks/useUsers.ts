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
    // La creación se hace en la Edge Function `create-user`, que usa service_role
    // para: (a) crear el usuario ya confirmado (email_confirm: true), sin enviar
    // correo ni tocar la sesión del admin, y (b) resolver rol/cuenta server-side.
    const { data, error } = await supabase.functions.invoke('create-user', {
      body: {
        email: userData.email,
        password: userData.password,
        full_name: userData.full_name,
        role: userData.role,
        account_id: userData.account_id,
        preferred_language: userData.preferred_language,
      },
    })

    if (error) {
      // En supabase-js v2, si la función responde no-2xx, el cuerpo está en
      // error.context (un Response). Extraemos el mensaje legible de la función.
      let message = error.message
      try {
        const body = await (error as any).context?.json?.()
        if (body?.error) message = body.error
      } catch {
        // sin cuerpo JSON: nos quedamos con error.message
      }
      throw new Error(message)
    }

    await fetchUsers()
    return data
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
    // Borrado vía Edge Function `delete-user` (service_role). El perfil cae por
    // CASCADE (ON DELETE CASCADE). No se puede borrar con anon key desde el cliente.
    const { data, error } = await supabase.functions.invoke('delete-user', {
      body: { user_id: id },
    })

    if (error) {
      let message = error.message
      try {
        const body = await (error as any).context?.json?.()
        if (body?.error) message = body.error
      } catch {
        // sin cuerpo JSON: nos quedamos con error.message
      }
      throw new Error(message)
    }

    await fetchUsers()
    return data
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

  const transferUser = async (userId: string, newAccountId: string) => {
    // Solo superadmin puede transferir usuarios
    if (profile?.role !== 'superadmin') {
      throw new Error('Only superadmin can transfer users between accounts')
    }

    const { error } = await supabase
      .from('profiles')
      .update({ account_id: newAccountId } as any)
      .eq('id', userId)

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
    transferUser,
    resetPassword,
    refresh: fetchUsers,
  }
}
