-- ============================================
-- FIX: prevent_account_id_change() rompe UPDATE en 13 tablas
-- ============================================
-- Fecha: 2026-07-09
-- Problema:
--   La función public.prevent_account_id_change() está enganchada como
--   trigger BEFORE UPDATE en 14 tablas (profiles, carriers, cities, nodes,
--   regions, materials, products, product_materials, material_catalog,
--   delivery_standards, diagnosis_*, rfid_intermediate_db).
--
--   Una modificación previa añadió `IF NEW.role = 'superadmin'` pensando en
--   `profiles` (única tabla con columna `role`). Pero la función es COMPARTIDA:
--   en las otras 13 tablas `NEW.role` no existe y PL/pgSQL falla en runtime con
--       ERROR 42703: record "new" has no field "role"
--   haciendo que CUALQUIER UPDATE en esas tablas aborte. Síntoma en la app:
--   los formularios de setup (Country Topology, Carriers & Products, Materials,
--   etc.) no persisten cambios al pulsar "Update".
--
-- Solución:
--   Referenciar NEW.role SOLO dentro de una rama `TG_TABLE_NAME = 'profiles'`,
--   de modo que en el resto de tablas nunca se evalúe. Se preserva EXACTAMENTE
--   el comportamiento previo de profiles (superadmin exento del bloqueo de
--   cambio de account_id) y se arregla el crash en las demás tablas.
-- ============================================

CREATE OR REPLACE FUNCTION public.prevent_account_id_change()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  -- Solo la tabla `profiles` tiene columna `role` por fila.
  -- Se accede a NEW.role únicamente dentro de esta rama para que en el resto
  -- de tablas (sin columna role) nunca se evalúe y no falle en runtime.
  IF TG_TABLE_NAME = 'profiles' THEN
    IF NEW.role = 'superadmin' THEN
      RETURN NEW;
    END IF;
  END IF;

  IF OLD.account_id IS DISTINCT FROM NEW.account_id THEN
    RAISE EXCEPTION 'account_id cannot be changed after creation';
  END IF;

  RETURN NEW;
END;
$function$;
