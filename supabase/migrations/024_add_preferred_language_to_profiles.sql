-- Add preferred_language field to profiles table
-- Supports: en (English), es (Spanish), fr (French), ar (Arabic)

-- Add column with default 'en'
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS preferred_language VARCHAR(2) DEFAULT 'en';

-- Add check constraint to ensure only valid language codes
ALTER TABLE profiles 
ADD CONSTRAINT check_preferred_language 
CHECK (preferred_language IN ('en', 'es', 'fr', 'ar'));

-- Add comment for documentation
COMMENT ON COLUMN profiles.preferred_language IS 'User preferred language: en (English), es (Spanish), fr (French), ar (Arabic)';

-- Create index for faster queries
CREATE INDEX IF NOT EXISTS idx_profiles_preferred_language 
ON profiles(preferred_language);
