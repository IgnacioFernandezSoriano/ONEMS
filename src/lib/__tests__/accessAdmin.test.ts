import { describe, it, expect } from 'vitest'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { ACCESS_OPTIONS } from '../access'
import {
  ACCOUNT_ROLES, GROUP_LABEL_KEYS, buildLevelMap, cellKey, mergeAccountUsers, accessErrorKey,
  summarizeLog, selectToLevel, levelToSelect, type LogNames,
} from '../accessAdmin'

const names: LogNames = {
  role: r => `R:${r}`,
  option: o => `O:${o}`,
  level: l => `L:${l ?? '-'}`,
  user: (id, hint) => hint ?? `U:${id}`,
  contact: f => `C:${f}`,
}

describe('accessAdmin', () => {
  it('seis roles y todos los grupos del catálogo tienen título', () => {
    expect(ACCOUNT_ROLES).toHaveLength(6)
    for (const o of ACCESS_OPTIONS) expect(GROUP_LABEL_KEYS[o.group]).toBeDefined()
    expect(GROUP_LABEL_KEYS.carrier_link).toBeDefined()
  })

  it('buildLevelMap ignora niveles desconocidos', () => {
    const m = buildLevelMap([
      { role: 'account_manager', option: 'dashboard', level: 'view' },
      { role: 'account_manager', option: 'topology', level: 'edit' },
      { role: 'account_manager', option: 'carriers', level: 'x' },
    ])
    expect(m.get(cellKey('account_manager', 'topology'))).toBe('edit')
    expect(m.get(cellKey('account_manager', 'dashboard'))).toBe('view')
    expect(m.has(cellKey('account_manager', 'carriers'))).toBe(false)
  })

  it('mergeAccountUsers une perfiles de la cuenta y usuarios con rol (incluidos ilegibles)', () => {
    const users = mergeAccountUsers(
      'A',
      [
        { id: 'u1', email: 'b@x.org', full_name: 'B', role: 'admin', account_id: 'A' },
        { id: 'u2', email: 'a@x.org', full_name: 'A', role: 'user', account_id: 'A' },
        { id: 'su', email: 's@x.org', full_name: null, role: 'superadmin', account_id: 'A' },
        { id: 'u9', email: 'other@x.org', full_name: null, role: 'user', account_id: 'B' },
      ],
      [
        { user_id: 'u1', role: 'account_manager', provisional: true },
        { user_id: 'u1', role: 'panelist_manager', provisional: false },
        { user_id: 'u3', role: 'upu_account_manager', provisional: false },
        { user_id: 'u4', role: 'do_coordinator', provisional: false },
      ],
      new Map([['u3', 'upu@x.org']]),
    )
    expect(users.map(u => u.user_id)).toEqual(['u2', 'u1', 'u3', 'u4'])
    const u1 = users.find(u => u.user_id === 'u1')!
    expect([...u1.roles].sort()).toEqual(['account_manager', 'panelist_manager'])
    expect([...u1.provisional]).toEqual(['account_manager'])
    expect(u1.activeHere).toBe(true)
    expect(users.find(u => u.user_id === 'u3')!).toMatchObject({ email: 'upu@x.org', profileReadable: false, activeHere: false })
    expect(users.find(u => u.user_id === 'u4')!.email).toBeNull()
  })

  it('accessErrorKey reconoce los errores de los RPC', () => {
    expect(accessErrorKey('Cannot remove your last editor role in this account')).toBe('roles_access.error.last_editor_role')
    expect(accessErrorKey('User is not a member of this account')).toBe('roles_access.error.not_member')
    expect(accessErrorKey('User not found: a@b.c')).toBe('roles_access.error.user_not_found')
    expect(accessErrorKey('Forbidden account')).toBe('roles_access.error.forbidden')
    expect(accessErrorKey('boom')).toBeNull()
    expect(accessErrorKey(undefined)).toBeNull()
  })

  it('summarizeLog resume cada tipo de cambio', () => {
    const base = { id: 1, changed_by: 'x', changed_at: '2026-11-18T10:00:00Z' }
    expect(summarizeLog({ ...base, kind: 'access_set', detail: { role: 'account_manager', option: 'topology', before: null, after: 'edit' } }, names))
      .toEqual({ key: 'roles_access.log.access_set', vars: { role: 'R:account_manager', option: 'O:topology', before: 'L:-', after: 'L:edit' } })
    expect(summarizeLog({ ...base, kind: 'access_reset', detail: {} }, names).key).toBe('roles_access.log.access_reset')
    expect(summarizeLog({ ...base, kind: 'user_role_set', detail: { user_id: 'u1', role: 'do_coordinator', enabled: false } }, names))
      .toEqual({ key: 'roles_access.log.user_role_removed', vars: { user: 'U:u1', role: 'R:do_coordinator' } })
    expect(summarizeLog({ ...base, kind: 'user_role_set', detail: { user_id: 'u1', role: 'do_coordinator', enabled: true } }, names).key)
      .toBe('roles_access.log.user_role_added')
    expect(summarizeLog({ ...base, kind: 'user_role_add_by_email', detail: { user_id: 'u1', email: 'e@x.org', role: 'account_manager' } }, names).vars.user)
      .toBe('e@x.org')
    expect(summarizeLog({ ...base, kind: 'contacts_set', detail: {
      before: { email_account_manager: 'a@x.org', email_do_coordinator: null },
      after: { email_account_manager: 'b@x.org', email_do_coordinator: null },
    } }, names)).toEqual({ key: 'roles_access.log.contacts_set', vars: { fields: 'C:email_account_manager' } })
    expect(summarizeLog({ ...base, kind: 'contacts_set', detail: { before: {}, after: {} } }, names).key)
      .toBe('roles_access.log.contacts_unchanged')
    expect(summarizeLog({ ...base, kind: 'activation', detail: { assignments: [{}, {}] } }, names).vars.count).toBe('2')
    expect(summarizeLog({ ...base, kind: 'weird', detail: null }, names)).toEqual({ key: 'roles_access.log.other', vars: { kind: 'weird' } })
  })

  it('selector de celda', () => {
    expect(selectToLevel('edit')).toBe('edit')
    expect(selectToLevel('')).toBeNull()
    expect(levelToSelect(undefined)).toBe('')
  })

  it('todas las claves roles_access usadas en el código existen en los 5 idiomas', () => {
    const files = [
      '../accessAdmin.ts',
      '../../components/accounts/RolesAccessTab.tsx',
      '../../components/accounts/roles/AccessMatrix.tsx',
      '../../components/accounts/roles/UserRolesSection.tsx',
      '../../components/accounts/roles/AccessLogSection.tsx',
      '../../components/accounts/roles/ContactsSection.tsx',
      '../../components/accounts/AccountForm.tsx',
      '../../pages/Settings/RolesAccess.tsx',
      '../../components/layout/Sidebar.tsx',
    ]
    const used = new Set<string>()
    for (const f of files) {
      const src = readFileSync(resolve(__dirname, f), 'utf8')
      for (const m of src.matchAll(/'(roles_access\.[a-z0-9_.]+)'/g)) used.add(m[1])
    }
    for (const r of ACCOUNT_ROLES) used.add(`roles_access.role.${r}`)
    expect(used.size).toBeGreaterThan(20)
    for (const lang of ['en', 'es', 'fr', 'ar', 'pt']) {
      const csv = readFileSync(resolve(__dirname, `../../../public/locales/${lang}.csv`), 'utf8')
      const keys = new Set(csv.split('\r\n').map(l => l.split(',')[0]))
      const missing = [...used].filter(k => !keys.has(k))
      expect({ lang, missing }).toEqual({ lang, missing: [] })
    }
  })
})
