-- ============================================
-- TEMPLATE PARA NUEVAS TABLAS CON RLS
-- ============================================
-- Copiar y adaptar este template para cada nueva tabla futura

/*
-- EJEMPLO DE USO (no ejecutar, solo referencia):

-- 1. CREAR TABLA
CREATE TABLE nombre_tabla (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  -- otros campos aquí
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- 2. CREAR ÍNDICE
CREATE INDEX nombre_tabla_account_id_idx ON nombre_tabla(account_id);

-- 3. HABILITAR RLS
ALTER TABLE nombre_tabla ENABLE ROW LEVEL SECURITY;

-- 4. POLÍTICAS RLS ESTÁNDAR (copiar exactamente estas 4)

-- SELECT: Lectura
CREATE POLICY "Users can view their account data"
  ON nombre_tabla FOR SELECT
  USING (
    auth.is_superadmin() OR 
    account_id = auth.user_account_id()
  );

-- INSERT: Creación
CREATE POLICY "Users can insert into their account"
  ON nombre_tabla FOR INSERT
  WITH CHECK (
    auth.is_superadmin() OR 
    account_id = auth.user_account_id()
  );

-- UPDATE: Actualización
CREATE POLICY "Users can update their account data"
  ON nombre_tabla FOR UPDATE
  USING (
    auth.is_superadmin() OR 
    account_id = auth.user_account_id()
  )
  WITH CHECK (
    auth.is_superadmin() OR 
    account_id = auth.user_account_id()
  );

-- DELETE: Eliminación
CREATE POLICY "Users can delete their account data"
  ON nombre_tabla FOR DELETE
  USING (
    auth.is_superadmin() OR 
    account_id = auth.user_account_id()
  );

-- 5. TRIGGERS DE SEGURIDAD

-- Auto-asignar account_id
CREATE TRIGGER set_nombre_tabla_account_id
  BEFORE INSERT ON nombre_tabla
  FOR EACH ROW
  EXECUTE FUNCTION set_account_id();

-- Prevenir cambio de account_id
CREATE TRIGGER prevent_nombre_tabla_account_change
  BEFORE UPDATE ON nombre_tabla
  FOR EACH ROW
  EXECUTE FUNCTION prevent_account_id_change();

-- Actualizar updated_at
CREATE TRIGGER update_nombre_tabla_updated_at
  BEFORE UPDATE ON nombre_tabla
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at();
*/

-- ============================================
-- SCRIPT DE TESTING DE SEGURIDAD
-- ============================================
-- Ejecutar estos tests después de crear cada tabla

/*
-- Conectarse como usuario normal (NO superadmin)

-- Test 1: Ver solo datos de mi cuenta
SELECT * FROM nombre_tabla; 
-- Resultado esperado: Solo registros de tu cuenta

-- Test 2: Intentar insertar con account_id de otra cuenta (DEBE FALLAR)
INSERT INTO nombre_tabla (campo, account_id) 
VALUES ('Test', '00000000-0000-0000-0000-000000000000');
-- Resultado esperado: ERROR de política RLS

-- Test 3: Insertar sin especificar account_id (DEBE ASIGNAR AUTOMÁTICAMENTE)
INSERT INTO nombre_tabla (campo) VALUES ('Test OK');
SELECT * FROM nombre_tabla WHERE campo = 'Test OK';
-- Resultado esperado: Registro creado con tu account_id

-- Test 4: Cambiar account_id (DEBE FALLAR)
UPDATE nombre_tabla SET account_id = '00000000-0000-0000-0000-000000000000' 
WHERE id = (SELECT id FROM nombre_tabla LIMIT 1);
-- Resultado esperado: ERROR 'account_id cannot be changed'

-- Test 5: Como superadmin ver todo
-- Conectarse como superadmin
SELECT * FROM nombre_tabla;
-- Resultado esperado: Ver registros de TODAS las cuentas
*/
