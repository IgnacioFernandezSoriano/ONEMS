import { useEffect, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '@/contexts/AuthContext'
import { useAccount } from '@/contexts/AccountContext'
import { supabase } from '@/lib/supabase'

/**
 * Herramientas de demo (generador ONDB, reinicio de datos): solo para superadmin o cuenta efectiva DEMO2.
 * Si no, redirige a '/'. Se usa dentro de ProtectedRoute (que ya exige sesión y derechos).
 */
export function DemoOnlyRoute({ children }: { children: React.ReactNode }) {
  const { profile } = useAuth()
  const { effectiveAccountId } = useAccount()
  const isSuper = profile?.role === 'superadmin'
  const [name, setName] = useState<string | null | undefined>(undefined) // undefined = cargando

  useEffect(() => {
    if (isSuper) return
    if (!effectiveAccountId) { setName(null); return }
    let alive = true
    setName(undefined)
    supabase.from('accounts').select('name').eq('id', effectiveAccountId).maybeSingle()
      .then(({ data }) => { if (alive) setName(data?.name ?? null) })
    return () => { alive = false }
  }, [isSuper, effectiveAccountId])

  if (isSuper) return <>{children}</>
  if (name === undefined) return <div className="min-h-screen flex items-center justify-center">Loading...</div>
  if (name !== 'DEMO2') return <Navigate to="/" replace />
  return <>{children}</>
}
