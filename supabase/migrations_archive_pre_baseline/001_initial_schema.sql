-- ============================================
-- TABLAS BASE
-- ============================================

-- Tabla de Cuentas
CREATE TABLE accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Tabla de Perfiles (extiende auth.users)
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL,
  full_name TEXT,
  role TEXT NOT NULL CHECK (role IN ('superadmin', 'admin', 'user')),
  account_id UUID REFERENCES accounts(id) ON DELETE CASCADE,
  status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  -- Constraint: superadmin sin account_id, otros roles CON account_id
  CONSTRAINT check_account_role CHECK (
    (role = 'superadmin' AND account_id IS NULL) OR
    (role != 'superadmin' AND account_id IS NOT NULL)
  )
);

-- Índices
CREATE INDEX profiles_account_id_idx ON profiles(account_id);
CREATE INDEX profiles_email_idx ON profiles(email);
CREATE INDEX accounts_slug_idx ON accounts(slug);

-- ============================================
-- FUNCIONES HELPER PARA RLS
-- ============================================

-- Obtiene el account_id del usuario actual
CREATE OR REPLACE FUNCTION auth.user_account_id()
RETURNS UUID AS $$
  SELECT account_id FROM profiles WHERE id = auth.uid()
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- Verifica si el usuario es superadmin
CREATE OR REPLACE FUNCTION auth.is_superadmin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles 
    WHERE id = auth.uid() AND role = 'superadmin'
  )
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================
-- TRIGGERS DE SEGURIDAD
-- ============================================

-- Previene cambios en account_id
CREATE OR REPLACE FUNCTION prevent_account_id_change()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.account_id IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'account_id cannot be changed after creation';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Auto-asigna account_id en INSERT
CREATE OR REPLACE FUNCTION set_account_id()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.account_id IS NULL THEN
    NEW.account_id := auth.user_account_id();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Actualiza updated_at automáticamente
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ============================================
-- RLS PARA ACCOUNTS
-- ============================================

ALTER TABLE accounts ENABLE ROW LEVEL SECURITY;

-- Superadmin gestiona todas las cuentas
CREATE POLICY "Superadmin manages all accounts"
  ON accounts FOR ALL
  USING (auth.is_superadmin())
  WITH CHECK (auth.is_superadmin());

-- Usuarios ven su propia cuenta
CREATE POLICY "Users view their own account"
  ON accounts FOR SELECT
  USING (id = auth.user_account_id());

-- ============================================
-- RLS PARA PROFILES
-- ============================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Superadmin gestiona todos los perfiles
CREATE POLICY "Superadmin manages all profiles"
  ON profiles FOR ALL
  USING (auth.is_superadmin())
  WITH CHECK (auth.is_superadmin());

-- Admins gestionan usuarios de su cuenta
CREATE POLICY "Admins manage their account users"
  ON profiles FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() 
      AND p.role = 'admin'
      AND p.account_id = profiles.account_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles p
      WHERE p.id = auth.uid() 
      AND p.role = 'admin'
      AND p.account_id = profiles.account_id
    )
  );

-- Usuarios ven su propio perfil
CREATE POLICY "Users view their own profile"
  ON profiles FOR SELECT
  USING (id = auth.uid());

-- Usuarios actualizan su propio perfil (sin cambiar rol)
CREATE POLICY "Users update their own profile"
  ON profiles FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (
    id = auth.uid() AND
    role = (SELECT role FROM profiles WHERE id = auth.uid())
  );

-- ============================================
-- TRIGGERS EN TABLAS
-- ============================================

-- Accounts
CREATE TRIGGER update_accounts_updated_at
  BEFORE UPDATE ON accounts
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

-- Profiles
CREATE TRIGGER update_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER prevent_profiles_account_change
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();
