import { useAuth } from '@/contexts/AuthContext'
import { useAccounts } from '@/hooks/useAccounts'
import { Button } from '@/components/common/Button'

export function Header() {
  const { profile, signOut } = useAuth()
  const { accounts } = useAccounts()

  const isSuperadmin = profile?.role === 'superadmin'

  return (
    <header className="bg-white border-b border-gray-200 px-6 py-4">
      <div className="flex items-center justify-between">
        <div className="flex-1">
          {/* Espacio para breadcrumbs o título de página */}
        </div>

        <div className="flex items-center gap-4">
          {/* Selector de cuenta solo para superadmin */}
          {isSuperadmin && accounts.length > 0 && (
            <div className="flex items-center gap-2">
              <label htmlFor="account-selector" className="text-sm text-gray-600">
                View as account:
              </label>
              <select
                id="account-selector"
                className="px-3 py-2 border border-gray-300 rounded-md text-sm"
                defaultValue=""
              >
                <option value="">All Accounts</option>
                {accounts.map((account) => (
                  <option key={account.id} value={account.id}>
                    {account.name}
                  </option>
                ))}
              </select>
            </div>
          )}

          <Button variant="secondary" size="sm" onClick={signOut}>
            Sign Out
          </Button>
        </div>
      </div>
    </header>
  )
}
