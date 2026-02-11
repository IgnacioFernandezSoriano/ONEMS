-- Sprint 10: Cut-off Times and Non-Working Days Calendars
-- This migration creates tables for managing cut-off times and non-working days calendars

-- Table: postal_center_cutoffs
-- Stores cut-off times for each postal center
CREATE TABLE IF NOT EXISTS postal_center_cutoffs (
    id BIGSERIAL PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    postal_center_id UUID NOT NULL REFERENCES postal_centers(id) ON DELETE CASCADE,
    
    -- Cut-off time configuration
    cutoff_time TIME NOT NULL, -- e.g., '18:00:00' for 6 PM
    timezone TEXT NOT NULL DEFAULT 'UTC', -- Timezone for the cut-off time
    
    -- Working hours configuration
    working_hours_start TIME NOT NULL DEFAULT '09:00:00',
    working_hours_end TIME NOT NULL DEFAULT '18:00:00',
    
    -- Days of week (1=Monday, 7=Sunday)
    working_days INTEGER[] NOT NULL DEFAULT '{1,2,3,4,5}', -- Monday to Friday by default
    
    -- Metadata
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id),
    
    -- Constraints
    UNIQUE(account_id, postal_center_id)
);

-- Table: non_working_days
-- Stores non-working days (holidays, special closures) per account
CREATE TABLE IF NOT EXISTS non_working_days (
    id BIGSERIAL PRIMARY KEY,
    account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    
    -- Date and description
    date DATE NOT NULL,
    name TEXT NOT NULL, -- e.g., "Christmas Day", "National Holiday"
    description TEXT,
    
    -- Scope: global for account or specific to postal centers
    applies_to_all_centers BOOLEAN NOT NULL DEFAULT true,
    postal_center_ids UUID[], -- NULL if applies_to_all_centers=true
    
    -- Type of non-working day
    day_type TEXT NOT NULL DEFAULT 'holiday', -- holiday, closure, maintenance
    
    -- Recurrence (for annual holidays)
    is_recurring BOOLEAN NOT NULL DEFAULT false,
    recurrence_pattern TEXT, -- e.g., "yearly", "monthly"
    
    -- Metadata
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID REFERENCES auth.users(id),
    updated_by UUID REFERENCES auth.users(id),
    
    -- Constraints
    UNIQUE(account_id, date, name)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_postal_center_cutoffs_account ON postal_center_cutoffs(account_id);
CREATE INDEX IF NOT EXISTS idx_postal_center_cutoffs_center ON postal_center_cutoffs(postal_center_id);
CREATE INDEX IF NOT EXISTS idx_non_working_days_account ON non_working_days(account_id);
CREATE INDEX IF NOT EXISTS idx_non_working_days_date ON non_working_days(date);

-- RLS Policies
ALTER TABLE postal_center_cutoffs ENABLE ROW LEVEL SECURITY;
ALTER TABLE non_working_days ENABLE ROW LEVEL SECURITY;

-- Policy: Users can only access cut-offs for their account
CREATE POLICY postal_center_cutoffs_account_isolation ON postal_center_cutoffs
    FOR ALL
    USING (account_id IN (
        SELECT account_id FROM user_accounts WHERE user_id = auth.uid()
    ));

-- Policy: Users can only access non-working days for their account
CREATE POLICY non_working_days_account_isolation ON non_working_days
    FOR ALL
    USING (account_id IN (
        SELECT account_id FROM user_accounts WHERE user_id = auth.uid()
    ));

-- Comments
COMMENT ON TABLE postal_center_cutoffs IS 'Cut-off times and working hours configuration for postal centers';
COMMENT ON TABLE non_working_days IS 'Non-working days calendar (holidays, closures) per account';
COMMENT ON COLUMN postal_center_cutoffs.cutoff_time IS 'Daily cut-off time after which events are considered next working day';
COMMENT ON COLUMN postal_center_cutoffs.working_hours_start IS 'Start of working hours for the center';
COMMENT ON COLUMN postal_center_cutoffs.working_hours_end IS 'End of working hours for the center';
COMMENT ON COLUMN postal_center_cutoffs.working_days IS 'Array of working days (1=Mon, 7=Sun)';
COMMENT ON COLUMN non_working_days.applies_to_all_centers IS 'If true, applies to all centers in account; if false, only to specified centers';
COMMENT ON COLUMN non_working_days.is_recurring IS 'If true, this day recurs annually (e.g., Christmas)';
