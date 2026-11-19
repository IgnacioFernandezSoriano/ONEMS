-- Carrier Link fase 0, tarea 1: campos nuevos en los maestros y opciones de acceso.
-- Spec: docs/superpowers/specs/2026-11-19-carrier-link-design.md §3.2 y §7
--
-- Los "puntos de lectura" de un transportista son filas de readers con capture_source = 'carrier_scan'.
-- Aditiva: no cambia nada visible para los usuarios actuales (todo lo existente queda como 'rfid' / 'panelist').
-- No toca allocation_plans, allocation_plan_details, transfer_to_one_db ni el ETL RFID.

-- ---------------------------------------------------------------- readers
ALTER TABLE public.readers
  ADD COLUMN capture_source    text NOT NULL DEFAULT 'rfid',
  ADD COLUMN carrier_id        uuid REFERENCES public.carriers(id),
  ADD COLUMN carrier_place_ref text,
  ADD COLUMN carrier_mode_ref  text,
  ADD COLUMN e2e_role          text NOT NULL DEFAULT 'none';

ALTER TABLE public.readers
  ADD CONSTRAINT readers_capture_source_check CHECK (capture_source IN ('rfid','carrier_scan')),
  ADD CONSTRAINT readers_e2e_role_check CHECK (e2e_role IN ('origin','destination','both','none')),
  ADD CONSTRAINT readers_cl_mode_not_blank CHECK (carrier_mode_ref IS NULL OR btrim(carrier_mode_ref) <> ''),
  ADD CONSTRAINT readers_cl_shape CHECK (
    (capture_source = 'rfid'
       AND carrier_id IS NULL AND carrier_place_ref IS NULL AND carrier_mode_ref IS NULL AND e2e_role = 'none')
    OR
    (capture_source = 'carrier_scan'
       AND carrier_id IS NOT NULL AND carrier_place_ref IS NOT NULL AND type IN ('Entry','Exit'))
  );

CREATE UNIQUE INDEX readers_cl_point_key
  ON public.readers (account_id, carrier_id, carrier_place_ref, COALESCE(carrier_mode_ref, ''))
  WHERE capture_source = 'carrier_scan' AND deleted_at IS NULL;

-- SECURITY DEFINER (decisión): lee accounts y carriers sin depender de la RLS del que inserta; es seguro porque
-- readers_cl_check_city (se ejecuta antes, orden alfabético) ya exige que el carrier sea de la misma cuenta,
-- así que nunca se vuelca el código de un carrier ajeno.
-- reader_id automático (siempre, en INSERT y UPDATE) para puntos de transportista: CL:<slug cuenta>:<código carrier>:<lugar>[:<modo>].
-- Lleva el slug de la cuenta, así es único aunque uq_readers_reader_id_active sea global.
CREATE OR REPLACE FUNCTION public.readers_cl_defaults()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  -- Modo en blanco = sin modo (evita un ':' final en el reader_id).
  NEW.carrier_mode_ref := NULLIF(btrim(NEW.carrier_mode_ref), '');
  IF NEW.capture_source = 'carrier_scan' THEN
    -- Siempre generado (se ignora el valor del que escribe): el espacio CL: es solo de los puntos de transportista.
    NEW.reader_id := 'CL:' || (SELECT a.slug FROM public.accounts a WHERE a.id = NEW.account_id)
                  || ':' || (SELECT c.code FROM public.carriers c WHERE c.id = NEW.carrier_id)
                  || ':' || NEW.carrier_place_ref
                  || COALESCE(':' || NEW.carrier_mode_ref, '');
  ELSIF NEW.reader_id LIKE 'CL:%' THEN
    RAISE EXCEPTION 'reader_id prefix CL: is reserved for carrier_scan points' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- El carrier debe ser de la misma cuenta; un punto con rol E2E (origen/destino) necesita un centro postal con ciudad.
CREATE OR REPLACE FUNCTION public.readers_cl_check_city()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.carrier_id IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM public.carriers c WHERE c.id = NEW.carrier_id AND c.account_id = NEW.account_id) THEN
    RAISE EXCEPTION 'carrier_id must belong to the same account' USING ERRCODE = 'check_violation';
  END IF;
  IF NEW.e2e_role <> 'none' THEN
    IF NEW.postal_center_id IS NULL
       OR NOT EXISTS (SELECT 1 FROM public.postal_centers pc
                       WHERE pc.id = NEW.postal_center_id AND pc.city_id IS NOT NULL
                          AND pc.account_id = NEW.account_id) THEN
      RAISE EXCEPTION 'e2e_role % requires a postal center with a city', NEW.e2e_role
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;

REVOKE ALL ON FUNCTION public.readers_cl_defaults() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.readers_cl_check_city() FROM PUBLIC, anon;

CREATE TRIGGER readers_cl_defaults
  BEFORE INSERT OR UPDATE ON public.readers
  FOR EACH ROW EXECUTE FUNCTION public.readers_cl_defaults();
CREATE TRIGGER readers_cl_check_city
  BEFORE INSERT OR UPDATE ON public.readers
  FOR EACH ROW EXECUTE FUNCTION public.readers_cl_check_city();

-- ---------------------------------------------------------------- delivery_standards
ALTER TABLE public.delivery_standards
  ADD COLUMN cl_first_mile_time numeric NOT NULL DEFAULT 0 CHECK (cl_first_mile_time >= 0),
  ADD COLUMN cl_last_mile_time  numeric NOT NULL DEFAULT 0 CHECK (cl_last_mile_time >= 0);

-- ---------------------------------------------------------------- one_db
ALTER TABLE public.one_db
  ADD COLUMN source                  text NOT NULL DEFAULT 'panelist' CHECK (source IN ('panelist','carrier')),
  ADD COLUMN cl_sample_id            uuid UNIQUE,
  ADD COLUMN carrier_id              uuid,
  ADD COLUMN equivalence_hours       numeric,
  ADD COLUMN equivalence_days        integer,
  ADD COLUMN measured_total_hours    numeric,
  ADD COLUMN measured_total_days     integer,
  ADD COLUMN measured_business_hours numeric,
  ADD COLUMN measured_business_days  integer;

CREATE INDEX one_db_account_source_idx ON public.one_db (account_id, source);

-- ---------------------------------------------------------------- opciones de acceso (spec §7)
INSERT INTO public.access_option (key, menu_group, sort) VALUES
  ('cl_plans',          'carrier_link', 152),
  ('cl_samples',        'carrier_link', 153),
  ('cl_reading_points', 'carrier_link', 154),
  ('cl_connectors',     'carrier_link', 155),
  ('cl_monitor',        'carrier_link', 156);

-- Columnas: AM, UPU, APM, DO (E = edit, V = view, '' = sin acceso). El resto de roles y no_role: nada.
WITH m(option, am, upu, apm, dco) AS (VALUES
  ('cl_plans',          'E','E','E','V'),
  ('cl_samples',        'V','V','V','V'),
  ('cl_reading_points', 'E','E','V','E'),
  ('cl_connectors',     'E','E','', ''),
  ('cl_monitor',        'E','E','V','V')
), cells(role, option, c) AS (
  SELECT 'account_manager', option, am FROM m UNION ALL
  SELECT 'upu_account_manager', option, upu FROM m UNION ALL
  SELECT 'allocation_plan_manager', option, apm FROM m UNION ALL
  SELECT 'do_coordinator', option, dco FROM m
)
INSERT INTO public.access_template (role, option, level)
SELECT role, option, CASE c WHEN 'E' THEN 'edit' ELSE 'view' END
  FROM cells WHERE c <> '';

-- Cuentas existentes: copia de las filas nuevas de la plantilla (las cuentas nuevas las copia el trigger
-- accounts_copy_access_template).
INSERT INTO public.account_access (account_id, role, option, level)
SELECT a.id, t.role, t.option, t.level
  FROM public.accounts a CROSS JOIN public.access_template t
 WHERE t.role <> 'no_role' AND t.option LIKE 'cl\_%'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------- políticas de escritura (readers)
-- postal_centers NO se toca (sigue exactamente como en 20261119100200). readers: mismo generador y formato que
-- 20261119100200, pero cl_reading_points solo alcanza filas carrier_scan (en USING y en WITH CHECK, así no se
-- convierte un lector RFID en punto de transportista ni al revés).
DO $$
DECLARE v_expr text; v_rfid text := '''postal_centers'', ''readers_management''';
BEGIN
  v_expr := format('(SELECT public.is_superadmin()) OR (account_id = (SELECT public.current_user_account_id()) '
                   'AND ((SELECT public.has_any_access(public.current_user_account_id(), ''edit'', %s)) '
                   'OR (capture_source = ''carrier_scan'' AND (SELECT public.has_any_access(public.current_user_account_id(), ''edit'', ''cl_reading_points'')))))', v_rfid);
  DROP POLICY readers_insert_edit ON public.readers;
  DROP POLICY readers_update_edit ON public.readers;
  DROP POLICY readers_delete_edit ON public.readers;
  EXECUTE format('CREATE POLICY readers_insert_edit ON public.readers FOR INSERT TO authenticated WITH CHECK (%s)', v_expr);
  EXECUTE format('CREATE POLICY readers_update_edit ON public.readers FOR UPDATE TO authenticated USING (%s) WITH CHECK (%s)', v_expr, v_expr);
  EXECUTE format('CREATE POLICY readers_delete_edit ON public.readers FOR DELETE TO authenticated USING (%s)', v_expr);
END $$;
