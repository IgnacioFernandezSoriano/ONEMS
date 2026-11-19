import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/contexts/AuthContext'
import { usePermissions } from '@/contexts/PermissionsContext'
import { PermissionsError } from './PermissionsError'
import { canAccess, deniedRedirect, landingPath, type RouteAccess } from '@/lib/access'

function Loading() {
  return <div className="min-h-screen flex items-center justify-center">Loading...</div>
}

interface ProtectedRouteProps {
  children: React.ReactNode
  /** Opción de la matriz de la cuenta que da acceso; sin option = solo hace falta sesión. */
  option?: RouteAccess
}

export function ProtectedRoute({ children, option = 'open' }: ProtectedRouteProps) {
  const { user, profile, loading } = useAuth()
  const permissions = usePermissions()
  const location = useLocation()

  // Esperar a la sesión y a los derechos antes de decidir (si no, redirigiría con derechos vacíos).
  if (loading) return <Loading />

  if (!user || !profile) {
    return <Navigate to="/login" />
  }

  if (option === 'open') return <>{children}</>
  // Error al cargar derechos: aviso con reintento, nunca redirigir (no son "derechos vacíos").
  if (permissions.error) return <PermissionsError />
  if (permissions.loading) return <Loading />

  if (!canAccess(option, profile.role === 'superadmin', permissions.canView)) {
    return <Navigate to={deniedRedirect(location.pathname, permissions.canView)} replace />
  }

  return <>{children}</>
}

/** '/' y la entrada tras el login: primera pantalla permitida según la matriz de la cuenta. */
export function HomeRedirect() {
  const { user, profile, loading } = useAuth()
  const permissions = usePermissions()

  if (loading) return <Loading />
  if (!user || !profile) return <Navigate to="/login" />
  if (permissions.error) return <PermissionsError />
  if (permissions.loading) return <Loading />

  return <Navigate to={landingPath(permissions.canView)} replace />
}
