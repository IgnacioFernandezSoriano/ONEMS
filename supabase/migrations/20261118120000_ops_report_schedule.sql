-- Calendario de emisión del informe de operación ("ONE operations report") por cuenta.
--
-- Hasta ahora el agente enviaba el informe L-X-V a todas las cuentas activas salvo las excluidas en su
-- config.yaml. A partir de aquí cada cuenta decide en su ficha:
--   ops_report_frequency  'never' (por defecto) | 'weekly' | 'monthly'
--   ops_report_weekdays   días de la semana para 'weekly' (ISO: 1 = lunes … 7 = domingo)
--   ops_report_month_day  día del mes para 'monthly' (1-31; en meses más cortos, el último día)
-- La hora sigue siendo las 08:00 de Madrid (temporizador del agente).
--
-- Arranque (decisión de Ignacio, 18/11/2026): todas en 'never' salvo KENYA, que sigue L-X-V.
-- Solo añade columnas y amplía la respuesta de ops_report_accounts (el agente antiguo ignora los campos
-- nuevos). Las políticas RLS de accounts cubren las columnas nuevas.

ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS ops_report_frequency text NOT NULL DEFAULT 'never',
  ADD COLUMN IF NOT EXISTS ops_report_weekdays  smallint[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS ops_report_month_day smallint NULL;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.accounts'::regclass
                   AND conname = 'accounts_ops_report_schedule_check') THEN
    ALTER TABLE public.accounts ADD CONSTRAINT accounts_ops_report_schedule_check CHECK (
          ops_report_frequency IN ('never', 'weekly', 'monthly')
      AND ops_report_weekdays <@ ARRAY[1,2,3,4,5,6,7]::smallint[]
      AND (ops_report_month_day IS NULL OR ops_report_month_day BETWEEN 1 AND 31)
      AND (ops_report_frequency <> 'weekly'  OR cardinality(ops_report_weekdays) > 0)
      AND (ops_report_frequency <> 'monthly' OR ops_report_month_day IS NOT NULL));
  END IF;
END $$;

COMMENT ON COLUMN public.accounts.ops_report_frequency IS 'Informe de operación: never | weekly | monthly. Lo lee el agente de operaciones cada día a las 08:00 Madrid.';
COMMENT ON COLUMN public.accounts.ops_report_weekdays  IS 'Informe semanal: días ISO (1 = lunes … 7 = domingo).';
COMMENT ON COLUMN public.accounts.ops_report_month_day IS 'Informe mensual: día del mes (1-31; si el mes es más corto, sale el último día).';

-- Arranque: KENYA sigue como hasta ahora (lunes, miércoles y viernes).
UPDATE public.accounts
   SET ops_report_frequency = 'weekly', ops_report_weekdays = ARRAY[1,3,5]::smallint[]
 WHERE name = 'KENYA' AND ops_report_frequency = 'never';

-- El agente recibe además el calendario de cada cuenta.
CREATE OR REPLACE FUNCTION public.ops_report_accounts(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM ops_test._check(p_token);
  RETURN (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                   'name', a.name, 'language', a.default_language,
                   'frequency', a.ops_report_frequency, 'weekdays', to_jsonb(a.ops_report_weekdays),
                   'month_day', a.ops_report_month_day) ORDER BY a.name), '[]'::jsonb)
            FROM public.accounts a WHERE a.status = 'active');
END $$;

REVOKE ALL ON FUNCTION public.ops_report_accounts(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_report_accounts(text) TO anon;

-- Los datos del informe incluyen también el Allocation Plan Manager (va en «Para»).
-- Se cambia solo esa línea sobre la definición viva de ops_report._data (20261117160000_ops_report_gps),
-- para no deshacer nada; si la línea no está exactamente una vez, la migración falla y no toca nada.
DO $$
DECLARE
  v_old text := '''upu_account_manager'', a.email_upu_account_manager))';
  v_new text := '''upu_account_manager'', a.email_upu_account_manager, ''allocation_plan_manager'', a.email_allocation_plan_manager))';
  v_def text := pg_get_functiondef('ops_report._data(uuid,date,date)'::regprocedure);
BEGIN
  IF position(v_new IN v_def) > 0 THEN RETURN; END IF;
  IF (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION 'ops_report._data: no encuentro la línea de contactos exactamente una vez';
  END IF;
  EXECUTE replace(v_def, v_old, v_new);
END $$;
