-- Sprint 10: Cut-off Times & Working Days (Adapted to use existing postal_centers fields)
-- Migration 1: Add missing fields to postal_centers and create non_working_days table

-- Add missing fields to postal_centers
ALTER TABLE postal_centers
ADD COLUMN IF NOT EXISTS working_hours_end TIME,
ADD COLUMN IF NOT EXISTS working_days TEXT[] DEFAULT ARRAY['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'],
ADD COLUMN IF NOT EXISTS timezone TEXT DEFAULT 'UTC';

-- Comment existing fields for clarity
COMMENT ON COLUMN postal_centers.opening_hour IS 'Working hours start time (used as working_hours_start)';
COMMENT ON COLUMN postal_centers.cutoff_time IS 'Daily cut-off time for processing';
COMMENT ON COLUMN postal_centers.working_hours_end IS 'Working hours end time';
COMMENT ON COLUMN postal_centers.working_days IS 'Array of working days (Monday, Tuesday, etc.)';
COMMENT ON COLUMN postal_centers.timezone IS 'Timezone for this postal center (e.g., UTC, Europe/Madrid)';

-- Set default working_hours_end if not set (18:00)
UPDATE postal_centers
SET working_hours_end = '18:00:00'
WHERE working_hours_end IS NULL;

-- Create non_working_days table
CREATE TABLE IF NOT EXISTS non_working_days (
    id BIGSERIAL PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    name TEXT NOT NULL,
    description TEXT,
    day_type TEXT NOT NULL CHECK (day_type IN ('holiday', 'closure', 'maintenance')),
    applies_to_all_centers BOOLEAN DEFAULT true,
    postal_center_ids UUID[] DEFAULT ARRAY[]::UUID[],
    is_recurring BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id),
    deleted_at TIMESTAMPTZ,
    
    CONSTRAINT unique_non_working_day UNIQUE (account_id, date, name)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_non_working_days_account_date ON non_working_days(account_id, date) WHERE deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_non_working_days_recurring ON non_working_days(account_id, is_recurring) WHERE deleted_at IS NULL AND is_recurring = true;

-- Enable RLS
ALTER TABLE non_working_days ENABLE ROW LEVEL SECURITY;

-- RLS Policies for non_working_days
CREATE POLICY "Users can view non_working_days for their account"
    ON non_working_days FOR SELECT
    USING (
        account_id IN (
            SELECT account_id FROM user_accounts WHERE user_id = auth.uid()
        )
        AND deleted_at IS NULL
    );

CREATE POLICY "Admins can insert non_working_days"
    ON non_working_days FOR INSERT
    WITH CHECK (
        account_id IN (
            SELECT ua.account_id 
            FROM user_accounts ua
            JOIN users u ON ua.user_id = u.id
            WHERE ua.user_id = auth.uid()
            AND u.user_type IN ('admin', 'superadmin')
        )
    );

CREATE POLICY "Admins can update non_working_days"
    ON non_working_days FOR UPDATE
    USING (
        account_id IN (
            SELECT ua.account_id 
            FROM user_accounts ua
            JOIN users u ON ua.user_id = u.id
            WHERE ua.user_id = auth.uid()
            AND u.user_type IN ('admin', 'superadmin')
        )
        AND deleted_at IS NULL
    );

CREATE POLICY "Admins can delete non_working_days"
    ON non_working_days FOR DELETE
    USING (
        account_id IN (
            SELECT ua.account_id 
            FROM user_accounts ua
            JOIN users u ON ua.user_id = u.id
            WHERE ua.user_id = auth.uid()
            AND u.user_type IN ('admin', 'superadmin')
        )
    );

-- Add comments
COMMENT ON TABLE non_working_days IS 'Calendar of non-working days (holidays, closures) per account';
COMMENT ON COLUMN non_working_days.day_type IS 'Type of non-working day: holiday, closure, or maintenance';
COMMENT ON COLUMN non_working_days.applies_to_all_centers IS 'If true, applies to all postal centers in the account';
COMMENT ON COLUMN non_working_days.postal_center_ids IS 'Specific postal centers affected (if applies_to_all_centers is false)';
COMMENT ON COLUMN non_working_days.is_recurring IS 'If true, this day recurs annually (e.g., Christmas)';
