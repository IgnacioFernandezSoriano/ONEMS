// Ayudas puras de la pestaña "Roles y accesos" (matriz, usuarios con rol, registro de cambios, errores).
import type { AccessLevel, AccountRole } from './access'
import type { AccountContactField } from './types'

/** Los seis roles fijos, en el orden de la matriz (el del documento de roles: UPU el último). */
export const ACCOUNT_ROLES: AccountRole[] = [
  'account_manager', 'allocation_plan_manager', 'panelist_manager',
  'materials_supplier', 'do_coordinator', 'upu_account_manager',
]

/** Clave i18n del nombre de un rol (los nombres se muestran en inglés: son nombres propios del documento). */
export function roleLabelKey(role: string): string {
  return `roles_access.role.${role}`
}

/** Clave i18n del título de cada grupo del menú (puede ser compuesta: módulo · grupo). */
export const GROUP_LABEL_KEYS: Record<string, string[]> = {
  dashboard: ['menu.dashboard'],
  e2e_setup: ['menu.e2e', 'menu.setup'],
  e2e_allocation: ['menu.e2e', 'menu.allocation'],
  e2e_materials: ['menu.e2e', 'menu.materials'],
  e2e_reporting: ['menu.e2e', 'menu.reporting'],
  e2e_database: ['menu.e2e', 'menu.database'],
  rfid_setup: ['menu.diagnosis', 'menu.setup'],
  rfid_reporting: ['menu.diagnosis', 'menu.reporting'],
  rfid_database: ['menu.diagnosis', 'menu.database'],
  incidents: ['incidents.menu_group'],
  administration: ['menu.administration'],
  help: ['menu.help_group'],
}

/** Clave i18n (etiqueta; ayuda = clave + '_help') de cada correo de contacto. */
export const CONTACT_I18N: Record<AccountContactField, string> = {
  email_account_manager: 'hc.account_form.account_manager_email',
  email_panelist_manager: 'hc.account_form.manager_email',
  email_materials_supplier: 'hc.account_form.materials_supplier_email',
  email_do_coordinator: 'hc.account_form.do_coordinator_email',
  email_upu_account_manager: 'hc.account_form.upu_account_manager_email',
  email_allocation_plan_manager: 'hc.account_form.allocation_plan_manager_email',
}

export type LevelMap = Map<string, AccessLevel>

export function cellKey(role: string, option: string): string {
  return `${role}|${option}`
}

/** Matriz rol×opción a partir de filas {role, option, level}. */
export function buildLevelMap(rows: { role: string; option: string; level: string }[]): LevelMap {
  const m: LevelMap = new Map()
  for (const r of rows) if (r.level === 'edit' || r.level === 'view') m.set(cellKey(r.role, r.option), r.level)
  return m
}

export interface RoleRow { user_id: string; role: string; provisional: boolean }
export interface ProfileLite { id: string; email: string | null; full_name: string | null; role?: string | null; account_id?: string | null }

export interface AccountUser {
  user_id: string
  email: string | null
  full_name: string | null
  roles: Set<AccountRole>
  provisional: Set<AccountRole>
  /** false si no llegó su perfil: solo se conoce el id (o el correo por el registro). */
  profileReadable: boolean
  /** true si su cuenta activa es esta; false = tiene rol aquí pero trabaja en otra cuenta. */
  activeHere: boolean
}

/**
 * Usuarios a listar: perfiles cuya cuenta activa es esta (sin superadmin) + quien tenga algún rol en la cuenta.
 * `emailHints` = correos conocidos por otra vía (p. ej. el registro de "añadir por correo").
 * Orden: por correo (los desconocidos al final, por id).
 */
export function mergeAccountUsers(
  accountId: string,
  profiles: ProfileLite[],
  roleRows: RoleRow[],
  emailHints: Map<string, string> = new Map(),
): AccountUser[] {
  const byId = new Map<string, AccountUser>()
  const profileById = new Map(profiles.map(p => [p.id, p]))
  const ensure = (id: string): AccountUser => {
    let u = byId.get(id)
    if (!u) {
      const p = profileById.get(id)
      u = {
        user_id: id,
        email: p?.email ?? emailHints.get(id) ?? null,
        full_name: p?.full_name ?? null,
        roles: new Set(),
        provisional: new Set(),
        profileReadable: !!p,
        activeHere: p?.account_id === accountId,
      }
      byId.set(id, u)
    }
    return u
  }
  for (const p of profiles) if (p.account_id === accountId && p.role !== 'superadmin') ensure(p.id)
  for (const r of roleRows) {
    const u = ensure(r.user_id)
    u.roles.add(r.role as AccountRole)
    if (r.provisional) u.provisional.add(r.role as AccountRole)
  }
  return [...byId.values()].sort((a, b) => {
    if (a.email && b.email) return a.email.localeCompare(b.email)
    if (a.email) return -1
    if (b.email) return 1
    return a.user_id.localeCompare(b.user_id)
  })
}

/** Errores conocidos de los RPC -> clave i18n; null si no se reconoce (se muestra el texto tal cual). */
export function accessErrorKey(message: string | null | undefined): string | null {
  const m = message ?? ''
  if (m.includes('Cannot remove your last editor role')) return 'roles_access.error.last_editor_role'
  if (m.includes('User is not a member of this account')) return 'roles_access.error.not_member'
  if (m.includes('User not found')) return 'roles_access.error.user_not_found'
  if (m.includes('Superadmin does not take account roles')) return 'roles_access.error.superadmin_role'
  if (m.includes('Forbidden account') || m.includes('Only superadmin') || m.includes('Not authenticated')) {
    return 'roles_access.error.forbidden'
  }
  return null
}

export interface LogEntry {
  id: number
  changed_by: string | null
  changed_at: string
  kind: string
  detail: Record<string, unknown> | null
}

/** Cómo nombrar cada pieza del resumen (lo pone la UI: traducciones y correos). */
export interface LogNames {
  role: (role: string) => string
  option: (option: string) => string
  level: (level: string | null) => string
  user: (userId: string, emailHint?: string) => string
  contact: (field: string) => string
}

/** Resumen corto de una fila del registro: clave i18n + variables ya nombradas. */
export function summarizeLog(e: LogEntry, n: LogNames): { key: string; vars: Record<string, string> } {
  const d = (e.detail ?? {}) as Record<string, unknown>
  const s = (v: unknown) => (typeof v === 'string' ? v : '')
  switch (e.kind) {
    case 'access_set':
      return {
        key: 'roles_access.log.access_set',
        vars: {
          role: n.role(s(d.role)),
          option: n.option(s(d.option)),
          before: n.level(s(d.before) || null),
          after: n.level(s(d.after) || null),
        },
      }
    case 'access_reset':
      return { key: 'roles_access.log.access_reset', vars: {} }
    case 'user_role_set':
      return {
        key: d.enabled === false ? 'roles_access.log.user_role_removed' : 'roles_access.log.user_role_added',
        vars: { user: n.user(s(d.user_id)), role: n.role(s(d.role)) },
      }
    case 'user_role_add_by_email':
      return {
        key: 'roles_access.log.user_added_by_email',
        vars: { user: n.user(s(d.user_id), s(d.email) || undefined), role: n.role(s(d.role)) },
      }
    case 'contacts_set': {
      const after = (d.after && typeof d.after === 'object' ? d.after : {}) as Record<string, unknown>
      const before = (d.before && typeof d.before === 'object' ? d.before : {}) as Record<string, unknown>
      const changed = Object.keys(after).filter(k => (after[k] ?? null) !== (before[k] ?? null))
      return {
        key: changed.length ? 'roles_access.log.contacts_set' : 'roles_access.log.contacts_unchanged',
        vars: { fields: changed.map(n.contact).join(', ') },
      }
    }
    case 'activation': {
      const list = Array.isArray(d.assignments) ? d.assignments : []
      return { key: 'roles_access.log.activation', vars: { count: String(list.length) } }
    }
    default:
      return { key: 'roles_access.log.other', vars: { kind: e.kind } }
  }
}

/** Valor del selector de celda: '' = sin acceso. */
export function levelToSelect(level: AccessLevel | undefined | null): '' | AccessLevel {
  return level ?? ''
}

export function selectToLevel(v: string): AccessLevel | null {
  return v === 'edit' || v === 'view' ? v : null
}
