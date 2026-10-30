-- =============================================================================
-- Viajes y tramos sin ciudad origen/destino, transportista ni producto
-- -----------------------------------------------------------------------------
-- Problema. El cron usa reconstruct_journeys + assemble_journeys. Esa generacion
-- no copia a journey_segments el transportista, el producto ni las ciudades que ya
-- llevan los processed_events, y assemble_journeys escribe NULL en origen/destino
-- del viaje (y nunca los actualiza). Route Path Analysis y aggregate_journey_paths
-- esperan esos campos, asi que para las cuentas reales salen vacios.
-- Ademas, un evento leido ANTES de que el panelista registre la etiqueta se queda
-- sin enriquecer para siempre: la consolidacion solo cruza con one_db una vez.
--
-- Solucion minima (sin tocar reconstruct_journeys ni assemble_journeys):
--   1) reenrich_processed_events(cuenta): eventos huerfanos cuya etiqueta ya esta
--      en one_db -> copia ciudades, transportista y producto.
--   2) propagate_journey_enrichment(cuenta): copia de processed_events a
--      journey_segments (via entry/exit_event_id) y a journeys (primer evento
--      enriquecido de la etiqueta + id de ciudad por nombre en el catalogo).
--   3) process_rfid_pipeline llama a (1) antes de reconstruir y a (2) tras montar.
--   4) Backfill unico de todas las cuentas al final de la migracion.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.reenrich_processed_events(p_account_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_n integer;
BEGIN
  UPDATE processed_events pe
     SET origin_city_name      = o.origin_city_name,
         destination_city_name = o.destination_city_name,
         carrier_id            = COALESCE(pe.carrier_id, c.id),
         product_id            = COALESCE(pe.product_id, p.id)
    FROM (
          SELECT DISTINCT ON (tag_id)
                 tag_id, carrier_name, product_name, origin_city_name, destination_city_name
            FROM one_db
           WHERE account_id = p_account_id
             AND tag_id IS NOT NULL
           ORDER BY tag_id, sent_at DESC NULLS LAST, created_at DESC
         ) o
    LEFT JOIN carriers c ON c.account_id = p_account_id AND c.name = o.carrier_name
    LEFT JOIN products p ON p.carrier_id = c.id AND p.code = o.product_name
   WHERE pe.account_id = p_account_id
     AND pe.tag_id = o.tag_id
     AND pe.origin_city_name IS NULL;

  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END;
$$;

COMMENT ON FUNCTION public.reenrich_processed_events(uuid) IS
  'Cruza de nuevo con one_db los processed_events sin ciudad origen (etiqueta registrada despues de leerse). Devuelve filas actualizadas.';


CREATE OR REPLACE FUNCTION public.propagate_journey_enrichment(p_account_id uuid)
RETURNS TABLE(segments_updated integer, journeys_updated integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seg integer := 0;
  v_jou integer := 0;
BEGIN
  -- ---------------------------------------------------------------------------
  -- Tramos: entry_event_id es el evento de entrada (operational) o la salida del
  -- centro origen (distribution); exit_event_id la salida (operational) o la
  -- entrada en el centro destino (distribution).
  -- ---------------------------------------------------------------------------
  WITH src AS (
    SELECT js.id,
           js.segment_type,
           COALESCE(pe_in.carrier_id,            pe_out.carrier_id)            AS carrier_id,
           COALESCE(pe_in.product_id,            pe_out.product_id)            AS product_id,
           COALESCE(pe_in.origin_city_name,      pe_out.origin_city_name)      AS origin_city_name,
           COALESCE(pe_in.destination_city_name, pe_out.destination_city_name) AS destination_city_name,
           pe_in.postal_center_city_snapshot  AS from_city,
           pe_out.postal_center_city_snapshot AS to_city
      FROM journey_segments js
      JOIN processed_events pe_in       ON pe_in.id  = js.entry_event_id
      LEFT JOIN processed_events pe_out ON pe_out.id = js.exit_event_id
     WHERE js.account_id = p_account_id
       AND (
            (js.origin_city_name IS NULL        AND COALESCE(pe_in.origin_city_name, pe_out.origin_city_name) IS NOT NULL)
         OR (js.destination_city_name IS NULL   AND COALESCE(pe_in.destination_city_name, pe_out.destination_city_name) IS NOT NULL)
         OR (js.carrier_id IS NULL              AND COALESCE(pe_in.carrier_id, pe_out.carrier_id) IS NOT NULL)
         OR (js.product_id IS NULL              AND COALESCE(pe_in.product_id, pe_out.product_id) IS NOT NULL)
         OR (js.from_postal_center_city IS NULL AND pe_in.postal_center_city_snapshot IS NOT NULL)
         OR (js.segment_type = 'distribution' AND js.to_postal_center_city IS NULL AND pe_out.postal_center_city_snapshot IS NOT NULL)
       )
  )
  UPDATE journey_segments js
     SET carrier_id              = COALESCE(js.carrier_id, src.carrier_id),
         carrier_name_snapshot   = COALESCE(js.carrier_name_snapshot, c.name),
         product_id              = COALESCE(js.product_id, src.product_id),
         product_name            = COALESCE(js.product_name, pr.code),
         origin_city_name        = COALESCE(js.origin_city_name, src.origin_city_name),
         destination_city_name   = COALESCE(js.destination_city_name, src.destination_city_name),
         from_postal_center_city = COALESCE(js.from_postal_center_city, src.from_city),
         to_postal_center_city   = COALESCE(js.to_postal_center_city,
                                            CASE WHEN src.segment_type = 'distribution' THEN src.to_city END)
    FROM src
    LEFT JOIN carriers c  ON c.id  = src.carrier_id
    LEFT JOIN products pr ON pr.id = src.product_id
   WHERE js.id = src.id;

  GET DIAGNOSTICS v_seg = ROW_COUNT;

  -- ---------------------------------------------------------------------------
  -- Viajes: primer evento enriquecido de la etiqueta; id de ciudad por nombre.
  -- ---------------------------------------------------------------------------
  WITH src AS (
    SELECT j.id,
           pe.origin_city_name,
           pe.destination_city_name,
           pe.product_id,
           (SELECT ci.id FROM cities ci
             WHERE ci.account_id = p_account_id
               AND lower(trim(ci.name)) = lower(trim(pe.origin_city_name))
             ORDER BY ci.created_at LIMIT 1) AS origin_city_id,
           (SELECT ci.id FROM cities ci
             WHERE ci.account_id = p_account_id
               AND lower(trim(ci.name)) = lower(trim(pe.destination_city_name))
             ORDER BY ci.created_at LIMIT 1) AS destination_city_id
      FROM journeys j
      JOIN LATERAL (
             SELECT e.origin_city_name, e.destination_city_name, e.product_id
               FROM processed_events e
              WHERE e.account_id = j.account_id
                AND e.tag_id = j.tag_id
                AND e.origin_city_name IS NOT NULL
              ORDER BY e.timestamp
              LIMIT 1
           ) pe ON TRUE
     WHERE j.account_id = p_account_id
       AND (j.origin_city_name IS NULL OR j.destination_city_name IS NULL
            OR j.origin_city_id IS NULL OR j.destination_city_id IS NULL
            OR (j.product_id IS NULL AND pe.product_id IS NOT NULL))
  )
  UPDATE journeys j
     SET origin_city_name      = COALESCE(j.origin_city_name, src.origin_city_name),
         destination_city_name = COALESCE(j.destination_city_name, src.destination_city_name),
         origin_city_id        = COALESCE(j.origin_city_id, src.origin_city_id),
         destination_city_id   = COALESCE(j.destination_city_id, src.destination_city_id),
         product_id            = COALESCE(j.product_id, src.product_id),
         product_name          = COALESCE(j.product_name, pr.code),
         updated_at            = NOW()
    FROM src
    LEFT JOIN products pr ON pr.id = src.product_id
   WHERE j.id = src.id
     AND (j.origin_city_name IS DISTINCT FROM COALESCE(j.origin_city_name, src.origin_city_name)
       OR j.destination_city_name IS DISTINCT FROM COALESCE(j.destination_city_name, src.destination_city_name)
       OR j.origin_city_id IS DISTINCT FROM COALESCE(j.origin_city_id, src.origin_city_id)
       OR j.destination_city_id IS DISTINCT FROM COALESCE(j.destination_city_id, src.destination_city_id)
       OR j.product_id IS DISTINCT FROM COALESCE(j.product_id, src.product_id));

  GET DIAGNOSTICS v_jou = ROW_COUNT;

  RETURN QUERY SELECT v_seg, v_jou;
END;
$$;

COMMENT ON FUNCTION public.propagate_journey_enrichment(uuid) IS
  'Copia transportista, producto y ciudades origen/destino de processed_events a journey_segments y journeys (solo rellena lo que esta a NULL).';

-- Solo las llama el pipeline (cron / service_role). Un usuario de la API no debe
-- poder dispararlas con la cuenta de otro.
REVOKE EXECUTE ON FUNCTION public.reenrich_processed_events(uuid)      FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.propagate_journey_enrichment(uuid)   FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.reenrich_processed_events(uuid)      TO service_role;
GRANT  EXECUTE ON FUNCTION public.propagate_journey_enrichment(uuid)   TO service_role;


-- -----------------------------------------------------------------------------
-- Pipeline por cuenta: misma firma; fases nuevas 'enrichment' y 'propagation'.
-- process_all_accounts_pipeline suma las columnas numericas con COALESCE, asi que
-- las filas nuevas no le afectan.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_rfid_pipeline(p_account_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(phase text, events_consolidated integer, incidents_created integer, segments_created integer, events_processed integer, execution_time_ms integer, status text, message text)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_start_time TIMESTAMPTZ;
    v_phase_start TIMESTAMPTZ;
    v_consolidation_result JSON;
    v_reenriched INTEGER := 0;
    v_reconstruction_segments INTEGER;
    v_reconstruction_events INTEGER;
    v_assembly_created INTEGER;
    v_assembly_updated INTEGER;
    v_prop_segments INTEGER := 0;
    v_prop_journeys INTEGER := 0;
    v_total_time INTEGER;
BEGIN
    v_start_time := clock_timestamp();

    -- PHASE 1: Consolidation
    v_phase_start := clock_timestamp();
    BEGIN
        v_consolidation_result := consolidate_rfid_events(p_account_id);
        RETURN QUERY SELECT
            'consolidation'::TEXT,
            (v_consolidation_result->>'events_created')::INTEGER,
            (v_consolidation_result->>'incidents_created')::INTEGER,
            0::INTEGER,
            (v_consolidation_result->>'events_processed')::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Processed %s events', (v_consolidation_result->>'events_processed')::INTEGER)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'consolidation'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- PHASE 1b: Re-enrichment of orphan events (tag registered in one_db after being read)
    v_phase_start := clock_timestamp();
    BEGIN
        v_reenriched := reenrich_processed_events(p_account_id);
        RETURN QUERY SELECT
            'enrichment'::TEXT, 0,0,0,
            v_reenriched,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Re-enriched %s events', v_reenriched)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        -- Not fatal: the rest of the pipeline can still run.
        RETURN QUERY SELECT
            'enrichment'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
    END;

    -- PHASE 2: Reconstruction
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT rj.segments_created, rj.events_processed
        INTO v_reconstruction_segments, v_reconstruction_events
        FROM reconstruct_journeys(p_account_id) rj;

        RETURN QUERY SELECT
            'reconstruction'::TEXT,
            0,0,
            v_reconstruction_segments,
            v_reconstruction_events,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Created %s segments', v_reconstruction_segments)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'reconstruction'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- PHASE 3: Assembly
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT aj.journeys_created, aj.journeys_updated
        INTO v_assembly_created, v_assembly_updated
        FROM assemble_journeys(p_account_id) aj;

        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,
            (v_assembly_created + v_assembly_updated)::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Created %s journeys', v_assembly_created + v_assembly_updated)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'assembly'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
        RETURN;
    END;

    -- PHASE 4: Propagation of carrier/product/cities to segments and journeys
    v_phase_start := clock_timestamp();
    BEGIN
        SELECT pj.segments_updated, pj.journeys_updated
        INTO v_prop_segments, v_prop_journeys
        FROM propagate_journey_enrichment(p_account_id) pj;

        RETURN QUERY SELECT
            'propagation'::TEXT, 0,0,0,
            (v_prop_segments + v_prop_journeys)::INTEGER,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'success'::TEXT,
            format('Enriched %s segments, %s journeys', v_prop_segments, v_prop_journeys)::TEXT;
    EXCEPTION WHEN OTHERS THEN
        RETURN QUERY SELECT
            'propagation'::TEXT, 0,0,0,0,
            EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_phase_start))::INTEGER,
            'error'::TEXT, SQLERRM::TEXT;
    END;

    -- Summary
    v_total_time := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))::INTEGER;
    RETURN QUERY SELECT
        'summary'::TEXT,
        (v_consolidation_result->>'events_created')::INTEGER,
        (v_consolidation_result->>'incidents_created')::INTEGER,
        v_reconstruction_segments,
        v_assembly_created + v_assembly_updated,
        v_total_time,
        'success'::TEXT,
        'Pipeline completed'::TEXT;
END;
$function$;


-- -----------------------------------------------------------------------------
-- Backfill unico: todas las cuentas (Kenya: 94 tramos y 62 viajes; DEMO2: 26 viajes).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_re integer;
  v_seg integer;
  v_jou integer;
BEGIN
  FOR r IN SELECT id, name FROM accounts ORDER BY name LOOP
    v_re := reenrich_processed_events(r.id);
    SELECT segments_updated, journeys_updated INTO v_seg, v_jou
      FROM propagate_journey_enrichment(r.id);
    RAISE NOTICE 'backfill % : % eventos reenriquecidos, % tramos, % viajes', r.name, v_re, v_seg, v_jou;
  END LOOP;
END $$;
