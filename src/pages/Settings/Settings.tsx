import { Navigate } from 'react-router-dom'

export function Settings() {
  // Redirect to accounts by default
  return <Navigate to="/settings/accounts" replace />
}
