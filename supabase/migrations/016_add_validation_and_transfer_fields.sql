-- Migration 016: Add validation and transfer tracking fields to allocation_plan_details
-- Version: 2.0
-- Date: 2025-12-10

-- Add new status values: 'invalid' and 'transfer_error'
ALTER TABLE allocation_plan_details DROP CONSTRAINT IF EXISTS allocation_plan_details_status_check;
ALTER TABLE allocation_plan_details 
  ADD CONSTRAINT allocation_plan_details_status_check 
  CHECK (status IN ('pending', 'notified', 'sent', 'received', 'cancelled', 'invalid', 'transfer_error'));

-- Add validation_errors field (array of error messages)
ALTER TABLE allocation_plan_details 
  ADD COLUMN IF NOT EXISTS validation_errors TEXT[] DEFAULT NULL;

-- Add transferred_to_one_db_at field (timestamp of successful transfer)
ALTER TABLE allocation_plan_details 
  ADD COLUMN IF NOT EXISTS transferred_to_one_db_at TIMESTAMPTZ DEFAULT NULL;

-- Add transfer_error_message field (for technical errors during transfer)
ALTER TABLE allocation_plan_details 
  ADD COLUMN IF NOT EXISTS transfer_error_message TEXT DEFAULT NULL;

-- Create index for filtering by transfer status
CREATE INDEX IF NOT EXISTS idx_allocation_plan_details_transfer_status 
  ON allocation_plan_details(status) 
  WHERE status IN ('invalid', 'transfer_error');

-- Create index for finding records ready to transfer
CREATE INDEX IF NOT EXISTS idx_allocation_plan_details_ready_to_transfer 
  ON allocation_plan_details(status, transferred_to_one_db_at) 
  WHERE status = 'received' AND transferred_to_one_db_at IS NULL;

-- Add comments
COMMENT ON COLUMN allocation_plan_details.validation_errors IS 'Array of validation error messages explaining why the record is invalid';
COMMENT ON COLUMN allocation_plan_details.transferred_to_one_db_at IS 'Timestamp when the record was successfully transferred to ONE_DB';
COMMENT ON COLUMN allocation_plan_details.transfer_error_message IS 'Technical error message if transfer to ONE_DB failed';
