import { useEffect, useState } from 'react'
import { Save } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { ACCOUNT_CONTACT_FIELDS } from '@/lib/types'
import { CONTACT_I18N } from '@/lib/accessAdmin'
import type { Contacts } from '@/hooks/useAccountAccess'

interface Props {
  contacts: Contacts
  canEdit: boolean
  /** Guarda; devuelve true si fue bien (los errores los enseña la pestaña). */
  onSave: (contacts: Contacts) => Promise<boolean>
}

/** Los seis correos de contacto de la cuenta (destino de avisos e informes; no dan derechos). */
export function ContactsSection({ contacts, canEdit, onSave }: Props) {
  const { t } = useTranslation()
  const [draft, setDraft] = useState<Contacts>(contacts)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  useEffect(() => setDraft(contacts), [contacts])

  const dirty = ACCOUNT_CONTACT_FIELDS.some(f => draft[f].trim() !== contacts[f])

  const save = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setSaved(false)
    const trimmed = { ...draft }
    for (const f of ACCOUNT_CONTACT_FIELDS) trimmed[f] = draft[f].trim()
    const ok = await onSave(trimmed)
    setSaving(false)
    setSaved(ok)
  }

  return (
    <form onSubmit={save} className="space-y-3">
      <p className="text-xs text-gray-500">{t('hc.account_form.contacts_help')}</p>
      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        {ACCOUNT_CONTACT_FIELDS.map(field => (
          <div key={field}>
            <label htmlFor={`contact_${field}`} className="block text-sm font-medium mb-1">
              {t(CONTACT_I18N[field])}
            </label>
            <input
              id={`contact_${field}`}
              type="email"
              value={draft[field]}
              disabled={!canEdit || saving}
              onChange={e => { setSaved(false); setDraft(prev => ({ ...prev, [field]: e.target.value })) }}
              className="w-full px-3 py-2 border border-gray-300 rounded-md disabled:bg-gray-100"
              placeholder="name@example.com"
            />
            <p className="text-xs text-gray-500 mt-1">{t(`${CONTACT_I18N[field]}_help`)}</p>
          </div>
        ))}
      </div>
      {canEdit && (
        <div className="flex items-center gap-3">
          <button
            type="submit"
            disabled={saving || !dirty}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
          >
            <Save className="w-4 h-4" />
            {saving ? t('roles_access.saving') : t('roles_access.contacts_save')}
          </button>
          {saved && !dirty && <span className="text-sm text-green-700">{t('roles_access.saved')}</span>}
        </div>
      )}
    </form>
  )
}
