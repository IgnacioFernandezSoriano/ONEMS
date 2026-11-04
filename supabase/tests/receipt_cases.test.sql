-- Errores de recepcion: registro de casos y recepcion del bot con arreglo automatico (spec 2026-11-04, tarea 1).
-- Fixture comun: C1 (N1,N2,N3) y C2 (N4). Receptor = P4 en N4/C2 con telegram_id '4004'. Cuenta en Africa/Nairobi.
-- POBOX desactivado salvo en el caso 7.
\set ON_ERROR_STOP on
CREATE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL %', p_msg; END IF; END $$;
CREATE FUNCTION pg_temp.setup() RETURNS void LANGUAGE sql AS $$
  UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
  UPDATE public.panelists SET telegram_id = ' 4004 ' WHERE id = 'e4000000-0000-0000-0000-000000000004';
$$;
CREATE FUNCTION pg_temp.pobox_on() RETURNS void LANGUAGE sql AS $$
  INSERT INTO public.account_config (account_id, pobox_enabled)
  VALUES ('a0000000-0000-0000-0000-000000000001', true)
  ON CONFLICT (account_id) DO UPDATE SET pobox_enabled = true;
$$;
-- Detalle con estado, etiqueta y sent_at; panelistas = el primero de cada nodo.
CREATE FUNCTION pg_temp.mk_det(p_o text, p_d text, p_status text, p_tag text,
                               p_sent timestamptz DEFAULT now() - interval '2 days') RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO public.allocation_plan_details
    (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status, sent_at, tag_id,
     origin_panelist_id, destination_panelist_id)
  SELECT gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001', o.id, d.id,
         p_sent::date, p_status, CASE WHEN p_status = 'sent' THEN p_sent END, p_tag,
         (SELECT id FROM public.panelists WHERE node_id = o.id ORDER BY panelist_code LIMIT 1),
         (SELECT id FROM public.panelists WHERE node_id = d.id ORDER BY panelist_code LIMIT 1)
    FROM public.nodes o, public.nodes d
   WHERE o.auto_id = p_o AND d.auto_id = p_d
  RETURNING id;
$$;
CREATE FUNCTION pg_temp.n_cases() RETURNS bigint LANGUAGE sql AS $$ SELECT count(*) FROM public.receipt_case $$;
CREATE FUNCTION pg_temp.n_deferred() RETURNS bigint LANGUAGE sql AS $$ SELECT count(*) FROM public.deferred_samples $$;

-- ===== Caso 1: etiqueta correcta -> ok, recibido, sin caso
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r jsonb; d record;
BEGIN
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'ok', 'c1 outcome ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM true, 'c1 registered');
  PERFORM pg_temp.fail_if(r->>'language' IS DISTINCT FROM 'en', 'c1 language');
  PERFORM pg_temp.fail_if(r->>'tag' IS DISTINCT FROM '00012345', 'c1 tag');
  PERFORM pg_temp.fail_if(r->>'origin_name' IS DISTINCT FROM 'Pan1', 'c1 origin_name');
  PERFORM pg_temp.fail_if(r->>'origin_city' IS DISTINCT FROM 'City1', 'c1 origin_city');
  PERFORM pg_temp.fail_if(r->>'case_id' IS NOT NULL, 'c1 case_id');
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.status <> 'received', 'c1 status ' || d.status);
  PERFORM pg_temp.fail_if(d.received_at IS NULL, 'c1 received_at');
  PERFORM pg_temp.fail_if(d.destination_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004', 'c1 dest panelist');
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 0, 'c1 casos ' || pg_temp.n_cases());
END $$;
ROLLBACK;

-- ===== Caso 2: dos cifras adyacentes intercambiadas -> ok_typo_fixed, culpa del remitente
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r jsonb; d record; c record;
BEGIN
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  r := public.bot_receive_parcel('4004', '00012354');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'ok_typo_fixed', 'c2 outcome ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM true, 'c2 registered');
  PERFORM pg_temp.fail_if(r->>'origin_name' IS DISTINCT FROM 'Pan1', 'c2 origin_name');
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.tag_id IS DISTINCT FROM '00012354', 'c2 tag_id ' || d.tag_id);
  PERFORM pg_temp.fail_if(d.idtag IS DISTINCT FROM '00012354', 'c2 idtag ' || coalesce(d.idtag, 'NULL'));
  PERFORM pg_temp.fail_if(d.status <> 'received', 'c2 status ' || d.status);
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1, 'c2 casos');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.id::text IS DISTINCT FROM r->>'case_id', 'c2 case_id');
  PERFORM pg_temp.fail_if(c.reason <> 'ok_typo_fixed' OR c.status <> 'fixed', 'c2 caso ' || c.reason || '/' || c.status);
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'sender', 'c2 culprit_role');
  PERFORM pg_temp.fail_if(c.culprit_panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c2 culprit');
  PERFORM pg_temp.fail_if(c.detail_id IS DISTINCT FROM v, 'c2 detail_id');
  PERFORM pg_temp.fail_if(c.panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004', 'c2 panelist_id');
  PERFORM pg_temp.fail_if(c.tag_raw <> '00012354' OR c.tag_norm IS DISTINCT FROM '00012354', 'c2 tags');
  PERFORM pg_temp.fail_if(c.original_tag IS DISTINCT FROM '00012345', 'c2 original_tag ' || coalesce(c.original_tag, 'NULL'));
  PERFORM pg_temp.fail_if(c.resolved_at IS NULL, 'c2 resolved_at');
  PERFORM pg_temp.fail_if(c.attempts <> 1, 'c2 attempts');
END $$;
ROLLBACK;

-- ===== Caso 3: una cifra distinta -> ok_typo_fixed
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r jsonb;
BEGIN
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  r := public.bot_receive_parcel('4004', '00012395');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'ok_typo_fixed', 'c3 outcome ' || r::text);
  PERFORM pg_temp.fail_if((SELECT tag_id FROM public.allocation_plan_details WHERE id = v) IS DISTINCT FROM '00012395', 'c3 tag');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'received', 'c3 status');
  PERFORM pg_temp.fail_if((SELECT original_tag FROM public.receipt_case) IS DISTINCT FROM '00012345', 'c3 original_tag');
  -- Dos cifras distintas no adyacentes / no intercambiadas: ningun candidato
  PERFORM pg_temp.mk_det('N1', 'N4', 'sent', '00055555');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.receipt_typo_candidates('a0000000-0000-0000-0000-000000000001',
                            'c2000000-0000-0000-0000-000000000002', '00055566', now())), 'c3 dos cifras no es typo');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.receipt_typo_candidates('a0000000-0000-0000-0000-000000000001',
                            'c2000000-0000-0000-0000-000000000002', '00055555', now())), 'c3 nunca la misma etiqueta');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.receipt_typo_candidates('a0000000-0000-0000-0000-000000000001',
                            'c1000000-0000-0000-0000-000000000001', '00055556', now())), 'c3 otra ciudad no es candidata');
  -- Declarado despues de la hora de recepcion: no es candidato
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM public.receipt_typo_candidates('a0000000-0000-0000-0000-000000000001',
                            'c2000000-0000-0000-0000-000000000002', '00055556', now())), 'c3 candidato con hora actual');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.receipt_typo_candidates('a0000000-0000-0000-0000-000000000001',
                            'c2000000-0000-0000-0000-000000000002', '00055556', now() - interval '3 days')), 'c3 declarado despues');
END $$;
ROLLBACK;

-- ===== Caso 4: dos candidatos -> ambiguous_typo, nada cambia, needs_decision
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v1 uuid; v2 uuid; r jsonb; c record;
BEGIN
  v1 := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  v2 := pg_temp.mk_det('N2', 'N4', 'sent', '00012347');
  r := public.bot_receive_parcel('4004', '00012346');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'ambiguous_typo', 'c4 outcome ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM false, 'c4 registered');
  PERFORM pg_temp.fail_if((SELECT tag_id FROM public.allocation_plan_details WHERE id = v1) <> '00012345', 'c4 tag1');
  PERFORM pg_temp.fail_if((SELECT tag_id FROM public.allocation_plan_details WHERE id = v2) <> '00012347', 'c4 tag2');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE status <> 'sent'), 'c4 estados');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status IS DISTINCT FROM 'needs_decision' OR c.reason <> 'ambiguous_typo', 'c4 caso');
  PERFORM pg_temp.fail_if(c.culprit_role IS NOT NULL OR c.detail_id IS NOT NULL OR c.resolved_at IS NOT NULL, 'c4 sin atribuir');
END $$;
ROLLBACK;

-- ===== Caso 5: recibido antes de declararse el envio -> anulado y por compensar
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r jsonb; d record; c record; s record;
BEGIN
  v := pg_temp.mk_det('N1', 'N4', 'pending', '00012345');
  r := public.bot_receive_parcel('4004', '00012345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_sent_cancelled', 'c5 outcome ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM false, 'c5 registered');
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.status <> 'cancelled', 'c5 status ' || d.status);
  PERFORM pg_temp.fail_if(d.cancellation_reason IS DISTINCT FROM 'receipt_before_sent', 'c5 reason');
  PERFORM pg_temp.fail_if(d.cancelled_at IS NULL, 'c5 cancelled_at');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 1, 'c5 deferred');
  SELECT * INTO s FROM public.deferred_samples;
  PERFORM pg_temp.fail_if(s.reason <> 'receipt_before_sent', 'c5 ds.reason');
  PERFORM pg_temp.fail_if(s.origin_city_id <> 'c1000000-0000-0000-0000-000000000001'
                          OR s.dest_city_id <> 'c2000000-0000-0000-0000-000000000002', 'c5 ds ciudades');
  PERFORM pg_temp.fail_if((s.row_snapshot->>'id')::uuid IS DISTINCT FROM v, 'c5 ds snapshot');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status IS DISTINCT FROM 'compensated' OR c.reason <> 'not_sent_cancelled', 'c5 caso');
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'sender'
                          OR c.culprit_panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c5 culprit');
END $$;
ROLLBACK;

-- ===== Caso 6a: el envio iba a otro nodo de la misma ciudad -> se mueve el destino y se registra
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N5');
DO $$
DECLARE v uuid; r jsonb; d record; c record;
BEGIN
  v := pg_temp.mk_det('N1', 'N5', 'sent', '00012345');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'ok_same_city', 'c6a outcome ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM true, 'c6a registered');
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.status <> 'received', 'c6a status ' || d.status);
  PERFORM pg_temp.fail_if(d.destination_node_id IS DISTINCT FROM 'b4000000-0000-0000-0000-000000000004', 'c6a destino');
  PERFORM pg_temp.fail_if(d.original_destination_node_id IS DISTINCT FROM 'b5000000-0000-0000-0000-000000000005', 'c6a original');
  PERFORM pg_temp.fail_if(d.destination_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004'
                          OR d.destination_panelist_name IS DISTINCT FROM 'Pan4', 'c6a panelista destino');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status IS DISTINCT FROM 'fixed' OR c.reason <> 'ok_same_city', 'c6a caso');
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'sender', 'c6a culprit');
END $$;
ROLLBACK;

-- ===== Caso 6b: la etiqueta es la de un envio hacia otra ciudad -> other_city_tag: el envio NO se toca (puede ser un
-- tecleo que acierta un envio sano en transito), sin compensar; caso needs_decision sin envio ni culpable, sin recordatorio
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r jsonb; c record; d record; d0 record;
BEGIN
  v := pg_temp.mk_det('N4', 'N1', 'sent', '00012345');
  SELECT * INTO d0 FROM public.allocation_plan_details WHERE id = v;
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'other_city_tag', 'c6b outcome ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM false, 'c6b registered');
  PERFORM pg_temp.fail_if(r->>'case_id' IS NULL, 'c6b case_id');
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.status <> 'sent' OR d.cancellation_reason IS NOT NULL OR d.received_at IS NOT NULL, 'c6b envio intacto (estado)');
  PERFORM pg_temp.fail_if(d.destination_node_id IS DISTINCT FROM d0.destination_node_id
                          OR d.original_destination_node_id IS NOT NULL
                          OR d.destination_panelist_id IS DISTINCT FROM d0.destination_panelist_id
                          OR d.tag_id IS DISTINCT FROM '00012345' OR d.idtag IS DISTINCT FROM d0.idtag, 'c6b envio intacto (destino/etiqueta)');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c6b sin deferred');
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1, 'c6b un caso');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.id::text IS DISTINCT FROM r->>'case_id', 'c6b mismo case_id');
  PERFORM pg_temp.fail_if(c.status IS DISTINCT FROM 'needs_decision' OR c.reason IS DISTINCT FROM 'other_city_tag',
                          'c6b caso ' || c.status || '/' || c.reason);
  PERFORM pg_temp.fail_if(c.detail_id IS NOT NULL, 'c6b detail_id NULL');
  PERFORM pg_temp.fail_if(c.culprit_role IS NOT NULL OR c.culprit_panelist_id IS NOT NULL, 'c6b sin culpable');
  PERFORM pg_temp.fail_if(c.resolved_at IS NOT NULL, 'c6b sin resolver');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.panelist_notification WHERE kind = 'receipt_reminder') <> 0, 'c6b sin recordatorio');
  -- otro intento con la misma etiqueta: el mismo caso, un intento mas, envio aun intacto
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'other_city_tag', 'c6b 2.o outcome ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1 OR (SELECT attempts FROM public.receipt_case) <> 2, 'c6b 2.o mismo caso');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'sent', 'c6b 2.o intacto');
END $$;
ROLLBACK;

-- ===== Caso 6c: caso not_found abierto y despues aparece un envio 'pending' (sin declarar) con esa etiqueta hacia
-- otra ciudad -> tampoco se anula: other_city_tag / needs_decision, detail_id NULL
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r1 jsonb; r jsonb; c record;
BEGIN
  r1 := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r1->>'outcome' IS DISTINCT FROM 'not_found', 'c6c primero ' || r1::text);
  v := pg_temp.mk_det('N4', 'N1', 'pending', '00012345');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'other_city_tag', 'c6c outcome ' || r::text);
  PERFORM pg_temp.fail_if(r->>'case_id' IS DISTINCT FROM r1->>'case_id', 'c6c mismo caso');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'pending', 'c6c intacto');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c6c sin deferred');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status <> 'needs_decision' OR c.reason <> 'other_city_tag' OR c.detail_id IS NOT NULL
                          OR c.culprit_role IS NOT NULL OR c.attempts <> 2, 'c6c caso ' || c.status || '/' || c.reason);
END $$;
ROLLBACK;

-- ===== Caso 7: POBOX, el dia laborable anterior N4 tenia un envio programado sin declarar -> no_visit
-- (como pobox_receipt_after_absence caso 2, con fechas relativas a hoy porque el bot recibe con la hora actual)
CREATE FUNCTION pg_temp.sc7() RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE v uuid; v_d date;
BEGIN
  v_d := public.pobox_previous_collection_day('a0000000-0000-0000-0000-000000000001', (now() AT TIME ZONE 'Africa/Nairobi')::date);
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', ((v_d - 7)::text || ' 10:00+03')::timestamptz);
  INSERT INTO public.allocation_plan_details (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, status)
  VALUES (gen_random_uuid(), 'a0000000-0000-0000-0000-000000000001', 'cc000000-0000-0000-0000-000000000001',
          'b4000000-0000-0000-0000-000000000004', 'b1000000-0000-0000-0000-000000000001', v_d, 'pending');
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.check7(v uuid, r jsonb, p text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE c record;
BEGIN
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'pobox_absent_no_visit', p || ' outcome ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM false, p || ' registered');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'cancelled', p || ' status');
  PERFORM pg_temp.fail_if((SELECT cancellation_reason FROM public.allocation_plan_details WHERE id = v)
                          IS DISTINCT FROM 'pobox_absent_no_visit', p || ' reason');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.one_db WHERE allocation_detail_id = v) <> 0, p || ' one_db');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 1, p || ' deferred');
  PERFORM pg_temp.fail_if((SELECT reason FROM public.deferred_samples) <> 'pobox_absent_no_visit', p || ' ds.reason');
  PERFORM pg_temp.fail_if((SELECT row_snapshot->>'status' FROM public.deferred_samples) IS DISTINCT FROM 'received', p || ' snapshot');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status IS DISTINCT FROM 'compensated' OR c.reason <> 'pobox_absent_no_visit', p || ' caso');
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'receiver'
                          OR c.culprit_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004', p || ' culprit');
  -- el ajuste local que salta el trigger queda restaurado
  PERFORM pg_temp.fail_if(COALESCE(current_setting('onems.skip_pobox_receipt_rule', true), '') = 'on', p || ' setting restaurado');
END $$;
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc7();
  PERFORM pg_temp.check7(v, public.bot_receive_parcel('4004', '12345'), 'c7');
END $$;
ROLLBACK;
-- 7b: igual con usuario web en la sesion (la regla se aplica igualmente)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc7();
  PERFORM set_config('request.jwt.claim.sub', '99000000-0000-0000-0000-000000000099', true);
  PERFORM pg_temp.check7(v, public.bot_receive_parcel('4004', '12345'), 'c7b');
END $$;
ROLLBACK;
-- 7c: un arreglo de typo que la regla POBOX anula queda con el outcome POBOX (culpa del receptor)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid;
BEGIN
  v := pg_temp.sc7();
  PERFORM pg_temp.check7(v, public.bot_receive_parcel('4004', '12354'), 'c7c');
  PERFORM pg_temp.fail_if((SELECT tag_id FROM public.allocation_plan_details WHERE id = v) <> '00012354', 'c7c tag corregido');
  PERFORM pg_temp.fail_if((SELECT original_tag FROM public.receipt_case) IS DISTINCT FROM '00012345', 'c7c original_tag');
END $$;
ROLLBACK;

-- ===== Caso 8: telegram inexistente -> no_panelist; la cuenta sale de la etiqueta
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE r jsonb; c record;
BEGIN
  PERFORM pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  r := public.bot_receive_parcel('9999', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'no_panelist', 'c8 outcome ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM false, 'c8 registered');
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1, 'c8 casos');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status IS DISTINCT FROM 'needs_decision' OR c.reason <> 'no_panelist', 'c8 caso');
  PERFORM pg_temp.fail_if(c.panelist_id IS NOT NULL OR c.telegram_id <> '9999', 'c8 panelista/telegram');
  PERFORM pg_temp.fail_if(c.account_id <> 'a0000000-0000-0000-0000-000000000001', 'c8 cuenta');
  PERFORM pg_temp.fail_if(EXISTS (SELECT 1 FROM public.allocation_plan_details WHERE status <> 'sent'), 'c8 nada cambia');
  -- 8b: sin envio con esa etiqueta no se puede saber la cuenta: contesta igual, sin caso
  r := public.bot_receive_parcel('9999', '77777');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'no_panelist', 'c8b outcome ' || r::text);
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1, 'c8b casos');
END $$;
ROLLBACK;

-- ===== Caso 8c: panelista sin nodo -> no_node, needs_decision
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
UPDATE public.panelists SET node_id = NULL WHERE id = 'e4000000-0000-0000-0000-000000000004';
DO $$
DECLARE r jsonb;
BEGIN
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'no_node', 'c8c outcome ' || r::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case) IS DISTINCT FROM 'needs_decision', 'c8c caso');
END $$;
ROLLBACK;

-- ===== Caso 9: not_found tres veces -> un caso con attempts = 3
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE r jsonb; c record; i int; v_ids text[] := '{}';
BEGIN
  FOR i IN 1..3 LOOP
    r := public.bot_receive_parcel('4004', '88888');
    PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_found', 'c9 outcome ' || r::text);
    v_ids := v_ids || (r->>'case_id');
    PERFORM pg_sleep(0.01);
  END LOOP;
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1, 'c9 casos ' || pg_temp.n_cases());
  PERFORM pg_temp.fail_if(v_ids[1] IS NULL OR v_ids[1] <> v_ids[2] OR v_ids[2] <> v_ids[3], 'c9 mismo case_id');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.attempts <> 3, 'c9 attempts ' || c.attempts);
  PERFORM pg_temp.fail_if(c.status <> 'pending' OR c.reason <> 'not_found', 'c9 estado');
  PERFORM pg_temp.fail_if(NOT (c.first_attempt_at < c.last_attempt_at), 'c9 first < last');
  PERFORM pg_temp.fail_if(c.culprit_role IS NOT NULL, 'c9 sin atribuir');
END $$;
ROLLBACK;

-- ===== Caso 10: formato invalido -> informative
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE r jsonb; c record;
BEGIN
  r := public.bot_receive_parcel('4004', 'abc');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'invalid_format', 'c10 outcome ' || r::text);
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status IS DISTINCT FROM 'informative' OR c.tag_raw <> 'abc' OR c.tag_norm IS NOT NULL, 'c10 caso');
END $$;
ROLLBACK;

-- ===== Caso 11: recibir dos veces el mismo envio -> already_received (informative); 11b: cancelado -> blocked
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r jsonb; c record;
BEGIN
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'ok', 'c11 primera ' || r::text);
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'already_received', 'c11 segunda ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM false, 'c11 registered');
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1, 'c11 casos');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status IS DISTINCT FROM 'informative' OR c.reason <> 'already_received', 'c11 caso');
  PERFORM pg_temp.fail_if(c.detail_id IS DISTINCT FROM v, 'c11 detail_id');
  -- otro intento el mismo dia -> mismo caso
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1 OR (SELECT attempts FROM public.receipt_case) <> 2, 'c11 agrupa');
  -- 11b
  PERFORM pg_temp.mk_det('N2', 'N4', 'cancelled', '00022222');
  r := public.bot_receive_parcel('4004', '22222');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'blocked', 'c11b outcome ' || r::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case WHERE reason = 'blocked') IS DISTINCT FROM 'informative', 'c11b caso');
END $$;
ROLLBACK;

-- ===== Caso 12: fallo al registrar el caso -> la recepcion sigue (fail-open)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
ALTER TABLE public.receipt_case ADD CONSTRAINT x CHECK (false) NOT VALID;
DO $$
DECLARE v uuid; r jsonb;
BEGIN
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  r := public.bot_receive_parcel('4004', '00012354');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'ok_typo_fixed', 'c12 outcome ' || r::text);
  PERFORM pg_temp.fail_if(r->>'case_id' IS NOT NULL, 'c12 case_id');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'received', 'c12 status');
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 0, 'c12 casos');
END $$;
ROLLBACK;

-- ===== Caso 13: register_receipt_with_rules directo con fecha pasada; permisos
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; t text;
BEGIN
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  t := public.register_receipt_with_rules(v, now() - interval '1 day', 'e4000000-0000-0000-0000-000000000004');
  PERFORM pg_temp.fail_if(t IS DISTINCT FROM 'ok', 'c13 ' || coalesce(t, 'NULL'));
  PERFORM pg_temp.fail_if((SELECT received_at FROM public.allocation_plan_details WHERE id = v)
                          IS DISTINCT FROM now() - interval '1 day', 'c13 received_at = el dado');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.bot_receive_parcel(text,text)', 'EXECUTE'), 'c13 authenticated');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.bot_receive_parcel(text,text)', 'EXECUTE'), 'c13 anon');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role', 'public.bot_receive_parcel(text,text)', 'EXECUTE'), 'c13 service_role');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.register_receipt_with_rules(uuid,timestamptz,uuid)', 'EXECUTE'), 'c13 register');
  PERFORM pg_temp.fail_if(has_table_privilege('authenticated', 'public.receipt_case', 'INSERT'), 'c13 insert directo');
  PERFORM pg_temp.fail_if(NOT has_table_privilege('authenticated', 'public.receipt_case', 'SELECT'), 'c13 select');
END $$;
ROLLBACK;

-- ===== Caso 14 (I1): not_found y despues aparece el envio (declarado ANTES del primer intento) -> el reintento
-- cierra el caso abierto: fixed, attempts 2, received_at = primer intento
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r1 jsonb; r2 jsonb; c record;
BEGIN
  r1 := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r1->>'outcome' IS DISTINCT FROM 'not_found', 'c14 primero ' || r1::text);
  PERFORM pg_sleep(0.01);
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', now() - interval '2 days');
  r2 := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r2->>'outcome' IS DISTINCT FROM 'ok', 'c14 reintento ' || r2::text);
  PERFORM pg_temp.fail_if(r2->>'case_id' IS DISTINCT FROM r1->>'case_id', 'c14 mismo caso');
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1, 'c14 casos');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status <> 'fixed' OR c.reason <> 'ok' OR c.attempts <> 2, 'c14 caso ' || c.status || '/' || c.reason || '/' || c.attempts);
  PERFORM pg_temp.fail_if(c.resolved_at IS NULL OR c.detail_id IS DISTINCT FROM v, 'c14 resolved/detail');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'received', 'c14 status');
  PERFORM pg_temp.fail_if((SELECT received_at FROM public.allocation_plan_details WHERE id = v) IS DISTINCT FROM c.first_attempt_at,
                          'c14 received_at = primer intento');
END $$;
ROLLBACK;

-- ===== Caso 15 (I2): not_found y despues el envio se declara DESPUES del primer intento -> recepcion anterior
-- al envio: not_sent_cancelled, compensado como receipt_before_sent
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r jsonb; c record;
BEGIN
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_found', 'c15 primero ' || r::text);
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345',
                      (SELECT first_attempt_at FROM public.receipt_case) + interval '1 day');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_sent_cancelled', 'c15 reintento ' || r::text);
  PERFORM pg_temp.fail_if((r->>'registered')::boolean IS DISTINCT FROM false, 'c15 registered');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'cancelled', 'c15 status');
  PERFORM pg_temp.fail_if((SELECT received_at FROM public.allocation_plan_details WHERE id = v) IS NOT NULL, 'c15 sin received_at');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 1 OR (SELECT reason FROM public.deferred_samples) <> 'receipt_before_sent', 'c15 ds');
  PERFORM pg_temp.fail_if((SELECT count(*) FROM public.one_db WHERE allocation_detail_id = v) <> 0, 'c15 one_db');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1 OR c.attempts <> 2, 'c15 un caso con 2 intentos');
  PERFORM pg_temp.fail_if(c.status <> 'compensated' OR c.reason <> 'not_sent_cancelled', 'c15 caso');
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'sender'
                          OR c.culprit_panelist_id IS DISTINCT FROM 'e1000000-0000-0000-0000-000000000001', 'c15 culprit');
END $$;
ROLLBACK;

-- ===== Caso 16 (I3): estado revisado tras bloquear la fila
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; v2 uuid; t text;
BEGIN
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345');
  t := public.register_receipt_with_rules(v, now() - interval '1 day', 'e4000000-0000-0000-0000-000000000004');
  PERFORM pg_temp.fail_if(t IS DISTINCT FROM 'ok', 'c16 primera ' || coalesce(t, 'NULL'));
  t := public.register_receipt_with_rules(v, now(), 'e4000000-0000-0000-0000-000000000004');
  PERFORM pg_temp.fail_if(t IS DISTINCT FROM 'already_received', 'c16 segunda ' || coalesce(t, 'NULL'));
  PERFORM pg_temp.fail_if((SELECT received_at FROM public.allocation_plan_details WHERE id = v)
                          IS DISTINCT FROM now() - interval '1 day', 'c16 received_at sin cambios');
  -- cancelar un recibido: no actua
  PERFORM pg_temp.fail_if(public.cancel_detail_for_compensation(v, 'receipt_before_sent'), 'c16 cancel sobre recibido');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'received', 'c16 sigue recibido');
  PERFORM pg_temp.fail_if(pg_temp.n_deferred() <> 0, 'c16 sin anotacion');
  -- registrar un cancelado: blocked, sin cambios
  v2 := pg_temp.mk_det('N2', 'N4', 'cancelled', '00022222');
  t := public.register_receipt_with_rules(v2, now(), 'e4000000-0000-0000-0000-000000000004');
  PERFORM pg_temp.fail_if(t IS DISTINCT FROM 'blocked', 'c16 cancelado ' || coalesce(t, 'NULL'));
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v2) <> 'cancelled'
                          OR (SELECT received_at FROM public.allocation_plan_details WHERE id = v2) IS NOT NULL, 'c16 cancelado intacto');
END $$;
ROLLBACK;

-- ===== Caso 17 (orden de busqueda): un pending de la MISMA ciudad gana a un sent de otra ciudad;
-- entre no-sent hacia su nodo gana el mas reciente
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N5');
DO $$
DECLARE v_same uuid; v_other uuid; v_old uuid; v_new uuid; r jsonb;
BEGIN
  v_other := pg_temp.mk_det('N4', 'N1', 'sent', '00012345');
  v_same := pg_temp.mk_det('N1', 'N5', 'pending', '00012345');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_sent_cancelled', 'c17 outcome ' || r::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v_same) <> 'cancelled', 'c17 misma ciudad anulado');
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v_other) <> 'sent', 'c17 otra ciudad intacto');
  -- no-sent hacia su nodo: cancelado antiguo y recibido reciente -> already_received
  v_old := pg_temp.mk_det('N1', 'N4', 'cancelled', '00033333', now() - interval '20 days');
  v_new := pg_temp.mk_det('N2', 'N4', 'sent', '00033333', now() - interval '3 days');
  UPDATE public.allocation_plan_details SET status = 'received', received_at = now() WHERE id = v_new;
  r := public.bot_receive_parcel('4004', '33333');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'already_received', 'c17 mas reciente ' || r::text);
END $$;
ROLLBACK;

-- ===== Caso 18: misma ciudad con original_destination_node_id ya fijado -> no se pisa
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N5');
DO $$
DECLARE v uuid; r jsonb;
BEGIN
  v := pg_temp.mk_det('N1', 'N5', 'sent', '00012345');
  UPDATE public.allocation_plan_details SET original_destination_node_id = 'b3000000-0000-0000-0000-000000000003' WHERE id = v;
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'ok_same_city', 'c18 outcome ' || r::text);
  PERFORM pg_temp.fail_if((SELECT original_destination_node_id FROM public.allocation_plan_details WHERE id = v)
                          IS DISTINCT FROM 'b3000000-0000-0000-0000-000000000003', 'c18 original intacto');
  PERFORM pg_temp.fail_if((SELECT destination_node_id FROM public.allocation_plan_details WHERE id = v)
                          IS DISTINCT FROM 'b4000000-0000-0000-0000-000000000004', 'c18 destino');
END $$;
ROLLBACK;

-- ===== Caso 19: POBOX, receptor indisponible el dia anterior de recogida -> pobox_absent_unavailable
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
SELECT pg_temp.pobox_on();
DO $$
DECLARE v uuid; v_d date; r jsonb; c record;
BEGIN
  v_d := public.pobox_previous_collection_day('a0000000-0000-0000-0000-000000000001', (now() AT TIME ZONE 'Africa/Nairobi')::date);
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012345', ((v_d - 7)::text || ' 10:00+03')::timestamptz);
  INSERT INTO public.panelist_unavailability (panelist_id, start_date, end_date, reason, status, account_id)
  VALUES ('e4000000-0000-0000-0000-000000000004', v_d, v_d, 'vacation', 'active', 'a0000000-0000-0000-0000-000000000001');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'pobox_absent_unavailable', 'c19 outcome ' || r::text);
  PERFORM pg_temp.fail_if((SELECT status FROM public.allocation_plan_details WHERE id = v) <> 'cancelled', 'c19 status');
  PERFORM pg_temp.fail_if((SELECT reason FROM public.deferred_samples) <> 'pobox_absent_unavailable', 'c19 ds');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(c.status <> 'compensated' OR c.reason <> 'pobox_absent_unavailable', 'c19 caso');
  PERFORM pg_temp.fail_if(c.culprit_role IS DISTINCT FROM 'receiver'
                          OR c.culprit_panelist_id IS DISTINCT FROM 'e4000000-0000-0000-0000-000000000004', 'c19 culprit');
END $$;
ROLLBACK;

-- ===== Caso 20: permisos de las funciones internas
DO $$
BEGIN
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.cancel_detail_for_compensation(uuid,text)', 'EXECUTE'), 'c20 cancel authenticated');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.cancel_detail_for_compensation(uuid,text)', 'EXECUTE'), 'c20 cancel anon');
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.receipt_typo_candidates(uuid,uuid,text,timestamptz)', 'EXECUTE'), 'c20 typo authenticated');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.receipt_typo_candidates(uuid,uuid,text,timestamptz)', 'EXECUTE'), 'c20 typo anon');
  PERFORM pg_temp.fail_if(to_regprocedure('public.receipt_typo_candidates(uuid,uuid,text)') IS NOT NULL, 'c20 firma antigua eliminada');
  PERFORM pg_temp.fail_if(has_function_privilege('anon', 'public.register_receipt_with_rules(uuid,timestamptz,uuid)', 'EXECUTE'), 'c20 register anon');
END $$;

-- ===== Caso 21 (I1): not_found y despues aparece un envio con etiqueta casi igual (1 cifra) declarado DESPUES del
-- primer intento -> el reintento del bot no lo toca (etiqueta, destino y estado intactos; el caso sigue pendiente)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
DO $$
DECLARE v uuid; r jsonb; c record; d record;
BEGIN
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_found', 'c21 primero ' || r::text);
  v := pg_temp.mk_det('N1', 'N4', 'sent', '00012395', (SELECT first_attempt_at FROM public.receipt_case) + interval '1 hour');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_found', 'c21 reintento ' || r::text);
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.tag_id <> '00012395' OR d.status <> 'sent' OR d.received_at IS NOT NULL
                          OR d.destination_node_id IS DISTINCT FROM 'b4000000-0000-0000-0000-000000000004', 'c21 envio intacto');
  SELECT * INTO c FROM public.receipt_case;
  PERFORM pg_temp.fail_if(pg_temp.n_cases() <> 1 OR c.status <> 'pending' OR c.reason <> 'not_found' OR c.attempts <> 2, 'c21 caso');
  PERFORM pg_temp.fail_if(c.original_tag IS NOT NULL OR c.detail_id IS NOT NULL, 'c21 sin arreglo');
END $$;
ROLLBACK;

-- ===== Caso 22 (I1): misma etiqueta hacia otro nodo de la misma ciudad, declarado DESPUES del primer intento ->
-- no se mueve el destino; se anula como receipt_before_sent (not_sent_cancelled)
BEGIN;
\ir fixtures/incident_city.sql
\ir fixtures/no_incident_triggers.sql
SELECT pg_temp.setup();
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b5000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N5');
DO $$
DECLARE v uuid; r jsonb; d record;
BEGIN
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_found', 'c22 primero ' || r::text);
  v := pg_temp.mk_det('N1', 'N5', 'sent', '00012345', (SELECT first_attempt_at FROM public.receipt_case) + interval '1 hour');
  r := public.bot_receive_parcel('4004', '12345');
  PERFORM pg_temp.fail_if(r->>'outcome' IS DISTINCT FROM 'not_sent_cancelled', 'c22 reintento ' || r::text);
  SELECT * INTO d FROM public.allocation_plan_details WHERE id = v;
  PERFORM pg_temp.fail_if(d.status <> 'cancelled' OR d.cancellation_reason IS DISTINCT FROM 'receipt_before_sent', 'c22 anulado');
  PERFORM pg_temp.fail_if(d.destination_node_id IS DISTINCT FROM 'b5000000-0000-0000-0000-000000000005'
                          OR d.original_destination_node_id IS NOT NULL, 'c22 destino sin mover');
  PERFORM pg_temp.fail_if((SELECT status FROM public.receipt_case) <> 'compensated', 'c22 caso');
END $$;
ROLLBACK;
