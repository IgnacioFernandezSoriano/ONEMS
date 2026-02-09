-- Network Diagnostics Module
-- Tables for postal centers, readers, weekly schedules, and non-working days

-- Table: postal_centers
CREATE TABLE IF NOT EXISTS postal_centers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  calculation_mode TEXT CHECK (calculation_mode IN ('natural_days', 'working_days')),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id),
  UNIQUE(account_id, code)
);

-- Table: readers
CREATE TABLE IF NOT EXISTS readers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  postal_center_id UUID NOT NULL REFERENCES postal_centers(id) ON DELETE CASCADE,
  reader_id TEXT NOT NULL,
  name TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL CHECK (type IN ('Entry', 'Exit', 'Mixed')),
  mixed_reader_gap_minutes INTEGER CHECK (mixed_reader_gap_minutes > 0),
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by UUID REFERENCES auth.users(id),
  updated_by UUID REFERENCES auth.users(id),
  UNIQUE(account_id, reader_id)
);

COMMENT ON COLUMN readers.mixed_reader_gap_minutes IS 'Time gap in minutes to separate entry/exit events. Only applicable for Mixed type readers. NULL means inherit from account configuration.';

-- Table: weekly_schedule
CREATE TABLE IF NOT EXISTS weekly_schedule (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  postal_center_id UUID REFERENCES postal_centers(id) ON DELETE CASCADE,
  day_of_week INTEGER NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6),
  is_working_day BOOLEAN NOT NULL DEFAULT true,
  opening_hour TIME,
  cutoff_time TIME,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(account_id, postal_center_id, day_of_week),
  CHECK (
    (is_working_day = false) OR 
    (is_working_day = true AND opening_hour IS NOT NULL AND cutoff_time IS NOT NULL)
  )
);

COMMENT ON TABLE weekly_schedule IS 'Weekly schedules for account or postal centers. postal_center_id NULL means account-level schedule.';
COMMENT ON COLUMN weekly_schedule.day_of_week IS '0=Sunday, 1=Monday, 2=Tuesday, 3=Wednesday, 4=Thursday, 5=Friday, 6=Saturday';

-- Table: non_working_days
CREATE TABLE IF NOT EXISTS non_working_days (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  postal_center_id UUID REFERENCES postal_centers(id) ON DELETE CASCADE,
  date DATE NOT NULL,
  reason TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(account_id, postal_center_id, date)
);

COMMENT ON TABLE non_working_days IS 'Non-working days (holidays) for account or postal centers. postal_center_id NULL means account-level holidays.';

-- Indexes
CREATE INDEX IF NOT EXISTS idx_postal_centers_account ON postal_centers(account_id);
CREATE INDEX IF NOT EXISTS idx_readers_account ON readers(account_id);
CREATE INDEX IF NOT EXISTS idx_readers_postal_center ON readers(postal_center_id);
CREATE INDEX IF NOT EXISTS idx_weekly_schedule_account ON weekly_schedule(account_id);
CREATE INDEX IF NOT EXISTS idx_weekly_schedule_postal_center ON weekly_schedule(postal_center_id);
CREATE INDEX IF NOT EXISTS idx_non_working_days_account ON non_working_days(account_id);
CREATE INDEX IF NOT EXISTS idx_non_working_days_postal_center ON non_working_days(postal_center_id);
CREATE INDEX IF NOT EXISTS idx_non_working_days_date ON non_working_days(date);

-- RLS Policies
ALTER TABLE postal_centers ENABLE ROW LEVEL SECURITY;
ALTER TABLE readers ENABLE ROW LEVEL SECURITY;
ALTER TABLE weekly_schedule ENABLE ROW LEVEL SECURITY;
ALTER TABLE non_working_days ENABLE ROW LEVEL SECURITY;

-- Postal Centers Policies
CREATE POLICY "Users can view postal centers in their account"
  ON postal_centers FOR SELECT
  USING (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can insert postal centers in their account"
  ON postal_centers FOR INSERT
  WITH CHECK (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can update postal centers in their account"
  ON postal_centers FOR UPDATE
  USING (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can delete postal centers in their account"
  ON postal_centers FOR DELETE
  USING (account_id IN (SELECT get_user_accounts()));

-- Readers Policies
CREATE POLICY "Users can view readers in their account"
  ON readers FOR SELECT
  USING (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can insert readers in their account"
  ON readers FOR INSERT
  WITH CHECK (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can update readers in their account"
  ON readers FOR UPDATE
  USING (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can delete readers in their account"
  ON readers FOR DELETE
  USING (account_id IN (SELECT get_user_accounts()));

-- Weekly Schedule Policies
CREATE POLICY "Users can view weekly schedules in their account"
  ON weekly_schedule FOR SELECT
  USING (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can insert weekly schedules in their account"
  ON weekly_schedule FOR INSERT
  WITH CHECK (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can update weekly schedules in their account"
  ON weekly_schedule FOR UPDATE
  USING (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can delete weekly schedules in their account"
  ON weekly_schedule FOR DELETE
  USING (account_id IN (SELECT get_user_accounts()));

-- Non-Working Days Policies
CREATE POLICY "Users can view non-working days in their account"
  ON non_working_days FOR SELECT
  USING (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can insert non-working days in their account"
  ON non_working_days FOR INSERT
  WITH CHECK (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can update non-working days in their account"
  ON non_working_days FOR UPDATE
  USING (account_id IN (SELECT get_user_accounts()));

CREATE POLICY "Users can delete non-working days in their account"
  ON non_working_days FOR DELETE
  USING (account_id IN (SELECT get_user_accounts()));
