-- Migration: Add manual shipment registration fields
-- Description: Add fields for manual registration of shipment and reception
-- Date: 2025-12-10
-- Note: Uses existing origin_panelist_id and destination_panelist_id fields

-- Add tag_id field (if not exists)
ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS tag_id TEXT;

-- Add sent_at field (rename from sent_date for consistency)
ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ;

-- Add received_at field (rename from delivery_date for consistency)
ALTER TABLE allocation_plan_details 
ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ;

-- Migrate data from old columns to new columns (if they exist)
UPDATE allocation_plan_details 
SET sent_at = sent_date 
WHERE sent_date IS NOT NULL AND sent_at IS NULL;

UPDATE allocation_plan_details 
SET received_at = delivery_date 
WHERE delivery_date IS NOT NULL AND received_at IS NULL;

-- Add comments to document the fields
COMMENT ON COLUMN allocation_plan_details.tag_id IS 
'ID of the physical tag attached to the shipment';

COMMENT ON COLUMN allocation_plan_details.sent_at IS 
'Timestamp when the shipment was sent from origin node';

COMMENT ON COLUMN allocation_plan_details.received_at IS 
'Timestamp when the shipment was received at destination node';

COMMENT ON COLUMN allocation_plan_details.origin_panelist_id IS 
'Panelist at origin node who handles the shipment';

COMMENT ON COLUMN allocation_plan_details.destination_panelist_id IS 
'Panelist at destination node who receives the shipment';

-- Create index for tag_id
CREATE INDEX IF NOT EXISTS idx_allocation_plan_details_tag_id 
ON allocation_plan_details(tag_id);
