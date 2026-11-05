-- ============================================================
-- Datos de prueba del agente de operaciones (fase 2) — 2026-11-05
-- ============================================================
-- Cada mañana el agente prepara en DEMO2 un envío y una recepción de prueba para el panelista de
-- prueba (PAN-DEM-004), recorre el bot de panelistas y lo borra todo. Estas funciones son lo único
-- que puede escribir: solo actúan sobre DEMO2, ese panelista y el plan "OPS-AGENT pruebas
-- automáticas (no tocar)". Las llama el agente con la clave pública (anon) más un token propio,
-- cuyo hash se guarda a mano en ops_test.secret (nunca en este archivo).
-- Guardarraíles: tope de 3 preparaciones al día (G4) y vigilante de efectos inesperados (G5).
-- ============================================================

CREATE SCHEMA IF NOT EXISTS ops_test;
REVOKE ALL ON SCHEMA ops_test FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS ops_test.secret (token_sha256 text NOT NULL);

CREATE TABLE IF NOT EXISTS ops_test.config (
  id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  account_id uuid NOT NULL,
  tester_panelist_id uuid NOT NULL,
  tester_telegram_id text NOT NULL,
  peer_panelist_id uuid NOT NULL,
  send_tag text NOT NULL,
  receive_tag text NOT NULL,
  fixture_date date NOT NULL,
  plan_name text NOT NULL,
  max_per_day int NOT NULL
);
INSERT INTO ops_test.config VALUES (1,
  'f4d823d2-93e6-4755-9a89-9da87e7fa86e',  -- DEMO2
  'ed98f175-853d-4a6b-a2fd-0c6d5641fd99',  -- PAN-DEM-004 (panelista de prueba)
  '7014977036',                            -- su telegram_id, fijado aqui (panelist_context no tiene cuenta)
  '9ba5739f-defd-4f3e-8bcd-f29bbec20eed',  -- PAN-DEM-003 (el otro extremo de los envíos)
  '73915086', '73915087', DATE '2020-01-06',  -- fecha que ningun dato real usa (revision I1)
  'OPS-AGENT pruebas automáticas (no tocar)', 3)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS ops_test.state (
  id int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  plan_id uuid,
  prepared_at timestamptz,
  prep_day date,
  prep_count int NOT NULL DEFAULT 0
);
INSERT INTO ops_test.state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

REVOKE ALL ON ALL TABLES IN SCHEMA ops_test FROM PUBLIC, anon, authenticated;

-- ---------- internas ----------
CREATE OR REPLACE FUNCTION ops_test._check(p_token text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  IF p_token IS NULL OR NOT EXISTS (
       SELECT 1 FROM ops_test.secret s
        WHERE s.token_sha256 = encode(extensions.digest(p_token, 'sha256'), 'hex')) THEN
    RAISE EXCEPTION 'ops_test: token no valido';
  END IF;
END $$;

-- Telegram del panelista de prueba, comprobado: panelist_context no lleva account_id, asi que solo
-- se borra si el panelista de DEMO2 sigue teniendo el telegram fijado y nadie de otra cuenta lo usa.
CREATE OR REPLACE FUNCTION ops_test._tester_telegram()
RETURNS text LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE c ops_test.config;
BEGIN
  SELECT * INTO c FROM ops_test.config WHERE id = 1;
  IF NOT EXISTS (SELECT 1 FROM public.panelists p
                  WHERE p.id = c.tester_panelist_id AND p.account_id = c.account_id
                    AND p.telegram_id = c.tester_telegram_id)
     OR EXISTS (SELECT 1 FROM public.panelists p
                 WHERE p.telegram_id = c.tester_telegram_id AND p.id <> c.tester_panelist_id) THEN
    RAISE EXCEPTION 'ops_test: el telegram del panelista de prueba no coincide o lo usa otro panelista; no toco nada';
  END IF;
  RETURN c.tester_telegram_id;
END $$;

-- Plan de prueba: se crea la primera vez (no en la migración, para no depender de los datos).
CREATE OR REPLACE FUNCTION ops_test._plan_id()
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE c ops_test.config; v_id uuid; v_prod record;
BEGIN
  SELECT * INTO c FROM ops_test.config WHERE id = 1;
  SELECT s.plan_id INTO v_id FROM ops_test.state s
    JOIN public.allocation_plans p ON p.id = s.plan_id AND p.account_id = c.account_id
   WHERE s.id = 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  SELECT pr.id, pr.carrier_id INTO v_prod FROM public.products pr
   WHERE pr.account_id = c.account_id AND pr.carrier_id IS NOT NULL
     AND pr.code NOT ILIKE '%pobox%' AND coalesce(pr.description, '') NOT ILIKE '%pobox%'
   ORDER BY pr.code LIMIT 1;
  IF v_prod.id IS NULL THEN
    RAISE EXCEPTION 'ops_test: DEMO2 no tiene ningun producto que no sea POBOX';
  END IF;
  INSERT INTO public.allocation_plans (account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status)
  VALUES (c.account_id, c.plan_name, v_prod.carrier_id, v_prod.id, 2, c.fixture_date, c.fixture_date, 'archived')
  RETURNING id INTO v_id;
  UPDATE ops_test.state SET plan_id = v_id WHERE id = 1;
  RETURN v_id;
END $$;

-- Lo creado por las pruebas que se espera (envío, recepción, incidencia "paquete dañado").
CREATE OR REPLACE FUNCTION ops_test._expected_incidents()
RETURNS SETOF uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT i.id FROM public.panelist_incident i, ops_test.config c, ops_test.state s
   WHERE c.id = 1 AND s.id = 1 AND s.prepared_at IS NOT NULL
     AND i.account_id = c.account_id AND i.panelist_id = c.tester_panelist_id
     AND i.category = 'parcel_damaged' AND i.created_via = 'telegram'
     AND i.created_at >= s.prepared_at
$$;

CREATE OR REPLACE FUNCTION ops_test._reset()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE c ops_test.config; s ops_test.state; v_tg text; v_inc uuid[]; n int;
        n_one int := 0; n_rc int := 0; n_msg int := 0; n_inc int := 0; n_ntf int := 0; n_ctx int := 0; n_det int := 0;
BEGIN
  SELECT * INTO c FROM ops_test.config WHERE id = 1;
  SELECT * INTO s FROM ops_test.state WHERE id = 1;
  v_tg := ops_test._tester_telegram();

  IF s.plan_id IS NOT NULL THEN
    DELETE FROM public.one_db o USING public.allocation_plan_details d
     WHERE o.allocation_detail_id = d.id AND d.plan_id = s.plan_id AND d.account_id = c.account_id;
    GET DIAGNOSTICS n_one = ROW_COUNT;
    DELETE FROM public.receipt_case r USING public.allocation_plan_details d
     WHERE r.detail_id = d.id AND d.plan_id = s.plan_id AND d.account_id = c.account_id;
    GET DIAGNOSTICS n_rc = ROW_COUNT;
  END IF;

  IF s.prepared_at IS NOT NULL THEN
    DELETE FROM public.receipt_case r
     WHERE r.account_id = c.account_id AND r.telegram_id = v_tg AND r.created_at >= s.prepared_at;
    GET DIAGNOSTICS n = ROW_COUNT; n_rc := n_rc + n;
    v_inc := ARRAY(SELECT ops_test._expected_incidents());
    DELETE FROM public.incident_message m WHERE m.account_id = c.account_id AND m.incident_id = ANY (v_inc);
    GET DIAGNOSTICS n_msg = ROW_COUNT;
    DELETE FROM public.panelist_incident i WHERE i.id = ANY (v_inc);
    GET DIAGNOSTICS n_inc = ROW_COUNT;
    DELETE FROM public.panelist_notification x
     WHERE x.account_id = c.account_id AND x.panelist_id = c.tester_panelist_id AND x.created_at >= s.prepared_at;
    GET DIAGNOSTICS n_ntf = ROW_COUNT;
  END IF;

  IF v_tg IS NOT NULL THEN
    DELETE FROM public.panelist_context x WHERE x.telegram_id = v_tg;
    GET DIAGNOSTICS n_ctx = ROW_COUNT;
  END IF;

  IF s.plan_id IS NOT NULL THEN
    DELETE FROM public.allocation_plan_details d WHERE d.plan_id = s.plan_id AND d.account_id = c.account_id;
    GET DIAGNOSTICS n_det = ROW_COUNT;
  END IF;

  UPDATE ops_test.state SET prepared_at = NULL WHERE id = 1;
  RETURN jsonb_build_object('one_db', n_one, 'receipt_case', n_rc, 'incident_message', n_msg,
                            'panelist_incident', n_inc, 'panelist_notification', n_ntf,
                            'panelist_context', n_ctx, 'allocation_plan_details', n_det);
END $$;

-- ---------- públicas (las llama el agente) ----------
CREATE OR REPLACE FUNCTION public.ops_test_prepare(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE c ops_test.config; v_plan uuid; v_today date; v_cnt int; v_day date;
        v_tester public.panelists; v_peer public.panelists; v_send uuid; v_recv uuid; v_now timestamptz := now();
BEGIN
  PERFORM ops_test._check(p_token);
  SELECT * INTO c FROM ops_test.config WHERE id = 1;

  -- G4: tope diario
  v_today := (v_now AT TIME ZONE 'Europe/Madrid')::date;
  SELECT prep_day, prep_count INTO v_day, v_cnt FROM ops_test.state WHERE id = 1 FOR UPDATE;
  IF v_day = v_today AND v_cnt >= c.max_per_day THEN
    RAISE EXCEPTION 'ops_test: tope diario de % preparaciones', c.max_per_day;
  END IF;

  PERFORM ops_test._reset();
  v_plan := ops_test._plan_id();

  SELECT * INTO v_tester FROM public.panelists WHERE id = c.tester_panelist_id AND account_id = c.account_id;
  SELECT * INTO v_peer FROM public.panelists WHERE id = c.peer_panelist_id AND account_id = c.account_id;
  IF v_tester.node_id IS NULL OR v_peer.node_id IS NULL THEN
    RAISE EXCEPTION 'ops_test: faltan el panelista de prueba o su pareja en DEMO2';
  END IF;
  IF EXISTS (SELECT 1 FROM public.allocation_plan_details d
              WHERE d.account_id = c.account_id AND btrim(d.tag_id) IN (c.send_tag, c.receive_tag)) THEN
    RAISE EXCEPTION 'ops_test: las etiquetas de prueba ya estan usadas en DEMO2';
  END IF;
  -- El agente elige la fila de la lista por su fecha: si otro envio del panelista de prueba la comparte, podria
  -- pulsar ese y marcarlo como enviado. Antes de eso, no prepara.
  IF EXISTS (SELECT 1 FROM public.allocation_plan_details d
              WHERE d.account_id = c.account_id AND d.fecha_programada = c.fixture_date
                AND v_tester.node_id IN (d.origin_node_id, d.destination_node_id)) THEN
    RAISE EXCEPTION 'ops_test: ya hay otro envío de DEMO2 con la fecha de prueba %; no preparo', to_char(c.fixture_date, 'DD/MM/YYYY');
  END IF;

  INSERT INTO public.allocation_plan_details
    (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, generation_source)
  VALUES (c.account_id, v_plan, v_tester.node_id, v_peer.node_id, c.fixture_date, 'pending', 'plan')
  RETURNING id INTO v_send;

  INSERT INTO public.allocation_plan_details
    (account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, generation_source,
     tag_id, idtag, sent_at, sent_date, origin_panelist_id, destination_panelist_id)
  VALUES (c.account_id, v_plan, v_peer.node_id, v_tester.node_id, c.fixture_date, 'sent', 'plan',
          c.receive_tag, c.receive_tag, v_now - interval '1 day', v_now - interval '1 day', v_peer.id, v_tester.id)
  RETURNING id INTO v_recv;

  UPDATE ops_test.state
     SET prepared_at = v_now,
         prep_count = CASE WHEN prep_day = v_today THEN prep_count + 1 ELSE 1 END,
         prep_day = v_today
   WHERE id = 1;

  RETURN jsonb_build_object(
    'send_tag', c.send_tag, 'receive_tag', c.receive_tag,
    'send_date', to_char(c.fixture_date, 'DD/MM/YYYY'), 'receive_date', to_char(c.fixture_date, 'DD/MM/YYYY'),
    'send_detail_id', v_send, 'receive_detail_id', v_recv, 'prepared_at', v_now);
END $$;

CREATE OR REPLACE FUNCTION public.ops_test_status(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE c ops_test.config; s ops_test.state; v_send record; v_recv record; v_one boolean; v_inc uuid[];
        v_unexp text[] := '{}'; n int;
BEGIN
  PERFORM ops_test._check(p_token);
  SELECT * INTO c FROM ops_test.config WHERE id = 1;
  SELECT * INTO s FROM ops_test.state WHERE id = 1;

  SELECT d.id, d.status, d.tag_id INTO v_send FROM public.allocation_plan_details d
   WHERE d.plan_id = s.plan_id AND d.account_id = c.account_id
     AND d.origin_node_id = (SELECT node_id FROM public.panelists WHERE id = c.tester_panelist_id) LIMIT 1;
  SELECT d.id, d.status INTO v_recv FROM public.allocation_plan_details d
   WHERE d.plan_id = s.plan_id AND d.account_id = c.account_id
     AND d.destination_node_id = (SELECT node_id FROM public.panelists WHERE id = c.tester_panelist_id) LIMIT 1;
  v_one := v_recv.id IS NOT NULL AND EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = v_recv.id);
  v_inc := ARRAY(SELECT ops_test._expected_incidents());

  -- G5: lo que no debería haber aparecido en DEMO2 desde la preparación
  IF s.prepared_at IS NOT NULL THEN
    SELECT count(*) INTO n FROM public.panelist_notification x WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at;
    IF n > 0 THEN v_unexp := v_unexp || (n || ' avisos a panelistas (panelist_notification)'); END IF;
    SELECT count(*) INTO n FROM public.receipt_case x WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at;
    IF n > 0 THEN v_unexp := v_unexp || (n || ' casos de recepción (receipt_case)'); END IF;
    SELECT count(*) INTO n FROM public.panelist_incident x
     WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at AND NOT (x.id = ANY (v_inc));
    IF n > 0 THEN v_unexp := v_unexp || (n || ' incidencias no esperadas (panelist_incident)'); END IF;
    SELECT count(*) INTO n FROM public.incident_message x
     WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at
       AND NOT (coalesce(x.incident_id = ANY (v_inc), false) OR coalesce(x.meta ? 'report_flow', false));
    IF n > 0 THEN v_unexp := v_unexp || (n || ' mensajes de incidencia (incident_message)'); END IF;
    SELECT count(*) INTO n FROM public.material_shipments x WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at;
    IF n > 0 THEN v_unexp := v_unexp || (n || ' envíos de material (material_shipments)'); END IF;
    -- Envios del panelista de prueba que NO son de prueba y han cambiado (p. ej. el agente pulso la fila
    -- equivocada). Lo unico esperado: el bot pasa a 'notified' sus envios pendientes al enseñar la lista.
    SELECT count(*) INTO n FROM public.allocation_plan_details x
     WHERE x.account_id = c.account_id AND x.plan_id IS DISTINCT FROM s.plan_id AND x.updated_at >= s.prepared_at
       AND (SELECT node_id FROM public.panelists WHERE id = c.tester_panelist_id) IN (x.origin_node_id, x.destination_node_id)
       AND NOT (x.status = 'notified' AND x.origin_node_id = (SELECT node_id FROM public.panelists WHERE id = c.tester_panelist_id));
    IF n > 0 THEN v_unexp := v_unexp || (n || ' envíos de DEMO2 que no son de prueba han cambiado (allocation_plan_details)'); END IF;
    SELECT count(*) INTO n FROM public.deferred_samples x WHERE x.account_id = c.account_id AND x.created_at >= s.prepared_at;
    IF n > 0 THEN v_unexp := v_unexp || (n || ' muestras apartadas al registro (deferred_samples)'); END IF;
  END IF;

  RETURN jsonb_build_object(
    'send_status', v_send.status, 'send_tag', v_send.tag_id, 'receive_status', v_recv.status,
    'one_db', v_one, 'incident', cardinality(v_inc) > 0, 'unexpected', to_jsonb(v_unexp));
END $$;

CREATE OR REPLACE FUNCTION public.ops_test_reset(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
BEGIN
  PERFORM ops_test._check(p_token);
  RETURN ops_test._reset();
END $$;

-- ---------- permisos ----------
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ops_test FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_test_prepare(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_test_status(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.ops_test_reset(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_test_prepare(text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_test_status(text) TO anon;
GRANT EXECUTE ON FUNCTION public.ops_test_reset(text) TO anon;
