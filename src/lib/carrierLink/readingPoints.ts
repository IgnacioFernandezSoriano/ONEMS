import { clErrorKey } from './clErrors'

export type E2eRole = 'origin' | 'destination' | 'both' | 'none'

export interface ReadingPointForm {
  carrier_id: string
  carrier_place_ref: string
  carrier_mode_ref: string
  postal_center_id: string
  e2e_role: E2eRole
  name: string
}

export type ReadingPointRowResult =
  | { ok: true; row: Record<string, unknown> }
  | { ok: false; error: 'no_account' | 'missing_place' | 'missing_carrier' | 'missing_center' }

/** Tipo de lector (CHECK Entry|Exit|Mixed) según el papel en el E2E. */
export function readerTypeForRole(role: E2eRole): 'Entry' | 'Exit' | 'Mixed' {
  if (role === 'origin') return 'Entry'
  if (role === 'both') return 'Mixed'
  return 'Exit'
}

/** Fila para `readers` de un punto de lectura del carrier. `reader_id` lo genera el trigger readers_cl_defaults. */
export function buildReadingPointRow(accountId: string | null, f: ReadingPointForm): ReadingPointRowResult {
  if (!accountId) return { ok: false, error: 'no_account' }
  if (!f.carrier_id) return { ok: false, error: 'missing_carrier' }
  const place = f.carrier_place_ref.trim()
  if (!place) return { ok: false, error: 'missing_place' }
  if (!f.postal_center_id) return { ok: false, error: 'missing_center' }
  const mode = f.carrier_mode_ref.trim()
  return {
    ok: true,
    row: {
      account_id: accountId,
      capture_source: 'carrier_scan',
      carrier_id: f.carrier_id,
      carrier_place_ref: place,
      carrier_mode_ref: mode === '' ? null : mode,
      postal_center_id: f.postal_center_id,
      e2e_role: f.e2e_role,
      type: readerTypeForRole(f.e2e_role),
      name: f.name.trim() || place,
    },
  }
}

export interface UnknownPlace {
  place_ref: string
  mode_ref: string | null
  readings: number
}

/**
 * Filas de la rpc cl_unknown_places (lugares/modos escaneados sin punto de lectura, ya agregados en el servidor),
 * leidas sin fiarse de su forma: se descartan las de lugar vacio o NULL y el modo en blanco cuenta como sin modo.
 */
export function parseUnknownPlaces(data: unknown): UnknownPlace[] {
  if (!Array.isArray(data)) return []
  const out: UnknownPlace[] = []
  for (const r of data) {
    if (!r || typeof r !== 'object') continue
    const o = r as Record<string, unknown>
    const place = typeof o.place_ref === 'string' ? o.place_ref.trim() : ''
    if (!place) continue
    const mode = typeof o.mode_ref === 'string' && o.mode_ref.trim() !== '' ? o.mode_ref.trim() : null
    const n = Number(o.readings)
    out.push({ place_ref: place, mode_ref: mode, readings: Number.isFinite(n) ? n : 0 })
  }
  return out
}

/**
 * Campos para reactivar un punto dado de baja (baja logica) con los datos del formulario: el reader_id generado
 * (CL:cuenta:carrier:lugar[:modo]) es unico por cuenta tambien entre los borrados, asi que dar de alta otra vez el
 * mismo lugar/modo reutiliza la fila borrada en vez de insertar otra.
 */
export function reviveReadingPointFields(row: Record<string, unknown>, now: string): Record<string, unknown> {
  const { account_id: _a, capture_source: _c, ...fields } = row
  void _a
  void _c
  return { ...fields, deleted_at: null, is_active: true, updated_at: now }
}

/** Clave i18n del error al guardar o borrar un punto: 23505 = ya hay un punto (o uno borrado) con ese lugar y modo. */
export function readingPointErrorKey(err: { message?: string; code?: string } | null): string {
  if (err?.code === '23505') return 'cl.reading_points.error.duplicate'
  return clErrorKey(err)
}

/** Quita de la lista los lugares que ya tienen un punto activo (modo NULL del punto = cualquier modo). */
export function excludeRegistered(
  unknown: UnknownPlace[],
  points: { carrier_place_ref: string; carrier_mode_ref: string | null; is_active?: boolean }[],
): UnknownPlace[] {
  return unknown.filter(
    (u) =>
      !points.some(
        (p) =>
          p.is_active !== false &&
          p.carrier_place_ref.trim() === u.place_ref.trim() &&
          (p.carrier_mode_ref === null || p.carrier_mode_ref.trim() === (u.mode_ref ?? '').trim()),
      ),
  )
}
