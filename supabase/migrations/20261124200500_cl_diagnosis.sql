-- Carrier Link v4, tarea 7: diagnostico de red (fase 4). Spec 2026-11-19-carrier-link-design.md v4.2 (R33-R36);
-- estudio .superpowers/sdd/2026-11-23-carrier-link-conector-diagnostico/task-d-design.md (opcion A, adaptada a v4).
--
-- Que entra (R33): SOLO los envios sorteados de una entrega real cuyo plan tiene Diagnostico (cl_plans.feed_diagnosis),
-- con TODAS sus lecturas validas (inicio, intermedias y fin). Nunca el resto de la entrega, nunca las de prueba.
-- Como entran: una fila en rfid_events_raw por lectura, en el paso transfer del proceso de la entrega (la zona de paso
-- se vacia despues: es el unico momento en que existen las lecturas intermedias). El ETL RFID de siempre (cron del
-- poll, cada 30 min, R35) las consolida -> processed_events -> journey_segments -> journeys. NO se toca ninguna funcion
-- del ETL (consolidate_rfid_events, reenrich, reconstruct_journeys, assemble, propagate, process_*_pipeline,
-- resolve_provider_reads, normalize_*), ni el cron del poll.
-- Contrato con el ETL (consolidate_rfid_events, 20261030142158):
--   rfid_events_raw(account_id, event_id, read_local_datetime, reader_id = readers.reader_id del punto ('CL:...'),
--   tag_id = item_id tal cual llega del carrier (= cl_samples.item_id = one_db.tag_id), is_processed = false,
--   carrier_id, product_id). event_id = 'cl:' || md5(item_id | reader_id | scan_at UTC): determinista, ON CONFLICT
--   (account_id, event_id) DO NOTHING -> reprocesar no duplica. El lector se busca por reader_id + cuenta y necesita
--   centro postal; one_db (fila 'carrier' de cl_transfer_sample) da carrier, producto y ciudades.
-- Origen (R34: sin logica de choques): prefijo 'cl:' en event_id y columna capture_source ('rfid' por defecto,
-- 'carrier' para estas lecturas) en processed_events y journey_segments, rellenada por disparadores. Las filas RFID
-- (Kenya) no pasan por el disparador de eventos (WHEN reader_id_snapshot LIKE 'CL:%') y quedan 'rfid'.
-- Puntos sin centro postal (R36): sus lecturas no entran; aviso diagnosis_point_without_center por entrega y plan.
-- Entrada tardia: las lecturas de esos envios en un lugar sin punto dado de alta (unknown_reading_point) o en un punto
-- sin centro se guardan en cl_diagnosis_pending (solo envios sorteados de planes con Diagnostico, R25/R33) y entran
-- en cuanto el punto se da de alta o recibe centro (disparador en readers, solo puntos carrier_scan). El ETL rehace los
-- tramos de toda la etiqueta al llegar un evento nuevo (reconstruct_journeys v2).
-- Deshacer (fallo terminal de una entrega, cl_delivery_undo_samples): se borran sus filas raw 'cl:' y, si ya se
-- consolidaron, sus eventos 'carrier' (en cascada tramos e incidencias ligadas), sus incidencias de consolidacion y sus
-- viajes. Reinicio de cuenta: al borrar un punto carrier_scan se borra antes su diagnostico (FK RESTRICT).
-- Forward-only. Ninguna migracion v4 anterior esta aplicada en remoto.
-- Bloqueos: ALTER TABLE ADD COLUMN toma ACCESS EXCLUSIVE en processed_events y journey_segments; CREATE TRIGGER toma
-- SHARE ROW EXCLUSIVE (bloquea escrituras, no lecturas) en processed_events, journey_segments y readers; todo hasta el
-- COMMIT. lock_timeout de 5 s: si el ETL RFID (cron del poll, cada 30 min) esta en marcha, la migracion falla
-- enseguida en vez de quedarse en cola bloqueando a todos detras; se reintenta mas tarde (entre dos pasadas del cron).
SET LOCAL lock_timeout = '5s';

-- ================================================================ 1. origen de captura en eventos y tramos
-- ADD COLUMN con DEFAULT constante: solo metadatos, sin reescribir la tabla (PG >= 11). El CHECK en linea comprueba las
-- filas existentes con un escaneo bajo el mismo ACCESS EXCLUSIVE (en prod: 945 eventos y 446 tramos, inmediato).
ALTER TABLE public.processed_events ADD COLUMN capture_source text NOT NULL DEFAULT 'rfid'
  CONSTRAINT processed_events_capture_source_check CHECK (capture_source IN ('rfid','carrier'));
ALTER TABLE public.journey_segments ADD COLUMN capture_source text NOT NULL DEFAULT 'rfid'
  CONSTRAINT journey_segments_capture_source_check CHECK (capture_source IN ('rfid','carrier'));
COMMENT ON COLUMN public.processed_events.capture_source IS
  'Origen de la lectura: rfid (lectores RFID) o carrier (escaneos de Carrier Link, event_id cl:...).';
COMMENT ON COLUMN public.journey_segments.capture_source IS
  'Origen de los eventos del tramo: rfid o carrier (Carrier Link).';

-- Evento de un punto de Carrier Link (reader_id 'CL:...', prefijo reservado a carrier_scan por readers_cl_defaults):
-- origen 'carrier'. Si el envio ya no tiene muestra activa (entrega deshecha mientras el ETL la consolidaba) el evento
-- no se crea: asi el diagnostico nunca guarda lecturas de una muestra anulada.
CREATE OR REPLACE FUNCTION public.cl_processed_events_capture_source()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.cl_samples s
                  WHERE s.account_id = NEW.account_id AND s.item_id = NEW.tag_id AND s.status = 'active') THEN
    RETURN NULL;
  END IF;
  NEW.capture_source := 'carrier';
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cl_processed_events_capture_source() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER cl_processed_events_capture_source
  BEFORE INSERT ON public.processed_events
  FOR EACH ROW WHEN (NEW.reader_id_snapshot LIKE 'CL:%')
  EXECUTE FUNCTION public.cl_processed_events_capture_source();

-- Tramo: el origen de su evento de entrada (o de salida). Un envio es solo RFID o solo carrier (R34).
CREATE OR REPLACE FUNCTION public.cl_journey_segments_capture_source()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  NEW.capture_source := COALESCE((SELECT e.capture_source FROM public.processed_events e
                                   WHERE e.id = COALESCE(NEW.entry_event_id, NEW.exit_event_id)), 'rfid');
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cl_journey_segments_capture_source() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER cl_journey_segments_capture_source
  BEFORE INSERT ON public.journey_segments
  FOR EACH ROW EXECUTE FUNCTION public.cl_journey_segments_capture_source();

-- ================================================================ 2. paso al diagnostico de un envio sorteado
-- Identificador del evento: determinista (reprocesar o reintentar no duplica).
CREATE OR REPLACE FUNCTION public.cl_diagnosis_event_id(p_item_id text, p_lpi text, p_scan_at timestamptz)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path = public, extensions
AS $$
  SELECT 'cl:' || md5(p_item_id || '|' || p_lpi || '|'
                      || to_char(p_scan_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US'))
$$;
REVOKE ALL ON FUNCTION public.cl_diagnosis_event_id(text, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;

-- Lecturas de envios sorteados (planes con Diagnostico) que aun no pueden entrar: lugar sin punto dado de alta o punto
-- sin centro postal. Entran con cl_diagnosis_retry_pending al dar de alta el punto o asignarle centro. Sin acceso web.
CREATE TABLE public.cl_diagnosis_pending (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id  uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  carrier_id  uuid NOT NULL,
  sample_id   uuid NOT NULL REFERENCES public.cl_samples(id) ON DELETE CASCADE,
  item_id     text NOT NULL,
  product_id  uuid,
  place_ref   text NOT NULL,
  mode_ref    text,
  scan_at     timestamptz NOT NULL,
  reason      text NOT NULL CHECK (reason IN ('unknown_reading_point','point_without_center')),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX cl_diagnosis_pending_uidx
  ON public.cl_diagnosis_pending (sample_id, place_ref, (COALESCE(mode_ref, '')), scan_at);
CREATE INDEX cl_diagnosis_pending_carrier_idx ON public.cl_diagnosis_pending (account_id, carrier_id, place_ref);
ALTER TABLE public.cl_diagnosis_pending ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cl_diagnosis_pending FROM PUBLIC, anon, authenticated, service_role;

-- Una fila raw por lectura valida del envio en un punto con centro postal (devuelve las filas nuevas). Las lecturas en
-- un lugar desconocido o en un punto sin centro quedan pendientes. Idempotente.
CREATE OR REPLACE FUNCTION public.cl_diagnosis_feed_item(p_d public.cl_deliveries, p_carrier_id uuid, p_sample_id uuid,
                                                         p_item_id text, p_product_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_n integer;
BEGIN
  IF p_d.is_test THEN RETURN 0; END IF;
  INSERT INTO public.rfid_events_raw (account_id, event_id, read_local_datetime, reader_id, tag_id, is_processed,
                                      carrier_id, product_id)
  SELECT DISTINCT ON (x.event_id) p_d.account_id, x.event_id, x.scan_at, x.lpi, p_item_id, false, p_carrier_id,
         p_product_id
    FROM (SELECT public.cl_diagnosis_event_id(p_item_id, rd.reader_id, r.scan_at) AS event_id,
                 r.scan_at, rd.reader_id AS lpi
            FROM public.cl_delivery_rows r
            JOIN public.readers rd ON rd.id = r.reader_id
           WHERE r.delivery_id = p_d.id AND r.item_id = p_item_id AND r.row_reason IS NULL
             AND rd.account_id = p_d.account_id AND rd.postal_center_id IS NOT NULL) x
   ORDER BY x.event_id
  ON CONFLICT (account_id, event_id) DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  INSERT INTO public.cl_diagnosis_pending (account_id, carrier_id, sample_id, item_id, product_id, place_ref, mode_ref,
                                           scan_at, reason)
  SELECT p_d.account_id, p_carrier_id, p_sample_id, p_item_id, p_product_id, left(r.place_ref, 100),
         left(r.mode_ref, 100), r.scan_at,
         CASE WHEN r.row_reason = 'unknown_reading_point' THEN 'unknown_reading_point' ELSE 'point_without_center' END
    FROM public.cl_delivery_rows r
    LEFT JOIN public.readers rd ON rd.id = r.reader_id
   WHERE r.delivery_id = p_d.id AND r.item_id = p_item_id AND r.scan_at IS NOT NULL
     AND ((r.row_reason = 'unknown_reading_point')
          OR (r.row_reason IS NULL AND rd.id IS NOT NULL AND rd.postal_center_id IS NULL))
  ON CONFLICT (sample_id, place_ref, (COALESCE(mode_ref, '')), scan_at) DO NOTHING;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.cl_diagnosis_feed_item(public.cl_deliveries, uuid, uuid, text, uuid) FROM PUBLIC, anon, authenticated, service_role;

-- Entrada tardia: las lecturas pendientes del carrier en la cuenta cuyo lugar ya tiene punto activo con centro postal
-- (misma regla que el proceso: lugar + modo exacto, si no el punto del lugar sin modo) pasan a rfid_events_raw y salen
-- de la lista. Solo muestras activas. Devuelve las filas nuevas en raw.
CREATE OR REPLACE FUNCTION public.cl_diagnosis_retry_pending(p_account_id uuid, p_carrier_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_n integer;
BEGIN
  WITH m AS MATERIALIZED (
    SELECT q.id, q.account_id, q.item_id, q.carrier_id, q.product_id, q.scan_at, rd.reader_id AS lpi
      FROM public.cl_diagnosis_pending q
      JOIN public.cl_samples s ON s.id = q.sample_id AND s.status = 'active'
      JOIN LATERAL (
        SELECT r.id FROM public.readers r
         WHERE r.account_id = q.account_id AND r.capture_source = 'carrier_scan' AND r.carrier_id = q.carrier_id
           AND r.deleted_at IS NULL AND r.is_active IS NOT FALSE AND r.carrier_place_ref = q.place_ref
           AND (r.carrier_mode_ref = q.mode_ref OR r.carrier_mode_ref IS NULL)
         ORDER BY (r.carrier_mode_ref IS NULL), r.id
         LIMIT 1) pt ON true
      JOIN public.readers rd ON rd.id = pt.id AND rd.postal_center_id IS NOT NULL
     WHERE q.account_id = p_account_id AND q.carrier_id = p_carrier_id
  ), ins AS (
    INSERT INTO public.rfid_events_raw (account_id, event_id, read_local_datetime, reader_id, tag_id, is_processed,
                                        carrier_id, product_id)
    SELECT DISTINCT ON (x.event_id) x.account_id, x.event_id, x.scan_at, x.lpi, x.item_id, false, x.carrier_id,
           x.product_id
      FROM (SELECT m.account_id, public.cl_diagnosis_event_id(m.item_id, m.lpi, m.scan_at) AS event_id, m.scan_at,
                   m.lpi, m.item_id, m.carrier_id, m.product_id FROM m) x
     ORDER BY x.event_id
    ON CONFLICT (account_id, event_id) DO NOTHING
    RETURNING 1
  ), del AS (
    DELETE FROM public.cl_diagnosis_pending q WHERE q.id IN (SELECT m.id FROM m)
    RETURNING 1
  )
  SELECT (SELECT count(*) FROM ins)::integer INTO v_n;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.cl_diagnosis_retry_pending(uuid, uuid) FROM PUBLIC, anon, authenticated, service_role;

-- Disparador: un punto de Carrier Link activo con centro postal (alta o cambio) hace entrar lo pendiente de su carrier.
-- Los lectores RFID no disparan nada (WHEN).
CREATE OR REPLACE FUNCTION public.cl_readers_retry_diagnosis()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.postal_center_id IS NOT NULL AND NEW.deleted_at IS NULL AND NEW.is_active IS NOT FALSE
     AND EXISTS (SELECT 1 FROM public.cl_diagnosis_pending q
                  WHERE q.account_id = NEW.account_id AND q.carrier_id = NEW.carrier_id
                    AND q.place_ref = NEW.carrier_place_ref) THEN
    PERFORM public.cl_diagnosis_retry_pending(NEW.account_id, NEW.carrier_id);
  END IF;
  RETURN NULL;
END $$;
REVOKE ALL ON FUNCTION public.cl_readers_retry_diagnosis() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER cl_readers_retry_diagnosis
  AFTER INSERT OR UPDATE ON public.readers
  FOR EACH ROW WHEN (NEW.capture_source = 'carrier_scan')
  EXECUTE FUNCTION public.cl_readers_retry_diagnosis();

-- R36: lecturas validas de los envios ya pasados de planes con Diagnostico en puntos SIN centro postal. No entran;
-- un aviso por entrega y plan con los puntos, las lecturas y los envios afectados. Idempotente (cl_delivery_alert).
CREATE OR REPLACE FUNCTION public.cl_diagnosis_point_alerts(p_d public.cl_deliveries)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_r record;
BEGIN
  IF p_d.is_test THEN RETURN; END IF;
  FOR v_r IN
    SELECT i.plan_id,
           jsonb_agg(DISTINCT jsonb_build_object('reader_id', rd.id, 'name', rd.name, 'place_ref', rd.carrier_place_ref,
                                                 'mode_ref', rd.carrier_mode_ref)) AS points,
           count(*) AS readings, count(DISTINCT i.item_id) AS shipments
      FROM public.cl_delivery_items i
      JOIN public.cl_plans p ON p.id = i.plan_id AND p.feed_diagnosis
      JOIN public.cl_delivery_rows r ON r.delivery_id = i.delivery_id AND r.item_id = i.item_id AND r.row_reason IS NULL
      JOIN public.readers rd ON rd.id = r.reader_id AND rd.postal_center_id IS NULL
     WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NOT NULL
     GROUP BY i.plan_id
     ORDER BY i.plan_id
  LOOP
    PERFORM public.cl_delivery_alert(p_d.id, v_r.plan_id, NULL, 'diagnosis_point_without_center', 'medium',
      jsonb_build_object('points', v_r.points, 'readings', v_r.readings, 'shipments', v_r.shipments));
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.cl_diagnosis_point_alerts(public.cl_deliveries) FROM PUBLIC, anon, authenticated, service_role;

-- Quita del diagnostico los envios p_items (Carrier Link) de la cuenta: lecturas pendientes, filas raw 'cl:', incidencias de consolidacion
-- de esas lecturas, eventos 'carrier' (en cascada sus tramos e incidencias ligadas por evento/tramo) y viajes que se
-- quedan sin eventos. Sirve antes y despues de la consolidacion. Las filas RFID no se tocan (prefijo y origen).
-- Carrera con el ETL: LOCK SHARE de processed_events espera a un ETL en curso que ya haya escrito eventos y frena sus
-- inserciones hasta el COMMIT; un evento que el ETL inserte despues encuentra la muestra anulada y el disparador lo
-- descarta. Solo se bloquea si hay algo de diagnostico de esos envios (planes sin Diagnostico: nada).
CREATE OR REPLACE FUNCTION public.cl_diagnosis_remove(p_account_id uuid, p_items text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_raw integer := 0;
  v_ev  integer := 0;
  v_inc integer := 0;
  v_jr  integer := 0;
BEGIN
  DELETE FROM public.cl_diagnosis_pending q WHERE q.account_id = p_account_id AND q.item_id = ANY (p_items);
  IF COALESCE(cardinality(p_items), 0) = 0
     OR NOT EXISTS (SELECT 1 FROM public.rfid_events_raw w
                     WHERE w.account_id = p_account_id AND w.tag_id = ANY (p_items) AND w.event_id LIKE 'cl:%')
        AND NOT EXISTS (SELECT 1 FROM public.processed_events e
                         WHERE e.account_id = p_account_id AND e.tag_id = ANY (p_items) AND e.capture_source = 'carrier') THEN
    RETURN jsonb_build_object('raw', 0, 'events', 0, 'incidents', 0, 'journeys', 0);
  END IF;
  LOCK TABLE public.processed_events IN SHARE MODE;

  DELETE FROM public.rfid_events_raw w
   WHERE w.account_id = p_account_id AND w.tag_id = ANY (p_items) AND w.event_id LIKE 'cl:%';
  GET DIAGNOSTICS v_raw = ROW_COUNT;
  DELETE FROM public.incidents i
   WHERE i.account_id = p_account_id AND i.tag_id = ANY (p_items)
     AND i.incident_type IN ('unknown_reader', 'unknown_tag') AND i.metadata->>'reader_lpi' LIKE 'CL:%';
  GET DIAGNOSTICS v_inc = ROW_COUNT;
  DELETE FROM public.processed_events e
   WHERE e.account_id = p_account_id AND e.tag_id = ANY (p_items) AND e.capture_source = 'carrier';
  GET DIAGNOSTICS v_ev = ROW_COUNT;
  DELETE FROM public.journeys j
   WHERE j.account_id = p_account_id AND j.tag_id = ANY (p_items)
     AND NOT EXISTS (SELECT 1 FROM public.processed_events e WHERE e.account_id = j.account_id AND e.tag_id = j.tag_id);
  GET DIAGNOSTICS v_jr = ROW_COUNT;
  RETURN jsonb_build_object('raw', v_raw, 'events', v_ev, 'incidents', v_inc, 'journeys', v_jr);
END $$;
REVOKE ALL ON FUNCTION public.cl_diagnosis_remove(uuid, text[]) FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 3. transfer (copia de 20261124200100 + diagnostico)
-- Unicos cambios: tras cl_transfer_sample, si el plan tiene Diagnostico, cl_diagnosis_feed_item (el TODO de la
-- tarea 2); y en el ultimo paso (no quedan elegidos) el aviso R36 de puntos sin centro.
CREATE OR REPLACE FUNCTION public.cl_delivery_phase_transfer(p_d public.cl_deliveries, p_feed public.cl_feeds,
                                                             p_chunk integer)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_it   record;
  v_sid  uuid;
  v_q    public.cl_plan_quotas;
  v_diag boolean;
  v_new  integer := 0;
  v_left boolean;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || p_d.account_id::text || ':' || p_feed.carrier_id::text));
  PERFORM 1 FROM public.cl_plan_quotas q
   WHERE q.id IN (SELECT i.quota_id FROM public.cl_delivery_items i
                   WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NULL)
   ORDER BY q.id FOR UPDATE;

  -- Defensa: un elegido cuya cuota ya no esta pending/open (liquidada por otra via) no se pasa; queda contado en
  -- cl_delivery_strata.skipped_settled (y alerta quota_already_settled en finish). Un elegido que ya tiene muestra de
  -- esta entrega (intento anterior) se enlaza abajo, no se salta.
  UPDATE public.cl_delivery_items i SET skipped_settled = true
   WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NULL AND NOT i.skipped_settled
     AND EXISTS (SELECT 1 FROM public.cl_plan_quotas q WHERE q.id = i.quota_id AND q.status NOT IN ('pending','open'))
     AND NOT EXISTS (SELECT 1 FROM public.cl_samples sm
                      WHERE sm.delivery_id = p_d.id AND sm.item_id = i.item_id AND sm.status = 'active');
  UPDATE public.cl_delivery_strata s SET skipped_settled = x.n
    FROM (SELECT i.quota_id, count(*)::integer AS n FROM public.cl_delivery_items i
           WHERE i.delivery_id = p_d.id AND i.skipped_settled GROUP BY i.quota_id) x
   WHERE s.delivery_id = p_d.id AND s.quota_id = x.quota_id AND s.skipped_settled IS DISTINCT FROM x.n;

  FOR v_it IN SELECT i.* FROM public.cl_delivery_items i
               WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NULL AND NOT i.skipped_settled
               ORDER BY i.quota_id, i.item_id COLLATE "C"
               LIMIT GREATEST(p_chunk, 1)
  LOOP
    SELECT sm.id INTO v_sid FROM public.cl_samples sm
     WHERE sm.delivery_id = p_d.id AND sm.item_id = v_it.item_id AND sm.status = 'active';
    IF v_sid IS NULL THEN
      SELECT q.* INTO v_q FROM public.cl_plan_quotas q WHERE q.id = v_it.quota_id;
      INSERT INTO public.cl_samples (account_id, plan_id, quota_id, delivery_id, carrier_id, product_id, item_id,
                                     start_reader_id, start_at, end_reader_id, end_at, origin_city_id,
                                     destination_city_id, extra)
      VALUES (p_d.account_id, v_it.plan_id, v_it.quota_id, p_d.id, p_feed.carrier_id, v_it.product_id, v_it.item_id,
              v_it.start_reader_id, v_it.start_at, v_it.end_reader_id, v_it.end_at, v_it.start_city_id,
              v_it.end_city_id,
              COALESCE((SELECT jsonb_object_agg(x.key, x.value) FROM (
                          SELECT DISTINCT ON (e.key) e.key, e.value
                            FROM public.cl_delivery_rows r CROSS JOIN LATERAL jsonb_each(COALESCE(r.extra, '{}'::jsonb)) e
                           WHERE r.delivery_id = p_d.id AND r.item_id = v_it.item_id
                           ORDER BY e.key, r.scan_at DESC NULLS LAST, r.row_no DESC) x), '{}'::jsonb))
      RETURNING id INTO v_sid;

      INSERT INTO public.cl_sample_scans (account_id, sample_id, reader_id, scan_at, role, place_ref, mode_ref)
      SELECT p_d.account_id, v_sid, r.reader_id, r.scan_at,
             CASE WHEN r.row_no = v_it.start_row THEN 'start'
                  WHEN r.row_no = v_it.end_row THEN 'end'
                  WHEN rd.e2e_role = 'origin' THEN 'start'
                  WHEN rd.e2e_role = 'destination' THEN 'end'
                  WHEN r.scan_at <= v_it.start_at THEN 'start'
                  ELSE 'end' END,
             r.place_ref, r.mode_ref
        FROM public.cl_delivery_rows r JOIN public.readers rd ON rd.id = r.reader_id
       WHERE r.delivery_id = p_d.id AND r.item_id = v_it.item_id AND r.row_reason IS NULL
         AND rd.e2e_role IN ('origin','destination','both')
       ORDER BY r.row_no;

      UPDATE public.cl_samples sm SET possible_misrouting = true
       WHERE sm.id = v_sid
         AND EXISTS (SELECT 1 FROM public.cl_delivery_rows r
                       JOIN public.readers rd ON rd.id = r.reader_id
                       JOIN public.postal_centers pc ON pc.id = rd.postal_center_id
                      WHERE r.delivery_id = p_d.id AND r.item_id = v_it.item_id AND r.row_reason IS NULL
                        AND rd.e2e_role IN ('origin','destination','both') AND pc.city_id IS NOT NULL
                        AND pc.city_id NOT IN (v_q.origin_city_id, v_q.destination_city_id));

      SELECT p.feed_diagnosis INTO v_diag FROM public.cl_plans p WHERE p.id = v_it.plan_id;

      PERFORM public.cl_transfer_sample(v_sid);
      -- Diagnostico (tarea 7, R33): todas las lecturas validas del envio (tambien las intermedias) al ETL RFID. Aqui,
      -- antes de vaciar la zona de paso, es el unico momento en que existen. Misma transaccion que la muestra.
      IF v_diag THEN
        PERFORM public.cl_diagnosis_feed_item(p_d, p_feed.carrier_id, v_sid, v_it.item_id, v_it.product_id);
      END IF;
      UPDATE public.cl_plan_quotas q SET samples_obtained = q.samples_obtained + 1 WHERE q.id = v_it.quota_id;
      v_new := v_new + 1;
    END IF;
    UPDATE public.cl_delivery_items i SET sample_id = v_sid
     WHERE i.delivery_id = p_d.id AND i.item_id = v_it.item_id;
  END LOOP;

  SELECT EXISTS (SELECT 1 FROM public.cl_delivery_items i
                  WHERE i.delivery_id = p_d.id AND i.drawn AND i.sample_id IS NULL AND NOT i.skipped_settled) INTO v_left;
  IF NOT v_left THEN
    PERFORM public.cl_diagnosis_point_alerts(p_d);
  END IF;
  UPDATE public.cl_deliveries d
     SET progress = d.progress || jsonb_build_object('phase', CASE WHEN v_left THEN 'transfer' ELSE 'finish' END)
   WHERE d.id = p_d.id;
  RETURN 'transfer';
END $$;
REVOKE ALL ON FUNCTION public.cl_delivery_phase_transfer(public.cl_deliveries, public.cl_feeds, integer) FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 4. deshacer una entrega (copia de 20261124200200 + diagnostico)
-- Unico cambio: antes de anular las muestras, cl_diagnosis_remove de sus envios (raw y, si ya se consolido, lo derivado).
CREATE OR REPLACE FUNCTION public.cl_delivery_undo_samples(p_d public.cl_deliveries)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_carrier uuid := (SELECT f.carrier_id FROM public.cl_feeds f WHERE f.id = p_d.feed_id);
  v_n integer;
  v_q uuid[];
  v_r record;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || p_d.account_id::text || ':' || v_carrier::text));
  PERFORM 1 FROM public.cl_plan_quotas q
   WHERE q.id IN (SELECT s.quota_id FROM public.cl_samples s WHERE s.delivery_id = p_d.id AND s.status = 'active')
   ORDER BY q.id FOR UPDATE;

  UPDATE public.cl_alerts a
     SET status = 'dismissed',
         details = COALESCE(a.details, '{}'::jsonb) || jsonb_build_object('dismissed_by_undo_delivery', p_d.id)
   WHERE a.status = 'open' AND a.account_id = p_d.account_id
     AND (a.delivery_id = p_d.id
          OR (a.alert_type = 'missing_standard'
              AND a.details->>'first_sample_id' IN (SELECT s.id::text FROM public.cl_samples s
                                                     WHERE s.delivery_id = p_d.id AND s.status = 'active')));

  DELETE FROM public.one_db o
   USING public.cl_samples s
   WHERE o.cl_sample_id = s.id AND s.delivery_id = p_d.id AND s.status = 'active';

  PERFORM public.cl_diagnosis_remove(p_d.account_id,
            ARRAY(SELECT s.item_id FROM public.cl_samples s WHERE s.delivery_id = p_d.id AND s.status = 'active'));

  WITH v AS (
    UPDATE public.cl_samples SET status = 'voided'
     WHERE delivery_id = p_d.id AND status = 'active'
    RETURNING quota_id
  )
  SELECT COALESCE(array_agg(v.quota_id) FILTER (WHERE v.quota_id IS NOT NULL), '{}'::uuid[]), count(*)::integer
    INTO v_q, v_n FROM v;

  UPDATE public.cl_plan_quotas q SET samples_obtained = GREATEST(q.samples_obtained - c.n, 0)
    FROM (SELECT x AS quota_id, count(*)::integer AS n FROM unnest(v_q) x GROUP BY x) c
   WHERE q.id = c.quota_id;

  FOR v_r IN SELECT q.id, q.plan_id, q.status, q.samples_planned + q.samples_carried_in - q.samples_obtained AS falta
               FROM public.cl_plan_quotas q
              WHERE q.id = ANY (v_q) AND q.status NOT IN ('pending','open')
                AND q.samples_planned + q.samples_carried_in - q.samples_obtained > 0
              ORDER BY q.id
  LOOP
    PERFORM public.cl_raise_alert(v_r.plan_id, v_r.id, 'quota_short_after_undo', 'high',
      jsonb_build_object('delivery_id', p_d.id, 'quota_status', v_r.status, 'missing', v_r.falta));
  END LOOP;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.cl_delivery_undo_samples(public.cl_deliveries) FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 5. reinicio de cuenta: borrar un punto de Carrier Link
-- Los reinicios (admin_reset_account_data / _demo2 / _and_seed_demo2) borran los puntos carrier_scan, pero no
-- processed_events (FK reader_id ON DELETE RESTRICT): sin esto fallarian en cuanto haya diagnostico del carrier.
-- Antes de borrar el punto se borran sus eventos (en cascada tramos e incidencias ligadas), sus filas raw 'cl:' y los
-- viajes que quedan sin eventos. Los lectores RFID no disparan nada (WHEN). Los puntos se dan de baja en la web con
-- deleted_at (no se borran), asi que esto solo actua en los reinicios.
CREATE OR REPLACE FUNCTION public.cl_readers_delete_diagnosis()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_tags text[];
BEGIN
  SELECT COALESCE(array_agg(DISTINCT e.tag_id), '{}'::text[]) INTO v_tags
    FROM public.processed_events e WHERE e.reader_id = OLD.id;
  DELETE FROM public.processed_events e WHERE e.reader_id = OLD.id;
  DELETE FROM public.rfid_events_raw w
   WHERE w.account_id = OLD.account_id AND w.reader_id = OLD.reader_id AND w.event_id LIKE 'cl:%';
  DELETE FROM public.journeys j
   WHERE j.account_id = OLD.account_id AND j.tag_id = ANY (v_tags)
     AND NOT EXISTS (SELECT 1 FROM public.processed_events e WHERE e.account_id = j.account_id AND e.tag_id = j.tag_id);
  RETURN OLD;
END $$;
REVOKE ALL ON FUNCTION public.cl_readers_delete_diagnosis() FROM PUBLIC, anon, authenticated, service_role;

CREATE TRIGGER cl_readers_delete_diagnosis
  BEFORE DELETE ON public.readers
  FOR EACH ROW WHEN (OLD.capture_source = 'carrier_scan')
  EXECUTE FUNCTION public.cl_readers_delete_diagnosis();
