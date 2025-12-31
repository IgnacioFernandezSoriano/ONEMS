import { useState } from 'react'
import { Button } from '@/components/common/Button'
import { useAuth } from '@/contexts/AuthContext'
import { useAccounts } from '@/hooks/useAccounts'
import { ROLE_LABELS } from '@/utils/constants'
import type { ProfileWithAccount } from '@/lib/types'

import { useTranslation } from '@/hooks/useTranslation';
interface UserFormProps {
  user?: ProfileWithAccount
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function UserForm({ user, onSubmit, onCancel }: UserFormProps) {
  const { t } = useTranslation();
  const { profile } = useAuth()
  const { accounts } = useAccounts()
  const [email, setEmail] = useState(user?.email || '')
  const [password, setPassword] = useState('')
  const [fullName, setFullName] = useState(user?.full_name || '')
  const [role, setRole] = useState<'superadmin' | 'admin' | 'user'>(user?.role || 'user')
  const [accountId, setAccountId] = useState(user?.account_id || profile?.account_id || '')
  const [status, setStatus] = useState<'active' | 'inactive'>(user?.status || 'active')
  const [preferredLanguage, setPreferredLanguage] = useState<string>((user as any)?.preferred_language || 'en')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const isSuperadmin = profile?.role === 'superadmin'

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      const data: any = {
        email,
        full_name: fullName,
        role,
        status,
        preferred_language: preferredLanguage,
      }

      if (!user) {
        data.password = password
      }

      if (role !== 'superadmin') {
        data.account_id = accountId
      }

      await onSubmit(data)
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Error submitting form')
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      {error && (
        <div className="bg-red-50 text-red-500 p-3 rounded text-sm">
          {error}
        </div>
      )}

      <div>
        <label htmlFor="email" className="block text-sm font-medium mb-1">
          Email
        </label>
        <input
          id="email"
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          disabled={!!user}
          className="w-full px-3 py-2 border border-gray-300 rounded-md disabled:bg-gray-100"
        />
      </div>

      {!user && (
        <div>
          <label htmlFor="password" className="block text-sm font-medium mb-1">
            Password
          </label>
          <input
            id="password"
            type="password"
            required
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
          />
        </div>
      )}

      <div>
        <label htmlFor="fullName" className="block text-sm font-medium mb-1">
          Full Name
        </label>
        <input
          id="fullName"
          type="text"
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        />
      </div>

      <div>
        <label htmlFor="role" className="block text-sm font-medium mb-1">
          Role
        </label>
        <select
          id="role"
          value={role}
          onChange={(e) => setRole(e.target.value as 'superadmin' | 'admin' | 'user')}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        >
          {isSuperadmin && <option value="superadmin">{ROLE_LABELS.superadmin}</option>}
          <option value="admin">{ROLE_LABELS.admin}</option>
          <option value="user">{ROLE_LABELS.user}</option>
        </select>
      </div>

      {role !== 'superadmin' && (
        <div>
          <label htmlFor="account" className="block text-sm font-medium mb-1">
            Account
          </label>
          <select
            id="account"
            value={accountId}
            onChange={(e) => setAccountId(e.target.value)}
            required
            disabled={!isSuperadmin}
            className="w-full px-3 py-2 border border-gray-300 rounded-md disabled:bg-gray-100"
          >
            <option value="">Select account</option>
            {accounts.map((account) => (
              <option key={account.id} value={account.id}>
                {account.name}
              </option>
            ))}
          </select>
        </div>
      )}

      {user && (
        <div>
          <label htmlFor="status" className="block text-sm font-medium mb-1">
            Status
          </label>
          <select
            id="status"
            value={status}
            onChange={(e) => setStatus(e.target.value as 'active' | 'inactive')}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
          >
            <option value="active">{t('common.active')}</option>
            <option value="inactive">{t('common.inactive')}</option>
          </select>
        </div>
      )}

      <div>
        <label htmlFor="preferredLanguage" className="block text-sm font-medium mb-1">
          Preferred Language
        </label>
        <select
          id="preferredLanguage"
          value={preferredLanguage}
          onChange={(e) => setPreferredLanguage(e.target.value)}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        >
          <option value="en">English</option>
          <option value="es">Español</option>
          <option value="fr">Français</option>
          <option value="ar">العربية (Arabic)</option>
        </select>
      </div>

      <div className="flex gap-2 justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? 'Saving...' : user ? 'Update' : 'Create'}
        </Button>
      </div>
    </form>
  )
}
