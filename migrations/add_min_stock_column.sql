-- Add min_stock column to material_catalog table
-- This column stores the minimum safety stock level for each material

ALTER TABLE material_catalog 
ADD COLUMN IF NOT EXISTS min_stock INTEGER DEFAULT 0;

-- Add comment to document the column
COMMENT ON COLUMN material_catalog.min_stock IS 'Minimum safety stock level for this material. Used in material requirements calculation.';

-- Update existing records to have a default value of 0
UPDATE material_catalog 
SET min_stock = 0 
WHERE min_stock IS NULL;
