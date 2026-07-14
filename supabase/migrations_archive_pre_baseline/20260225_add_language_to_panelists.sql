-- Migration: Add language field to panelists table
-- Date: 2026-02-25
-- Description: Adds a language field to panelists, inherited from the account's default_language

ALTER TABLE panelists
ADD COLUMN IF NOT EXISTS language VARCHAR(5) NOT NULL DEFAULT 'en'
CHECK (language IN ('en', 'es', 'fr', 'ar'));

-- Update existing records to use 'en' as default
UPDATE panelists
SET language = 'en'
WHERE language IS NULL OR language NOT IN ('en', 'es', 'fr', 'ar');

COMMENT ON COLUMN panelists.language IS 
'Language of the panelist. Inherited from account default_language when created. Options: en, es, fr, ar.';
