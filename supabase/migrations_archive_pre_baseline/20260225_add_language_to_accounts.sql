-- Migration: Add default_language field to accounts table
-- Date: 2026-02-25
-- Description: Adds a default language field to accounts that will be inherited by panelists

ALTER TABLE accounts
ADD COLUMN IF NOT EXISTS default_language VARCHAR(5) NOT NULL DEFAULT 'en'
CHECK (default_language IN ('en', 'es', 'fr', 'ar'));

-- Update existing records to use 'en' as default
UPDATE accounts
SET default_language = 'en'
WHERE default_language IS NULL OR default_language NOT IN ('en', 'es', 'fr', 'ar');

COMMENT ON COLUMN accounts.default_language IS 
'Default language for the account. Inherited by panelists when created. Options: en, es, fr, ar.';
