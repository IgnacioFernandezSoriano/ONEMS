-- ============================================================
-- Analisis de casos para TODAS las cuentas — 2026-11-11
-- ============================================================
-- Decision de Ignacio (2026-11-11): el analisis de casos es una funcion del software para cualquier cuenta,
-- tambien las que se abran despues. Lo que se controla por cuenta es quien se da de alta en el bot de managers
-- (los correos de los roles en la ficha de la cuenta) y el tope de gasto mensual por cuenta (en el agente).
--   1. case_analysis_allowed: cualquier cuenta ACTIVA (antes solo DEMO2). Lo usan el boton de ONEMS
--      (case_analysis_enabled / _for_account / request_case_analysis) y el bot de managers (ops_case._actor,
--      ops_case_account_enabled). El aislamiento entre cuentas no cambia: cada usuario solo ve su cuenta.
--   2. ops_manager_accounts(p_token, p_exclude): nombres de las cuentas activas (fuera p_exclude), para los
--      botones de pais del superadmin en el bot de managers. Token owner o manager.
-- Forward-only.
-- ============================================================

CREATE OR REPLACE FUNCTION public.case_analysis_allowed(p_account uuid)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_account IS NULL THEN RETURN false; END IF;
  RETURN EXISTS (SELECT 1 FROM public.accounts a WHERE a.id = p_account AND a.status = 'active');
END $$;
REVOKE ALL ON FUNCTION public.case_analysis_allowed(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.ops_manager_accounts(p_token text, p_exclude text[] DEFAULT '{}')
RETURNS text[] LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM ops_test._caller(p_token);   -- owner o manager
  RETURN ARRAY(SELECT a.name FROM public.accounts a
                WHERE a.status = 'active' AND a.name IS NOT NULL
                  AND NOT (a.name = ANY (COALESCE(p_exclude, '{}')))
                ORDER BY a.name);
END $$;
REVOKE ALL ON FUNCTION public.ops_manager_accounts(text, text[]) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_manager_accounts(text, text[]) TO anon;
