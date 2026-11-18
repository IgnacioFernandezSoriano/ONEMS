import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from 'react'
import { supabase } from '../lib/supabase'
import { useLatestRequest } from '../lib/latestRequest'
import { useAuth } from './AuthContext'
import { useEffectiveAccountId } from '../hooks/useEffectiveAccountId'
import type { AccessLevel, AccessOption } from '../lib/access'

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

export function PermissionsProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth()
  const accountId = useEffectiveAccountId()
  const begin = useLatestRequest()
  const [levels, setLevels] = useState<Map<AccessOption, AccessLevel>>(new Map())
  const [canManageAccess, setCanManageAccess] = useState(false)
  const [isProvisional, setIsProvisional] = useState(false)
  const [loading, setLoading] = useState(true)
  const [tick, setTick] = useState(0)

  useEffect(() => {
    const isStale = begin()
    if (!user || !accountId) {
      setLevels(new Map())
      setCanManageAccess(false)
      setIsProvisional(false)
      setLoading(false)
      return
    }
    setLoading(true)
    ;(async () => {
      try {
        const [acc, mng, prov] = await Promise.all([
          supabase.rpc('my_access', { p_account_id: accountId }),
          supabase.rpc('can_manage_account_access', { p_account_id: accountId }),
          supabase.from('account_user_role').select('role')
            .eq('user_id', user.id).eq('account_id', accountId).eq('provisional', true).limit(1),
        ])
        if (isStale()) return
        if (acc.error) console.error('my_access', acc.error)
        const m = new Map<AccessOption, AccessLevel>()
        for (const r of (acc.data ?? []) as { option: AccessOption; level: AccessLevel }[]) m.set(r.option, r.level)
        setLevels(m)
        setCanManageAccess(mng.data === true)
        setIsProvisional(((prov.data ?? []) as unknown[]).length > 0)
      } catch (e) {
        if (isStale()) return
        console.error('permissions', e)
        setLevels(new Map())
        setCanManageAccess(false)
        setIsProvisional(false)
      } finally {
        if (!isStale()) setLoading(false)
      }
    })()
  }, [user, accountId, tick, begin])

  const reload = useCallback(() => setTick(t => t + 1), [])

  const value = useMemo<PermissionsValue>(() => ({
    loading,
    level: o => levels.get(o) ?? null,
    canView: o => levels.has(o),
    canEdit: o => levels.get(o) === 'edit',
    canManageAccess,
    isProvisional,
    reload,
  }), [loading, levels, canManageAccess, isProvisional, reload])

  return <PermissionsContext.Provider value={value}>{children}</PermissionsContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function usePermissions(): PermissionsValue {
  const ctx = useContext(PermissionsContext)
  if (!ctx) throw new Error('usePermissions must be used within PermissionsProvider')
  return ctx
}
