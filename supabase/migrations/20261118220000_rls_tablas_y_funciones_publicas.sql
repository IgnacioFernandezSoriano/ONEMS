-- ============================================================================================================
-- SEGURIDAD 18/11/2026: tablas sin RLS abiertas a la clave pública y funciones SECURITY DEFINER sin control
-- ejecutables por anon.
--
-- La clave "anon" va dentro del bundle web: cualquiera que la copie podía leer/escribir/borrar las 14 tablas de
-- abajo (RLS desactivado + privilegios completos a anon) y ejecutar funciones que operan sobre cualquier cuenta.
--
-- Quién sigue funcionando y por qué (verificado en el repo: src/, supabase/functions/, panelist_n8n/workflows):
--   * Web (rol authenticated): cada usuario ve/escribe SOLO su cuenta; el superadmin lee y escribe todas (hace
--     falta: cambia de cuenta en la cabecera, pulsa "Consolidate"/"Assemble" sobre otra cuenta y el reseteo de
--     DEMO2 en useAccountManagement.ts borra journey_segments/processed_events de DEMO2).
--   * Edge functions con SERVICE_ROLE (onedb-api, rfid-provider-poll, consolidate-rfid-events-cron,
--     weekly-aggregation): service_role tiene BYPASSRLS -> sin cambio.
--   * Edge consolidate-rfid-events: clave anon + JWT del usuario -> actúa como authenticated -> igual que la web.
--   * n8n: nodos Postgres / memoria de chat conectan directos como usuario de BD (dueño de las tablas, salta RLS);
--     el nodo Supabase de register-new-panelist usa la credencial service_role -> sin cambio.
--   * Funciones SECURITY DEFINER (dueño postgres) y crons (pg_cron corre como postgres) -> saltan RLS.
--
-- Forward-only e idempotente: ENABLE RLS / REVOKE / GRANT se pueden repetir; las políticas nuevas se crean con
-- DROP POLICY IF EXISTS antes.
-- ============================================================================================================


-- ------------------------------------------------------------------------------------------------------------
-- 1. Activar RLS en las 14 tablas y quitar todo privilegio a anon (ningún camino legítimo usa anon sobre ellas).
-- ------------------------------------------------------------------------------------------------------------
ALTER TABLE public.api_keys               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.api_usage_log          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.demo2_seed_data        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journey_segments       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journeys               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.n8n_upu_agent          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.n8n_upu_incident       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.n8n_upu_timeoff        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.panelist_context       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.postal_center_carriers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.processed_events       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_orders        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rfid_events_raw        ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE
  public.api_keys, public.api_usage_log, public.demo2_seed_data, public.journey_segments, public.journeys,
  public.n8n_upu_agent, public.n8n_upu_incident, public.n8n_upu_timeoff, public.panelist_context,
  public.postal_center_carriers, public.processed_events, public.purchase_order_items, public.purchase_orders,
  public.rfid_events_raw
FROM anon;

-- service_role (edge functions, nodo Supabase de n8n) conserva todo (ya lo tenía; se repite por claridad).
GRANT ALL ON TABLE
  public.api_keys, public.api_usage_log, public.demo2_seed_data, public.journey_segments, public.journeys,
  public.n8n_upu_agent, public.n8n_upu_incident, public.n8n_upu_timeoff, public.panelist_context,
  public.postal_center_carriers, public.processed_events, public.purchase_order_items, public.purchase_orders,
  public.rfid_events_raw
TO service_role;


-- ------------------------------------------------------------------------------------------------------------
-- 2. Tablas solo de backend: RLS sin políticas y sin privilegios para authenticated.
--    Ni la web ni las edge functions con JWT de usuario las tocan.
-- ------------------------------------------------------------------------------------------------------------
-- demo2_seed_data: solo la leen admin_reset_demo2 / admin_reset_and_seed_demo2 (SECURITY DEFINER, ya solo
--   service_role desde 20261118210000).
-- n8n_upu_agent / n8n_upu_incident / n8n_upu_timeoff: memoria de chat de los agentes n8n (nodos Postgres y
--   memoryPostgresChat por conexión directa; un nodo Supabase con service_role). Trigger prune_tool_messages_
--   chat_memory se dispara con el usuario de n8n.
-- panelist_context: estado de conversación del bot (106 nodos Postgres de n8n) + funciones gps_*, ops_fix_r1_apply
--   y triggers tg_close_*_conversation, todas SECURITY DEFINER.
-- postal_center_carriers: solo la lee reconstruct_journeys (SECURITY DEFINER).
REVOKE ALL ON TABLE
  public.demo2_seed_data, public.n8n_upu_agent, public.n8n_upu_incident, public.n8n_upu_timeoff,
  public.panelist_context, public.postal_center_carriers
FROM authenticated;


-- ------------------------------------------------------------------------------------------------------------
-- 3. purchase_orders / purchase_order_items: se mantienen las políticas existentes (insert/update/delete solo
--    superadmin, TO authenticated; no hay política SELECT -> nadie las lee por la API). Nadie las usa desde la
--    web ni desde n8n; las borran admin_reset_* (SECURITY DEFINER). Basta con activar RLS (hecho arriba).
-- ------------------------------------------------------------------------------------------------------------


-- ------------------------------------------------------------------------------------------------------------
-- 4. api_keys / api_usage_log (página OneDB API, hook useOneDBAPI.ts; edge onedb-api usa service_role).
--    Se mantienen las políticas existentes por cuenta ("Users can manage their account's API keys",
--    "Users can view their account's API usage", "Service role bypass RLS").
--    Nuevo: el superadmin gestiona las claves de la cuenta elegida en la cabecera (ver, generar, desactivar) y ve
--    su uso.
-- ------------------------------------------------------------------------------------------------------------
DROP POLICY IF EXISTS api_keys_superadmin_all ON public.api_keys;
CREATE POLICY api_keys_superadmin_all ON public.api_keys
  FOR ALL TO authenticated
  USING ((SELECT public.is_superadmin()))
  WITH CHECK ((SELECT public.is_superadmin()));

DROP POLICY IF EXISTS api_usage_log_superadmin_select ON public.api_usage_log;
CREATE POLICY api_usage_log_superadmin_select ON public.api_usage_log
  FOR SELECT TO authenticated
  USING ((SELECT public.is_superadmin()));


-- ------------------------------------------------------------------------------------------------------------
-- 5. Tablas del pipeline RFID por cuenta: journey_segments, journeys, processed_events, rfid_events_raw.
--    Lectores web: Diagnosis (RoutePath*, SegmentTable, JKPerformanceSegments, EventConsolidation,
--    IncidentDetailsRow, CompleteJourneys, ProcessedEvents, downloadRouteSamples) y las RPC SECURITY INVOKER
--    get_* / assemble_journeys / consolidate_rfid_events, que el superadmin lanza sobre otra cuenta.
--    Escrituras: pipeline SECURITY DEFINER / service_role (saltan RLS); consolidate_rfid_events y
--    assemble_journeys (INVOKER) desde la web; borrado DEMO2 por el superadmin.
--
--    Se recrean las políticas por cuenta con la MISMA semántica que las vivas (account_id = cuenta del usuario),
--    pero TO authenticated y con la función envuelta en (SELECT ...) para que se evalúe una vez por consulta y
--    no por fila (estas tablas son grandes). La rama "OR superadmin" pasa a una política propia FOR ALL.
-- ------------------------------------------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['journey_segments','journeys','processed_events','rfid_events_raw'] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_select_policy', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_insert_policy', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_update_policy', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_delete_policy', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || '_superadmin_all', t);

    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR SELECT TO authenticated
                      USING (account_id = (SELECT public.current_user_account_id()))$p$, t || '_select_policy', t);
    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR INSERT TO authenticated
                      WITH CHECK (account_id = (SELECT public.current_user_account_id()))$p$, t || '_insert_policy', t);
    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR UPDATE TO authenticated
                      USING (account_id = (SELECT public.current_user_account_id()))
                      WITH CHECK (account_id = (SELECT public.current_user_account_id()))$p$, t || '_update_policy', t);
    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR DELETE TO authenticated
                      USING (account_id = (SELECT public.current_user_account_id()))$p$, t || '_delete_policy', t);
    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR ALL TO authenticated
                      USING ((SELECT public.is_superadmin()))
                      WITH CHECK ((SELECT public.is_superadmin()))$p$, t || '_superadmin_all', t);
  END LOOP;
END $$;
-- rfid_events_raw tenía además una política SELECT superadmin aparte; queda cubierta por _superadmin_all.
DROP POLICY IF EXISTS rfid_events_raw_select_superadmin ON public.rfid_events_raw;


-- ------------------------------------------------------------------------------------------------------------
-- 6. Vista v_segment_details: lee journey_segments con los permisos de su dueño (saltaba el RLS que activamos)
--    y anon/authenticated tenían todos los privilegios. Nadie la usa (ni web, ni edge, ni n8n).
--    -> security_invoker (respeta el RLS de quien consulta) y sin privilegios para anon/authenticated.
-- ------------------------------------------------------------------------------------------------------------
DO $$
BEGIN
  IF to_regclass('public.v_segment_details') IS NOT NULL THEN
    EXECUTE 'ALTER VIEW public.v_segment_details SET (security_invoker = true)';
    EXECUTE 'REVOKE ALL ON TABLE public.v_segment_details FROM anon, authenticated';
  END IF;
END $$;


-- ------------------------------------------------------------------------------------------------------------
-- 7. Funciones: quitar EXECUTE a PUBLIC y anon. Ningún llamador legítimo usa anon:
--    balance_node_load_matrix ........ solo desde rpc_balance_node_load (SECURITY DEFINER).
--    cleanup_processed_rfid_events ... sin llamadores en el repo.
--    generate_delivery_standards ..... web (useDeliveryStandards) con sesión.
--    process_all_accounts_pipeline ... edge rfid-provider-poll con service_role (cron cada 30 min).
--    process_rfid_pipeline ........... desde process_all_accounts_pipeline (DEFINER); tests.
--    recalculate_on_time_delivery_on_sla_change, set_account_id, transfer_to_one_db: funciones de TRIGGER (el
--        disparo de un trigger no comprueba EXECUTE).
--    reconstruct_journeys ............ web (useJourneySegments) con sesión; process_rfid_pipeline y
--        rpc_execute_pipeline_phase (DEFINER).
--    reprocess_transfer_errors ....... web (AllocationPlans) con sesión.
--    resolve_provider_reads .......... edge rfid-provider-poll con service_role.
--    rpc_get_node_load_by_period ..... web (useNodeLoadBalancing, useCityNodeLoad) con sesión.
--    consolidate_rfid_events (INVOKER) web (EventConsolidation) y edge consolidate-rfid-events con JWT de usuario;
--        edge consolidate-rfid-events-cron con service_role; process_rfid_pipeline / rpc_execute_pipeline_phase.
--    El agente de operaciones usa anon, pero solo llama a ops_* (no se tocan).
--    authenticated y service_role conservan EXECUTE (se concede explícitamente: hasta ahora authenticated podía
--    tenerlo solo vía PUBLIC). Restringir authenticated por cuenta queda para una fase posterior.
--    Se aplica a todas las sobrecargas existentes de cada nombre.
-- ------------------------------------------------------------------------------------------------------------
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN
    SELECT p.oid::regprocedure
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname = ANY (ARRAY[
        'balance_node_load_matrix','cleanup_processed_rfid_events','generate_delivery_standards',
        'process_all_accounts_pipeline','process_rfid_pipeline','recalculate_on_time_delivery_on_sla_change',
        'reconstruct_journeys','reprocess_transfer_errors','resolve_provider_reads','rpc_get_node_load_by_period',
        'set_account_id','transfer_to_one_db','consolidate_rfid_events'])
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', f);
  END LOOP;
END $$;
