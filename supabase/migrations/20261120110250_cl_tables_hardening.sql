-- Carrier Link fase 0, tarea 3 (endurecimiento, forward-only sobre 20261120110200_cl_tables.sql):
-- 1. cl_alerts: el usuario solo cambia status; quien reconoce y cuando lo fija un trigger (no se puede falsear).
-- 2. cl_check_same_account: el disparador BEFORE corre antes del WITH CHECK de RLS, asi que sin guarda era un oraculo
--    de existencia entre cuentas. Ahora un usuario que escribe en una cuenta que no es la suya recibe 42501 antes de
--    cualquier consulta.

-- ---------------------------------------------------------------- 1. cl_alerts
REVOKE UPDATE ON public.cl_alerts FROM authenticated;
GRANT UPDATE (status) ON public.cl_alerts TO authenticated;

CREATE OR REPLACE FUNCTION public.cl_alerts_set_ack()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NEW.status = 'open' THEN
      NEW.acknowledged_by := NULL;
      NEW.acknowledged_at := NULL;
    ELSE
      NEW.acknowledged_by := auth.uid();
      NEW.acknowledged_at := now();
    END IF;
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cl_alerts_set_ack() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS cl_alerts_set_ack ON public.cl_alerts;
CREATE TRIGGER cl_alerts_set_ack BEFORE UPDATE ON public.cl_alerts
  FOR EACH ROW EXECUTE FUNCTION public.cl_alerts_set_ack();

-- ---------------------------------------------------------------- 2. guarda de cuenta en cl_check_same_account
-- La funcion es SECURITY DEFINER (current_user = dueno), por eso el rol de quien llama se lee de current_setting('role')
-- (lo fija PostgREST con SET LOCAL ROLE y se conserva dentro de funciones definer). Pasan sin comprobar la cuenta:
-- superadmin, la cuenta activa del usuario, service_role/postgres/supabase_admin, sesion sin rol (cron, n8n) y auth.uid() NULL.
CREATE OR REPLACE FUNCTION public.cl_check_same_account()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  i int := 0;
  v_id text;
  v_ok boolean;
BEGIN
  IF NOT (public.is_superadmin()
          OR NEW.account_id = public.current_user_account_id()
          OR current_setting('role') IN ('none', 'service_role', 'postgres', 'supabase_admin')
          OR auth.uid() IS NULL) THEN
    RAISE EXCEPTION 'Operacion no permitida' USING ERRCODE = '42501';
  END IF;

  WHILE i + 1 < TG_NARGS LOOP
    v_id := to_jsonb(NEW) ->> TG_ARGV[i];
    IF v_id IS NOT NULL THEN
      EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I t WHERE t.id = $1::uuid AND t.account_id = $2)', TG_ARGV[i + 1])
        INTO v_ok USING v_id, NEW.account_id;
      IF NOT v_ok THEN
        RAISE EXCEPTION '% % debe pertenecer a la misma cuenta (%)', TG_TABLE_NAME, TG_ARGV[i], TG_ARGV[i + 1]
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
    i := i + 2;
  END LOOP;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cl_check_same_account() FROM PUBLIC, anon, authenticated;
