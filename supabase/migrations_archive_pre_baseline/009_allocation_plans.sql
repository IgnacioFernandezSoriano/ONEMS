-- ============================================
-- ALLOCATION PLANS MODULE
-- ============================================

-- Helper functions (if not already exist)
CREATE OR REPLACE FUNCTION public.current_user_account_id()
RETURNS UUID AS $$
  SELECT account_id FROM profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT AS $$
  SELECT role FROM profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Table: generated_allocation_plans (temporary/draft plans)
CREATE TABLE generated_allocation_plans (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  plan_name TEXT NOT NULL,
  carrier_id UUID NOT NULL REFERENCES carriers(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  total_samples INTEGER NOT NULL CHECK (total_samples > 0),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL CHECK (end_date >= start_date),
  status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'pending', 'applied')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES profiles(id),
  UNIQUE(account_id, plan_name)
);

-- Table: generated_allocation_plan_details (temporary/draft plan details)
CREATE TABLE generated_allocation_plan_details (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  plan_id UUID NOT NULL REFERENCES generated_allocation_plans(id) ON DELETE CASCADE,
  origin_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  destination_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  fecha_programada DATE NOT NULL,
  week_number INTEGER NOT NULL CHECK (week_number >= 1 AND week_number <= 53),
  month INTEGER NOT NULL CHECK (month >= 1 AND month <= 12),
  year INTEGER NOT NULL CHECK (year >= 2000),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'cancelled')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Table: allocation_plans (applied/confirmed plans - historical)
CREATE TABLE allocation_plans (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  plan_name TEXT NOT NULL,
  carrier_id UUID NOT NULL REFERENCES carriers(id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  total_samples INTEGER NOT NULL CHECK (total_samples > 0),
  start_date DATE NOT NULL,
  end_date DATE NOT NULL CHECK (end_date >= start_date),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
  applied_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID REFERENCES profiles(id),
  applied_by UUID REFERENCES profiles(id),
  UNIQUE(account_id, plan_name)
);

-- Table: allocation_plan_details (applied plan details - historical)
CREATE TABLE allocation_plan_details (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  plan_id UUID NOT NULL REFERENCES allocation_plans(id) ON DELETE CASCADE,
  origin_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  destination_node_id UUID NOT NULL REFERENCES nodes(id) ON DELETE CASCADE,
  fecha_programada DATE NOT NULL,
  week_number INTEGER NOT NULL CHECK (week_number >= 1 AND week_number <= 53),
  month INTEGER NOT NULL CHECK (month >= 1 AND month <= 12),
  year INTEGER NOT NULL CHECK (year >= 2000),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'delivered', 'cancelled')),
  origin_panelist_name TEXT,
  destination_panelist_name TEXT,
  sent_date TIMESTAMPTZ,
  delivery_date TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for performance
CREATE INDEX idx_generated_allocation_plans_account ON generated_allocation_plans(account_id);
CREATE INDEX idx_generated_allocation_plans_status ON generated_allocation_plans(status);
CREATE INDEX idx_generated_allocation_plans_carrier ON generated_allocation_plans(carrier_id);
CREATE INDEX idx_generated_allocation_plans_product ON generated_allocation_plans(product_id);

CREATE INDEX idx_generated_allocation_plan_details_account ON generated_allocation_plan_details(account_id);
CREATE INDEX idx_generated_allocation_plan_details_plan ON generated_allocation_plan_details(plan_id);
CREATE INDEX idx_generated_allocation_plan_details_date ON generated_allocation_plan_details(fecha_programada);
CREATE INDEX idx_generated_allocation_plan_details_origin ON generated_allocation_plan_details(origin_node_id);
CREATE INDEX idx_generated_allocation_plan_details_destination ON generated_allocation_plan_details(destination_node_id);

CREATE INDEX idx_allocation_plans_account ON allocation_plans(account_id);
CREATE INDEX idx_allocation_plans_status ON allocation_plans(status);
CREATE INDEX idx_allocation_plans_carrier ON allocation_plans(carrier_id);
CREATE INDEX idx_allocation_plans_product ON allocation_plans(product_id);
CREATE INDEX idx_allocation_plans_applied_date ON allocation_plans(applied_date);

CREATE INDEX idx_allocation_plan_details_account ON allocation_plan_details(account_id);
CREATE INDEX idx_allocation_plan_details_plan ON allocation_plan_details(plan_id);
CREATE INDEX idx_allocation_plan_details_date ON allocation_plan_details(fecha_programada);
CREATE INDEX idx_allocation_plan_details_origin ON allocation_plan_details(origin_node_id);
CREATE INDEX idx_allocation_plan_details_destination ON allocation_plan_details(destination_node_id);
CREATE INDEX idx_allocation_plan_details_status ON allocation_plan_details(status);

-- Triggers for updated_at
CREATE TRIGGER update_generated_allocation_plans_updated_at
  BEFORE UPDATE ON generated_allocation_plans
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_generated_allocation_plan_details_updated_at
  BEFORE UPDATE ON generated_allocation_plan_details
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_allocation_plans_updated_at
  BEFORE UPDATE ON allocation_plans
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_allocation_plan_details_updated_at
  BEFORE UPDATE ON allocation_plan_details
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Triggers for account_id assignment
CREATE TRIGGER set_generated_allocation_plans_account_id
  BEFORE INSERT ON generated_allocation_plans
  FOR EACH ROW EXECUTE FUNCTION set_account_id();

CREATE TRIGGER set_generated_allocation_plan_details_account_id
  BEFORE INSERT ON generated_allocation_plan_details
  FOR EACH ROW EXECUTE FUNCTION set_account_id();

CREATE TRIGGER set_allocation_plans_account_id
  BEFORE INSERT ON allocation_plans
  FOR EACH ROW EXECUTE FUNCTION set_account_id();

CREATE TRIGGER set_allocation_plan_details_account_id
  BEFORE INSERT ON allocation_plan_details
  FOR EACH ROW EXECUTE FUNCTION set_account_id();

-- RLS Policies
ALTER TABLE generated_allocation_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE generated_allocation_plan_details ENABLE ROW LEVEL SECURITY;
ALTER TABLE allocation_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE allocation_plan_details ENABLE ROW LEVEL SECURITY;

-- Generated allocation plans policies
CREATE POLICY generated_allocation_plans_select ON generated_allocation_plans
  FOR SELECT USING (account_id = public.current_user_account_id());

CREATE POLICY generated_allocation_plans_insert ON generated_allocation_plans
  FOR INSERT WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY generated_allocation_plans_update ON generated_allocation_plans
  FOR UPDATE USING (account_id = public.current_user_account_id());

CREATE POLICY generated_allocation_plans_delete ON generated_allocation_plans
  FOR DELETE USING (account_id = public.current_user_account_id());

-- Generated allocation plan details policies
CREATE POLICY generated_allocation_plan_details_select ON generated_allocation_plan_details
  FOR SELECT USING (account_id = public.current_user_account_id());

CREATE POLICY generated_allocation_plan_details_insert ON generated_allocation_plan_details
  FOR INSERT WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY generated_allocation_plan_details_update ON generated_allocation_plan_details
  FOR UPDATE USING (account_id = public.current_user_account_id());

CREATE POLICY generated_allocation_plan_details_delete ON generated_allocation_plan_details
  FOR DELETE USING (account_id = public.current_user_account_id());

-- Allocation plans policies
CREATE POLICY allocation_plans_select ON allocation_plans
  FOR SELECT USING (account_id = public.current_user_account_id());

CREATE POLICY allocation_plans_insert ON allocation_plans
  FOR INSERT WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY allocation_plans_update ON allocation_plans
  FOR UPDATE USING (account_id = public.current_user_account_id());

CREATE POLICY allocation_plans_delete ON allocation_plans
  FOR DELETE USING (account_id = public.current_user_account_id());

-- Allocation plan details policies
CREATE POLICY allocation_plan_details_select ON allocation_plan_details
  FOR SELECT USING (account_id = public.current_user_account_id());

CREATE POLICY allocation_plan_details_insert ON allocation_plan_details
  FOR INSERT WITH CHECK (account_id = public.current_user_account_id());

CREATE POLICY allocation_plan_details_update ON allocation_plan_details
  FOR UPDATE USING (account_id = public.current_user_account_id());

CREATE POLICY allocation_plan_details_delete ON allocation_plan_details
  FOR DELETE USING (account_id = public.current_user_account_id());

SELECT 'Allocation plans module created successfully' as status;
