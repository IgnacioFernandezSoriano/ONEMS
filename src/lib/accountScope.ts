/**
 * Limits a Supabase query to one account when an account is selected. RLS lets a superadmin read every
 * account, so account-data queries must add this filter themselves; with no account (superadmin viewing
 * "all accounts") the query is returned unchanged. Normal users are already limited to their account by RLS.
 */
export function scopeToAccount<Q extends { eq: (column: string, value: any) => any }>(
  query: Q,
  accountId: string | null | undefined,
): Q {
  return accountId ? (query.eq('account_id', accountId) as Q) : query
}
