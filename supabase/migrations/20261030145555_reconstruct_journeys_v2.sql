-- =============================================================================
-- Reconstruccion de tramos v2
-- Spec: docs/superpowers/specs/2026-10-30-reconstruccion-tramos-v2-design.md
-- -----------------------------------------------------------------------------
-- - Visitas = eventos consecutivos de la etiqueta en el mismo centro.
-- - Tramo operational por visita con entrada y salida posterior (tiempos natural y
--   laborable en centro, SLA operativo, next_entry_timestamp).
-- - Tramo distribution entre visitas consecutivas a centros distintos, desde la
--   ULTIMA lectura de la visita anterior hasta la PRIMERA de la siguiente (una
--   lectura suelta ya genera transito), con tiempos natural/laborable y SLA.
-- - Enriquecimiento (transportista, producto, ciudades, ids de evento) en origen.
-- - Idempotente: por etiqueta con eventos pendientes se borran sus tramos y se
--   reconstruyen desde TODOS sus eventos; todos quedan is_consolidated=true.
-- - Misma firma y mismo retorno que la version anterior.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tiempo laborable dentro de un centro con horario (lunes-viernes, opening_hour a
-- working_hours_end, en la zona horaria del centro). La version anterior nunca se
-- habia ejecutado: fallaba con "cannot cast integer to time" y contaba horas
-- enteras. Sin horario definido devuelve el tiempo natural.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_working_time_minutes(p_start_time timestamptz, p_end_time timestamptz, p_postal_center_id uuid)
RETURNS integer
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
    v_open  TIME;
    v_close TIME;
    v_tz    TEXT;
    v_s     TIMESTAMP;
    v_e     TIMESTAMP;
    v_day   DATE;
    v_ws    TIMESTAMP;
    v_we    TIMESTAMP;
    v_minutes NUMERIC := 0;
BEGIN
    IF p_start_time IS NULL OR p_end_time IS NULL OR p_end_time <= p_start_time THEN
        RETURN 0;
    END IF;

    SELECT opening_hour, working_hours_end, timezone
      INTO v_open, v_close, v_tz
      FROM postal_centers WHERE id = p_postal_center_id;

    IF v_open IS NULL OR v_close IS NULL OR v_close <= v_open THEN
        RETURN (EXTRACT(EPOCH FROM (p_end_time - p_start_time)) / 60)::INTEGER;
    END IF;

    v_tz := COALESCE(NULLIF(v_tz, ''), 'UTC');
    v_s := p_start_time AT TIME ZONE v_tz;
    v_e := p_end_time   AT TIME ZONE v_tz;

    v_day := v_s::DATE;
    WHILE v_day <= v_e::DATE LOOP
        IF EXTRACT(ISODOW FROM v_day) BETWEEN 1 AND 5 THEN
            v_ws := v_day + v_open;
            v_we := v_day + v_close;
            IF LEAST(v_e, v_we) > GREATEST(v_s, v_ws) THEN
                v_minutes := v_minutes + EXTRACT(EPOCH FROM (LEAST(v_e, v_we) - GREATEST(v_s, v_ws))) / 60;
            END IF;
        END IF;
        v_day := v_day + 1;
    END LOOP;

    RETURN ROUND(v_minutes)::INTEGER;
END;
$function$;


CREATE OR REPLACE FUNCTION public.reconstruct_journeys(p_account_id uuid DEFAULT NULL::uuid, p_tag_id text DEFAULT NULL::text)
RETURNS TABLE(segments_created bigint, events_processed bigint, execution_time_ms bigint)
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_start_time TIMESTAMPTZ := clock_timestamp();
    v_segments_created BIGINT := 0;
    v_events_processed BIGINT := 0;
    v_tag RECORD;
    v_visit RECORD;
    v_prev RECORD;
    v_has_prev BOOLEAN;
    v_prev_op_id BIGINT;
    v_enr RECORD;
    v_carrier_name TEXT;
    v_product_name TEXT;
    v_sla_carrier_id UUID;
    v_sla_carrier_name TEXT;
    v_sla RECORD;
    v_from_ts TIMESTAMPTZ;
    v_natural INTEGER;
    v_working INTEGER;
    v_adjusted INTEGER;
    v_pre_op_wait INTEGER;
    v_compliance TEXT;
    v_mode TEXT;
    v_rows INTEGER;
BEGIN
    FOR v_tag IN
        SELECT DISTINCT pe.account_id, pe.tag_id
        FROM processed_events pe
        WHERE pe.is_consolidated = false
          AND (p_account_id IS NULL OR pe.account_id = p_account_id)
          AND (p_tag_id IS NULL OR pe.tag_id = p_tag_id)
        ORDER BY pe.account_id, pe.tag_id
    LOOP
      BEGIN  -- aislamiento por etiqueta: una etiqueta rota no tumba la pasada
        DELETE FROM journey_segments
         WHERE account_id = v_tag.account_id AND tag_id = v_tag.tag_id;

        -- Enriquecimiento del envio: primer evento que lo lleve
        SELECT pe.carrier_id, pe.product_id, pe.origin_city_name, pe.destination_city_name
          INTO v_enr
          FROM processed_events pe
         WHERE pe.account_id = v_tag.account_id AND pe.tag_id = v_tag.tag_id
           AND (pe.carrier_id IS NOT NULL OR pe.product_id IS NOT NULL OR pe.origin_city_name IS NOT NULL)
         ORDER BY pe.timestamp, pe.id
         LIMIT 1;

        v_carrier_name := NULL;  v_product_name := NULL;
        IF v_enr.carrier_id IS NOT NULL THEN
            SELECT c.name INTO v_carrier_name FROM carriers c WHERE c.id = v_enr.carrier_id;
        END IF;
        IF v_enr.product_id IS NOT NULL THEN
            SELECT p.code INTO v_product_name FROM products p WHERE p.id = v_enr.product_id;
        END IF;

        v_has_prev := false;
        v_prev_op_id := NULL;

        FOR v_visit IN
            WITH ev AS (
                SELECT pe.id, pe.postal_center_id, pe.event_type, pe.timestamp, pe.analysis_datetime,
                       pe.postal_center_code_snapshot, pe.postal_center_name_snapshot, pe.postal_center_city_snapshot,
                       CASE WHEN lag(pe.postal_center_id) OVER (ORDER BY pe.timestamp, pe.id)
                                 IS DISTINCT FROM pe.postal_center_id THEN 1 ELSE 0 END AS new_run
                  FROM processed_events pe
                 WHERE pe.account_id = v_tag.account_id AND pe.tag_id = v_tag.tag_id
            ), runs AS (
                SELECT ev.*, sum(new_run) OVER (ORDER BY timestamp, id ROWS UNBOUNDED PRECEDING) AS run_no
                  FROM ev
            )
            SELECT run_no,
                   postal_center_id,
                   min(postal_center_code_snapshot) AS code,
                   min(postal_center_name_snapshot) AS name,
                   min(postal_center_city_snapshot) AS city,
                   min(timestamp)                   AS first_ts,
                   (array_agg(id ORDER BY timestamp, id))[1]            AS first_id,
                   max(timestamp)                   AS last_ts,
                   (array_agg(id ORDER BY timestamp DESC, id DESC))[1]  AS last_id,
                   min(timestamp)         FILTER (WHERE event_type = 'entry') AS entry_ts,
                   (array_agg(id ORDER BY timestamp, id) FILTER (WHERE event_type = 'entry'))[1] AS entry_id,
                   (array_agg(analysis_datetime ORDER BY timestamp, id) FILTER (WHERE event_type = 'entry'))[1] AS entry_analysis,
                   max(timestamp)         FILTER (WHERE event_type = 'exit')  AS exit_ts,
                   (array_agg(id ORDER BY timestamp DESC, id DESC) FILTER (WHERE event_type = 'exit'))[1] AS exit_id,
                   (array_agg(analysis_datetime ORDER BY timestamp DESC, id DESC) FILTER (WHERE event_type = 'exit'))[1] AS exit_analysis
              FROM runs
             GROUP BY run_no, postal_center_id
             ORDER BY run_no
        LOOP
            -- -------------------------------------------------------------
            -- Transito desde la visita anterior (ultima lectura -> primera)
            -- -------------------------------------------------------------
            IF v_has_prev THEN
              IF v_prev.postal_center_id IS DISTINCT FROM v_visit.postal_center_id THEN
                v_from_ts := v_prev.last_ts;
                v_natural := GREATEST(0, (EXTRACT(EPOCH FROM (v_visit.first_ts - v_from_ts)) / 60)::INTEGER);

                SELECT pc.calculation_mode INTO v_mode FROM postal_centers pc WHERE pc.id = v_prev.postal_center_id;
                IF v_mode = 'working_days' THEN
                    v_working := calculate_working_time_minutes(v_from_ts, v_visit.first_ts, v_prev.postal_center_id);
                ELSE
                    v_working := v_natural;
                END IF;

                -- Transportista para el SLA: el del envio; si no, el del centro destino (como antes)
                v_sla_carrier_id := v_enr.carrier_id;
                v_sla_carrier_name := v_carrier_name;
                IF v_sla_carrier_id IS NULL THEN
                    SELECT pcc.carrier_id, c.name INTO v_sla_carrier_id, v_sla_carrier_name
                      FROM postal_center_carriers pcc
                      JOIN carriers c ON c.id = pcc.carrier_id
                     WHERE pcc.postal_center_id = v_visit.postal_center_id
                     LIMIT 1;
                END IF;

                v_adjusted := calculate_adjusted_time(v_from_ts, v_visit.first_ts, NULL);

                SELECT * INTO v_sla
                  FROM find_applicable_sla(v_tag.account_id, 'distribution',
                                           p_from_postal_center_id => v_prev.postal_center_id,
                                           p_to_postal_center_id   => v_visit.postal_center_id,
                                           p_carrier_id            => v_sla_carrier_id);
                v_compliance := determine_sla_compliance(v_adjusted, v_sla.expected_time_minutes,
                                    v_sla.on_time_percentage, v_sla.warning_threshold, v_sla.critical_threshold);

                INSERT INTO journey_segments (
                    account_id, tag_id, segment_type,
                    from_postal_center_id, to_postal_center_id,
                    entry_event_id, exit_event_id,
                    entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
                    actual_time_minutes, adjusted_time_minutes,
                    natural_transit_time_minutes, working_transit_time_minutes,
                    sla_id, expected_time_minutes, sla_compliance,
                    from_postal_center_code_snapshot, from_postal_center_name_snapshot, from_postal_center_city,
                    to_postal_center_code_snapshot,   to_postal_center_name_snapshot,   to_postal_center_city,
                    carrier_id, carrier_name_snapshot, product_id, product_name,
                    origin_city_name, destination_city_name
                ) VALUES (
                    v_tag.account_id, v_tag.tag_id, 'distribution',
                    v_prev.postal_center_id, v_visit.postal_center_id,
                    v_prev.last_id, v_visit.first_id,
                    v_from_ts, v_visit.first_ts, v_from_ts, v_visit.first_ts,
                    v_natural, v_adjusted,
                    v_natural, v_working,
                    v_sla.sla_id, v_sla.expected_time_minutes, v_compliance,
                    v_prev.code, v_prev.name, v_prev.city,
                    v_visit.code, v_visit.name, v_visit.city,
                    v_sla_carrier_id, v_sla_carrier_name, v_enr.product_id, v_product_name,
                    v_enr.origin_city_name, v_enr.destination_city_name
                );
                v_segments_created := v_segments_created + 1;

                IF v_prev_op_id IS NOT NULL THEN
                    UPDATE journey_segments SET next_entry_timestamp = v_visit.first_ts WHERE id = v_prev_op_id;
                END IF;
              END IF;
            END IF;

            -- -------------------------------------------------------------
            -- Operativo en esta visita (entrada y salida posterior)
            -- -------------------------------------------------------------
            v_prev_op_id := NULL;
            IF v_visit.entry_ts IS NOT NULL AND v_visit.exit_ts IS NOT NULL AND v_visit.exit_ts >= v_visit.entry_ts THEN
                v_natural := (EXTRACT(EPOCH FROM (v_visit.exit_ts - v_visit.entry_ts)) / 60)::INTEGER;

                SELECT pc.calculation_mode INTO v_mode FROM postal_centers pc WHERE pc.id = v_visit.postal_center_id;
                IF v_mode = 'working_days' THEN
                    v_working := calculate_working_time_minutes(v_visit.entry_ts, v_visit.exit_ts, v_visit.postal_center_id);
                ELSE
                    v_working := v_natural;
                END IF;

                v_adjusted := calculate_adjusted_time(v_visit.entry_ts, v_visit.exit_ts, v_visit.postal_center_id);
                v_pre_op_wait := calculate_pre_operational_wait(v_visit.entry_ts, COALESCE(v_visit.entry_analysis, v_visit.entry_ts));

                SELECT * INTO v_sla
                  FROM find_applicable_sla(v_tag.account_id, 'operational',
                                           p_postal_center_id => v_visit.postal_center_id);
                v_compliance := determine_sla_compliance(v_adjusted, v_sla.expected_time_minutes,
                                    v_sla.on_time_percentage, v_sla.warning_threshold, v_sla.critical_threshold);

                INSERT INTO journey_segments (
                    account_id, tag_id, segment_type,
                    postal_center_id,
                    entry_event_id, exit_event_id,
                    entry_timestamp, exit_timestamp, entry_analysis_datetime, exit_analysis_datetime,
                    actual_time_minutes, adjusted_time_minutes, pre_operational_wait_minutes,
                    natural_time_in_center_minutes, working_time_in_center_minutes,
                    sla_id, expected_time_minutes, sla_compliance,
                    postal_center_code_snapshot, postal_center_name_snapshot, from_postal_center_city,
                    carrier_id, carrier_name_snapshot, product_id, product_name,
                    origin_city_name, destination_city_name
                ) VALUES (
                    v_tag.account_id, v_tag.tag_id, 'operational',
                    v_visit.postal_center_id,
                    v_visit.entry_id, v_visit.exit_id,
                    v_visit.entry_ts, v_visit.exit_ts,
                    COALESCE(v_visit.entry_analysis, v_visit.entry_ts), COALESCE(v_visit.exit_analysis, v_visit.exit_ts),
                    v_natural, v_adjusted, v_pre_op_wait,
                    v_natural, v_working,
                    v_sla.sla_id, v_sla.expected_time_minutes, v_compliance,
                    v_visit.code, v_visit.name, v_visit.city,
                    v_enr.carrier_id, v_carrier_name, v_enr.product_id, v_product_name,
                    v_enr.origin_city_name, v_enr.destination_city_name
                )
                RETURNING id INTO v_prev_op_id;
                v_segments_created := v_segments_created + 1;
            END IF;

            v_prev := v_visit;
            v_has_prev := true;
        END LOOP;

        UPDATE processed_events
           SET is_consolidated = true, processed_at = NOW()
         WHERE account_id = v_tag.account_id AND tag_id = v_tag.tag_id;
        GET DIAGNOSTICS v_rows = ROW_COUNT;
        v_events_processed := v_events_processed + v_rows;

      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'reconstruct_journeys: tag % de la cuenta % fallo: %', v_tag.tag_id, v_tag.account_id, SQLERRM;
      END;
    END LOOP;

    RETURN QUERY SELECT
        v_segments_created,
        v_events_processed,
        EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_start_time))::BIGINT;
END;
$function$;

COMMENT ON FUNCTION public.reconstruct_journeys(uuid, text) IS
  'v2 (2026-10-30): visitas por centro, transito desde la ultima lectura, tiempos natural/laborable, SLAs, enriquecimiento en origen; reconstruye por etiqueta de forma idempotente.';


-- -----------------------------------------------------------------------------
-- El boton "segments" del monitor de pipeline llamaba a build_journey_segments
-- (otra semantica de fila, sin SLAs, falla con exit NOT NULL). Que use el pipeline real.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_execute_pipeline_phase(p_phase text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
    v_account_id uuid;
    v_consolidation_result json;
    v_segments_result json;
    v_aggregation_result json;
    v_rj RECORD;
    v_aj RECORD;
BEGIN
    SELECT
        COALESCE(
            (SELECT (raw_user_meta_data->>'account_id')::uuid FROM auth.users WHERE id = auth.uid()),
            (SELECT (auth.jwt()->>'account_id')::uuid),
            'f4d823d2-93e6-4755-9a89-9da87e7fa86e'::uuid
        )
    INTO v_account_id;

    IF v_account_id IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'No account_id found');
    END IF;

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
END;
$function$;


-- -----------------------------------------------------------------------------
-- Rebuild unico de KENYA con la v2. DEMO2 no se toca (tramos sembrados sin eventos).
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_kenya uuid;
  r RECORD;
BEGIN
  SELECT id INTO v_kenya FROM accounts WHERE name = 'KENYA' LIMIT 1;
  IF v_kenya IS NULL THEN
    RAISE NOTICE 'rebuild KENYA: cuenta no encontrada, nada que hacer';
    RETURN;
  END IF;

  UPDATE processed_events SET is_consolidated = false, processed_at = NULL WHERE account_id = v_kenya;
  DELETE FROM journey_segments WHERE account_id = v_kenya;
  DELETE FROM journeys WHERE account_id = v_kenya;

  FOR r IN SELECT * FROM process_rfid_pipeline(v_kenya) LOOP
    RAISE NOTICE 'rebuild KENYA % : % (%)', r.phase, r.status, r.message;
    IF r.status <> 'success' THEN
      RAISE EXCEPTION 'rebuild KENYA: fase % fallo: %', r.phase, r.message;
    END IF;
  END LOOP;
END $$;
