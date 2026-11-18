import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { supabase } from '../lib/supabase'
import { useLatestRequest } from '../lib/latestRequest'
import { useAuth } from './AuthContext'
import { useEffectiveAccountId } from '../hooks/useEffectiveAccountId'
import { ACCESS_OPTIONS, isPermissionsLoading, type AccessLevel, type AccessOption } from '../lib/access'

interface PermissionsValue {
  loading: boolean
  level: (o: AccessOption) => AccessLevel | null
  canView: (o: AccessOption) => boolean
  canEdit: (o: AccessOption) => boolean
  canManageAccess: boolean
  isProvisional: boolean
  reload: () => void
}

const PermissionsContext = createContext<PermissionsValue | undefined>(undefined)

const ALL_EDIT: Map<AccessOption, AccessLevel> = new Map(ACCESS_OPTIONS.map(o => [o.key, 'edit' as AccessLevel]))
const EMPTY: Map<AccessOption, AccessLevel> = new Map()

export function PermissionsProvider({ children }: { children: ReactNode }) {
  const { user, profile } = useAuth()
  const accountId = useEffectiveAccountId()
  const begin = useLatestRequest()
  const [loaded, setLoaded] = useState<{ key: string; levels: Map<AccessOption, AccessLevel>; manage: boolean; prov: boolean } | null>(null)
  const [tick, setTick] = useState(0)

  const isSuper = profile?.role === 'superadmin'
  const userId = user?.id ?? null
  const key = userId && accountId ? `${userId}|${accountId}` : null

  useEffect(() => {
    const isStale = begin()
    if (isSuper || !userId || !accountId || !key) return
    ;(async () => {
      let result = { key, levels: EMPTY, manage: false, prov: false }
      try {
        const [acc, mng, prov] = await Promise.all([
          supabase.rpc('my_access', { p_account_id: accountId }),
          supabase.rpc('can_manage_account_access', { p_account_id: accountId }),
          supabase.from('account_user_role').select('role')
            .eq('user_id', userId).eq('account_id', accountId).eq('provisional', true).limit(1),
        ])
        if (isStale()) return
        if (acc.error) console.error('my_access', acc.error)
        if (mng.error) console.error('can_manage_account_access', mng.error)
        if (prov.error) console.error('account_user_role provisional', prov.error)
        const m = new Map<AccessOption, AccessLevel>()
        for (const r of (acc.data ?? []) as { option: AccessOption; level: AccessLevel }[]) m.set(r.option, r.level)
        result = { key, levels: m, manage: mng.data === true, prov: ((prov.data ?? []) as unknown[]).length > 0 }
      } catch (e) {
        if (isStale()) return
        console.error('permissions', e)
      }
      setLoaded(result)
    })()
  }, [isSuper, userId, accountId, key, tick, begin])

  const reload = useCallback(() => setTick(t => t + 1), [])

  const value = useMemo<PermissionsValue>(() => {
    // Superadmin: todo en edición, sin depender de la cuenta ni del RPC.
    const fresh = loaded && loaded.key === key ? loaded : null
    const levels = isSuper ? ALL_EDIT : fresh?.levels ?? EMPTY
    return {
      // Carga pendiente mientras la clave (usuario+cuenta) actual no coincide con la de los niveles guardados.
      loading: isSuper ? false : isPermissionsLoading(key, loaded?.key ?? null),
      level: o => levels.get(o) ?? null,
      canView: o => levels.has(o),
      canEdit: o => levels.get(o) === 'edit',
      canManageAccess: isSuper ? true : fresh?.manage ?? false,
      isProvisional: isSuper ? false : fresh?.prov ?? false,
      reload,
    }
  }, [isSuper, key, loaded, reload])

  return <PermissionsContext.Provider value={value}>{children}</PermissionsContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function usePermissions(): PermissionsValue {
  const ctx = useContext(PermissionsContext)
  if (!ctx) throw new Error('usePermissions must be used within PermissionsProvider')
  return ctx
}
