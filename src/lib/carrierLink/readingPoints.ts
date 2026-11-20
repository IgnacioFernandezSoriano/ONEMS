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

/** Lugares/modos escaneados que no corresponden a ningún punto de lectura, por lecturas desc. */
export function unknownPlaces(
  scans: { place_ref: string; mode_ref: string | null; reject_reason: string | null; reader_id: string | null }[],
): UnknownPlace[] {
  const map = new Map<string, UnknownPlace>()
  for (const s of scans) {
    if (s.reject_reason !== 'unknown_reading_point' && s.reader_id !== null) continue
    const key = JSON.stringify([s.place_ref, s.mode_ref])
    const cur = map.get(key)
    if (cur) cur.readings += 1
    else map.set(key, { place_ref: s.place_ref, mode_ref: s.mode_ref, readings: 1 })
  }
  return [...map.values()].sort((a, b) => b.readings - a.readings)
}
