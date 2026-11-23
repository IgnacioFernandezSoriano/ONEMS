/** Códigos de error que lanzan las funciones de Carrier Link (CL_*). Cada uno tiene `cl.error.<código en minúsculas>`. */
export const CL_ERROR_CODES = [
  'CL_BAD_CONTROL_TOTALS',
  'CL_BAD_PAYLOAD',
  'CL_BAD_PERIOD',
  'CL_BAD_REQUEST',
  'CL_BATCH_ALREADY_UNDONE',
  'CL_BATCH_NOT_FOUND',
  'CL_BATCH_NOT_UNDOABLE',
  'CL_BATCH_NOT_VALIDATED',
  'CL_BODY_TOO_LARGE',
  'CL_CURSOR_MISMATCH',
  'CL_DELIVERY_BAD_TRANSITION',
  'CL_DELIVERY_IMMUTABLE',
  'CL_DELIVERY_NOT_FOUND',
  'CL_DELIVERY_NOT_LOADING',
  'CL_DEMAND_NOT_OPEN',
  'CL_DEMAND_TESTING_DRY_RUN_ONLY',
  'CL_DUPLICATE_QUOTA',
  'CL_FEED_CARRIER_MISMATCH',
  'CL_FEED_NOT_FOUND',
  'CL_FEED_PAUSED',
  'CL_FEED_TESTING_DRY_RUN_ONLY',
  'CL_FILE_NOT_UPLOADED',
  'CL_FILE_TOO_LARGE',
  'CL_FORBIDDEN',
  'CL_INCIDENT_CLOSED',
  'CL_LEASE_LOST',
  'CL_MAPPING_INCOMPLETE',
  'CL_MISSING_POINTS',
  'CL_NO_ACTIVE_PLAN',
  'CL_NO_FEED',
  'CL_NO_QUOTAS',
  'CL_PERIOD_ALREADY_DELIVERED',
  'CL_PERIOD_NOT_CLOSED',
  'CL_PERIOD_NOT_IN_CALENDAR',
  'CL_PLAN_CLOSED',
  'CL_PLAN_LOCKED_FIELD',
  'CL_PLAN_NOT_DRAFT',
  'CL_QUOTA_LOCKED',
  'CL_QUOTA_NOT_FOUND',
  'CL_REBALANCE_TOTAL_CHANGED',
  'CL_STAGING_NOT_EMPTY',
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
