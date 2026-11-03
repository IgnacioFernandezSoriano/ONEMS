import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { supabase } from '@/lib/supabase'
import { Button } from '@/components/common/Button'
import { PageHeader } from '@/components/common/PageHeader'
import { Eye, EyeOff, Lock } from 'lucide-react'

export function ChangePassword() {
  const { t } = useTranslation()
  const [newPassword, setNewPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [showNewPassword, setShowNewPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)
  const [loading, setLoading] = useState(false)
  const [message, setMessage] = useState<{ type: 'success' | 'error', text: string } | null>(null)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setMessage(null)

    // Validaciones
    if (newPassword !== confirmPassword) {
      setMessage({ type: 'error', text: t('hc.change_password.passwords_no_match') })
      return
    }

    if (newPassword.length < 8) {
      setMessage({ type: 'error', text: t('hc.change_password.min_length_error') })
      return
    }

    setLoading(true)

    try {
      const { error } = await supabase.auth.updateUser({
        password: newPassword
      })

      if (error) throw error

      setMessage({ type: 'success', text: t('hc.change_password.success') })
      setNewPassword('')
      setConfirmPassword('')
      setShowNewPassword(false)
      setShowConfirmPassword(false)
    } catch (error) {
      setMessage({ 
        type: 'error', 
        text: error instanceof Error ? error.message : t('hc.change_password.failed') 
      })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="p-8">
      <PageHeader
        title={t('hc.change_password.title')}
      />

      <div className="max-w-md mx-auto mt-8">
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center gap-3 mb-6">
            <div className="p-3 bg-blue-50 rounded-lg">
              <Lock className="text-blue-600" size={24} />
            </div>
            <div>
              <h3 className="font-semibold text-gray-900">{t('hc.change_password.security')}</h3>
              <p className="text-sm text-gray-500">{t('hc.change_password.choose_strong')}</p>
            </div>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {message && (
              <div 
                className={`p-4 rounded-md ${
                  message.type === 'success' 
                    ? 'bg-green-50 text-green-800 border border-green-200' 
                    : 'bg-red-50 text-red-800 border border-red-200'
                }`}
              >
                {message.text}
              </div>
            )}

            <div>
              <label htmlFor="newPassword" className="block text-sm font-medium text-gray-700 mb-2">
                {t('hc.change_password.new_password_label')}
              </label>
              <div className="relative">
                <input
                  id="newPassword"
                  type={showNewPassword ? 'text' : 'password'}
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
                  required
                  minLength={8}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 pr-10"
                  placeholder={t('hc.change_password.enter_new_placeholder')}
                />
                <button
                  type="button"
                  onClick={() => setShowNewPassword(!showNewPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-700"
                >
                  {showNewPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
              <p className="text-xs text-gray-500 mt-1">
                {t('hc.change_password.min_8_chars')}
              </p>
            </div>

            <div>
              <label htmlFor="confirmPassword" className="block text-sm font-medium text-gray-700 mb-2">
                {t('hc.change_password.confirm_label')}
              </label>
              <div className="relative">
                <input
                  id="confirmPassword"
                  type={showConfirmPassword ? 'text' : 'password'}
                  value={confirmPassword}
                  onChange={(e) => setConfirmPassword(e.target.value)}
                  required
                  minLength={8}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 pr-10"
                  placeholder={t('hc.change_password.confirm_placeholder')}
                />
                <button
                  type="button"
                  onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-500 hover:text-gray-700"
                >
                  {showConfirmPassword ? <EyeOff size={18} /> : <Eye size={18} />}
                </button>
              </div>
            </div>

            <div className="pt-4">
              <Button 
                type="submit" 
                disabled={loading || !newPassword || !confirmPassword}
                className="w-full"
              >
                {loading ? t('hc.change_password.changing') : t('hc.change_password.title')}
              </Button>
            </div>
          </form>

          <div className="mt-6 p-4 bg-blue-50 rounded-md">
            <h4 className="text-sm font-medium text-blue-900 mb-2">{t('hc.change_password.tips_title')}</h4>
            <ul className="text-xs text-blue-800 space-y-1">
              <li>• {t('hc.change_password.tip_length')}</li>
              <li>• {t('hc.change_password.tip_case')}</li>
              <li>• {t('hc.change_password.tip_symbols')}</li>
              <li>• {t('hc.change_password.tip_avoid')}</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  )
}
