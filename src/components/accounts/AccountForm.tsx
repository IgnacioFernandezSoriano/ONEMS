import { useState } from 'react'
import { Button } from '@/components/common/Button'
import type { Account, SupportedLanguage } from '@/lib/types'
import { SUPPORTED_LANGUAGES } from '@/lib/types'
import { useTranslation } from '@/hooks/useTranslation';

interface AccountFormProps {
  account?: Account
  onSubmit: (data: { name: string; slug: string; status?: 'active' | 'inactive'; default_language: SupportedLanguage; email_panelist_manager: string | null }) => Promise<void>
  onCancel: () => void
}

export function AccountForm({ account, onSubmit, onCancel }: AccountFormProps) {
  const { t } = useTranslation();
  const [name, setName] = useState(account?.name || '')
  const [slug, setSlug] = useState(account?.slug || '')
  const [status, setStatus] = useState<'active' | 'inactive'>(account?.status || 'active')
  const [defaultLanguage, setDefaultLanguage] = useState<SupportedLanguage>(account?.default_language || 'en')
  const [emailPanelistManager, setEmailPanelistManager] = useState(account?.email_panelist_manager || '')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      const trimmed = emailPanelistManager.trim()
      await onSubmit({
        name,
        slug,
        status,
        default_language: defaultLanguage,
        email_panelist_manager: trimmed === '' ? null : trimmed,
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : t('hc.account_form.submit_error'))
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
        <label htmlFor="name" className="block text-sm font-medium mb-1">
          {t('hc.account_form.account_name')}
        </label>
        <input
          id="name"
          type="text"
          required
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        />
      </div>

      <div>
        <label htmlFor="slug" className="block text-sm font-medium mb-1">
          {t('hc.account_form.slug')}
        </label>
        <input
          id="slug"
          type="text"
          required
          value={slug}
          onChange={(e) => setSlug(e.target.value)}
          disabled={!!account}
          className="w-full px-3 py-2 border border-gray-300 rounded-md disabled:bg-gray-100"
        />
        <p className="text-xs text-gray-500 mt-1">
          {t('hc.account_form.slug_help')}
        </p>
      </div>

      <div>
        <label htmlFor="default_language" className="block text-sm font-medium mb-1">
          {t('hc.account_form.default_language')}
        </label>
        <select
          id="default_language"
          value={defaultLanguage}
          onChange={(e) => setDefaultLanguage(e.target.value as SupportedLanguage)}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        >
          {SUPPORTED_LANGUAGES.map(lang => (
            <option key={lang.code} value={lang.code}>
              {lang.name}
            </option>
          ))}
        </select>
        <p className="text-xs text-gray-500 mt-1">
          {t('hc.account_form.default_language_help')}
        </p>
      </div>

      <div>
        <label htmlFor="email_panelist_manager" className="block text-sm font-medium mb-1">
          {t('hc.account_form.manager_email')}
        </label>
        <input
          id="email_panelist_manager"
          type="email"
          value={emailPanelistManager}
          onChange={(e) => setEmailPanelistManager(e.target.value)}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder="manager@example.com"
        />
        <p className="text-xs text-gray-500 mt-1">
          {t('hc.account_form.manager_email_help')}
        </p>
      </div>

      {account && (
        <div>
          <label htmlFor="status" className="block text-sm font-medium mb-1">
            {t('hc.account_form.status')}
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

      <div className="flex gap-2 justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>
          {t('hc.account_form.cancel')}
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? t('hc.account_form.saving') : account ? t('hc.account_form.update') : t('hc.account_form.create')}
        </Button>
      </div>
    </form>
  )
}
