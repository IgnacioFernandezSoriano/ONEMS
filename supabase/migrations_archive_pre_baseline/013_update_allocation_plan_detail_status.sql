-- Migration: Update allocation_plan_details status values
-- Description: Add new status values (notified, received) and rename delivered to received
-- Date: 2025-12-10
-- Note: VALIDATED status is NOT included as per requirements

-- Step 1: Add new status values to the CHECK constraint
ALTER TABLE allocation_plan_details 
DROP CONSTRAINT IF EXISTS allocation_plan_details_status_check;

ALTER TABLE allocation_plan_details
ADD CONSTRAINT allocation_plan_details_status_check 
CHECK (status IN ('pending', 'notified', 'sent', 'received', 'cancelled'));

-- Step 2: Update existing 'delivered' records to 'received' (if any exist)
UPDATE allocation_plan_details 
SET status = 'received' 
WHERE status = 'delivered';

-- Step 3: Add comment to document the status values
COMMENT ON COLUMN allocation_plan_details.status IS 
'Status of the shipment: pending (initial), notified (panelist notified), sent (dispatched), received (delivered), cancelled (rejected)';

-- Note: The VALIDATED status exists in the specification but is NOT implemented in this version
-- It will be added in a future migration when the validation workflow is implemented
