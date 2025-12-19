import { useState } from 'react'
import { Button } from '@/components/common/Button'
import type { Account, ResetResult } from '@/hooks/useAccountManagement'

interface AccountResetCardProps {
  account: Account
  onReset: (accountId: string) => Promise<ResetResult>
  disabled?: boolean
}

export function AccountResetCard({ account, onReset, disabled }: AccountResetCardProps) {
  const [showConfirm, setShowConfirm] = useState(false)
  const [resetting, setResetting] = useState(false)
  const [result, setResult] = useState<ResetResult | null>(null)

  const handleReset = async () => {
    setResetting(true)
    setResult(null)
    
    try {
      const resetResult = await onReset(account.name)
      setResult(resetResult)
      
      if (resetResult.success) {
        // Auto-hide success message after 5 seconds
        setTimeout(() => {
          setResult(null)
          setShowConfirm(false)
        }, 5000)
      }
    } catch (error) {
      setResult({
        success: false,
        message: 'An unexpected error occurred'
      })
    } finally {
      setResetting(false)
    }
  }

  const handleCancel = () => {
    setShowConfirm(false)
    setResult(null)
  }

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <h3 className="text-lg font-semibold text-gray-900">{account.name}</h3>
          <p className="text-xs text-gray-500 mt-2">
            Created: {new Date(account.created_at).toLocaleDateString()}
          </p>
        </div>

        <div className="ml-4">
          {!showConfirm ? (
            <Button
              variant="danger"
              onClick={() => setShowConfirm(true)}
              disabled={disabled || resetting}
            >
              Reset Data
            </Button>
          ) : (
            <div className="flex flex-col gap-2">
              <Button
                variant="danger"
                onClick={handleReset}
                disabled={resetting}
                className="whitespace-nowrap"
              >
                {resetting ? 'Resetting...' : 'Confirm Reset'}
              </Button>
              <Button
                variant="secondary"
                onClick={handleCancel}
                disabled={resetting}
                className="whitespace-nowrap"
              >
                Cancel
              </Button>
            </div>
          )}
        </div>
      </div>

      {result && (
        <div className={`mt-4 p-4 rounded-md ${
          result.success 
            ? 'bg-green-50 border border-green-200' 
            : 'bg-red-50 border border-red-200'
        }`}>
          <div className="flex">
            <div className="flex-shrink-0">
              {result.success ? (
                <svg className="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                </svg>
              ) : (
                <svg className="h-5 w-5 text-red-400" viewBox="0 0 20 20" fill="currentColor">
                  <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293 1.293a1 1 0 001.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z" clipRule="evenodd" />
                </svg>
              )}
            </div>
            <div className="ml-3 flex-1">
              <p className={`text-sm font-medium ${
                result.success ? 'text-green-800' : 'text-red-800'
              }`}>
                {result.message}
              </p>
              
              {result.success && result.deleted_records && (
                <div className="mt-2 text-sm text-green-700">
                  <p className="font-medium">Deleted records:</p>
                  <ul className="mt-1 list-disc list-inside space-y-1">
                    {Object.entries(result.deleted_records).map(([table, count]) => (
                      count > 0 && (
                        <li key={table}>
                          {table.replace(/_/g, ' ')}: <span className="font-semibold">{count}</span>
                        </li>
                      )
                    ))}
                  </ul>
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {showConfirm && !result && (
        <div className="mt-4 p-4 bg-yellow-50 border border-yellow-200 rounded-md">
          <div className="flex">
            <div className="flex-shrink-0">
              <svg className="h-5 w-5 text-yellow-400" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
              </svg>
            </div>
            <div className="ml-3">
              <h3 className="text-sm font-medium text-yellow-800">
                Warning: This action cannot be undone
              </h3>
              <div className="mt-2 text-sm text-yellow-700">
                <p>This will permanently delete:</p>
                <ul className="list-disc list-inside mt-1 space-y-1">
                  <li>All allocation plans and details</li>
                  <li>All material shipments and movements</li>
                  <li>All material stocks</li>
                  <li>All purchase orders</li>
                  <li>All balancing history</li>
                </ul>
                <p className="mt-2 font-medium">
                  Configuration data (nodes, panelists, materials, etc.) will be preserved.
                </p>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
