-- ============================================
-- PERMITIR TRANSFERENCIA DE USUARIOS ENTRE CUENTAS
-- ============================================
-- Fecha: 2026-01-16
-- Descripción: Permite que superadmin pueda mover usuarios entre cuentas
-- Elimina trigger que bloqueaba cambios de account_id
-- ============================================

-- Eliminar trigger que previene cambios de account_id
DROP TRIGGER IF EXISTS prevent_profiles_account_change ON profiles;

-- Crear nueva función que solo permite cambios de account_id a superadmin
CREATE OR REPLACE FUNCTION prevent_account_id_change_non_superadmin()
RETURNS TRIGGER AS $$
BEGIN
  -- Si el account_id cambió
  IF OLD.account_id IS DISTINCT FROM NEW.account_id THEN
    -- Solo superadmin puede cambiar account_id
    IF public.current_user_role() != 'superadmin' THEN
      RAISE EXCEPTION 'Only superadmin can transfer users between accounts';
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Aplicar nuevo trigger
CREATE TRIGGER prevent_profiles_account_change_non_superadmin
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change_non_superadmin();

-- Comentario
COMMENT ON FUNCTION prevent_account_id_change_non_superadmin() IS 
  'Permite a superadmin transferir usuarios entre cuentas, bloquea cambios para otros roles';
