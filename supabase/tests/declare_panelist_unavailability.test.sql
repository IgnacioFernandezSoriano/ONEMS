-- Tarea 7: declare_panelist_unavailability (puerta de entrada n8n) y aviso 'recibido' en altas web.
-- Fechas relativas al "hoy local" del panelista P1 (KENYA): no dependen del dia de la semana ni del mes.
\set ON_ERROR_STOP on

CREATE FUNCTION pg_temp.d(p_start int, p_len int DEFAULT 2, p_reason text DEFAULT 'vacation')
RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.declare_panelist_unavailability(
    'e1000000-0000-0000-0000-000000000001',
    public.panelist_local_today('e1000000-0000-0000-0000-000000000001') + p_start,
    public.panelist_local_today('e1000000-0000-0000-0000-000000000001') + p_start + p_len,
    p_reason);
$$;
CREATE FUNCTION pg_temp.chk(p_ok boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  IF NOT COALESCE(p_ok, false) THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF;
  RAISE NOTICE 'PASS %', p_msg;
END $$;

-- ===== Privilegios =====
DO $$
BEGIN
  PERFORM pg_temp.chk(NOT has_function_privilege('authenticated',
    'public.declare_panelist_unavailability(uuid,date,date,text,text)', 'EXECUTE'), 'authenticated sin EXECUTE');
  PERFORM pg_temp.chk(NOT has_function_privilege('anon',
    'public.declare_panelist_unavailability(uuid,date,date,text,text)', 'EXECUTE'), 'anon sin EXECUTE');
  PERFORM pg_temp.chk(has_function_privilege('service_role',
    'public.declare_panelist_unavailability(uuid,date,date,text,text)', 'EXECUTE'), 'service_role con EXECUTE');
  PERFORM pg_temp.chk(NOT has_function_privilege('authenticated',
    'public.tg_enqueue_unavailability_received()', 'EXECUTE'), 'trigger fn sin EXECUTE para authenticated');
END $$;

-- ===== Exito sin muestras: auto_resolved, sin aviso encolado =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb; t date := public.panelist_local_today('e1000000-0000-0000-0000-000000000001');
BEGIN
  r := pg_temp.d(2, 2);
  PERFORM pg_temp.chk((r->>'ok')::boolean, 'ok');
  PERFORM pg_temp.chk(r->>'start_date' = (t+2)::text AND r->>'end_date' = (t+4)::text, 'fechas devueltas');
  PERFORM pg_temp.chk((r->>'days')::int = 3, 'days = 3');
  PERFORM pg_temp.chk(r->>'incident_status' = 'auto_resolved', 'sin muestras -> auto_resolved');
  PERFORM pg_temp.chk((r->>'affected_samples')::int = 0 AND (r->>'pending_samples')::int = 0, 'sin muestras: 0/0');
  PERFORM pg_temp.chk((r->>'unavailability_id')::uuid IN (SELECT id FROM public.panelist_unavailability
     WHERE reason = 'vacation' AND status = 'active'), 'baja creada');
  PERFORM pg_temp.chk(NOT EXISTS (SELECT 1 FROM public.panelist_notification), 'alta n8n: 0 avisos');
END $$;
ROLLBACK;

-- ===== Limites de fecha: hoy permitido, 90 dias exactos permitido, 91 rechazado =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb;
BEGIN
  r := pg_temp.d(0, 0);
  PERFORM pg_temp.chk((r->>'ok')::boolean AND (r->>'days')::int = 1, 'start == hoy permitido');
END $$;
ROLLBACK;
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb;
BEGIN
  r := pg_temp.d(0, 89);
  PERFORM pg_temp.chk((r->>'ok')::boolean AND (r->>'days')::int = 90, 'exactamente 90 dias permitido');
END $$;
ROLLBACK;
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb;
BEGIN
  r := pg_temp.d(0, 90);
  PERFORM pg_temp.chk(NOT (r->>'ok')::boolean AND r->>'error_code' = 'too_long', '91 dias -> too_long');
  PERFORM pg_temp.chk(NOT EXISTS (SELECT 1 FROM public.panelist_unavailability), 'too_long no crea nada');
END $$;
ROLLBACK;

-- ===== Codigos de error y su orden =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb; t date := public.panelist_local_today('e1000000-0000-0000-0000-000000000001');
  p uuid := 'e1000000-0000-0000-0000-000000000001';
BEGIN
  r := public.declare_panelist_unavailability('99999999-0000-0000-0000-000000000000', t+1, t+2, 'vacation');
  PERFORM pg_temp.chk(NOT (r->>'ok')::boolean AND r->>'error_code' = 'panelist_not_found', 'panelist_not_found (inexistente)');
  -- Panelista inexistente gana a fechas NULL (orden).
  r := public.declare_panelist_unavailability('99999999-0000-0000-0000-000000000000', NULL, NULL, 'bad');
  PERFORM pg_temp.chk(r->>'error_code' = 'panelist_not_found', 'panelist_not_found va primero');
  UPDATE public.panelists SET status = 'inactive' WHERE id = p;
  r := pg_temp.d(1, 1);
  PERFORM pg_temp.chk(r->>'error_code' = 'panelist_not_found', 'panelista no activo -> panelist_not_found');
  UPDATE public.panelists SET status = 'active' WHERE id = p;

  r := public.declare_panelist_unavailability(p, NULL, t+2, 'vacation');
  PERFORM pg_temp.chk(r->>'error_code' = 'no_date', 'start NULL -> no_date');
  r := public.declare_panelist_unavailability(p, t+2, NULL, 'vacation');
  PERFORM pg_temp.chk(r->>'error_code' = 'no_date', 'end NULL -> no_date');
  r := public.declare_panelist_unavailability(p, t+2, t+3, 'nope');
  PERFORM pg_temp.chk(r->>'error_code' = 'bad_reason', 'bad_reason');
  r := public.declare_panelist_unavailability(p, t+2, t+3, NULL);
  PERFORM pg_temp.chk(r->>'error_code' = 'bad_reason', 'reason NULL explicito -> bad_reason');
  r := public.declare_panelist_unavailability(p, t+5, t+3, 'vacation');
  PERFORM pg_temp.chk(r->>'error_code' = 'end_before_start', 'end_before_start');
  r := public.declare_panelist_unavailability(p, t-1, t-3, 'vacation');
  PERFORM pg_temp.chk(r->>'error_code' = 'end_before_start', 'end_before_start va antes que in_past');
  r := public.declare_panelist_unavailability(p, t-1, t+2, 'vacation');
  PERFORM pg_temp.chk(r->>'error_code' = 'in_past', 'in_past con hoy-1');
  r := public.declare_panelist_unavailability(p, t+1, t+200, 'vacation');
  PERFORM pg_temp.chk(r->>'error_code' = 'too_long', 'too_long');
  PERFORM pg_temp.chk(NOT EXISTS (SELECT 1 FROM public.panelist_unavailability), 'errores no crean filas');
END $$;
ROLLBACK;

-- ===== reason por defecto 'other' y 'materials' aceptado; notas =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb; t date := public.panelist_local_today('e1000000-0000-0000-0000-000000000001');
BEGIN
  r := public.declare_panelist_unavailability('e1000000-0000-0000-0000-000000000001', t+1, t+2);
  PERFORM pg_temp.chk((r->>'ok')::boolean, 'defaults ok');
  PERFORM pg_temp.chk((SELECT reason FROM public.panelist_unavailability WHERE id = (r->>'unavailability_id')::uuid) = 'other',
    'reason por defecto other');
  r := public.declare_panelist_unavailability('e1000000-0000-0000-0000-000000000001', t+10, t+11, 'materials', 'sin sobres');
  PERFORM pg_temp.chk((r->>'ok')::boolean, 'materials aceptado');
  PERFORM pg_temp.chk((SELECT notes FROM public.panelist_unavailability WHERE id = (r->>'unavailability_id')::uuid) = 'sin sobres',
    'notas guardadas');
END $$;
ROLLBACK;

-- ===== Solape: devuelve ov_start/ov_end y no crea nada =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb; t date := public.panelist_local_today('e1000000-0000-0000-0000-000000000001');
BEGIN
  r := pg_temp.d(5, 3);
  PERFORM pg_temp.chk((r->>'ok')::boolean, 'primera baja');
  r := pg_temp.d(7, 4);
  PERFORM pg_temp.chk(NOT (r->>'ok')::boolean AND r->>'error_code' = 'overlap', 'solape -> overlap');
  PERFORM pg_temp.chk(r->>'ov_start' = (t+5)::text AND r->>'ov_end' = (t+8)::text, 'ov_start/ov_end de la baja existente');
  PERFORM pg_temp.chk((SELECT count(*) FROM public.panelist_unavailability) = 1, 'overlap no crea nada');
  r := pg_temp.d(6, 0);
  PERFORM pg_temp.chk(r->>'error_code' = 'overlap', 'contenida -> overlap');
  r := pg_temp.d(3, 10);
  PERFORM pg_temp.chk(r->>'error_code' = 'overlap', 'envolvente -> overlap');
  UPDATE public.panelist_unavailability SET status = 'cancelled';
  r := pg_temp.d(5, 3);
  PERFORM pg_temp.chk((r->>'ok')::boolean, 'baja cancelada no solapa');
END $$;
ROLLBACK;

-- ===== Con muestra dentro: affected_samples = 1 =====
BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE r jsonb; t date := public.panelist_local_today('e1000000-0000-0000-0000-000000000001');
BEGIN
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  VALUES ('d0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
          'cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001',
          'b4000000-0000-0000-0000-000000000004', t+3, 'pending');
  r := pg_temp.d(2, 3);
  PERFORM pg_temp.chk((r->>'ok')::boolean, 'ok con muestra');
  PERFORM pg_temp.chk((r->>'affected_samples')::int = 1, 'affected_samples = 1');
  PERFORM pg_temp.chk((r->>'pending_samples')::int
     = (SELECT count(*) FROM public.panelist_reassignment_proposal
         WHERE unavailability_id = (r->>'unavailability_id')::uuid AND status = 'pending'), 'pending_samples coherente');
  PERFORM pg_temp.chk(r->>'incident_status' = (SELECT incident_status FROM public.panelist_unavailability
         WHERE id = (r->>'unavailability_id')::uuid), 'incident_status coherente con la fila');
  PERFORM pg_temp.chk(r->>'incident_status' <> 'new', 'el motor ya corrio');
END $$;
ROLLBACK;

-- ===== Alta web: exactamente 1 aviso 'unavailability_received' =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000099', true);
DO $$
DECLARE t date := public.panelist_local_today('e1000000-0000-0000-0000-000000000001'); n record;
BEGIN
  INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
  VALUES ('f0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001',
          'e1000000-0000-0000-0000-000000000001', t+2, t+4, 'vacation', 'active');
  PERFORM pg_temp.chk((SELECT count(*) FROM public.panelist_notification WHERE kind = 'unavailability_received') = 1,
    'alta web: 1 aviso');
  SELECT * INTO n FROM public.panelist_notification WHERE kind = 'unavailability_received';
  PERFORM pg_temp.chk(n.panelist_id = 'e1000000-0000-0000-0000-000000000001'
    AND n.account_id = 'a0000000-0000-0000-0000-000000000001'
    AND n.payload->>'unavailability_id' = 'f0000000-0000-0000-0000-000000000001'
    AND n.payload->>'start_date' = (t+2)::text AND n.payload->>'end_date' = (t+4)::text, 'payload y cuenta del aviso');
  INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status)
  VALUES ('f0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',
          'e1000000-0000-0000-0000-000000000001', t+20, t+21, 'vacation', 'cancelled');
  PERFORM pg_temp.chk((SELECT count(*) FROM public.panelist_notification WHERE kind = 'unavailability_received') = 1,
    'alta no activa: sin aviso');
END $$;
ROLLBACK;

-- ===== Alta web con supresion: sin aviso =====
BEGIN;
\ir fixtures/incident_city.sql
SELECT set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000099', true);
SELECT set_config('onems.suppress_notifications', 'on', true);
DO $$
DECLARE t date := public.panelist_local_today('e1000000-0000-0000-0000-000000000001');
BEGIN
  INSERT INTO public.panelist_unavailability (account_id, panelist_id, start_date, end_date, reason, status)
  VALUES ('a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001', t+2, t+4, 'vacation', 'active');
  PERFORM pg_temp.chk(NOT EXISTS (SELECT 1 FROM public.panelist_notification), 'supresion: sin aviso');
END $$;
ROLLBACK;
