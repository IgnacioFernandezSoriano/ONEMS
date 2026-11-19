-- Plantilla de roles: Account Manager pasa a Edit en 'users' (antes View). Decisión de Ignacio, 2026-11-18.
-- Spec: docs/superpowers/specs/2026-11-18-roles-derechos-cuenta-design.md (tabla de la plantilla).
--
-- 1. access_template: account_manager / users -> edit.
-- 2. account_access: solo las cuentas que siguen con el valor de la plantilla (view) pasan a edit; si una cuenta
--    lo cambió a mano (fila borrada o ya edit), no se toca.
-- 3. Una fila de account_access_log por cuenta afectada (kind 'template_update', changed_by NULL = sistema).
-- Se aplica sola y antes de 20261119100200 (fase 3).

SET LOCAL lock_timeout = '5s';

UPDATE public.access_template
   SET level = 'edit'
 WHERE role = 'account_manager' AND option = 'users';

WITH changed AS (
  UPDATE public.account_access
     SET level = 'edit'
   WHERE role = 'account_manager' AND option = 'users' AND level = 'view'
  RETURNING account_id
)
INSERT INTO public.account_access_log (account_id, changed_by, kind, detail)
SELECT c.account_id, NULL, 'template_update',
       jsonb_build_object('role', 'account_manager', 'option', 'users', 'before', 'view', 'after', 'edit')
  FROM changed c;
