import { useState, useEffect } from 'react'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/contexts/AuthContext'
import type { ProfileWithAccount, Profile, Role } from '@/lib/types'

/**
 * Reglas de cambio de rol. Espejo de las políticas RLS de `public.profiles`
 * (ver 20260715120000_fix_profiles_role_update_policies.sql): esto sólo da un
 * mensaje de error decente en la UI; quien manda es RLS.
 *
 *  - superadmin: cualquier rol, en cualquier cuenta.
 *  - admin:      sólo entre `admin` y `user`, y sólo dentro de su cuenta.
 *  - user:       ningún cambio de rol.
 */
function assertRoleChangeAllowed(
  actor: Profile | null,
  target: ProfileWithAccount,
  nextRole: Role
) {
  if (actor?.role === 'superadmin') return

  if (actor?.role === 'admin') {
    if (target.account_id !== actor.account_id) {
      throw new Error('You can only change roles of users in your own account')
    }
    if (target.role === 'superadmin' || nextRole === 'superadmin') {
      throw new Error('Only a superadmin can grant or revoke the superadmin role')
    }
    return
  }

  throw new Error('You do not have permission to change roles')
}

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
    const target = users.find((u) => u.id === id)
    if (!target) throw new Error('User not found')

    const cleanUpdates: any = { ...updates }
    delete cleanUpdates.email

    const nextRole = cleanUpdates.role as Role | undefined
    const roleChanged = !!nextRole && nextRole !== target.role

    if (!roleChanged) {
      // Sin cambio de rol no se toca ni el rol ni la cuenta: mover un perfil de
      // cuenta es una operación aparte (`transferUser`).
      delete cleanUpdates.role
      delete cleanUpdates.account_id
    } else {
      assertRoleChangeAllowed(profile, target, nextRole!)

      // La restricción `check_account_role` exige que un superadmin no tenga
      // cuenta y que cualquier otro rol sí la tenga, así que rol y cuenta viajan
      // juntos en el mismo UPDATE.
      if (nextRole === 'superadmin') {
        cleanUpdates.account_id = null
      } else if (target.role === 'superadmin') {
        if (!cleanUpdates.account_id) {
          throw new Error('An account is required when a superadmin is demoted')
        }
      } else {
        delete cleanUpdates.account_id
      }
    }

    // Si se proporciona una nueva contraseña, actualizarla via resetPassword
    if (cleanUpdates.password) {
      await resetPassword(id, cleanUpdates.password)
      delete cleanUpdates.password
    }

    // `.select()` es imprescindible: si RLS filtra la fila, el UPDATE no es un
    // error, simplemente afecta a 0 filas y el cambio se perdería en silencio.
    const { data, error } = await supabase
      .from('profiles')
      .update(cleanUpdates)
      .eq('id', id)
      .select('id')

    if (error) throw error
    if (!data || data.length === 0) {
      throw new Error('The change was rejected: you do not have permission to update this user')
    }
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
