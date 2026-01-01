import { useEffect } from 'react'
import { PageHeader } from '@/components/common/PageHeader'
import { AccountResetCard } from '@/components/admin/AccountResetCard'
import { useAccountManagement } from '@/hooks/useAccountManagement'

import { useTranslation } from '@/hooks/useTranslation';
export function AccountManagement() {
  const { t } = useTranslation();
  const { accounts, loading, resetting, fetchAccounts, resetAccountData } = useAccountManagement()

  useEffect(() => {
    fetchAccounts()
  }, [])

  if (loading) {
    return (
      <div className="p-8">
        <div className="flex items-center justify-center h-64">
          <div className="text-center">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
            <p className="mt-2 text-gray-600">{t('admin.loading_accounts')}</p>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="p-8">
      <PageHeader
        title={t('admin.demo_reset')}
      />

      <div className="mt-6 bg-blue-50 border border-blue-200 rounded-lg p-4">
        <div className="flex">
          <div className="flex-shrink-0">
            <svg className="h-5 w-5 text-blue-400" viewBox="0 0 20 20" fill="currentColor">
              <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
            </svg>
          </div>
          <div className="ml-3 flex-1">
            <h3 className="text-sm font-medium text-blue-800">
              {t('admin.about_account_reset')}
            </h3>
            <div className="mt-2 text-sm text-blue-700">
              <p>
                {t('admin.use_this_feature_to_prepare_accounts')}
              </p>
              <ul className="list-disc list-inside mt-2 space-y-1">
                <li><strong>{t('common.delete')}</strong> {t('admin.all_operational_data')}</li>
                <li><strong>{t('admin.preserve')}</strong> {t('admin.all_configuration_data')}</li>
                <li><strong>{t('admin.cannot_be_undone')}</strong> - {t('admin.use_with_caution')}</li>
              </ul>
            </div>
          </div>
        </div>
      </div>

      <div className="mt-8 space-y-4">
        {accounts.length === 0 ? (
          <div className="text-center py-12">
            <svg
              className="mx-auto h-12 w-12 text-gray-400"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={2}
                d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4"
              />
            </svg>
            <h3 className="mt-2 text-sm font-medium text-gray-900">{t('admin.demo2_account_not_found')}</h3>
            <p className="mt-1 text-sm text-gray-500">
              {t('admin.the_demo2_account_is_not_available_please_contact_')}
            </p>
          </div>
        ) : (
          accounts.map((account) => (
            <AccountResetCard
              key={account.id}
              account={account}
              onReset={resetAccountData}
              disabled={resetting}
            />
          ))
        )}
      </div>
    </div>
  )
}
