-- ============================================
-- ADD IDTAG FIELD TO ALLOCATION PLAN DETAILS
-- ============================================

-- Add idtag to generated_allocation_plan_details
ALTER TABLE generated_allocation_plan_details
  ADD COLUMN idtag TEXT;

-- Add idtag to allocation_plan_details
ALTER TABLE allocation_plan_details
  ADD COLUMN idtag TEXT;

-- Create index for idtag lookups
CREATE INDEX allocation_plan_details_idtag_idx ON allocation_plan_details(idtag) WHERE idtag IS NOT NULL;

SELECT 'IDTAG field added to allocation plan details' as status;
