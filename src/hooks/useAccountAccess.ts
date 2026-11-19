import { useCallback, useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useLatestRequest } from '../lib/latestRequest'
import { ACCOUNT_CONTACT_FIELDS, type AccountContactField } from '../lib/types'
import type { AccessLevel, AccountRole } from '../lib/access'
import {
  buildLevelMap, mergeAccountUsers, type AccountUser, type LevelMap, type LogEntry, type ProfileLite, type RoleRow,
} from '../lib/accessAdmin'

export type Contacts = Record<AccountContactField, string>

interface AccessData {
  accountId: string
  matrix: LevelMap
  noRole: Map<string, AccessLevel>
  users: AccountUser[]
  contacts: Contacts
  log: LogEntry[]
  /** id -> correo, de los perfiles legibles y de los avisos del registro. */
  emails: Map<string, string>
}

/** Fila de public.account_members (ya sin superadmins). */
interface MemberRow {
  user_id: string
  email: string | null
  full_name: string | null
  active_here: boolean
  roles: string[]
  provisional: boolean
}

function emptyContacts(): Contacts {
  const c = {} as Contacts
  for (const f of ACCOUNT_CONTACT_FIELDS) c[f] = ''
  return c
}

/** RPC que lanza el error de Supabase (con su mensaje) para que la UI lo traduzca. */
async function rpc(fn: string, args: Record<string, unknown>): Promise<void> {
  const { error } = await supabase.rpc(fn, args)
  if (error) throw new Error(error.message)
}

/**
 * Datos y acciones de la pestaña "Roles y accesos" de una cuenta: matriz, columna "Sin rol" (plantilla),
 * usuarios con sus roles, contactos y últimos 50 cambios. Las escrituras van por los RPC (que comprueban
 * quién puede editar); tras cada una se recarga todo.
 */
export function useAccountAccess(accountId: string | null) {
  const begin = useLatestRequest()
  const [data, setData] = useState<AccessData | null>(null)
  const [failed, setFailed] = useState<{ accountId: string; message: string } | null>(null)
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const isStale = begin()
    if (!accountId) return
    ;(async () => {
      try {
        const [acc, tpl, roles, members, people, account, log] = await Promise.all([
          supabase.from('account_access').select('role, option, level').eq('account_id', accountId),
          supabase.from('access_template').select('option, level').eq('role', 'no_role'),
          supabase.from('account_user_role').select('user_id, role, provisional').eq('account_id', accountId),
          // Miembros y autores del registro por RPC: la RLS de profiles no deja leerlos a un gestor
          // con profiles.role = 'user' ni a quien tiene rol aquí con otra cuenta activa.
          supabase.rpc('account_members', { p_account_id: accountId }),
          supabase.rpc('account_log_people', { p_account_id: accountId }),
          supabase.from('accounts').select(ACCOUNT_CONTACT_FIELDS.join(', ')).eq('id', accountId).maybeSingle(),
          supabase.from('account_access_log').select('id, changed_by, changed_at, kind, detail')
            .eq('account_id', accountId).order('changed_at', { ascending: false }).order('id', { ascending: false })
            .limit(50),
        ])
        if (isStale()) return
        const firstError = [acc, tpl, roles, members, people, account, log].find(r => r.error)?.error
        if (firstError) throw new Error(firstError.message)

        const roleRows = (roles.data ?? []) as RoleRow[]
        const logRows = (log.data ?? []) as LogEntry[]
        const profiles: ProfileLite[] = ((members.data ?? []) as MemberRow[]).map(m => ({
          id: m.user_id,
          email: m.email,
          full_name: m.full_name,
          account_id: m.active_here ? accountId : null,
        }))

        const emails = new Map<string, string>()
        for (const l of logRows) {
          const d = (l.detail ?? {}) as Record<string, unknown>
          if (l.kind === 'user_role_add_by_email' && typeof d.user_id === 'string' && typeof d.email === 'string') {
            emails.set(d.user_id, d.email)
          }
        }
        for (const p of (people.data ?? []) as { user_id: string; email: string | null }[]) if (p.email) emails.set(p.user_id, p.email)
        for (const p of profiles) if (p.email) emails.set(p.id, p.email)

        const contacts = emptyContacts()
        const row = (account.data ?? {}) as Partial<Record<AccountContactField, string | null>>
        for (const f of ACCOUNT_CONTACT_FIELDS) contacts[f] = row[f] ?? ''

        const noRole = new Map<string, AccessLevel>()
        for (const r of (tpl.data ?? []) as { option: string; level: AccessLevel }[]) noRole.set(r.option, r.level)

        setData({
          accountId,
          matrix: buildLevelMap((acc.data ?? []) as { role: string; option: string; level: string }[]),
          noRole,
          users: mergeAccountUsers(accountId, profiles, roleRows, emails),
          contacts,
          log: logRows,
          emails,
        })
        setFailed(null)
      } catch (e) {
        if (isStale()) return
        console.error('useAccountAccess', e)
        setFailed({ accountId, message: e instanceof Error ? e.message : String(e) })
      }
    })()
  }, [accountId, tick, begin])

  const reload = useCallback(() => setTick(t => t + 1), [])

  const after = useCallback(async (p: Promise<void>) => {
    try {
      await p
    } finally {
      reload()
    }
  }, [reload])

  const setLevel = useCallback((role: AccountRole, option: string, level: AccessLevel | null) =>
    after(rpc('account_access_set', { p_account_id: accountId, p_role: role, p_option: option, p_level: level })),
  [accountId, after])

  const resetToTemplate = useCallback(() =>
    after(rpc('account_access_reset', { p_account_id: accountId })), [accountId, after])

  const setUserRole = useCallback((userId: string, role: AccountRole, enabled: boolean) =>
    after(rpc('account_user_role_set', { p_account_id: accountId, p_user_id: userId, p_role: role, p_enabled: enabled })),
  [accountId, after])

  const addUserByEmail = useCallback((email: string, role: AccountRole) =>
    after(rpc('account_user_role_add_by_email', { p_account_id: accountId, p_email: email.trim(), p_role: role })),
  [accountId, after])

  const saveContacts = useCallback((contacts: Contacts) =>
    after(rpc('account_contacts_set', { p_account_id: accountId, p_contacts: contacts })), [accountId, after])

  // Solo vale lo cargado para la cuenta actual (evita enseñar la anterior mientras carga la nueva).
  const fresh = data && data.accountId === accountId ? data : null
  const loadError = failed && failed.accountId === accountId ? failed.message : null
  return {
    data: fresh,
    loading: !!accountId && !fresh && !loadError,
    loadError,
    reload,
    setLevel,
    resetToTemplate,
    setUserRole,
    addUserByEmail,
    saveContacts,
  }
}
