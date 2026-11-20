/** Códigos de error que lanzan las funciones de Carrier Link (CL_*). Cada uno tiene `cl.error.<código en minúsculas>`. */
export const CL_ERROR_CODES = [
  'CL_BAD_PAYLOAD',
  'CL_BATCH_ALREADY_UNDONE',
  'CL_BATCH_NOT_FOUND',
  'CL_BATCH_NOT_UNDOABLE',
  'CL_BATCH_NOT_VALIDATED',
  'CL_DEMAND_NOT_OPEN',
  'CL_DEMAND_TESTING_DRY_RUN_ONLY',
  'CL_DUPLICATE_QUOTA',
  'CL_FEED_CARRIER_MISMATCH',
  'CL_FEED_PAUSED',
  'CL_FORBIDDEN',
  'CL_MAPPING_INCOMPLETE',
  'CL_MISSING_POINTS',
  'CL_NO_FEED',
  'CL_NO_QUOTAS',
  'CL_PLAN_CLOSED',
  'CL_PLAN_LOCKED_FIELD',
  'CL_PLAN_NOT_DRAFT',
  'CL_QUOTA_LOCKED',
  'CL_QUOTA_NOT_FOUND',
  'CL_STRATUM_ALREADY_DELIVERED',
  'CL_TOO_MANY_ROWS',
  'CL_UNKNOWN_STRATUM',
] as const

/** Clave i18n del mensaje para un error de Supabase/RPC de Carrier Link. */
export function clErrorKey(err: { message?: string; code?: string } | null): string {
  if (!err) return 'cl.error.generic'
  const m = /CL_[A-Z_]+/.exec(err.message ?? '')
  if (m) return `cl.error.${m[0].toLowerCase()}`
  if (err.code === '42501') return 'cl.error.forbidden'
  return 'cl.error.generic'
}
