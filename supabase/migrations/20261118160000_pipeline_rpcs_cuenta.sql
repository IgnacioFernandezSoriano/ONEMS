-- Funciones del Pipeline Monitor y contador de conversaciones: usan la cuenta ELEGIDA en pantalla.
--
-- Antes: rpc_get_pipeline_status / rpc_execute_pipeline_phase / rpc_get_recent_incidents sacaban la cuenta de
-- auth.users.raw_user_meta_data (vacío para todos los usuarios) y si no, de una cuenta fija (DEMO2): todo el mundo
-- veía y procesaba DEMO2. Además eran ejecutables sin sesión (anon/PUBLIC).
-- unread_incident_conversations devolvía al superadmin las conversaciones de todas las cuentas.
--
-- Ahora: parámetro opcional p_account_id (DEFAULT NULL, así las llamadas antiguas siguen funcionando).
--   * Con p_account_id: solo el superadmin (o service_role) puede pedir otra cuenta; un usuario normal solo la suya.
--   * Sin p_account_id: la cuenta del perfil del usuario (profiles.account_id). Sin cuenta -> error, nunca DEMO2.
--   * Sin sesión: rechazado; EXECUTE solo para authenticated y service_role.
-- El cuerpo de rpc_execute_pipeline_phase es el de 20261030145555_reconstruct_journeys_v2.sql (sin cambios).

-- Cuenta sobre la que actúa la llamada, o NULL + motivo. Interna: no ejecutable desde la API.
CREATE OR REPLACE FUNCTION public.pipeline_resolve_account(p_account_id uuid, OUT account_id uuid, OUT error text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
  v_service boolean := coalesce(auth.role(), '') = 'service_role';
  v_own uuid;
BEGIN
  IF auth.uid() IS NULL AND NOT v_service THEN
    error := 'Not authenticated'; RETURN;
  END IF;
  v_own := public.current_user_account_id();
  IF p_account_id IS NOT NULL THEN
    IF v_service OR public.is_superadmin() OR p_account_id = v_own THEN
      account_id := p_account_id;
    ELSE
      error := 'Forbidden account'; RETURN;
    END IF;
  ELSE
    account_id := v_own;
  END IF;
  IF account_id IS NULL THEN
    error := 'No account selected';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.pipeline_resolve_account(uuid) FROM PUBLIC, anon, authenticated;

-- ---------- rpc_get_pipeline_status ----------
DROP FUNCTION IF EXISTS public.rpc_get_pipeline_status();
CREATE FUNCTION public.rpc_get_pipeline_status(p_account_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
    v_res record;
    v_account_id uuid;
    v_raw_events_count integer;
    v_raw_events_pending integer;
    v_processed_events_count integer;
    v_segments_count integer;
    v_paths_count integer;
    v_last_consolidation timestamp with time zone;
    v_last_segment_build timestamp with time zone;
    v_last_aggregation timestamp with time zone;
BEGIN
    v_res := public.pipeline_resolve_account(p_account_id);
    IF v_res.error IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'error', v_res.error);
    END IF;
    v_account_id := v_res.account_id;

    SELECT COUNT(*), COUNT(*) FILTER (WHERE is_processed = FALSE OR is_processed IS NULL)
      INTO v_raw_events_count, v_raw_events_pending
      FROM rfid_events_raw WHERE account_id = v_account_id;

    SELECT COUNT(*) INTO v_processed_events_count FROM processed_events WHERE account_id = v_account_id;
    SELECT COUNT(*) INTO v_segments_count FROM journey_segments WHERE account_id = v_account_id;
    SELECT COUNT(*) INTO v_paths_count FROM journey_paths WHERE account_id = v_account_id;

    SELECT MAX(created_at) INTO v_last_consolidation FROM processed_events WHERE account_id = v_account_id;
    SELECT MAX(created_at) INTO v_last_segment_build FROM journey_segments WHERE account_id = v_account_id;
    SELECT MAX(created_at) INTO v_last_aggregation FROM journey_paths WHERE account_id = v_account_id;

    RETURN jsonb_build_object(
        'success', true,
        'account_id', v_account_id,
        'raw_events', jsonb_build_object('total', v_raw_events_count, 'pending', v_raw_events_pending,
                                         'processed', v_raw_events_count - v_raw_events_pending),
        'processed_events', jsonb_build_object('total', v_processed_events_count),
        'segments', jsonb_build_object('total', v_segments_count),
        'paths', jsonb_build_object('total', v_paths_count),
        'last_run', jsonb_build_object('consolidation', v_last_consolidation,
                                       'segment_building', v_last_segment_build,
                                       'aggregation', v_last_aggregation)
    );
END $$;
REVOKE ALL ON FUNCTION public.rpc_get_pipeline_status(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_pipeline_status(uuid) TO authenticated, service_role;

-- ---------- rpc_get_recent_incidents (stub: sin incidencias de pipeline todavía) ----------
DROP FUNCTION IF EXISTS public.rpc_get_recent_incidents(integer);
CREATE FUNCTION public.rpc_get_recent_incidents(p_limit integer DEFAULT 10, p_account_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
    v_res record;
BEGIN
    v_res := public.pipeline_resolve_account(p_account_id);
    IF v_res.error IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'error', v_res.error);
    END IF;
    RETURN jsonb_build_object('success', true, 'account_id', v_res.account_id,
                              'incidents', '[]'::jsonb, 'total', 0, 'limit', p_limit);
END $$;
REVOKE ALL ON FUNCTION public.rpc_get_recent_incidents(integer, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_recent_incidents(integer, uuid) TO authenticated, service_role;

-- ---------- rpc_execute_pipeline_phase ----------
DROP FUNCTION IF EXISTS public.rpc_execute_pipeline_phase(text);
CREATE FUNCTION public.rpc_execute_pipeline_phase(p_phase text, p_account_id uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions AS $$
DECLARE
    v_res record;
    v_account_id uuid;
    v_consolidation_result json;
    v_segments_result json;
    v_aggregation_result json;
    v_rj RECORD;
    v_aj RECORD;
BEGIN
    v_res := public.pipeline_resolve_account(p_account_id);
    IF v_res.error IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'error', v_res.error);
    END IF;
    v_account_id := v_res.account_id;

    IF p_phase IS NULL OR p_phase NOT IN ('consolidation', 'segments', 'aggregation', 'all') THEN
        RETURN jsonb_build_object('success', false, 'error', 'Invalid phase');
    END IF;

    IF p_phase = 'consolidation' OR p_phase = 'all' THEN
        v_consolidation_result := consolidate_rfid_events(v_account_id);
        PERFORM reenrich_processed_events(v_account_id);
    END IF;

    IF p_phase = 'segments' OR p_phase = 'all' THEN
        SELECT * INTO v_rj FROM reconstruct_journeys(v_account_id);
        SELECT * INTO v_aj FROM assemble_journeys(v_account_id);
        PERFORM * FROM propagate_journey_enrichment(v_account_id);
        v_segments_result := json_build_object(
            'success', true,
            'segments_created', v_rj.segments_created,
            'events_processed', v_rj.events_processed,
            'journeys_created', v_aj.journeys_created,
            'journeys_updated', v_aj.journeys_updated);
    END IF;

    IF p_phase = 'aggregation' OR p_phase = 'all' THEN
        v_aggregation_result := aggregate_journey_paths(v_account_id);
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'account_id', v_account_id,
        'phase', p_phase,
        'consolidation', v_consolidation_result,
        'segments', v_segments_result,
        'aggregation', v_aggregation_result
    );
END $$;
REVOKE ALL ON FUNCTION public.rpc_execute_pipeline_phase(text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_execute_pipeline_phase(text, uuid) TO authenticated, service_role;

-- ---------- unread_incident_conversations ----------
DROP FUNCTION IF EXISTS public.unread_incident_conversations();
CREATE FUNCTION public.unread_incident_conversations(p_account_id uuid DEFAULT NULL)
RETURNS TABLE(incident_kind text, incident_id uuid, unread integer, last_at timestamp with time zone)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT m.incident_kind, m.incident_id, count(*)::int, max(m.created_at)
    FROM incident_message m
   WHERE m.direction = 'inbound' AND m.read_at IS NULL AND NOT (m.meta ?| array['callback','report_flow'])
     AND coalesce(m.meta->>'kind','') NOT LIKE 'material%'
     AND auth.uid() IS NOT NULL
     AND (is_superadmin() OR m.account_id = current_user_account_id())
     AND (p_account_id IS NULL OR m.account_id = p_account_id)
   GROUP BY m.incident_kind, m.incident_id
   ORDER BY max(m.created_at) DESC;
$$;
REVOKE ALL ON FUNCTION public.unread_incident_conversations(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.unread_incident_conversations(uuid) TO authenticated, service_role;
