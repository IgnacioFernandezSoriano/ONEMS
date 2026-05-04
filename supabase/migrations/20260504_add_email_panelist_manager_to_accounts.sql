-- Add email_panelist_manager column to accounts table.
-- RLS: row-level policies on `accounts` (defined in 001_initial_schema.sql)
-- already cover this column. No policy changes are required:
--   * "Superadmin manages all accounts"  (FOR ALL)
--   * "Users view their own account"     (FOR SELECT)

ALTER TABLE accounts
  ADD COLUMN IF NOT EXISTS email_panelist_manager TEXT;

COMMENT ON COLUMN accounts.email_panelist_manager IS
  'Email address of the panelist manager for this account.';
