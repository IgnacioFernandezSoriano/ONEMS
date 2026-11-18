import { Fragment, useEffect, useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { ACCESS_OPTIONS, type AccessLevel, type AccountRole } from '@/lib/access'
import {
  ACCOUNT_ROLES, GROUP_LABEL_KEYS, cellKey, levelToSelect, roleLabelKey, selectToLevel, type LevelMap,
} from '@/lib/accessAdmin'

interface Props {
  matrix: LevelMap
  noRole: Map<string, AccessLevel>
  canEdit: boolean
  onChange: (role: AccountRole, option: string, level: AccessLevel | null) => Promise<boolean>
}

const LEVEL_KEYS: Record<'' | AccessLevel, string> = {
  edit: 'roles_access.level.edit',
  view: 'roles_access.level.view',
  '': 'roles_access.level.none',
}

const LEVEL_STYLE: Record<'' | AccessLevel, string> = {
  edit: 'bg-green-50 text-green-800 border-green-300',
  view: 'bg-blue-50 text-blue-800 border-blue-300',
  '': 'bg-white text-gray-400 border-gray-200',
}

/** Matriz opciones × roles de la cuenta. Columna "Sin rol" fija (plantilla), de solo lectura. */
export function AccessMatrix({ matrix, noRole, canEdit, onChange }: Props) {
  const { t } = useTranslation()
  const [busy, setBusy] = useState<string | null>(null)
  // Valor elegido mientras llega la matriz recargada (evita que el selector vuelva un instante al valor viejo).
  const [overrides, setOverrides] = useState<Map<string, '' | AccessLevel>>(new Map())
  useEffect(() => setOverrides(new Map()), [matrix])

  const groupLabel = (g: string) => (GROUP_LABEL_KEYS[g] ?? [g]).map(k => t(k)).join(' · ')

  const change = async (role: AccountRole, option: string, value: string) => {
    const k = cellKey(role, option)
    setBusy(k)
    setOverrides(prev => new Map(prev).set(k, levelToSelect(selectToLevel(value))))
    const ok = await onChange(role, option, selectToLevel(value))
    if (!ok) setOverrides(prev => { const m = new Map(prev); m.delete(k); return m })
    setBusy(null)
  }

  return (
    <div className="overflow-x-auto border border-gray-200 rounded-lg">
      <table className="min-w-full text-sm">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-3 py-2 text-start font-medium text-gray-700">{t('roles_access.matrix_option')}</th>
            {ACCOUNT_ROLES.map(r => (
              <th key={r} className="px-2 py-2 text-center font-medium text-gray-700 whitespace-nowrap">{t(roleLabelKey(r))}</th>
            ))}
            <th className="px-2 py-2 text-center font-medium text-gray-500 whitespace-nowrap" title={t('roles_access.no_role_help')}>
              {t('roles_access.no_role')}
            </th>
          </tr>
        </thead>
        <tbody>
          {ACCESS_OPTIONS.map((o, i) => (
            <Fragment key={o.key}>
              {(i === 0 || ACCESS_OPTIONS[i - 1].group !== o.group) && (
                <tr className="bg-gray-100">
                  <td colSpan={ACCOUNT_ROLES.length + 2} className="px-3 py-1 text-xs font-semibold uppercase text-gray-600">
                    {groupLabel(o.group)}
                  </td>
                </tr>
              )}
              <tr className="border-t border-gray-100">
                <td className="px-3 py-1 text-gray-900 whitespace-nowrap">{t(o.labelKey)}</td>
                {ACCOUNT_ROLES.map(r => {
                  const k = cellKey(r, o.key)
                  const v = overrides.get(k) ?? levelToSelect(matrix.get(k))
                  return (
                    <td key={r} className="px-2 py-1 text-center">
                      {canEdit ? (
                        <select
                          aria-label={`${t(o.labelKey)} · ${t(roleLabelKey(r))}`}
                          value={v}
                          disabled={busy !== null}
                          onChange={e => change(r, o.key, e.target.value)}
                          className={`text-xs border rounded px-1 py-0.5 disabled:opacity-60 ${LEVEL_STYLE[v]}`}
                        >
                          <option value="edit">{t(LEVEL_KEYS.edit)}</option>
                          <option value="view">{t(LEVEL_KEYS.view)}</option>
                          <option value="">{t(LEVEL_KEYS[''])}</option>
                        </select>
                      ) : (
                        <span className={`inline-block text-xs border rounded px-2 py-0.5 ${LEVEL_STYLE[v]}`}>{t(LEVEL_KEYS[v])}</span>
                      )}
                    </td>
                  )
                })}
                <td className="px-2 py-1 text-center bg-gray-50">
                  {(() => {
                    const v = levelToSelect(noRole.get(o.key))
                    return <span className={`inline-block text-xs border rounded px-2 py-0.5 ${LEVEL_STYLE[v]}`}>{t(LEVEL_KEYS[v])}</span>
                  })()}
                </td>
              </tr>
            </Fragment>
          ))}
        </tbody>
      </table>
    </div>
  )
}
