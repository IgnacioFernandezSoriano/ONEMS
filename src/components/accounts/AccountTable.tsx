import { Button } from '@/components/common/Button'
import { useTranslation } from '@/hooks/useTranslation'
import type { Account } from '@/lib/types'
import { SUPPORTED_LANGUAGES } from '@/lib/types'

interface AccountTableProps {
  accounts: Account[]
  onEdit: (account: Account) => void
  onDelete: (id: string) => void
}

export function AccountTable({ accounts, onEdit, onDelete }: AccountTableProps) {
  const { t } = useTranslation()

  if (accounts.length === 0) {
    return (
      <div className="text-center py-8 text-gray-500">
        {t('hc.account_table.no_accounts')}
      </div>
    )
  }

  return (
    <div className="overflow-x-auto">
      <table className="min-w-full bg-white border border-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
              {t('hc.account_table.name')}
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
              {t('hc.account_table.slug')}
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
              {t('hc.account_table.default_language')}
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
              {t('hc.account_table.status')}
            </th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
              {t('hc.account_table.created')}
            </th>
            <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">
              {t('hc.account_table.actions')}
            </th>
          </tr>
        </thead>
        <tbody className="divide-y divide-gray-200">
          {accounts.map((account) => (
            <tr key={account.id} className="hover:bg-gray-50">
              <td className="px-6 py-4 whitespace-nowrap">
                {account.name}
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {account.slug}
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-700">
                {SUPPORTED_LANGUAGES.find(l => l.code === account.default_language)?.name || account.default_language || t('hc.account_table.english')}
              </td>
              <td className="px-6 py-4 whitespace-nowrap">
                <span
                  className={`px-2 py-1 text-xs rounded-full ${
                    account.status === 'active'
                      ? 'bg-green-100 text-green-800'
                      : 'bg-gray-100 text-gray-800'
                  }`}
                >
                  {account.status}
                </span>
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                {new Date(account.created_at).toLocaleDateString()}
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-right text-sm">
                <Button
                  size="sm"
                  variant="secondary"
                  onClick={() => onEdit(account)}
                  className="mr-2"
                >
                  {t('hc.account_table.edit')}
                </Button>
                <Button
                  size="sm"
                  variant="danger"
                  onClick={() => {
                    if (confirm(t('hc.account_table.confirm_delete'))) {
                      onDelete(account.id)
                    }
                  }}
                >
                  {t('hc.account_table.delete')}
                </Button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}
