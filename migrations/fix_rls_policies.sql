-- Fix RLS policies for material_requirements_periods and proposed_shipments tables
-- These tables need proper RLS policies to allow authenticated users to read/write

-- Check if RLS is enabled and disable if causing issues
-- Material Requirements Periods
ALTER TABLE material_requirements_periods DISABLE ROW LEVEL SECURITY;

-- Proposed Shipments
ALTER TABLE proposed_shipments DISABLE ROW LEVEL SECURITY;

-- Material Movements (for adjust stock functionality)
ALTER TABLE material_movements DISABLE ROW LEVEL SECURITY;

-- Panelist Stock (for adjust stock in panelist)
ALTER TABLE panelist_stock DISABLE ROW LEVEL SECURITY;

-- Alternative: If you want to keep RLS enabled, use these policies instead:
-- (Comment out the DISABLE commands above and uncomment these)

/*
-- Enable RLS
ALTER TABLE material_requirements_periods ENABLE ROW LEVEL SECURITY;
ALTER TABLE proposed_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE material_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE panelist_stock ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Allow all for authenticated users" ON material_requirements_periods;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON proposed_shipments;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON material_movements;
DROP POLICY IF EXISTS "Allow all for authenticated users" ON panelist_stock;

-- Create permissive policies for authenticated users
CREATE POLICY "Allow all for authenticated users" 
ON material_requirements_periods 
FOR ALL 
TO authenticated 
USING (true) 
WITH CHECK (true);

CREATE POLICY "Allow all for authenticated users" 
ON proposed_shipments 
FOR ALL 
TO authenticated 
USING (true) 
WITH CHECK (true);

CREATE POLICY "Allow all for authenticated users" 
ON material_movements 
FOR ALL 
TO authenticated 
USING (true) 
WITH CHECK (true);

CREATE POLICY "Allow all for authenticated users" 
ON panelist_stock 
FOR ALL 
TO authenticated 
USING (true) 
WITH CHECK (true);
*/
