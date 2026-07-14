-- ============================================================
-- REPAIR de prod — reconciliar schema_migrations con el baseline squasheado
-- ============================================================
-- ⚠️  ESTO ESCRIBE EN PRODUCCIÓN (onems-dev / sehbnpgzqljrsqimwyuz).
--     NO ejecutar sin confirmación explícita del usuario.
--     NO modifica el esquema ni los datos de la app: SOLO la tabla interna de
--     bookkeeping `supabase_migrations.schema_migrations`.
--
-- Contexto (2026-07-14): el repo pasó de 130 migraciones históricas (archivadas en
-- supabase/migrations_archive_pre_baseline/) a UNA baseline:
--   supabase/migrations/00000000000000_baseline_prod_schema.sql
-- Prod tenía 18 versiones registradas (20260611133907 .. 20260710075033), todas ya
-- incluidas en el baseline. Este script deja SOLO el baseline registrado, para que
-- un futuro `supabase db push` vea repo == prod y no intente re-aplicar nada.
--
-- Respaldo: se guardan las 18 filas en schema_migrations_backup_20260714 (dentro de
-- la BD) y también en supabase/tests/_prod_schema_migrations_backup.json (repo).
-- Es transaccional: si algo falla, ROLLBACK automático.
-- ============================================================
BEGIN;

-- 1. Respaldo dentro de la BD (idempotente por fecha)
CREATE TABLE IF NOT EXISTS supabase_migrations.schema_migrations_backup_20260714 AS
  SELECT * FROM supabase_migrations.schema_migrations;

-- 2. Limpiar el registro actual (18 filas, ya cubiertas por el baseline)
DELETE FROM supabase_migrations.schema_migrations;

-- 3. Sembrar el baseline como "ya aplicado"
INSERT INTO supabase_migrations.schema_migrations(version, name)
  VALUES ('00000000000000', 'baseline_prod_schema');

-- 4. Verificación en la misma transacción (debe devolver 1 fila)
SELECT version, name FROM supabase_migrations.schema_migrations;

COMMIT;
