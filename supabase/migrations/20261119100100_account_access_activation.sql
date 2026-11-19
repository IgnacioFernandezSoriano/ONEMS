-- Roles y derechos por cuenta (fase 1): asignación inicial de roles a los usuarios existentes.
-- Spec: docs/superpowers/specs/2026-11-18-roles-derechos-cuenta-design.md
--
-- Para cada perfil no superadmin con cuenta:
--   * recibe cada rol cuyo contacto accounts.email_<rol> coincide con su correo (lower/trim);
--     puede ser más de uno. Contactos nulos o vacíos se ignoran.
--   * si no coincide ninguno y profiles.role = 'admin' -> account_manager provisional.
--   * profiles.role = 'user' sin coincidencia -> nada.
-- Idempotente (ON CONFLICT DO NOTHING); el log solo recoge lo insertado en esta ejecución.
-- Vista previa de solo lectura: supabase/tests/adhoc/account_access_activation_preview.sql
WITH matches AS (
  SELECT p.account_id, p.id AS user_id, c.role, false AS provisional
    FROM public.profiles p
    JOIN public.accounts a ON a.id = p.account_id
   CROSS JOIN LATERAL (VALUES
     ('account_manager',         a.email_account_manager),
     ('panelist_manager',        a.email_panelist_manager),
     ('materials_supplier',      a.email_materials_supplier),
     ('do_coordinator',          a.email_do_coordinator),
     ('upu_account_manager',     a.email_upu_account_manager),
     ('allocation_plan_manager', a.email_allocation_plan_manager)) AS c(role, email)
   WHERE p.role IS DISTINCT FROM 'superadmin'
     AND nullif(trim(c.email), '') IS NOT NULL
     AND lower(trim(c.email)) = lower(trim(p.email))
), fallback AS (
  SELECT p.account_id, p.id AS user_id, 'account_manager'::text AS role, true AS provisional
    FROM public.profiles p
   WHERE p.role = 'admin' AND p.account_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM matches m WHERE m.user_id = p.id)
), ins AS (
  INSERT INTO public.account_user_role (account_id, user_id, role, provisional)
  SELECT account_id, user_id, role, provisional FROM matches
  UNION ALL
  SELECT account_id, user_id, role, provisional FROM fallback
  ON CONFLICT (account_id, user_id, role) DO NOTHING
  RETURNING account_id, user_id, role, provisional
)
INSERT INTO public.account_access_log (account_id, changed_by, kind, detail)
SELECT account_id, NULL, 'activation',
       jsonb_build_object('assignments',
         jsonb_agg(jsonb_build_object('user_id', user_id, 'role', role, 'provisional', provisional)
                   ORDER BY user_id, role))
  FROM ins
 GROUP BY account_id;
