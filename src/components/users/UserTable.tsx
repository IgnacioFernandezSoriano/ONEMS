import { useState } from 'react'
import { Button } from '@/components/common/Button'
import { Modal } from '@/components/common/Modal'
import { ROLE_LABELS } from '@/utils/constants'
import { useTranslation } from '@/hooks/useTranslation'
import { useAuth } from '@/contexts/AuthContext'
import type { ProfileWithAccount } from '@/lib/types'
import { Key, RefreshCw, Copy, Check, Eye, EyeOff } from 'lucide-react'

interface UserTableProps {
  users: ProfileWithAccount[]
  onEdit: (user: ProfileWithAccount) => void
  onDelete: (id: string) => void
  onResetPassword: (userId: string, newPassword: string) => Promise<void>
}

export function UserTable({ users, onEdit, onDelete, onResetPassword }: UserTableProps) {
  const { t } = useTranslation()
  const { profile } = useAuth()
  const [resetUserId, setResetUserId] = useState<string | null>(null)
  const [resetUserEmail, setResetUserEmail] = useState<string>('')
  const [newPassword, setNewPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [copied, setCopied] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  // Verificar si el usuario actual puede resetear la contraseña de otro usuario
  const canResetPassword = (user: ProfileWithAccount) => {
    // Superadmin puede resetear cualquier contraseña
    if (profile?.role === 'superadmin') return true
    
    // Admin puede resetear contraseñas de usuarios (no admins) de su cuenta
    if (profile?.role === 'admin' && 
        user.role === 'user' && 
        user.account_id === profile.account_id) {
      return true
    }
    
    return false
  }

  // Generar contraseña aleatoria
  const generatePassword = () => {
    const uppercase = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
    const lowercase = 'abcdefghjkmnpqrstuvwxyz'
    const numbers = '23456789'
    const symbols = '!@#$%'
    const allChars = uppercase + lowercase + numbers + symbols
    
    let pwd = ''
    pwd += uppercase[Math.floor(Math.random() * uppercase.length)]
    pwd += lowercase[Math.floor(Math.random() * lowercase.length)]
    pwd += numbers[Math.floor(Math.random() * numbers.length)]
    pwd += symbols[Math.floor(Math.random() * symbols.length)]
    
    for (let i = 4; i < 12; i++) {
      pwd += allChars[Math.floor(Math.random() * allChars.length)]
    }
    
    pwd = pwd.split('').sort(() => Math.random() - 0.5).join('')
    setNewPassword(pwd)
    setShowPassword(true)
  }

  // Copiar contraseña
  const copyPassword = async () => {
    try {
      await navigator.clipboard.writeText(newPassword)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch (err) {
      console.error('Failed to copy:', err)
    }
  }

  // Abrir modal de reset
  const openResetModal = (user: ProfileWithAccount) => {
    setResetUserId(user.id)
    setResetUserEmail(user.email)
    setNewPassword('')
    setShowPassword(false)
    setError('')
  }

  // Cerrar modal
  const closeResetModal = () => {
    setResetUserId(null)
    setResetUserEmail('')
    setNewPassword('')
    setShowPassword(false)
    setError('')
    setCopied(false)
  }

  // Ejecutar reset de contraseña
  const handleResetPassword = async () => {
    if (!resetUserId || !newPassword) {
      setError(t('hc.user_table.password_required'))
      return
    }

    if (newPassword.length < 8) {
      setError(t('hc.user_table.password_min_length'))
      return
    }

    setLoading(true)
    setError('')

    try {
      await onResetPassword(resetUserId, newPassword)
      closeResetModal()
    } catch (err) {
      setError(err instanceof Error ? err.message : t('hc.user_table.reset_failed'))
    } finally {
      setLoading(false)
    }
  }

  if (users.length === 0) {
    return (
      <div className="text-center py-8 text-gray-500">
        {t('hc.user_table.no_users')}
      </div>
    )
  }

  return (
    <>
      <div className="overflow-x-auto">
        <table className="min-w-full bg-white border border-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('hc.user_table.email')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('hc.user_table.name')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('hc.user_table.role')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('hc.user_table.account')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                {t('hc.user_table.status')}
              </th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
                {t('hc.user_table.actions')}
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {users.map((user) => (
              <tr key={user.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap">
                  {user.email}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  {user.full_name || '-'}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span className="px-2 py-1 text-xs rounded-full bg-blue-100 text-blue-800">
                    {ROLE_LABELS[user.role]}
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {user.account?.name || '-'}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span
                    className={`px-2 py-1 text-xs rounded-full ${
                      user.status === 'active'
                        ? 'bg-green-100 text-green-800'
                        : 'bg-gray-100 text-gray-800'
                    }`}
                  >
                    {user.status}
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm space-x-2">
                  <Button
                    size="sm"
                    variant="secondary"
                    onClick={() => onEdit(user)}
                  >
                    {t('hc.user_table.edit')}
                  </Button>
                  {canResetPassword(user) && (
                    <Button
                      size="sm"
                      variant="secondary"
                      onClick={() => openResetModal(user)}
                      className="inline-flex items-center gap-1"
                    >
                      <Key size={14} />
                      <span className="hidden sm:inline">{t('hc.user_table.reset_password')}</span>
                    </Button>
                  )}
                  <Button
                    size="sm"
                    variant="danger"
                    onClick={() => {
                      if (confirm(t('hc.user_table.confirm_delete'))) {
                        onDelete(user.id)
                      }
                    }}
                  >
                    {t('hc.user_table.delete')}
                  </Button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Modal de Reset Password */}
      <Modal
        isOpen={!!resetUserId}
        onClose={closeResetModal}
        title={t('hc.user_table.reset_user_password')}
      >
        <div className="space-y-4">
          {error && (
            <div className="bg-red-50 text-red-500 p-3 rounded text-sm">
              {error}
            </div>
          )}

          <div>
            <p className="text-sm text-gray-600 mb-4">
              {t('hc.user_table.reset_password_for')} <strong>{resetUserEmail}</strong>
            </p>
          </div>

          <div>
            <label className="block text-sm font-medium mb-2">
              {t('hc.user_table.new_password')} *
            </label>
            <div className="flex gap-2">
              <div className="flex-1 relative">
                <input
                  type={showPassword ? 'text' : 'password'}
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  placeholder={t('hc.user_table.enter_new_password')}
                  minLength={8}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md pr-10"
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-2 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-700"
                >
                  {showPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
              <button
                type="button"
                onClick={generatePassword}
                className="px-3 py-2 bg-blue-50 text-blue-700 rounded-md hover:bg-blue-100 transition-colors"
                title={t('hc.user_table.generate_password')}
              >
                <RefreshCw size={18} />
              </button>
              {newPassword && (
                <button
                  type="button"
                  onClick={copyPassword}
                  className="px-3 py-2 bg-green-50 text-green-700 rounded-md hover:bg-green-100 transition-colors"
                  title={t('hc.user_table.copy_password')}
                >
                  {copied ? <Check size={18} /> : <Copy size={18} />}
                </button>
              )}
            </div>
            {newPassword && (
              <p className="text-xs text-orange-600 mt-2">
                ⚠️ {t('hc.user_table.remember_send')}
              </p>
            )}
          </div>

          <div className="flex gap-2 justify-end pt-4">
            <Button
              variant="secondary"
              onClick={closeResetModal}
              disabled={loading}
            >
              {t('hc.user_table.cancel')}
            </Button>
            <Button
              onClick={handleResetPassword}
              disabled={loading || !newPassword}
            >
              {loading ? t('hc.user_table.resetting') : t('hc.user_table.reset_password')}
            </Button>
          </div>
        </div>
      </Modal>
    </>
  )
}
