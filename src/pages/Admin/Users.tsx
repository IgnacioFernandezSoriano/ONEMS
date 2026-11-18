import { useState } from 'react'
import { PageHeader } from '@/components/common/PageHeader'
import { Button } from '@/components/common/Button'
import { Modal } from '@/components/common/Modal'
import { UserTable } from '@/components/users/UserTable'
import { UserForm } from '@/components/users/UserForm'
import { useUsers } from '@/hooks/useUsers'
import type { ProfileWithAccount } from '@/lib/types'
import { useTranslation } from '@/hooks/useTranslation'
import { usePermissions } from '@/contexts/PermissionsContext'

export function Users() {
  const { t } = useTranslation()
  const { canEdit } = usePermissions()
  const canEditUsers = canEdit('users')
  const { users, loading, createUser, updateUser, deleteUser, resetPassword } = useUsers()
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [selectedUser, setSelectedUser] = useState<ProfileWithAccount | undefined>()

  const handleCreate = () => {
    setSelectedUser(undefined)
    setIsModalOpen(true)
  }

  const handleEdit = (user: ProfileWithAccount) => {
    setSelectedUser(user)
    setIsModalOpen(true)
  }

  const handleSubmit = async (data: any) => {
    if (selectedUser) {
      await updateUser(selectedUser.id, data)
    } else {
      const res = await createUser(data)
      if (res?.roles_warning) alert(t('hc.users.roles_warning'))
    }
    setIsModalOpen(false)
  }

  const handleDelete = async (id: string) => {
    try {
      await deleteUser(id)
    } catch (err) {
      const msg = err instanceof Error ? err.message : ''
      alert(msg.includes('other accounts') ? t('hc.users.delete_other_accounts') : msg || t('hc.user_form.error_submitting'))
    }
  }

  if (loading) {
    return <div className="p-8">{t('hc.users.loading')}</div>
  }

  return (
    <div className="p-8">
      <PageHeader
        title={t('hc.users.title')}
        action={
          canEditUsers ? (
            <Button onClick={handleCreate}>
              {t('hc.users.create')}
            </Button>
          ) : undefined
        }
      />

      <UserTable
        users={users}
        onEdit={handleEdit}
        onDelete={handleDelete}
        canDelete={canEditUsers}
        onResetPassword={resetPassword}
      />

      <Modal
        isOpen={isModalOpen}
        onClose={() => setIsModalOpen(false)}
        title={selectedUser ? t('hc.users.edit') : t('hc.users.create')}
      >
        <UserForm
          user={selectedUser}
          onSubmit={handleSubmit}
          onCancel={() => setIsModalOpen(false)}
        />
      </Modal>
    </div>
  )
}
