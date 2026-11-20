import { useEffect, useState } from 'react'
import { Plus, Pencil, Trash2 } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { ClHelpLink } from '@/components/carrier-link/ClHelpLink'
import { usePermissions } from '@/contexts/PermissionsContext'
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId'
import { ReadOnlyBadge } from '@/components/common/ReadOnlyBadge'
import { SelectAccountNotice } from '@/components/carrier-link/SelectAccountNotice'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import type { E2eRole, ReadingPointForm } from '@/lib/carrierLink/readingPoints'
import { useClReadingPoints, useClCarriersAndCenters, type ClReadingPoint } from '@/hooks/carrierLink/useClReadingPoints'

const ROLES: E2eRole[] = ['origin', 'destination', 'both', 'none']

interface EditorState {
  id: string | null
  form: ReadingPointForm
}

export function ClReadingPoints() {
  const { t } = useTranslation()
  const { canEdit } = usePermissions()
  const accountId = useEffectiveAccountId()
  const readOnly = !canEdit('cl_reading_points')

  const { carriers, centers, error: lookupError } = useClCarriersAndCenters(accountId)
  const [carrierId, setCarrierId] = useState('')
  const { points, unknown, loading, error, create, update, remove } = useClReadingPoints(accountId, carrierId || null)

  const [editor, setEditor] = useState<EditorState | null>(null)
  const [saving, setSaving] = useState(false)
  const [formError, setFormError] = useState<string | null>(null)
  const [deleting, setDeleting] = useState<ClReadingPoint | null>(null)

  useEffect(() => {
    if (!carrierId && carriers.length > 0) setCarrierId(carriers[0].id)
  }, [carriers, carrierId])

  const roleLabel = (r: E2eRole) => t(`cl.reading_points.role.${r}`)

  const emptyForm = (place = '', mode: string | null = ''): ReadingPointForm => ({
    carrier_id: carrierId,
    carrier_place_ref: place,
    carrier_mode_ref: mode ?? '',
    postal_center_id: '',
    e2e_role: 'origin',
    name: '',
  })

  const openNew = (place = '', mode: string | null = '') => {
    setFormError(null)
    setEditor({ id: null, form: emptyForm(place, mode) })
  }

  const openEdit = (p: ClReadingPoint) => {
    setFormError(null)
    setEditor({
      id: p.id,
      form: {
        carrier_id: p.carrier_id,
        carrier_place_ref: p.carrier_place_ref,
        carrier_mode_ref: p.carrier_mode_ref ?? '',
        postal_center_id: p.postal_center_id ?? '',
        e2e_role: p.e2e_role,
        name: p.name,
      },
    })
  }

  const setField = <K extends keyof ReadingPointForm>(k: K, v: ReadingPointForm[K]) =>
    setEditor((e) => (e ? { ...e, form: { ...e.form, [k]: v } } : e))

  const selectedCenter = editor ? centers.find((c) => c.id === editor.form.postal_center_id) : undefined
  const centerLacksCity = !!selectedCenter && !selectedCenter.city_id && editor?.form.e2e_role !== 'none'

  const save = async () => {
    if (!editor) return
    setSaving(true)
    setFormError(null)
    const res = editor.id ? await update(editor.id, editor.form) : await create(editor.form)
    setSaving(false)
    if (res.success) {
      setEditor(null)
    } else {
      setFormError(res.key ?? clErrorKey({ message: res.error }))
    }
  }

  const confirmDelete = async () => {
    if (!deleting) return
    const res = await remove(deleting.id)
    if (res.success) setDeleting(null)
    else setFormError(res.key ?? clErrorKey({ message: res.error }))
  }

  return (
    <div className="p-6 space-y-4">
      <div className="flex items-center gap-3">
        <h1 className="text-2xl font-bold text-gray-900">{t('cl.reading_points.title')}</h1>
        <ClHelpLink section="reading-points" />
        {readOnly && <ReadOnlyBadge />}
      </div>
      <p className="text-sm text-gray-600">{t('cl.reading_points.help')}</p>

      {accountId === null ? (
        <SelectAccountNotice />
      ) : (
        <>
          <div className="flex flex-wrap items-end gap-3">
            <label className="text-sm text-gray-700">
              <span className="block mb-1">{t('cl.reading_points.carrier')}</span>
              <select
                className="border border-gray-300 rounded-lg px-3 py-2 min-w-[14rem]"
                value={carrierId}
                onChange={(e) => setCarrierId(e.target.value)}
              >
                {carriers.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name} ({c.code})
                  </option>
                ))}
              </select>
            </label>
            {!readOnly && (
              <button
                type="button"
                disabled={!carrierId}
                onClick={() => openNew()}
                className="inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
              >
                <Plus className="w-4 h-4" />
                {t('cl.reading_points.add')}
              </button>
            )}
          </div>

          {lookupError && <p className="text-sm text-red-600">{t(clErrorKey(lookupError))}</p>}
          {!lookupError && carriers.length === 0 && <p className="text-sm text-gray-500">{t('cl.reading_points.no_carriers')}</p>}
          {error && <p className="text-sm text-red-600">{t(clErrorKey(error))}</p>}

          {carrierId && (
            <div className="bg-white rounded-lg border border-gray-200 overflow-x-auto">
              <table className="min-w-full text-sm">
                <thead className="bg-gray-50 text-gray-600">
                  <tr>
                    <th className="text-start px-4 py-2">{t('cl.reading_points.place')}</th>
                    <th className="text-start px-4 py-2">{t('cl.reading_points.mode')}</th>
                    <th className="text-start px-4 py-2">{t('cl.reading_points.center')}</th>
                    <th className="text-start px-4 py-2">{t('cl.reading_points.city')}</th>
                    <th className="text-start px-4 py-2">{t('cl.reading_points.role')}</th>
                    {!readOnly && <th className="text-start px-4 py-2">{t('common.actions')}</th>}
                  </tr>
                </thead>
                <tbody>
                  {loading && (
                    <tr>
                      <td className="px-4 py-3 text-gray-500" colSpan={6}>
                        {t('common.loading')}
                      </td>
                    </tr>
                  )}
                  {!loading && points.length === 0 && (
                    <tr>
                      <td className="px-4 py-3 text-gray-500" colSpan={6}>
                        {t('cl.reading_points.empty')}
                      </td>
                    </tr>
                  )}
                  {points.map((p) => (
                    <tr key={p.id} className="border-t border-gray-100">
                      <td className="px-4 py-2 font-medium">{p.carrier_place_ref}</td>
                      <td className="px-4 py-2">{p.carrier_mode_ref ?? t('cl.reading_points.any_mode')}</td>
                      <td className="px-4 py-2">{p.postal_center_name ?? '-'}</td>
                      <td className="px-4 py-2">{p.city_name ?? '-'}</td>
                      <td className="px-4 py-2">{roleLabel(p.e2e_role)}</td>
                      {!readOnly && (
                        <td className="px-4 py-2">
                          <div className="flex gap-2">
                            <button type="button" title={t('common.edit')} onClick={() => openEdit(p)} className="text-blue-600 hover:text-blue-800">
                              <Pencil className="w-4 h-4" />
                            </button>
                            <button
                              type="button"
                              title={t('common.delete')}
                              onClick={() => {
                                setFormError(null)
                                setDeleting(p)
                              }}
                              className="text-red-600 hover:text-red-800"
                            >
                              <Trash2 className="w-4 h-4" />
                            </button>
                          </div>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}

          {carrierId && unknown.length > 0 && (
            <div className="bg-amber-50 border border-amber-200 rounded-lg p-4 space-y-2">
              <h2 className="font-semibold text-amber-900">{t('cl.reading_points.unknown_title')}</h2>
              <p className="text-sm text-amber-900">{t('cl.reading_points.unknown_help')}</p>
              <table className="min-w-full text-sm">
                <thead className="text-amber-900">
                  <tr>
                    <th className="text-start px-2 py-1">{t('cl.reading_points.place')}</th>
                    <th className="text-start px-2 py-1">{t('cl.reading_points.mode')}</th>
                    <th className="text-start px-2 py-1">{t('cl.reading_points.readings')}</th>
                    {!readOnly && <th />}
                  </tr>
                </thead>
                <tbody>
                  {unknown.map((u) => (
                    <tr key={`${u.place_ref}|${u.mode_ref ?? ''}`} className="border-t border-amber-100">
                      <td className="px-2 py-1">{u.place_ref}</td>
                      <td className="px-2 py-1">{u.mode_ref ?? t('cl.reading_points.any_mode')}</td>
                      <td className="px-2 py-1">{u.readings}</td>
                      {!readOnly && (
                        <td className="px-2 py-1 text-end">
                          <button type="button" onClick={() => openNew(u.place_ref, u.mode_ref)} className="text-blue-700 hover:underline">
                            {t('cl.reading_points.register')}
                          </button>
                        </td>
                      )}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </>
      )}

      {editor && !readOnly && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl w-full max-w-lg p-6 space-y-4">
            <h2 className="text-lg font-semibold">{editor.id ? t('cl.reading_points.edit') : t('cl.reading_points.add')}</h2>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.reading_points.place')}</span>
              <input
                className="w-full border border-gray-300 rounded-lg px-3 py-2"
                value={editor.form.carrier_place_ref}
                onChange={(e) => setField('carrier_place_ref', e.target.value)}
              />
            </label>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.reading_points.mode')}</span>
              <input
                className="w-full border border-gray-300 rounded-lg px-3 py-2"
                value={editor.form.carrier_mode_ref}
                placeholder={t('cl.reading_points.any_mode')}
                onChange={(e) => setField('carrier_mode_ref', e.target.value)}
              />
              <span className="text-xs text-gray-500">{t('cl.reading_points.mode_hint')}</span>
            </label>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.reading_points.center')}</span>
              <select
                className="w-full border border-gray-300 rounded-lg px-3 py-2"
                value={editor.form.postal_center_id}
                onChange={(e) => setField('postal_center_id', e.target.value)}
              >
                <option value="">{t('cl.reading_points.select_center')}</option>
                {centers.map((c) => (
                  <option key={c.id} value={c.id}>
                    {c.name}
                    {c.city_name ? ` - ${c.city_name}` : ''}
                  </option>
                ))}
              </select>
              {centerLacksCity && <span className="text-xs text-red-600">{t('cl.reading_points.center_no_city')}</span>}
            </label>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.reading_points.role')}</span>
              <select
                className="w-full border border-gray-300 rounded-lg px-3 py-2"
                value={editor.form.e2e_role}
                onChange={(e) => setField('e2e_role', e.target.value as E2eRole)}
              >
                {ROLES.map((r) => (
                  <option key={r} value={r}>
                    {roleLabel(r)}
                  </option>
                ))}
              </select>
            </label>
            <label className="block text-sm">
              <span className="block mb-1">{t('cl.reading_points.name')}</span>
              <input
                className="w-full border border-gray-300 rounded-lg px-3 py-2"
                value={editor.form.name}
                onChange={(e) => setField('name', e.target.value)}
              />
            </label>
            {formError && <p className="text-sm text-red-600">{t(formError)}</p>}
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setEditor(null)} className="px-4 py-2 border border-gray-300 rounded-lg">
                {t('common.cancel')}
              </button>
              <button
                type="button"
                disabled={saving}
                onClick={() => void save()}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
              >
                {saving ? t('common.saving') : t('common.save')}
              </button>
            </div>
          </div>
        </div>
      )}

      {deleting && !readOnly && (
        <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl w-full max-w-md p-6 space-y-4">
            <h2 className="text-lg font-semibold">{t('cl.reading_points.delete_title')}</h2>
            <p className="text-sm text-gray-700">
              {t('cl.reading_points.delete_confirm', { name: deleting.carrier_place_ref })}
            </p>
            {formError && <p className="text-sm text-red-600">{t(formError)}</p>}
            <div className="flex justify-end gap-2">
              <button type="button" onClick={() => setDeleting(null)} className="px-4 py-2 border border-gray-300 rounded-lg">
                {t('common.cancel')}
              </button>
              <button type="button" onClick={() => void confirmDelete()} className="px-4 py-2 bg-red-600 text-white rounded-lg hover:bg-red-700">
                {t('common.delete')}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
