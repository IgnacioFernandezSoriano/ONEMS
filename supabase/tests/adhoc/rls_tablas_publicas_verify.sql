-- SOLO LECTURA. Verificación en la BD viva tras aplicar 20261118220000_rls_tablas_y_funciones_publicas.sql.
-- Cada consulta devuelve las filas problemáticas: lo esperado es 0 filas, salvo donde se indica.

-- 1. Tablas de la lista sin RLS (esperado: 0 filas).
SELECT c.relname AS tabla_sin_rls
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace
  AND c.relname IN ('api_keys','api_usage_log','demo2_seed_data','journey_segments','journeys','n8n_upu_agent',
                    'n8n_upu_incident','n8n_upu_timeoff','panelist_context','postal_center_carriers','processed_events',
                    'purchase_order_items','purchase_orders','rfid_events_raw')
  AND NOT c.relrowsecurity;

-- 2. Cualquier tabla de public sin RLS (informativo: lo ideal es 0 filas).
SELECT c.relname AS tabla_public_sin_rls, c.relowner::regrole AS dueno
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace AND c.relkind IN ('r','p') AND NOT c.relrowsecurity
ORDER BY 1;

-- 3. Privilegios de anon / authenticated en las 14 tablas (esperado: anon ninguno; authenticated ninguno en las
--    6 de backend; authenticated con SELECT/INSERT/UPDATE/DELETE en las otras 8).
SELECT t AS tabla,
       has_table_privilege('anon', 'public.'||t, 'SELECT') AS anon_sel,
       has_table_privilege('anon', 'public.'||t, 'INSERT,UPDATE,DELETE,TRUNCATE') AS anon_write,
       has_table_privilege('authenticated', 'public.'||t, 'SELECT') AS auth_sel,
       has_table_privilege('authenticated', 'public.'||t, 'INSERT,UPDATE,DELETE') AS auth_write,
       has_table_privilege('service_role', 'public.'||t, 'SELECT,INSERT,UPDATE,DELETE') AS service_role_ok
FROM unnest(ARRAY['api_keys','api_usage_log','demo2_seed_data','journey_segments','journeys','n8n_upu_agent',
                  'n8n_upu_incident','n8n_upu_timeoff','panelist_context','postal_center_carriers','processed_events',
                  'purchase_order_items','purchase_orders','rfid_events_raw']) t
ORDER BY 1;

-- 4. Políticas actuales de las 14 tablas (revisar a ojo: deben estar las *_superadmin_all nuevas y ninguna TO public
--    en journey_segments/journeys/processed_events/rfid_events_raw).
SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('api_keys','api_usage_log','demo2_seed_data','journey_segments','journeys','n8n_upu_agent',
                    'n8n_upu_incident','n8n_upu_timeoff','panelist_context','postal_center_carriers','processed_events',
                    'purchase_order_items','purchase_orders','rfid_events_raw')
ORDER BY tablename, policyname;

-- 5. Funciones de la lista ejecutables por anon o por PUBLIC (esperado: 0 filas).
SELECT p.oid::regprocedure AS funcion,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE') AS public_exec
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('balance_node_load_matrix','cleanup_processed_rfid_events','generate_delivery_standards',
                    'process_all_accounts_pipeline','process_rfid_pipeline','recalculate_on_time_delivery_on_sla_change',
                    'reconstruct_journeys','reprocess_transfer_errors','resolve_provider_reads','rpc_get_node_load_by_period',
                    'set_account_id','transfer_to_one_db','consolidate_rfid_events',
                    'admin_reset_account_data','admin_reset_account_data_backup','admin_reset_demo2','admin_reset_and_seed_demo2')
  AND (has_function_privilege('anon', p.oid, 'EXECUTE')
       OR EXISTS (SELECT 1 FROM aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
                  WHERE a.grantee = 0 AND a.privilege_type = 'EXECUTE'));

-- 6. Las mismas funciones: service_role y authenticated deben poder (esperado: todo true, salvo admin_reset_*
--    con authenticated=false).
SELECT p.oid::regprocedure AS funcion, p.prosecdef AS security_definer, p.proowner::regrole AS dueno,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec,
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_exec
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('balance_node_load_matrix','cleanup_processed_rfid_events','generate_delivery_standards',
                    'process_all_accounts_pipeline','process_rfid_pipeline','recalculate_on_time_delivery_on_sla_change',
                    'reconstruct_journeys','reprocess_transfer_errors','resolve_provider_reads','rpc_get_node_load_by_period',
                    'set_account_id','transfer_to_one_db','consolidate_rfid_events',
                    'admin_reset_account_data','admin_reset_account_data_backup','admin_reset_demo2','admin_reset_and_seed_demo2')
ORDER BY 1;

-- 7. Dueños de las tablas y de las funciones SECURITY DEFINER que las tocan: deben ser roles que saltan RLS
--    (dueño de la tabla o rolbypassrls). Esperado: dueño postgres en todas.
SELECT c.relname, c.relowner::regrole AS dueno, c.relforcerowsecurity AS force_rls
FROM pg_class c
WHERE c.relnamespace = 'public'::regnamespace
  AND c.relname IN ('api_keys','api_usage_log','demo2_seed_data','journey_segments','journeys','n8n_upu_agent',
                    'n8n_upu_incident','n8n_upu_timeoff','panelist_context','postal_center_carriers','processed_events',
                    'purchase_order_items','purchase_orders','rfid_events_raw')
ORDER BY 1;
SELECT rolname, rolsuper, rolbypassrls FROM pg_roles
WHERE rolname IN ('postgres','service_role','authenticated','anon','supabase_admin','monitoring_reader')
ORDER BY 1;

-- 8. Funciones SECURITY DEFINER cuyo dueño NO es postgres/supabase_admin (podrían dejar de ver filas). Esperado: 0.
SELECT p.oid::regprocedure, p.proowner::regrole
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace AND p.prosecdef
  AND p.proowner::regrole::text NOT IN ('postgres','supabase_admin');

-- 9. Vista v_segment_details: security_invoker y sin privilegios para anon (esperado: reloptions con
--    security_invoker=true; anon_sel=false).
SELECT c.relname, c.reloptions, has_table_privilege('anon', c.oid, 'SELECT') AS anon_sel,
       has_table_privilege('authenticated', c.oid, 'SELECT') AS auth_sel
FROM pg_class c WHERE c.oid = to_regclass('public.v_segment_details');

-- 10. Otras vistas de public que leen las 14 tablas sin security_invoker (por si la BD viva tiene vistas que no
--     están en el repo). Esperado: 0 filas.
SELECT DISTINCT v.relname AS vista, t.relname AS tabla, v.reloptions
FROM pg_depend d
JOIN pg_rewrite r ON r.oid = d.objid
JOIN pg_class v ON v.oid = r.ev_class AND v.relkind IN ('v','m')
JOIN pg_class t ON t.oid = d.refobjid
WHERE t.relnamespace = 'public'::regnamespace
  AND t.relname IN ('api_keys','api_usage_log','demo2_seed_data','journey_segments','journeys','n8n_upu_agent',
                    'n8n_upu_incident','n8n_upu_timeoff','panelist_context','postal_center_carriers','processed_events',
                    'purchase_order_items','purchase_orders','rfid_events_raw')
  AND v.oid <> t.oid
  AND coalesce(array_to_string(v.reloptions, ','), '') NOT LIKE '%security_invoker=true%';

-- 11. Usuario con el que conecta n8n (nodos Postgres): debe ser postgres (dueño de las tablas). Mirar usename de
--     las conexiones con application_name de n8n o desde la IP del servidor de n8n.
SELECT usename, application_name, client_addr, count(*)
FROM pg_stat_activity
WHERE datname = current_database()
GROUP BY 1, 2, 3
ORDER BY 4 DESC;
