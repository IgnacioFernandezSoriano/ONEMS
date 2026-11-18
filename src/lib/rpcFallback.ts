import { supabase } from './supabase'

/** ¿El error de un RPC indica que la función no existe (PostgREST PGRST202 / Postgres 42883)? */
export function isMissingFunctionError(err: { code?: string | null; message?: string | null } | null | undefined): boolean {
  if (!err) return false
  if (err.code === 'PGRST202' || err.code === '42883') return true
  const msg = (err.message ?? '').toLowerCase()
  return msg.includes('could not find the function') || (msg.includes('function') && msg.includes('does not exist'))
}

/**
 * Llama a `primary` y, si aún no existe en la base (despliegue escalonado: frontend antes que la
 * migración), reintenta con `fallback` y los mismos argumentos. Cualquier otro error se devuelve tal cual.
 */
export async function rpcWithFallback<T = unknown>(primary: string, fallback: string, args: Record<string, unknown>) {
  const first = await supabase.rpc(primary, args)
  if (!first.error || !isMissingFunctionError(first.error)) return first as { data: T | null; error: typeof first.error }
  const second = await supabase.rpc(fallback, args)
  return second as { data: T | null; error: typeof second.error }
}
