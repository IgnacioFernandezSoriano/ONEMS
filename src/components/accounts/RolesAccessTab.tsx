import { useState, type ReactNode } from 'react'
import { History, Mail, RotateCcw, Shield, Users } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { useAuth } from '@/contexts/AuthContext'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useAccountAccess } from '@/hooks/useAccountAccess'
import { accessErrorKey } from '@/lib/accessAdmin'
import { ContactsSection } from './roles/ContactsSection'
import { AccessMatrix } from './roles/AccessMatrix'
import { UserRolesSection } from './roles/UserRolesSection'
import { AccessLogSection } from './roles/AccessLogSection'

interface Props {
  accountId: string
  /** Quien puede editar la pestaña (Account Manager, UPU account manager de la cuenta o superadmin). */
  canEdit: boolean
}

function Section({ icon, title, action, children }: { icon: ReactNode; title: string; action?: ReactNode; children: ReactNode }) {
  return (
    <section className="bg-white rounded-lg shadow p-4 md:p-6">
      <div className="flex flex-wrap items-center justify-between gap-2 mb-4">
        <div className="flex items-center gap-2">
          {icon}
          <h2 className="text-lg font-semibold text-gray-900">{title}</h2>
        </div>
        {action}
      </div>
      {children}
    </section>
  )
}

/** Pestaña "Roles y accesos" de una cuenta: contactos, matriz de derechos, roles de usuarios y registro. */
export function RolesAccessTab({ accountId, canEdit }: Props) {
  const { t } = useTranslation()
  const { profile } = useAuth()
  const { reload: reloadPermissions } = usePermissions()
  const access = useAccountAccess(accountId)
  const [error, setError] = useState<string | null>(null)
  const [resetting, setResetting] = useState(false)
  const isSuperadmin = profile?.role === 'superadmin'

  const message = (e: unknown) => {
    const raw = e instanceof Error ? e.message : String(e)
    const key = accessErrorKey(raw)
    return key ? t(key) : t('roles_access.error.generic', { message: raw })
  }

  /** Ejecuta una escritura; enseña el error legible. `affectsMe` recarga los derechos propios. */
  const run = async (p: () => Promise<void>, affectsMe: boolean): Promise<boolean> => {
    setError(null)
    try {
      await p()
      return true
    } catch (e) {
      setError(message(e))
      return false
    } finally {
      if (affectsMe) reloadPermissions()
    }
  }

  const reset = async () => {
    if (!window.confirm(t('roles_access.reset_confirm'))) return
    setResetting(true)
    await run(access.resetToTemplate, true)
    setResetting(false)
  }

  if (access.loadError) {
    return (
      <div className="bg-red-50 text-red-600 p-3 rounded text-sm">
        {t('roles_access.load_error', { message: access.loadError })}
      </div>
    )
  }
  if (!access.data) return <div className="p-4 text-gray-500">{t('common.loading')}</div>
  const d = access.data

  return (
    <div className="space-y-6">
      {error && (
        <div role="alert" className="bg-red-50 text-red-600 p-3 rounded text-sm flex justify-between gap-2">
          <span>{error}</span>
          <button type="button" onClick={() => setError(null)} className="text-red-400 hover:text-red-600" aria-label={t('roles_access.dismiss')}>
            ✕
          </button>
        </div>
      )}
      {!canEdit && <div className="bg-gray-50 text-gray-600 p-3 rounded text-sm">{t('roles_access.read_only')}</div>}

      <Section icon={<Mail className="w-5 h-5 text-gray-500" />} title={t('hc.account_form.contacts_title')}>
        <ContactsSection contacts={d.contacts} canEdit={canEdit} onSave={c => run(() => access.saveContacts(c), false)} />
      </Section>

      <Section
        icon={<Shield className="w-5 h-5 text-gray-500" />}
        title={t('roles_access.matrix_title')}
        action={canEdit && (
          <button
            type="button"
            onClick={reset}
            disabled={resetting}
            className="flex items-center gap-2 px-3 py-1.5 bg-gray-600 text-white text-sm rounded-lg hover:bg-gray-700 disabled:opacity-50"
          >
            <RotateCcw className="w-4 h-4" />
            {t('roles_access.reset')}
          </button>
        )}
      >
        <p className="text-xs text-gray-500 mb-3">{t('roles_access.matrix_help')}</p>
        <AccessMatrix
          matrix={d.matrix}
          noRole={d.noRole}
          canEdit={canEdit}
          onChange={(role, option, level) => run(() => access.setLevel(role, option, level), true)}
        />
      </Section>

      <Section icon={<Users className="w-5 h-5 text-gray-500" />} title={t('roles_access.users_title')}>
        <UserRolesSection
          users={d.users}
          canEdit={canEdit}
          isSuperadmin={isSuperadmin}
          onToggle={(userId, role, enabled) => run(() => access.setUserRole(userId, role, enabled), userId === profile?.id)}
          onAddByEmail={(email, role) => run(() => access.addUserByEmail(email, role), false)}
        />
      </Section>

      <Section icon={<History className="w-5 h-5 text-gray-500" />} title={t('roles_access.log_title')}>
        <AccessLogSection log={d.log} emails={d.emails} />
      </Section>
    </div>
  )
}
