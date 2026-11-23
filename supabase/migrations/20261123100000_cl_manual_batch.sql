-- Carrier Link: carga manual de un lote desde la pantalla Conectores ("Cargar lote").
-- Para carriers que mandan ficheros en vez de llamar a la API. Reproduce, paso a paso, lo que hace la Edge Function
-- carrier-link-ingest con un lote real (POST /batches sin dry_run):
--   1. comprobaciones del conector: pausado -> CL_FEED_PAUSED; en prueba -> CL_FEED_TESTING_DRY_RUN_ONLY (un conector
--      en prueba solo admite ensayos); tope de 5 MB (CL_BODY_TOO_LARGE) y de 5.000 lecturas (CL_TOO_MANY_ROWS),
--      igual que la Edge Function;
--   2. cl_ingest_batch(feed, lote, false);
--   3. cl_sample_stratum por cada estrato del resumen (solo si el lote guardado sigue 'validated');
--   4. cl_finish_batch.
-- La web llama a cl_manual_ingest, despues a cl_manual_sample una vez por estrato (barra de progreso; cada llamada va
-- por separado para quedar lejos del statement_timeout de 8 s de PostgREST) y al final a cl_manual_finish.
-- Un lote ya cargado (mismo batch_id) devuelve su resumen guardado; si se quedo a medias (fallo un sorteo), volver a
-- cargarlo retoma el sorteo donde quedo (cl_sample_stratum es idempotente por estrato), como un reintento por la API.
--
-- Permisos: authenticated con Edit en cl_connectors de la cuenta del conector, o superadmin. Conector ajeno,
-- inexistente o sin derecho: el mismo 42501 CL_FORBIDDEN (sin oraculo de existencia). Un lote que no es de ese
-- conector: CL_BATCH_NOT_FOUND (el mismo error que un lote inexistente).
-- cl_ingest_batch, cl_sample_stratum y cl_finish_batch siguen cerradas a authenticated: solo se llegan por aqui.

--
-- cl_manual_ingest devuelve { ingest, needs_sampling, batch_status }: batch_status es el estado ACTUAL del lote guardado
-- (validated, sampled, rejected, undone, expired, received) para que la web explique un lote repetido.

-- ================================================================ autorizacion comun (interna)
-- Solo permisos: devuelve el conector o 42501 CL_FORBIDDEN (igual para ajeno, inexistente, NULL o sin Edit).
CREATE OR REPLACE FUNCTION public.cl_manual_authorize(p_feed_id uuid)
 RETURNS public.cl_feeds
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_feed public.cl_feeds;
BEGIN
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF v_feed.id IS NULL
     OR NOT (public.is_superadmin()
             OR (v_feed.account_id = public.current_user_account_id()
                 AND public.has_any_access(v_feed.account_id, 'edit', 'cl_connectors'))) THEN
    RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  RETURN v_feed;
END $$;
REVOKE ALL ON FUNCTION public.cl_manual_authorize(uuid) FROM PUBLIC, anon, authenticated, service_role;

-- Estado del conector: mismas reglas que la Edge Function para un lote real.
CREATE OR REPLACE FUNCTION public.cl_manual_check_status(p_status text)
 RETURNS void
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path = public, extensions
AS $$
BEGIN
  IF p_status = 'paused' THEN
    RAISE EXCEPTION 'CL_FEED_PAUSED: the connector is paused' USING ERRCODE = '22023';
  END IF;
  IF p_status = 'testing' THEN
    RAISE EXCEPTION 'CL_FEED_TESTING_DRY_RUN_ONLY: the connector is testing; only dry runs are accepted' USING ERRCODE = '22023';
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.cl_manual_check_status(text) FROM PUBLIC, anon, authenticated, service_role;

-- Estado del lote si es de ese conector (via su demanda); NULL si no lo es o no existe.
CREATE OR REPLACE FUNCTION public.cl_manual_batch_status(p_feed_id uuid, p_batch_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT b.status FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id
   WHERE b.id = p_batch_id AND d.feed_id = p_feed_id
$$;
REVOKE ALL ON FUNCTION public.cl_manual_batch_status(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 1. entrada del lote
-- needs_sampling es la misma condicion con la que la Edge Function decide sortear: resumen 'validated' con lote y
-- lote guardado de ESTE conector aun 'validated'.
CREATE OR REPLACE FUNCTION public.cl_manual_ingest(p_feed_id uuid, p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  c_max_bytes constant integer := 5 * 1024 * 1024;   -- MAX_BODY_BYTES de la Edge Function
  c_max_rows  constant integer := 5000;              -- MAX_ROWS de la Edge Function
  v_feed   public.cl_feeds;
  v_rows   bigint;
  v_ingest jsonb;
  v_batch  uuid;
  v_bstatus text;
BEGIN
  -- Permisos antes que nada (sin oraculo de existencia ni del tamano del lote).
  v_feed := public.cl_manual_authorize(p_feed_id);

  -- Orden de la Edge Function: tamano, forma, numero de lecturas y, despues, estado del conector.
  IF pg_column_size(p_payload) > c_max_bytes THEN
    RAISE EXCEPTION 'CL_BODY_TOO_LARGE: the batch is larger than 5 MB' USING ERRCODE = '22023';
  END IF;
  IF p_payload IS NULL OR jsonb_typeof(p_payload) <> 'object' THEN
    RAISE EXCEPTION 'CL_BAD_PAYLOAD: the batch must be a JSON object' USING ERRCODE = '22023';
  END IF;
  -- countRows de la Edge Function: solo estratos objeto con rows array.
  SELECT COALESCE(sum(jsonb_array_length(e->'rows')), 0) INTO v_rows
    FROM jsonb_array_elements(CASE WHEN jsonb_typeof(p_payload->'strata') = 'array' THEN p_payload->'strata' ELSE '[]'::jsonb END) e
   WHERE jsonb_typeof(e) = 'object' AND jsonb_typeof(e->'rows') = 'array';
  IF v_rows > c_max_rows THEN
    RAISE EXCEPTION 'CL_TOO_MANY_ROWS: % rows (max %)', v_rows, c_max_rows USING ERRCODE = '22023';
  END IF;

  PERFORM public.cl_manual_check_status(v_feed.status);

  v_ingest := public.cl_ingest_batch(p_feed_id, p_payload, false);

  IF jsonb_typeof(v_ingest) = 'object' AND v_ingest->>'batch' IS NOT NULL THEN
    BEGIN
      v_batch := (v_ingest->>'batch')::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
      v_batch := NULL;
    END;
    IF v_batch IS NOT NULL THEN
      v_bstatus := public.cl_manual_batch_status(p_feed_id, v_batch);
    END IF;
  END IF;
  RETURN jsonb_build_object('ingest', v_ingest,
                            'needs_sampling', COALESCE(v_ingest->>'status' = 'validated' AND v_bstatus = 'validated', false),
                            'batch_status', v_bstatus);
END $$;
REVOKE ALL ON FUNCTION public.cl_manual_ingest(uuid, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_manual_ingest(uuid, jsonb) TO authenticated;

-- ================================================================ 2. sorteo de un estrato
CREATE OR REPLACE FUNCTION public.cl_manual_sample(p_feed_id uuid, p_batch_id uuid, p_stratum_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.cl_manual_check_status((public.cl_manual_authorize(p_feed_id)).status);
  IF public.cl_manual_batch_status(p_feed_id, p_batch_id) IS NULL THEN
    RAISE EXCEPTION 'CL_BATCH_NOT_FOUND: batch not found' USING ERRCODE = '22023';
  END IF;
  RETURN public.cl_sample_stratum(p_batch_id, p_stratum_id);
END $$;
REVOKE ALL ON FUNCTION public.cl_manual_sample(uuid, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_manual_sample(uuid, uuid, uuid) TO authenticated;

-- ================================================================ 3. cierre del lote
CREATE OR REPLACE FUNCTION public.cl_manual_finish(p_feed_id uuid, p_batch_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.cl_manual_check_status((public.cl_manual_authorize(p_feed_id)).status);
  IF public.cl_manual_batch_status(p_feed_id, p_batch_id) IS NULL THEN
    RAISE EXCEPTION 'CL_BATCH_NOT_FOUND: batch not found' USING ERRCODE = '22023';
  END IF;
  RETURN public.cl_finish_batch(p_batch_id);
END $$;
REVOKE ALL ON FUNCTION public.cl_manual_finish(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_manual_finish(uuid, uuid) TO authenticated;
