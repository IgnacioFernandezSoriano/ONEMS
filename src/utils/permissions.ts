import type { Role } from '@/lib/types'

export const canManageAccounts = (role: Role): boolean => {
  return role === 'superadmin'
}

export const canManageUsers = (role: Role): boolean => {
  return role === 'superadmin' || role === 'admin'
}

export const canCreateSuperadmin = (role: Role): boolean => {
  return role === 'superadmin'
}
