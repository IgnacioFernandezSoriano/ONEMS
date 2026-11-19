-- Vista previa SOLO LECTURA de la migración 20261119100100_account_access_activation.sql.
-- No lee account_user_role: aplica la misma regla sobre profiles y accounts, así que se puede
-- ejecutar en la base compartida antes de aplicar la migración.
-- Una fila por usuario y cuenta, con los roles resultantes y si son provisionales.
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
), result AS (
  SELECT * FROM matches UNION ALL SELECT * FROM fallback
)
SELECT p.email AS user_email, a.name AS account_name,
       string_agg(r.role, ', ' ORDER BY r.role) AS roles,
       bool_or(r.provisional) AS provisional
  FROM result r
  JOIN public.profiles p ON p.id = r.user_id
  JOIN public.accounts a ON a.id = r.account_id
 GROUP BY p.email, a.name
 ORDER BY a.name, p.email;
