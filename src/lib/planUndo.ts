import { supabase } from '@/lib/supabase'

// Pila de "Deshacer" del Allocation Plan: las últimas acciones de la cuenta quedan en plan_undo_log
// (las escriben las RPC plan_action_*). Aquí solo se consulta la última y se pide revertirla.
export type UndoAction = 'delete' | 'update' | 'cancel' | 'edit' | 'create'

export interface UndoEntry {
  id: number
  action: UndoAction
  n_rows: number
  user_name: string | null
  created_at: string
}

export interface UndoResult {
  action: UndoAction
  restored: number
  skipped: number
  skipped_ids: string[]
}

// Última acción de la cuenta (la de id más alto: es la que deshace plan_undo_last). Nunca se piden las columnas jsonb (pueden pesar mucho).
export async function fetchLastUndo(accountId: string): Promise<UndoEntry | null> {
  const { data, error } = await supabase
    .from('plan_undo_log')
    .select('id, action, n_rows, user_name, created_at')
    .eq('account_id', accountId)
    .order('id', { ascending: false })
    .limit(1)
  if (error) throw error
  return (data && data[0] ? (data[0] as UndoEntry) : null)
}

// Revierte la última acción de la cuenta, solo si sigue siendo expectedId (la que el usuario confirmó). Si en
// medio otra persona actuó o deshizo, la BD no cambia nada y lanza el error PU001 (ver isUndoChangedError).
export async function undoLast(accountId: string, expectedId: number): Promise<UndoResult | null> {
  const { data, error } = await supabase.rpc('plan_undo_last', {
    p_account_id: accountId,
    p_expected_id: expectedId,
  })
  if (error) throw error
  return (data as UndoResult | null) ?? null
}

// Error de plan_undo_last cuando la última acción ya no es la confirmada.
export function isUndoChangedError(err: unknown): boolean {
  const e = err as { code?: string; message?: string } | null
  return e?.code === 'PU001' || (typeof e?.message === 'string' && e.message.includes('plan_undo_changed'))
}

// Texto de la entrada: "<acción> <n> registros · <usuario> · HH:mm" (hora local del navegador, 24 h).
export function undoLabel(
  entry: UndoEntry,
  t: (k: string, p?: Record<string, unknown>) => string
): string {
  const d = new Date(entry.created_at)
  const time = `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
  return t('allocation_plans.undo_label', {
    action: t('allocation_plans.undo_action_' + entry.action),
    count: entry.n_rows,
    user: entry.user_name || '—',
    time,
  })
}
