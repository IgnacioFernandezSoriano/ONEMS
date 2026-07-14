-- ============================================================
-- 001a — Forward-declaración de helpers RLS en public
-- ============================================================
-- REPRODUCIBILIDAD (2026-07-14): las políticas RLS de 002_network_topology y otras
-- migraciones tempranas referencian public.current_user_account_id() /
-- public.current_user_role(), pero el repo solo las define más tarde
-- (009_allocation_plans, 20260102_fix_rls_recursion_v2). En un replay desde cero
-- (orden lexicográfico, igual que la CLI de Supabase) esas funciones aún no existen
-- y 002 falla con "function public.current_user_account_id() does not exist".
--
-- Prod SÍ tiene estas funciones (se crearon en su momento, en otro orden). Esta
-- migración las declara pronto para que el repo reconstruya la BD. Las migraciones
-- posteriores las redefinen con CREATE OR REPLACE (idempotente, sin efecto).
-- Definición idéntica a la de prod (20260102_fix_rls_recursion_v2).
-- ============================================================

CREATE OR REPLACE FUNCTION public.current_user_account_id()
RETURNS UUID
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT account_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS TEXT
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public
AS $$
  SELECT role FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;
