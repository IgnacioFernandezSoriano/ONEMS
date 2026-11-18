import { useEffect, useState } from 'react'
import { UserPlus } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import type { AccountRole } from '@/lib/access'
import { ACCOUNT_ROLES, roleLabelKey, type AccountUser } from '@/lib/accessAdmin'

interface Props {
  users: AccountUser[]
  canEdit: boolean
  isSuperadmin: boolean
  onToggle: (userId: string, role: AccountRole, enabled: boolean) => Promise<boolean>
  onAddByEmail: (email: string, role: AccountRole) => Promise<boolean>
}

/** Usuarios de la cuenta con una casilla por rol; "provisional" marca la asignación automática del arranque. */
export function UserRolesSection({ users, canEdit, isSuperadmin, onToggle, onAddByEmail }: Props) {
  const { t } = useTranslation()
  const [busy, setBusy] = useState<string | null>(null)
  const [email, setEmail] = useState('')
  const [newRole, setNewRole] = useState<AccountRole>('account_manager')
  const [adding, setAdding] = useState(false)
  // Casilla marcada/desmarcada mientras llega la lista recargada.
  const [overrides, setOverrides] = useState<Map<string, boolean>>(new Map())
  useEffect(() => setOverrides(new Map()), [users])

  const toggle = async (userId: string, role: AccountRole, enabled: boolean) => {
    const k = `${userId}|${role}`
    setBusy(k)
    setOverrides(prev => new Map(prev).set(k, enabled))
    const ok = await onToggle(userId, role, enabled)
    if (!ok) setOverrides(prev => { const m = new Map(prev); m.delete(k); return m })
    setBusy(null)
  }

  const add = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!email.trim()) return
    setAdding(true)
    const ok = await onAddByEmail(email, newRole)
    setAdding(false)
    if (ok) setEmail('')
  }

  return (
    <div className="space-y-3">
      <p className="text-xs text-gray-500">{t('roles_access.users_help')}</p>
      <div className="overflow-x-auto border border-gray-200 rounded-lg">
        <table className="min-w-full text-sm">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-3 py-2 text-start font-medium text-gray-700">{t('roles_access.user')}</th>
              {ACCOUNT_ROLES.map(r => (
                <th key={r} className="px-2 py-2 text-center font-medium text-gray-700 whitespace-nowrap">{t(roleLabelKey(r))}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {users.length === 0 && (
              <tr>
                <td colSpan={ACCOUNT_ROLES.length + 1} className="px-3 py-4 text-center text-gray-500">
                  {t('roles_access.no_users')}
                </td>
              </tr>
            )}
            {users.map(u => (
              <tr key={u.user_id} className="border-t border-gray-100">
                <td className="px-3 py-2">
                  <div className="text-gray-900">{u.email ?? u.user_id}</div>
                  {u.full_name && <div className="text-xs text-gray-500">{u.full_name}</div>}
                  <div className="flex flex-wrap gap-1 mt-0.5">
                    {u.roles.size === 0 && (
                      <span className="text-xs px-1.5 py-0.5 rounded bg-gray-100 text-gray-600">{t('roles_access.no_role')}</span>
                    )}
                    {u.provisional.size > 0 && (
                      <span
                        className="text-xs px-1.5 py-0.5 rounded bg-amber-100 text-amber-800"
                        title={t('roles_access.provisional_help')}
                      >
                        {t('roles_access.provisional')}
                      </span>
                    )}
                    {!u.activeHere && (
                      <span className="text-xs px-1.5 py-0.5 rounded bg-gray-100 text-gray-600" title={t('roles_access.other_account_help')}>
                        {t('roles_access.other_account')}
                      </span>
                    )}
                  </div>
                </td>
                {ACCOUNT_ROLES.map(r => {
                  const checked = overrides.get(`${u.user_id}|${r}`) ?? u.roles.has(r)
                  return (
                    <td key={r} className="px-2 py-2 text-center">
                      <input
                        type="checkbox"
                        aria-label={`${u.email ?? u.user_id} · ${t(roleLabelKey(r))}`}
                        checked={checked}
                        disabled={!canEdit || busy !== null}
                        onChange={e => toggle(u.user_id, r, e.target.checked)}
                        className={u.provisional.has(r) ? 'accent-amber-500' : undefined}
                        title={u.provisional.has(r) ? t('roles_access.provisional') : undefined}
                      />
                    </td>
                  )
                })}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {isSuperadmin && canEdit && (
        <form onSubmit={add} className="flex flex-wrap items-end gap-2">
          <div className="flex-1 min-w-[14rem]">
            <label htmlFor="roles_add_email" className="block text-sm font-medium mb-1">{t('roles_access.add_by_email')}</label>
            <input
              id="roles_add_email"
              type="email"
              required
              value={email}
              onChange={e => setEmail(e.target.value)}
              className="w-full px-3 py-2 border border-gray-300 rounded-md"
              placeholder="name@example.com"
            />
          </div>
          <div>
            <label htmlFor="roles_add_role" className="block text-sm font-medium mb-1">{t('roles_access.role')}</label>
            <select
              id="roles_add_role"
              value={newRole}
              onChange={e => setNewRole(e.target.value as AccountRole)}
              className="px-3 py-2 border border-gray-300 rounded-md"
            >
              {ACCOUNT_ROLES.map(r => <option key={r} value={r}>{t(roleLabelKey(r))}</option>)}
            </select>
          </div>
          <button
            type="submit"
            disabled={adding}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
          >
            <UserPlus className="w-4 h-4" />
            {adding ? t('roles_access.saving') : t('roles_access.add')}
          </button>
          <p className="w-full text-xs text-gray-500">{t('roles_access.add_by_email_help')}</p>
        </form>
      )}
    </div>
  )
}
