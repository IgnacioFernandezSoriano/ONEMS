import { useState } from 'react'
import { PageHeader } from '@/components/common/PageHeader'
import { Button } from '@/components/common/Button'
import { Modal } from '@/components/common/Modal'
import { AccountTable } from '@/components/accounts/AccountTable'
import { AccountForm } from '@/components/accounts/AccountForm'
import { useAccounts } from '@/hooks/useAccounts'
import type { Account } from '@/lib/types'

export function Accounts() {
  const { accounts, loading, createAccount, updateAccount, deleteAccount } = useAccounts()
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [selectedAccount, setSelectedAccount] = useState<Account | undefined>()

  const handleCreate = () => {
    setSelectedAccount(undefined)
    setIsModalOpen(true)
  }

  const handleEdit = (account: Account) => {
    setSelectedAccount(account)
    setIsModalOpen(true)
  }

  const handleSubmit = async (data: { name: string; slug: string; status?: string }) => {
    if (selectedAccount) {
      await updateAccount(selectedAccount.id, data)
    } else {
      await createAccount(data)
    }
    setIsModalOpen(false)
  }

  const handleDelete = async (id: string) => {
    await deleteAccount(id)
  }

  if (loading) {
    return <div className="p-8">Loading...</div>
  }

  return (
    <div className="p-8">
      <PageHeader
        title="Account Management"
        action={
          <Button onClick={handleCreate}>
            Create Account
          </Button>
        }
      />

      <AccountTable
        accounts={accounts}
        onEdit={handleEdit}
        onDelete={handleDelete}
      />

      <Modal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        title={selectedAccount ? 'Edit Account' : 'Create Account'}
      >
        <AccountForm
          account={selectedAccount}
          onSubmit={handleSubmit}
          onCancel={() => setIsModalOpen(false)}
        />
      </Modal>
    </div>
  )
}
