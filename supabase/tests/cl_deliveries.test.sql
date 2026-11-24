-- Carrier Link v4, tarea 1: modelo de entrega completa por periodo (20261124200000_cl_deliveries.sql).
-- Estructura (zona de paso UNLOGGED cerrada, sin datos personales), privilegios, RLS y aislamiento por cuenta,
-- bucket privado y politicas de Storage, validacion del periodo frente al calendario, idempotencia por
-- sha256 + periodo, estados, y contenido de cl_connector_config. Todo en BEGIN ... ROLLBACK.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid text, p_role text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub', coalesce(p_uid, ''), true);
  PERFORM set_config('request.jwt.claim.role', coalesce(p_role, ''), true);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.raises(p_sql text) RETURNS text LANGUAGE plpgsql AS $$
BEGIN EXECUTE p_sql; RETURN NULL; EXCEPTION WHEN OTHERS THEN RETURN SQLSTATE || ':' || SQLERRM; END $$;

-- Apertura con reloj fijo (nucleo; las envolturas usan now()).
CREATE OR REPLACE FUNCTION pg_temp.op(p_feed text, p_start text, p_end text, p_sha text, p_now text,
                                      p_totals jsonb DEFAULT '[]'::jsonb, p_format text DEFAULT 'jsonl',
                                      p_comp text DEFAULT 'none') RETURNS jsonb LANGUAGE sql AS $$
  SELECT public.cl_delivery_open_core(p_feed::uuid, p_start::date, p_end::date, p_sha, p_totals, p_format, p_comp,
                                      'api', NULL, p_now::timestamptz)
$$;
CREATE OR REPLACE FUNCTION pg_temp.op_sql(p_feed text, p_start text, p_end text, p_sha text, p_now text,
                                          p_totals text DEFAULT '[]', p_format text DEFAULT 'jsonl',
                                          p_comp text DEFAULT 'none') RETURNS text LANGUAGE sql AS $$
  SELECT format('SELECT pg_temp.op(%L, %L, %L, %L, %L, %L::jsonb, %L, %L)', p_feed, p_start, p_end, p_sha, p_now,
                p_totals, p_format, p_comp)
$$;
CREATE OR REPLACE FUNCTION pg_temp.sha(p_n int) RETURNS text LANGUAGE sql AS $$
  SELECT encode(sha256(convert_to('file-' || p_n, 'UTF8')), 'hex')
$$;
-- Simula el objeto subido al bucket (como lo dejaria Storage).
CREATE OR REPLACE FUNCTION pg_temp.put(p_path text, p_size bigint) RETURNS void LANGUAGE sql AS $$
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES ('cl-deliveries', p_path, jsonb_build_object('size', p_size))
$$;

BEGIN;
\set fixture_sin_roles 1
\ir fixtures/incident_city.sql
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

-- Cuenta A1 en Nairobi. Feed A1 activo, entregas lunes y jueves a las 03:00 (jue..dom y lun..mie).
UPDATE public.accounts SET timezone = 'Africa/Nairobi' WHERE id = 'a0000000-0000-0000-0000-000000000001';
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('d1000000-0000-0000-0000-0000000000c1','a0000000-0000-0000-0000-000000000001','PC1','Center 1','City1','c1000000-0000-0000-0000-000000000001'),
  ('d2000000-0000-0000-0000-0000000000c2','a0000000-0000-0000-0000-000000000001','PC2','Center 2','City2','c2000000-0000-0000-0000-000000000002');
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role) VALUES
  ('ad000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-0000000000c1','NBO ADM','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','NBO','ADM','origin'),
  ('ad000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001',NULL,'HUB','Entry','carrier_scan','ca000000-0000-0000-0000-000000000001','HUB',NULL,'none'),
  ('ad000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','MBA any','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','MBA',NULL,'destination');
INSERT INTO public.readers (id, account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role, deleted_at) VALUES
  ('ad000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-0000000000c2','OLD','Exit','carrier_scan','ca000000-0000-0000-0000-000000000001','OLD',NULL,'destination', now());
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed A1','active','{1,4}',3),
  ('f0000000-0000-0000-0000-0000000000a4','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed T','testing','{1,2,3,4,5,6,7}',3),
  ('f0000000-0000-0000-0000-0000000000a5','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed Z','paused','{1}',3),
  ('f0000000-0000-0000-0000-0000000000a6','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed W','active','{1}',3),
  ('f0000000-0000-0000-0000-0000000000a7','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed M','active','{1,2,3,4,5,6,7}',3),
  ('f0000000-0000-0000-0000-0000000000a8','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed G','active','{1}',3),
  ('f0000000-0000-0000-0000-0000000000a9','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','Feed R','active','{1,2,3,4,5,6,7}',3);
INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field, format, timezone) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','item_id','trk',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','svc',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','scan_at','ts','DD/MM/YYYY HH24:MI','Africa/Nairobi'),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','place_ref','office',NULL,NULL),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','mode_ref','evt',NULL,NULL);
INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','EXP','PR'),
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','product','EXP2','PR');
INSERT INTO public.cl_extra_fields (account_id, carrier_id, carrier_field) VALUES
  ('a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','weight');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id, feed_diagnosis) VALUES
  ('90000000-0000-0000-0000-0000000000a1','a0000000-0000-0000-0000-000000000001','P1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000a1',true),
  ('90000000-0000-0000-0000-0000000000a4','a0000000-0000-0000-0000-000000000001','PT','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000a4',false),
  ('90000000-0000-0000-0000-0000000000a6','a0000000-0000-0000-0000-000000000001','PW','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-04','2026-11-29','active','f0000000-0000-0000-0000-0000000000a6',false),
  ('90000000-0000-0000-0000-0000000000a7','a0000000-0000-0000-0000-000000000001','PM','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,current_date - 30,current_date + 30,'active','f0000000-0000-0000-0000-0000000000a7',false),
  -- G: dos planes con hueco (02/11-15/11 y 09/12 (miercoles)-20/12).
  ('90000000-0000-0000-0000-0000000000a8','a0000000-0000-0000-0000-000000000001','PG1','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-02','2026-11-15','active','f0000000-0000-0000-0000-0000000000a8',false),
  ('90000000-0000-0000-0000-0000000000b8','a0000000-0000-0000-0000-000000000001','PG2','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-12-09','2026-12-20','active','f0000000-0000-0000-0000-0000000000a8',false),
  ('90000000-0000-0000-0000-0000000000a9','a0000000-0000-0000-0000-000000000001','PR','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000a9',false);
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000b1','a0000000-0000-0000-0000-000000000001','90000000-0000-0000-0000-0000000000a1','c1000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002',2026,47,'2026-11-16','2026-11-22',3);

-- Cuenta A2 con su feed y una entrega.
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','CB','Carrier2');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','PB','Prod2',48);
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days) VALUES
  ('f0000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000002','ca000000-0000-0000-0000-000000000002','Feed A2','active','{1}');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000b2','a0000000-0000-0000-0000-000000000002','PB','ca000000-0000-0000-0000-000000000002','cb000000-0000-0000-0000-000000000002',10,'2026-11-02','2026-11-29','active','f0000000-0000-0000-0000-0000000000b2');
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000002','Reg2','R2');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000002','City3','C3');
INSERT INTO public.cl_plan_quotas (id, account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned) VALUES
  ('91000000-0000-0000-0000-0000000000b9','a0000000-0000-0000-0000-000000000002','90000000-0000-0000-0000-0000000000b2','c3000000-0000-0000-0000-000000000003','c3000000-0000-0000-0000-000000000003',2026,47,'2026-11-16','2026-11-22',3);

-- 93 AM de A1 (Edit en cl_connectors), 94 APM de A1 (cl_connectors solo View), 95 sin acceso a Carrier Link,
-- 92 UPU AM de A2, 97 superadmin.
INSERT INTO auth.users (id, email) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l'),
  ('94000000-0000-0000-0000-000000000094','apm@t.l'),
  ('95000000-0000-0000-0000-000000000095','ms@t.l'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l'),
  ('97000000-0000-0000-0000-000000000097','super@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('93000000-0000-0000-0000-000000000093','am@t.l','AM','user','a0000000-0000-0000-0000-000000000001'),
  ('94000000-0000-0000-0000-000000000094','apm@t.l','APM','user','a0000000-0000-0000-0000-000000000001'),
  ('95000000-0000-0000-0000-000000000095','ms@t.l','MS','user','a0000000-0000-0000-0000-000000000001'),
  ('92000000-0000-0000-0000-000000000092','upu2@t.l','UPU2','user','a0000000-0000-0000-0000-000000000002'),
  ('97000000-0000-0000-0000-000000000097','super@t.l','Super','superadmin',NULL);
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000093','account_manager'),
  ('a0000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000094','allocation_plan_manager'),
  ('a0000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000095','materials_supplier'),
  ('a0000000-0000-0000-0000-000000000002','92000000-0000-0000-0000-000000000092','upu_account_manager');
INSERT INTO public.account_access (account_id, role, option, level) VALUES
  ('a0000000-0000-0000-0000-000000000001','allocation_plan_manager','cl_connectors','view')
ON CONFLICT (account_id, role, option) DO UPDATE SET level = EXCLUDED.level;
DELETE FROM public.account_access
 WHERE account_id = 'a0000000-0000-0000-0000-000000000001' AND role = 'materials_supplier'
   AND option IN ('cl_connectors','cl_monitor');

-- ================================================================ 1. estructura
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT relpersistence = 'u' FROM pg_class WHERE oid = 'public.cl_delivery_rows'::regclass),
                     'cl_delivery_rows es UNLOGGED');
  PERFORM pg_temp.ok((SELECT relpersistence = 'p' FROM pg_class WHERE oid = 'public.cl_deliveries'::regclass),
                     'cl_deliveries es permanente');
  PERFORM pg_temp.ok((SELECT bool_and(relrowsecurity) FROM pg_class
                       WHERE oid IN ('public.cl_deliveries'::regclass, 'public.cl_delivery_strata'::regclass,
                                     'public.cl_delivery_rows'::regclass)), 'RLS activado en las 3 tablas');
  -- Zona de paso: lista cerrada de columnas (nada de datos personales) y sin privilegios para nadie.
  PERFORM pg_temp.ok((SELECT array_agg(attname::text ORDER BY attnum) FROM pg_attribute
                       WHERE attrelid = 'public.cl_delivery_rows'::regclass AND attnum > 0 AND NOT attisdropped)
                     = ARRAY['delivery_id','row_no','item_id','product','scan_at_raw','place_ref','mode_ref','extra',
                             'product_id','scan_at','reader_id','resolved_mode','row_reason'],
                     'columnas cerradas de cl_delivery_rows');
  PERFORM pg_temp.ok(NOT has_table_privilege(r, 'public.cl_delivery_rows', p), 'cl_delivery_rows sin ' || p || ' para ' || r)
    FROM unnest(ARRAY['anon','authenticated','service_role']) r, unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) p;
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid = 'public.cl_delivery_rows'::regclass
                               AND i.indisprimary
                               AND pg_get_indexdef(i.indexrelid) LIKE '%(delivery_id, row_no)%'), 'PK (delivery_id, row_no)');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM pg_indexes WHERE tablename = 'cl_delivery_rows'
                               AND indexdef LIKE '%(delivery_id, item_id)%'), 'indice por entrega e item');
  -- Ninguna tabla nueva guarda campos personales.
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM pg_attribute
                                  WHERE attrelid IN ('public.cl_deliveries'::regclass, 'public.cl_delivery_strata'::regclass,
                                                     'public.cl_delivery_rows'::regclass)
                                    AND attnum > 0 AND NOT attisdropped
                                    AND attname ~ '(name|email|phone|mobile|address|recipient|sender|panelist)'),
                     'sin columnas de datos personales');
  -- Escritura: nadie directamente (ni service_role); lectura authenticated + service_role.
  PERFORM pg_temp.ok(NOT has_table_privilege(r, t, p), t || ' sin ' || p || ' para ' || r)
    FROM unnest(ARRAY['anon','authenticated','service_role']) r,
         unnest(ARRAY['public.cl_deliveries','public.cl_delivery_strata']) t,
         unnest(ARRAY['INSERT','UPDATE','DELETE','TRUNCATE']) p;
  PERFORM pg_temp.ok(has_table_privilege('authenticated', 'public.cl_deliveries', 'SELECT')
                 AND has_table_privilege('service_role', 'public.cl_deliveries', 'SELECT')
                 AND NOT has_table_privilege('anon', 'public.cl_deliveries', 'SELECT'), 'SELECT de cl_deliveries');
  -- Traza de la entrega en muestras y alertas.
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.cl_samples'::regclass AND attname = 'delivery_id'),
                     'cl_samples.delivery_id');
  PERFORM pg_temp.ok(EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.cl_alerts'::regclass AND attname = 'delivery_id'),
                     'cl_alerts.delivery_id');
  -- Bucket privado con tope.
  PERFORM pg_temp.ok((SELECT NOT public AND file_size_limit = 524288000 FROM storage.buckets WHERE id = 'cl-deliveries'),
                     'bucket cl-deliveries privado, 500 MB');
END $$;

-- ================================================================ 2. privilegios de funciones
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY['public.cl_delivery_open(uuid,date,date,text,jsonb,text,bigint)',
                           'public.cl_delivery_complete(uuid,uuid)',
                           'public.cl_connector_config(uuid,timestamptz)'] LOOP
    PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure), f || ' SECURITY DEFINER');
    PERFORM pg_temp.ok((SELECT proconfig @> ARRAY['search_path=public, extensions'] FROM pg_proc WHERE oid = f::regprocedure), f || ' search_path');
    PERFORM pg_temp.ok(has_function_privilege('service_role', f, 'EXECUTE'), f || ' service_role');
    PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', f, 'EXECUTE')
                   AND NOT has_function_privilege('anon', f, 'EXECUTE'), f || ' solo service_role');
  END LOOP;
  FOREACH f IN ARRAY ARRAY['public.cl_manual_delivery_open(uuid,date,date,text,jsonb,text)',
                           'public.cl_manual_delivery_complete(uuid,uuid)',
                           'public.cl_delivery_can_upload(text)', 'public.cl_delivery_can_read(text)'] LOOP
    PERFORM pg_temp.ok((SELECT prosecdef FROM pg_proc WHERE oid = f::regprocedure), f || ' SECURITY DEFINER');
    PERFORM pg_temp.ok((SELECT proconfig @> ARRAY['search_path=public, extensions'] FROM pg_proc WHERE oid = f::regprocedure), f || ' search_path');
    PERFORM pg_temp.ok(has_function_privilege('authenticated', f, 'EXECUTE'), f || ' authenticated');
    PERFORM pg_temp.ok(NOT has_function_privilege('anon', f, 'EXECUTE'), f || ' sin anon');
  END LOOP;
  FOREACH f IN ARRAY ARRAY['public.cl_delivery_open_core(uuid,date,date,text,jsonb,text,text,text,uuid,timestamptz)',
                           'public.cl_delivery_complete_core(uuid,uuid,text)', 'public.cl_delivery_summary(uuid)',
                           'public.cl_delivery_authorize_manual(uuid)', 'public.cl_delivery_next_period(uuid,timestamptz)',
                           'public.cl_delivery_limits(jsonb)', 'public.cl_account_date_tz(uuid)',
                           'public.cl_delivery_aligned_period(smallint[],date)', 'public.cl_deliveries_guard()'] LOOP
    PERFORM pg_temp.ok(NOT has_function_privilege('authenticated', f, 'EXECUTE')
                   AND NOT has_function_privilege('anon', f, 'EXECUTE')
                   AND NOT has_function_privilege('service_role', f, 'EXECUTE'), f || ' interna');
  END LOOP;
END $$;

-- ================================================================ 3. periodos del calendario
DO $$
DECLARE r record;
BEGIN
  -- lunes y jueves: el jueves 26/11 entrega lun 23..mie 25; el lunes 23/11 entrega jue 19..dom 22.
  SELECT * INTO r FROM public.cl_delivery_aligned_period('{1,4}', '2026-11-24');
  PERFORM pg_temp.ok(r.period_start = '2026-11-23' AND r.period_end = '2026-11-25', 'lun-jue: periodo de un martes');
  SELECT * INTO r FROM public.cl_delivery_aligned_period('{1,4}', '2026-11-22');
  PERFORM pg_temp.ok(r.period_start = '2026-11-19' AND r.period_end = '2026-11-22', 'lun-jue: periodo de un domingo');
  SELECT * INTO r FROM public.cl_delivery_aligned_period('{1,2,3,4,5,6,7}', '2026-11-22');
  PERFORM pg_temp.ok(r.period_start = '2026-11-22' AND r.period_end = '2026-11-22', 'diaria: un dia');
  SELECT * INTO r FROM public.cl_delivery_aligned_period('{2}', '2026-11-23');
  PERFORM pg_temp.ok(r.period_start = '2026-11-17' AND r.period_end = '2026-11-23', 'semanal martes: mar..lun (dos semanas ISO)');
END $$;

-- Validaciones (reloj: miercoles 25/11/2026 10:00 en Nairobi).
DO $$
DECLARE
  a1 constant text := 'f0000000-0000-0000-0000-0000000000a1';
  v_now constant text := '2026-11-25 10:00+03';
  e text;
BEGIN
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-20', '2026-11-22', pg_temp.sha(1), v_now));
  PERFORM pg_temp.ok(e LIKE '22023:CL_PERIOD_NOT_IN_CALENDAR%must start on 2026-11-19%', 'inicio desalineado: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-19', '2026-11-21', pg_temp.sha(1), v_now));
  PERFORM pg_temp.ok(e LIKE '22023:CL_PERIOD_NOT_IN_CALENDAR%not the day before%', 'fin desalineado: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-23', '2026-11-25', pg_temp.sha(1), v_now));
  PERFORM pg_temp.ok(e LIKE '22023:CL_PERIOD_NOT_CLOSED%', 'periodo sin cerrar: ' || coalesce(e, 'ok'));
  -- 20:59 UTC del 25/11 aun es 25/11 en Nairobi (23:59): el periodo lun..mie no esta cerrado (fecha local de la cuenta).
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-23', '2026-11-25', pg_temp.sha(1), '2026-11-25 20:59+00'));
  PERFORM pg_temp.ok(e LIKE '22023:CL_PERIOD_NOT_CLOSED%', 'antes de medianoche local: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-10-26', '2026-10-28', pg_temp.sha(1), v_now));
  PERFORM pg_temp.ok(e LIKE '22023:CL_NO_ACTIVE_PLAN%', 'fuera de plan: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-22', '2026-11-19', pg_temp.sha(1), v_now));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_PERIOD%', 'inicio > fin: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-19', '2026-11-22', 'abc', v_now));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_REQUEST%sha256%', 'sha256 invalido: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-19', '2026-11-22', pg_temp.sha(1), v_now, '[]', 'xlsx'));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_REQUEST%format%', 'formato invalido: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-19', '2026-11-22', pg_temp.sha(1), v_now, '[]', 'csv', 'zip'));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_REQUEST%compression%', 'compresion invalida: ' || coalesce(e, 'ok'));
  -- Totales de control: claves cerradas (un nombre de destinatario se rechaza), entero >= 0.
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-19', '2026-11-22', pg_temp.sha(1), v_now,
         '[{"place_ref":"MBA","delivered":3,"recipient_name":"X"}]'));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_CONTROL_TOTALS%', 'clave no permitida: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-19', '2026-11-22', pg_temp.sha(1), v_now, '[{"place_ref":"MBA","delivered":"x"}]'));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_CONTROL_TOTALS%', 'delivered no numerico: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-19', '2026-11-22', pg_temp.sha(1), v_now, '[{"place_ref":"MBA","delivered":-1}]'));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_CONTROL_TOTALS%', 'delivered negativo: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-19', '2026-11-22', pg_temp.sha(1), v_now, '{"place_ref":"MBA"}'));
  PERFORM pg_temp.ok(e LIKE '22023:CL_BAD_CONTROL_TOTALS%', 'totales no lista: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql('f0000000-0000-0000-0000-0000000000a5', '2026-11-16', '2026-11-22', pg_temp.sha(1), v_now));
  PERFORM pg_temp.ok(e LIKE '22023:CL_FEED_PAUSED%', 'conector pausado: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(pg_temp.op_sql('f0000000-0000-0000-0000-0000000000ff', '2026-11-16', '2026-11-22', pg_temp.sha(1), v_now));
  PERFORM pg_temp.ok(e LIKE '22023:CL_FEED_NOT_FOUND%', 'conector inexistente: ' || coalesce(e, 'ok'));
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_deliveries) = 0, 'nada escrito tras errores');
END $$;

-- ================================================================ 4. abrir, idempotencia, completar, estados
DO $$
DECLARE
  a1 constant text := 'f0000000-0000-0000-0000-0000000000a1';
  v_now constant text := '2026-11-25 10:00+03';
  j jsonb; j2 jsonb; j3 jsonb; e text; v_id uuid; v_id2 uuid;
BEGIN
  j := pg_temp.op(a1, '2026-11-19', '2026-11-22', upper(pg_temp.sha(1)), v_now,
                  '[{"place_ref":"MBA","mode_ref":null,"product":"EXP","delivered":42}]');
  v_id := (j->>'delivery_id')::uuid;
  PERFORM pg_temp.ok(j->>'status' = 'pending_upload' AND (j->>'existing')::boolean = false, 'abierta: ' || j::text);
  PERFORM pg_temp.ok(j->>'file_path' = 'a0000000-0000-0000-0000-000000000001/' || a1 || '/' || v_id || '.jsonl', 'ruta por cuenta');
  PERFORM pg_temp.ok(j->>'sha256' = pg_temp.sha(1), 'sha256 en minusculas');
  PERFORM pg_temp.ok((j->>'max_file_bytes')::bigint = 524288000 AND NOT (j->>'is_test')::boolean, 'tope y no prueba');
  PERFORM pg_temp.ok((SELECT control_totals->0->>'delivered' = '42' AND source = 'api' FROM public.cl_deliveries WHERE id = v_id),
                     'totales de control guardados');

  -- Mismo fichero y periodo: la misma entrega.
  j2 := pg_temp.op(a1, '2026-11-19', '2026-11-22', pg_temp.sha(1), v_now);
  PERFORM pg_temp.ok((j2->>'delivery_id')::uuid = v_id AND (j2->>'existing')::boolean, 'idempotente pending_upload');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_deliveries) = 1, 'una sola fila');

  -- Otro fichero para el mismo periodo antes de subir: la primera queda CL_SUPERSEDED.
  j2 := pg_temp.op(a1, '2026-11-19', '2026-11-22', pg_temp.sha(2), v_now, '[]', 'csv', 'none');
  v_id2 := (j2->>'delivery_id')::uuid;
  PERFORM pg_temp.ok(v_id2 <> v_id AND j2->>'file_path' LIKE '%/' || v_id2 || '.csv', 'nueva entrega csv sin comprimir');
  PERFORM pg_temp.ok((SELECT status = 'rejected' AND error = 'CL_SUPERSEDED' FROM public.cl_deliveries WHERE id = v_id),
                     'la anterior queda superada');

  -- Completar sin fichero: error; con fichero: received; repetir: mismo resumen.
  e := pg_temp.raises(format('SELECT public.cl_delivery_complete_core(%L, %L, ''api'')', a1, v_id2));
  PERFORM pg_temp.ok(e LIKE '22023:CL_FILE_NOT_UPLOADED%', 'sin fichero: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_delivery_complete_core(%L, %L, ''manual'')', a1, v_id2));
  PERFORM pg_temp.ok(e LIKE '22023:CL_DELIVERY_NOT_FOUND%', 'otro origen: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_delivery_complete_core(%L, %L, ''api'')', 'f0000000-0000-0000-0000-0000000000a4', v_id2));
  PERFORM pg_temp.ok(e LIKE '22023:CL_DELIVERY_NOT_FOUND%', 'otro conector: ' || coalesce(e, 'ok'));
  PERFORM pg_temp.put(j2->>'file_path', 1234);
  j3 := public.cl_delivery_complete_core(a1::uuid, v_id2, 'api');
  PERFORM pg_temp.ok(j3->>'status' = 'received' AND (j3->>'file_bytes')::bigint = 1234 AND j3->>'received_at' IS NOT NULL,
                     'recibida: ' || j3::text);
  j3 := public.cl_delivery_complete_core(a1::uuid, v_id2, 'api');
  PERFORM pg_temp.ok(j3->>'status' = 'received', 'completar dos veces');

  -- Ya entregado: mismo fichero -> la misma; otro fichero o periodo solapado -> CL_PERIOD_ALREADY_DELIVERED.
  j3 := pg_temp.op(a1, '2026-11-19', '2026-11-22', pg_temp.sha(2), v_now, '[]', 'csv', 'none');
  PERFORM pg_temp.ok((j3->>'delivery_id')::uuid = v_id2 AND (j3->>'existing')::boolean AND j3->>'status' = 'received',
                     'idempotente received');
  e := pg_temp.raises(pg_temp.op_sql(a1, '2026-11-19', '2026-11-22', pg_temp.sha(3), v_now));
  PERFORM pg_temp.ok(e LIKE 'P0001:CL_PERIOD_ALREADY_DELIVERED%', 'periodo ya entregado: ' || coalesce(e, 'ok'));

  -- Estados: transiciones permitidas y prohibidas; campos de identidad inmutables.
  UPDATE public.cl_deliveries SET status = 'processing', processing_started_at = now() WHERE id = v_id2;
  e := pg_temp.raises(format('UPDATE public.cl_deliveries SET status = ''received'' WHERE id = %L', v_id2));
  PERFORM pg_temp.ok(e LIKE '22023:CL_DELIVERY_BAD_TRANSITION%', 'processing -> received: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('UPDATE public.cl_deliveries SET sha256 = %L WHERE id = %L', pg_temp.sha(9), v_id2));
  PERFORM pg_temp.ok(e LIKE '22023:CL_DELIVERY_IMMUTABLE%', 'sha256 inmutable: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('UPDATE public.cl_deliveries SET period_end = ''2026-11-21'' WHERE id = %L', v_id2));
  PERFORM pg_temp.ok(e LIKE '22023:CL_DELIVERY_IMMUTABLE%', 'periodo inmutable: ' || coalesce(e, 'ok'));
  UPDATE public.cl_deliveries SET status = 'failed', error = 'CL_WORKER_ERROR' WHERE id = v_id2;
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = v_id2;     -- reanudar
  UPDATE public.cl_deliveries SET status = 'processed', finished_at = now() WHERE id = v_id2;
  e := pg_temp.raises(format('UPDATE public.cl_deliveries SET status = ''failed'' WHERE id = %L', v_id2));
  PERFORM pg_temp.ok(e LIKE '22023:CL_DELIVERY_BAD_TRANSITION%', 'processed es final: ' || coalesce(e, 'ok'));

  -- Siguiente periodo (jue 26/11 entrega lun 23..mie 25), con reloj del jueves.
  j3 := pg_temp.op(a1, '2026-11-23', '2026-11-25', pg_temp.sha(4), '2026-11-26 04:00+03');
  PERFORM pg_temp.ok(j3->>'status' = 'pending_upload', 'periodo siguiente');
  -- Fichero demasiado grande para el tope del conector: rejected; el mismo fichero se puede volver a abrir.
  UPDATE public.cl_feeds SET config = '{"max_file_bytes": 1000}' WHERE id = a1::uuid;
  PERFORM pg_temp.put(j3->>'file_path', 1001);
  j := public.cl_delivery_complete_core(a1::uuid, (j3->>'delivery_id')::uuid, 'api');
  PERFORM pg_temp.ok(j->>'status' = 'rejected' AND j->>'error' = 'CL_FILE_TOO_LARGE', 'demasiado grande: ' || j::text);
  j := pg_temp.op(a1, '2026-11-23', '2026-11-25', pg_temp.sha(4), '2026-11-26 04:00+03');
  PERFORM pg_temp.ok((j->>'delivery_id')::uuid <> (j3->>'delivery_id')::uuid AND NOT (j->>'existing')::boolean
                     AND (j->>'max_file_bytes')::bigint = 1000, 'reintento tras rechazo');
  UPDATE public.cl_feeds SET config = '{}' WHERE id = a1::uuid;

  -- Conector en prueba: entrega de prueba (diaria).
  j := pg_temp.op('f0000000-0000-0000-0000-0000000000a4', '2026-11-24', '2026-11-24', pg_temp.sha(5), v_now);
  PERFORM pg_temp.ok((j->>'is_test')::boolean, 'entrega de prueba');

  -- R25: una sola entrega 'processing' en toda la base.
  PERFORM pg_temp.put(j->>'file_path', 10);
  PERFORM public.cl_delivery_complete_core('f0000000-0000-0000-0000-0000000000a4', (j->>'delivery_id')::uuid, 'api');
  UPDATE public.cl_deliveries SET status = 'processing' WHERE id = (j->>'delivery_id')::uuid;
  j2 := pg_temp.op('f0000000-0000-0000-0000-0000000000a4', '2026-11-23', '2026-11-23', pg_temp.sha(6), v_now);
  PERFORM pg_temp.put(j2->>'file_path', 10);
  PERFORM public.cl_delivery_complete_core('f0000000-0000-0000-0000-0000000000a4', (j2->>'delivery_id')::uuid, 'api');
  e := pg_temp.raises(format('UPDATE public.cl_deliveries SET status = ''processing'' WHERE id = %L', j2->>'delivery_id'));
  PERFORM pg_temp.ok(e LIKE '23505:%', 'una sola entrega en proceso: ' || coalesce(e, 'ok'));
  UPDATE public.cl_deliveries SET status = 'processed' WHERE id = (j->>'delivery_id')::uuid;

  -- Misma cuenta: un estrato con la cuota de otra cuenta.
  e := pg_temp.raises(format('INSERT INTO public.cl_delivery_strata (account_id, delivery_id, quota_id) VALUES (%L, %L, %L)',
         'a0000000-0000-0000-0000-000000000001', v_id2, '91000000-0000-0000-0000-0000000000b9'));
  PERFORM pg_temp.ok(e LIKE '23514:%', 'cuota de otra cuenta: ' || coalesce(e, 'ok'));
  INSERT INTO public.cl_delivery_strata (account_id, delivery_id, quota_id, population, quota_for_delivery, selected)
  VALUES ('a0000000-0000-0000-0000-000000000001', v_id2, '91000000-0000-0000-0000-0000000000b1', 120, 2, 2);
  PERFORM pg_temp.ok((SELECT seed ~ '^[0-9a-f]{32}$' FROM public.cl_delivery_strata WHERE delivery_id = v_id2), 'semilla registrada');
END $$;

-- Calendario cambiado a mitad de periodo: el inicio esperado es el dia siguiente a lo ya entregado.
DO $$
DECLARE
  w constant text := 'f0000000-0000-0000-0000-0000000000a6';
  j jsonb; e text;
BEGIN
  -- Semanal (lunes): lun 16..dom 22 entregado.
  j := pg_temp.op(w, '2026-11-16', '2026-11-22', pg_temp.sha(7), '2026-11-25 10:00+03');
  PERFORM pg_temp.put(j->>'file_path', 10);
  PERFORM public.cl_delivery_complete_core(w::uuid, (j->>'delivery_id')::uuid, 'api');
  -- Pasa a lunes y jueves: el periodo que acaba el mie 25 empieza el lun 23 (alineado), no antes.
  UPDATE public.cl_feeds SET emit_days = '{1,4}' WHERE id = w::uuid;
  e := pg_temp.raises(pg_temp.op_sql(w, '2026-11-22', '2026-11-25', pg_temp.sha(8), '2026-11-26 10:00+03'));
  PERFORM pg_temp.ok(e LIKE 'P0001:CL_PERIOD_ALREADY_DELIVERED%', 'solape con lo entregado: ' || coalesce(e, 'ok'));
  -- Pasa a jueves: el periodo jue 19..mie 25 se recorta a lun 23..mie 25.
  UPDATE public.cl_feeds SET emit_days = '{4}' WHERE id = w::uuid;
  e := pg_temp.raises(pg_temp.op_sql(w, '2026-11-19', '2026-11-25', pg_temp.sha(8), '2026-11-26 10:00+03'));
  PERFORM pg_temp.ok(e LIKE 'P0001:CL_PERIOD_ALREADY_DELIVERED%', 'solape tras cambio: ' || coalesce(e, 'ok'));
  j := pg_temp.op(w, '2026-11-23', '2026-11-25', pg_temp.sha(8), '2026-11-26 10:00+03');
  PERFORM pg_temp.ok(j->>'status' = 'pending_upload', 'periodo recortado tras cambio de calendario');
END $$;

-- Fix 1: completar y sustituir no dejan dos entregas "entregadas" del mismo periodo.
DO $$
DECLARE
  r constant text := 'f0000000-0000-0000-0000-0000000000a9';
  v_now constant text := '2026-11-25 10:00+03';
  d1 jsonb; d2 jsonb; j jsonb; e text; v_id uuid;
BEGIN
  -- Secuencia: abrir D1, abrir D2 (mismo periodo, otro fichero), completar D1, completar D2.
  d1 := pg_temp.op(r, '2026-11-20', '2026-11-20', pg_temp.sha(50), v_now);
  PERFORM pg_temp.put(d1->>'file_path', 10);
  d2 := pg_temp.op(r, '2026-11-20', '2026-11-20', pg_temp.sha(51), v_now);
  PERFORM pg_temp.put(d2->>'file_path', 10);
  j := public.cl_delivery_complete_core(r::uuid, (d1->>'delivery_id')::uuid, 'api');
  PERFORM pg_temp.ok(j->>'status' = 'rejected' AND j->>'error' = 'CL_SUPERSEDED', 'D1 superada no se recibe: ' || j::text);
  j := public.cl_delivery_complete_core(r::uuid, (d2->>'delivery_id')::uuid, 'api');
  PERFORM pg_temp.ok(j->>'status' = 'received', 'D2 recibida');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_deliveries
                       WHERE feed_id = r::uuid AND period_start = '2026-11-20' AND status = 'received') = 1,
                     'una sola entrega recibida para el periodo');

  -- Interleaving de la carrera: D3 pendiente que ya habia pasado la comprobacion de solape cuando otra entrega se
  -- recibio. Al completarla se vuelve a comprobar el solape bajo el bloqueo del conector -> rejected.
  v_id := gen_random_uuid();
  INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, format, compression, file_path, sha256)
  VALUES (v_id, 'a0000000-0000-0000-0000-000000000001', r::uuid, '2026-11-20', '2026-11-20', 'api', 'jsonl', 'gzip',
          'a0000000-0000-0000-0000-000000000001/' || r || '/' || v_id || '.jsonl.gz', pg_temp.sha(52));
  PERFORM pg_temp.put('a0000000-0000-0000-0000-000000000001/' || r || '/' || v_id || '.jsonl.gz', 10);
  j := public.cl_delivery_complete_core(r::uuid, v_id, 'api');
  PERFORM pg_temp.ok(j->>'status' = 'rejected' AND j->>'error' = 'CL_PERIOD_ALREADY_DELIVERED',
                     're-comprobacion al completar: ' || j::text);

  -- Garantia en la base: dos entregas "entregadas" solapadas del mismo conector -> 23P01 (exclusion).
  v_id := gen_random_uuid();
  INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, format, compression, file_path, sha256)
  VALUES (v_id, 'a0000000-0000-0000-0000-000000000001', r::uuid, '2026-11-20', '2026-11-20', 'api', 'jsonl', 'gzip',
          'x/' || v_id, pg_temp.sha(53));
  e := pg_temp.raises(format('UPDATE public.cl_deliveries SET status = ''received'' WHERE id = %L', v_id));
  PERFORM pg_temp.ok(e LIKE '23P01:%', 'exclusion por solape: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('INSERT INTO public.cl_deliveries (account_id, feed_id, period_start, period_end, source, format, compression, file_path, sha256, status) VALUES (%L, %L, ''2026-11-19'', ''2026-11-21'', ''api'', ''csv'', ''none'', ''y'', %L, ''failed'')',
         'a0000000-0000-0000-0000-000000000001', r, pg_temp.sha(54)));
  PERFORM pg_temp.ok(e LIKE '23P01:%', 'exclusion con failed: ' || coalesce(e, 'ok'));
  -- Periodo contiguo sin solape: permitido.
  INSERT INTO public.cl_deliveries (account_id, feed_id, period_start, period_end, source, format, compression, file_path, sha256, status)
  VALUES ('a0000000-0000-0000-0000-000000000001', r::uuid, '2026-11-21', '2026-11-21', 'api', 'csv', 'none', 'z', pg_temp.sha(55), 'received');
END $$;

-- Fix 2: next_period salta el hueco entre planes (y la apertura acepta el periodo que devuelve).
DO $$
DECLARE
  g constant text := 'f0000000-0000-0000-0000-0000000000a8';
  c jsonb; j jsonb;
BEGIN
  j := pg_temp.op(g, '2026-11-09', '2026-11-15', pg_temp.sha(60), '2026-11-25 10:00+03');
  PERFORM pg_temp.put(j->>'file_path', 10);
  PERFORM public.cl_delivery_complete_core(g::uuid, (j->>'delivery_id')::uuid, 'api');
  c := public.cl_connector_config(g::uuid, '2026-12-15 10:00+03');
  -- El plan 2 empieza el miercoles 09/12: el periodo semanal alineado es lun 07..dom 13.
  PERFORM pg_temp.ok(c->'next_period'->>'period_start' = '2026-12-07' AND c->'next_period'->>'period_end' = '2026-12-13'
                     AND (c->'next_period'->>'deliverable')::boolean, 'salta el hueco: ' || (c->'next_period')::text);
  j := pg_temp.op(g, c->'next_period'->>'period_start', c->'next_period'->>'period_end', pg_temp.sha(61), '2026-12-15 10:00+03');
  PERFORM pg_temp.ok(j->>'status' = 'pending_upload', 'la apertura acepta el periodo propuesto');
  PERFORM pg_temp.put(j->>'file_path', 10);
  PERFORM public.cl_delivery_complete_core(g::uuid, (j->>'delivery_id')::uuid, 'api');
  c := public.cl_connector_config(g::uuid, '2026-12-15 10:00+03');
  PERFORM pg_temp.ok(c->'next_period'->>'period_start' = '2026-12-14' AND c->'next_period'->>'period_end' = '2026-12-20'
                     AND NOT (c->'next_period'->>'deliverable')::boolean, 'siguiente dentro del plan 2: ' || (c->'next_period')::text);
  j := pg_temp.op(g, '2026-12-14', '2026-12-20', pg_temp.sha(62), '2026-12-22 10:00+03');
  PERFORM pg_temp.put(j->>'file_path', 10);
  PERFORM public.cl_delivery_complete_core(g::uuid, (j->>'delivery_id')::uuid, 'api');
  c := public.cl_connector_config(g::uuid, '2026-12-22 10:00+03');
  PERFORM pg_temp.ok(c->'next_period' IS NULL OR jsonb_typeof(c->'next_period') = 'null',
                     'sin plan pendiente: ' || coalesce((c->'next_period')::text, 'NULL'));
END $$;

-- ================================================================ 5. cl_connector_config
DO $$
DECLARE
  c jsonb; e text; k text;
BEGIN
  c := public.cl_connector_config('f0000000-0000-0000-0000-0000000000a1', '2026-11-26 10:00+03');
  PERFORM pg_temp.ok(c->>'schema_version' = '4.0' AND c->'connector'->>'carrier' = 'CA'
                     AND c->'connector'->>'status' = 'active', 'conector: ' || (c->'connector')::text);
  PERFORM pg_temp.ok(c->>'date_timezone' = 'Africa/Nairobi', 'zona de fechas');
  PERFORM pg_temp.ok(c->'calendar' = '{"delivery_days":[1,4],"delivery_hour":3,"timezone":"Africa/Nairobi","deliveries_per_week":2,"frequency":"several_per_week"}'::jsonb,
                     'calendario: ' || (c->'calendar')::text);
  PERFORM pg_temp.ok(c->'fields'->'item_id'->>'field' = 'trk' AND c->'fields'->'product'->>'field' = 'svc'
                     AND c->'fields'->'scan_at' = '{"field":"ts","format":"DD/MM/YYYY HH24:MI","timezone":"Africa/Nairobi"}'::jsonb
                     AND c->'fields'->'place_ref'->>'field' = 'office' AND c->'fields'->'mode_ref'->>'field' = 'evt'
                     AND (c->>'mapping_complete')::boolean, 'campos: ' || (c->'fields')::text);
  PERFORM pg_temp.ok(c->'extra_fields' = '["weight"]'::jsonb, 'extras');
  PERFORM pg_temp.ok(c->'products' = '[{"code":"PR","carrier_codes":["EXP","EXP2"]}]'::jsonb, 'productos: ' || (c->'products')::text);
  PERFORM pg_temp.ok((c->>'include_all_scans')::boolean
                     AND c->'plans' = '[{"product":"PR","start_date":"2026-11-02","end_date":"2026-11-29","include_all_scans":true}]'::jsonb,
                     'planes: ' || (c->'plans')::text);
  PERFORM pg_temp.ok(c->'points' = '[{"place_ref":"HUB","mode_ref":null,"role":"intermediate","city_id":null,"city":null},
      {"place_ref":"MBA","mode_ref":null,"role":"destination","city_id":"c2000000-0000-0000-0000-000000000002","city":"City2"},
      {"place_ref":"NBO","mode_ref":"ADM","role":"origin","city_id":"c1000000-0000-0000-0000-000000000001","city":"City1"}]'::jsonb,
                     'puntos (sin el borrado): ' || (c->'points')::text);
  -- Ultima entregada: lun 23..mie 25 queda pending/rejected -> la ultima "entregada" es jue 19..dom 22 -> siguiente lun 23..mie 25.
  PERFORM pg_temp.ok(c->'next_period'->>'period_start' = '2026-11-23' AND c->'next_period'->>'period_end' = '2026-11-25'
                     AND (c->'next_period'->>'due_at')::timestamptz = '2026-11-26 03:00+03'
                     AND (c->'next_period'->>'deliverable')::boolean,
                     'siguiente periodo: ' || (c->'next_period')::text);
  PERFORM pg_temp.ok(c->'last_delivery'->>'period_end' = '2026-11-25', 'ultima entrega: ' || (c->'last_delivery')::text);
  PERFORM pg_temp.ok(c->'limits' = '{"max_file_bytes":524288000,"max_rows":5000000,"file_retention_days":30,"max_control_totals":10000}'::jsonb,
                     'topes: ' || (c->'limits')::text);
  PERFORM pg_temp.ok(c->'formats' = '{"format":["jsonl","csv"],"compression":["none"]}'::jsonb, 'formatos');
  -- Ninguna clave de datos personales en todo el documento.
  FOR k IN WITH RECURSIVE t(v) AS (SELECT c UNION ALL
             SELECT x.value FROM t, LATERAL (SELECT value FROM jsonb_each(CASE WHEN jsonb_typeof(t.v) = 'object' THEN t.v ELSE '{}' END)
                                             UNION ALL
                                             SELECT value FROM jsonb_array_elements(CASE WHEN jsonb_typeof(t.v) = 'array' THEN t.v ELSE '[]' END)) x)
           SELECT DISTINCT key FROM t, jsonb_object_keys(CASE WHEN jsonb_typeof(t.v) = 'object' THEN t.v ELSE '{}' END) key LOOP
    PERFORM pg_temp.ok(k !~ '(email|phone|mobile|address|recipient|sender|panelist)', 'clave sin datos personales: ' || k);
  END LOOP;

  -- Diario (en prueba) y semanal; sin entregas, el primer periodo contiene el inicio del plan.
  c := public.cl_connector_config('f0000000-0000-0000-0000-0000000000a4', '2026-11-26 10:00+03');
  PERFORM pg_temp.ok(c->'calendar'->>'frequency' = 'daily' AND c->'connector'->>'status' = 'testing'
                     AND NOT (c->>'include_all_scans')::boolean, 'diario');
  -- Las entregas de prueba (24/11 procesada, 23/11 recibida) no consumen periodos: sigue el primero del plan.
  PERFORM pg_temp.ok(c->'next_period'->>'period_start' = '2026-11-02' AND c->'next_period'->>'period_end' = '2026-11-02',
                     'diario en prueba: las entregas de prueba no cuentan: ' || (c->'next_period')::text);
  c := public.cl_connector_config('f0000000-0000-0000-0000-0000000000b2', '2026-11-03 10:00+00');
  PERFORM pg_temp.ok(c->'calendar'->>'frequency' = 'weekly' AND c->'calendar'->>'timezone' = 'UTC' AND c->>'date_timezone' = 'UTC',
                     'semanal en UTC');
  PERFORM pg_temp.ok(c->'next_period'->>'period_start' = '2026-11-02' AND c->'next_period'->>'period_end' = '2026-11-08'
                     AND (c->'next_period'->>'due_at')::timestamptz = '2026-11-09 03:00+00'
                     AND NOT (c->'next_period'->>'deliverable')::boolean,
                     'semanal: primer periodo del plan, aun no entregable: ' || (c->'next_period')::text);
  PERFORM pg_temp.ok(c->'products' = '[{"code":"PB","carrier_codes":["PB"]}]'::jsonb AND c->'points' = '[]'::jsonb
                     AND NOT (c->>'mapping_complete')::boolean, 'cuenta 2 sin equivalencias ni puntos');
  e := pg_temp.raises('SELECT public.cl_connector_config(''f0000000-0000-0000-0000-0000000000ff'')');
  PERFORM pg_temp.ok(e LIKE '22023:CL_FEED_NOT_FOUND%', 'config de conector inexistente');
END $$;

-- Entrega de A2 (para el aislamiento).
SELECT pg_temp.op('f0000000-0000-0000-0000-0000000000b2', '2026-11-16', '2026-11-22', pg_temp.sha(20), '2026-11-25 10:00+00');
SELECT set_config('t.n', (SELECT count(*) FROM public.cl_deliveries)::text, true);

-- ================================================================ 6. RLS, aislamiento, subida manual y Storage
SET ROLE authenticated;
DO $$
DECLARE
  a1 constant text := 'f0000000-0000-0000-0000-0000000000a1';
  e text; j jsonb; v_path text; v_api_path text;
  m constant text := 'f0000000-0000-0000-0000-0000000000a7';
  v_day date := (now() AT TIME ZONE 'Africa/Nairobi')::date - 2;
BEGIN
  -- AM de A1: ve solo las de A1 (con View o Edit en cl_connectors / cl_monitor).
  PERFORM pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_deliveries) = current_setting('t.n')::bigint - 1, 'AM A1 ve las de A1');
  PERFORM pg_temp.ok(NOT EXISTS (SELECT 1 FROM public.cl_deliveries WHERE account_id = 'a0000000-0000-0000-0000-000000000002'),
                     'AM A1 no ve las de A2');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_delivery_strata) = 1, 'AM A1 ve sus estratos');
  e := pg_temp.raises(format('INSERT INTO public.cl_deliveries (account_id, feed_id, period_start, period_end, source, format, compression, file_path, sha256) VALUES (%L, %L, ''2026-11-30'', ''2026-11-30'', ''api'', ''csv'', ''none'', ''x'', %L)',
         'a0000000-0000-0000-0000-000000000001', a1, pg_temp.sha(30)));
  PERFORM pg_temp.ok(e LIKE '42501:%', 'sin INSERT directo: ' || coalesce(e, 'ok'));
  e := pg_temp.raises('UPDATE public.cl_deliveries SET error = ''x'' WHERE true');
  PERFORM pg_temp.ok(e LIKE '42501:%', 'sin UPDATE directo: ' || coalesce(e, 'ok'));
  e := pg_temp.raises('DELETE FROM public.cl_deliveries WHERE true');
  PERFORM pg_temp.ok(e LIKE '42501:%', 'sin DELETE directo: ' || coalesce(e, 'ok'));
  e := pg_temp.raises('SELECT count(*) FROM public.cl_delivery_rows');
  PERFORM pg_temp.ok(e LIKE '42501:%', 'zona de paso cerrada: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_delivery_open(%L, ''2026-11-23'', ''2026-11-25'', %L, ''[]'')', a1, pg_temp.sha(31)));
  PERFORM pg_temp.ok(e LIKE '42501:%', 'cl_delivery_open cerrada a la web: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_connector_config(%L)', a1));
  PERFORM pg_temp.ok(e LIKE '42501:%', 'cl_connector_config cerrada a la web: ' || coalesce(e, 'ok'));

  -- Subida manual en el conector diario M (reloj real: anteayer, fecha local de la cuenta).
  j := public.cl_manual_delivery_open(m::uuid, v_day, v_day, pg_temp.sha(40), '[]', 'csv');
  v_path := j->>'file_path';
  PERFORM pg_temp.ok(j->>'status' = 'pending_upload' AND j->>'source' = 'manual' AND v_path LIKE '%.csv', 'apertura manual: ' || j::text);
  PERFORM pg_temp.ok((SELECT created_by = '93000000-0000-0000-0000-000000000093' FROM public.cl_deliveries
                       WHERE id = (j->>'delivery_id')::uuid), 'created_by');
  -- Storage: sube a la ruta de su entrega manual; no a otra ruta, ni a la de una entrega por API.
  INSERT INTO storage.objects (bucket_id, name, metadata) VALUES ('cl-deliveries', v_path, '{"size": 99}');
  e := pg_temp.raises(format('INSERT INTO storage.objects (bucket_id, name) VALUES (''cl-deliveries'', %L)',
         'a0000000-0000-0000-0000-000000000001/' || a1 || '/otro.csv'));
  PERFORM pg_temp.ok(e LIKE '42501:%', 'ruta libre prohibida: ' || coalesce(e, 'ok'));
  SELECT file_path INTO v_api_path FROM public.cl_deliveries WHERE status = 'pending_upload' AND source = 'api'
   AND account_id = 'a0000000-0000-0000-0000-000000000001' LIMIT 1;
  PERFORM pg_temp.ok(v_api_path IS NOT NULL, 'hay una entrega API pendiente');
  e := pg_temp.raises(format('INSERT INTO storage.objects (bucket_id, name) VALUES (''cl-deliveries'', %L)', v_api_path));
  PERFORM pg_temp.ok(e LIKE '42501:%', 'ruta de entrega API prohibida: ' || coalesce(e, 'ok'));
  PERFORM pg_temp.ok((SELECT count(*) FROM storage.objects WHERE name = v_path) = 1, 'AM lee su fichero');
  -- Completar a mano.
  e := pg_temp.raises(format('SELECT public.cl_delivery_complete_core(%L, %L, ''api'')', m, j->>'delivery_id'));
  PERFORM pg_temp.ok(e LIKE '42501:%', 'la web no llama al nucleo: ' || coalesce(e, 'ok'));
  j := public.cl_manual_delivery_complete(m::uuid, (j->>'delivery_id')::uuid);
  PERFORM pg_temp.ok(j->>'status' = 'received' AND (j->>'file_bytes')::bigint = 99, 'completada a mano: ' || j::text);
  -- Ya no esta pending_upload: no se puede volver a subir a esa ruta (ni sustituir: sin UPDATE / DELETE).
  e := pg_temp.raises(format('INSERT INTO storage.objects (bucket_id, name) VALUES (''cl-deliveries'', %L)', v_path));
  PERFORM pg_temp.ok(e LIKE '42501:%', 'subida tras completar: ' || coalesce(e, 'ok'));
  UPDATE storage.objects SET metadata = '{"size": 1}' WHERE name = v_path;
  DELETE FROM storage.objects WHERE name = v_path;
  RESET ROLE;
  PERFORM pg_temp.ok((SELECT metadata->>'size' = '99' FROM storage.objects WHERE name = v_path), 'sin UPDATE / DELETE del fichero');
  SET LOCAL ROLE authenticated;

  -- APM (cl_connectors solo View): ve, pero no abre ni completa ni sube.
  PERFORM pg_temp.as_user('94000000-0000-0000-0000-000000000094', 'authenticated');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_deliveries) > 0, 'APM ve las entregas');
  PERFORM pg_temp.ok((SELECT count(*) FROM storage.objects WHERE name = v_path) = 1, 'APM lee el fichero');
  e := pg_temp.raises(format('SELECT public.cl_manual_delivery_open(%L, %L, %L, %L, ''[]'')',
         m, v_day - 1, v_day - 1, pg_temp.sha(41)));
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'APM no abre: ' || coalesce(e, 'ok'));

  -- Sin acceso a Carrier Link: no ve nada.
  PERFORM pg_temp.as_user('95000000-0000-0000-0000-000000000095', 'authenticated');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_deliveries) = 0, 'sin acceso no ve entregas');
  PERFORM pg_temp.ok((SELECT count(*) FROM storage.objects WHERE name = v_path) = 0, 'sin acceso no ve el fichero');

  -- Usuario de A2: no ve A1, no abre en A1 (mismo 42501 que un conector inexistente), no sube a rutas de A1.
  PERFORM pg_temp.as_user('92000000-0000-0000-0000-000000000092', 'authenticated');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_deliveries) = 1
                     AND NOT EXISTS (SELECT 1 FROM public.cl_deliveries WHERE account_id = 'a0000000-0000-0000-0000-000000000001'),
                     'A2 solo ve lo suyo');
  PERFORM pg_temp.ok((SELECT count(*) FROM storage.objects WHERE name = v_path) = 0, 'A2 no ve el fichero de A1');
  e := pg_temp.raises(format('SELECT public.cl_manual_delivery_open(%L, %L, %L, %L, ''[]'')',
         m, v_day - 1, v_day - 1, pg_temp.sha(42)));
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'A2 no abre en A1: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_manual_delivery_open(%L, %L, %L, %L, ''[]'')',
         'f0000000-0000-0000-0000-0000000000ff', v_day - 1, v_day - 1, pg_temp.sha(42)));
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'inexistente: mismo error');
  e := pg_temp.raises(format('SELECT public.cl_manual_delivery_complete(%L, gen_random_uuid())', m));
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'A2 no completa en A1');

  -- Superadmin: ve todo.
  PERFORM pg_temp.as_user('97000000-0000-0000-0000-000000000097', 'authenticated');
  PERFORM pg_temp.ok((SELECT count(*) FROM public.cl_deliveries) = current_setting('t.n')::bigint + 1, 'superadmin ve todo');
END $$;
RESET ROLE;

-- Revision final (I1): un usuario CON el derecho pero sin cuenta activa (profiles.account_id NULL) no pasa la guarda
-- (antes: account_id = NULL daba NULL y el IF no saltaba).
-- Hoy no se puede dar (check_account_role + account_id inmutable): se simula dentro de esta transaccion de prueba
-- (ROLLBACK) quitando la restriccion y sin disparadores para este UPDATE. La guarda debe negar igual.
ALTER TABLE public.profiles DROP CONSTRAINT check_account_role;
SET session_replication_role = replica;
UPDATE public.profiles SET account_id = NULL WHERE id = '93000000-0000-0000-0000-000000000093';
SET session_replication_role = origin;
SET ROLE authenticated;
DO $$
DECLARE e text; v_day date := (now() AT TIME ZONE 'Africa/Nairobi')::date - 4;
BEGIN
  PERFORM pg_temp.as_user('93000000-0000-0000-0000-000000000093', 'authenticated');
  e := pg_temp.raises(format('SELECT public.cl_manual_delivery_open(%L, %L, %L, %L, ''[]'')',
         'f0000000-0000-0000-0000-0000000000a7', v_day, v_day, pg_temp.sha(43)));
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'sin cuenta activa no abre: ' || coalesce(e, 'ok'));
  e := pg_temp.raises(format('SELECT public.cl_manual_delivery_complete(%L, gen_random_uuid())', 'f0000000-0000-0000-0000-0000000000a7'));
  PERFORM pg_temp.ok(e = '42501:CL_FORBIDDEN', 'sin cuenta activa no completa: ' || coalesce(e, 'ok'));
END $$;
RESET ROLE;
SET session_replication_role = replica;
UPDATE public.profiles SET account_id = 'a0000000-0000-0000-0000-000000000001' WHERE id = '93000000-0000-0000-0000-000000000093';
SET session_replication_role = origin;

-- anon: nada.
SET ROLE anon;
DO $$
BEGIN
  PERFORM pg_temp.ok(pg_temp.raises('SELECT 1 FROM public.cl_deliveries') LIKE '42501:%', 'anon sin lectura');
  PERFORM pg_temp.ok(pg_temp.raises('SELECT public.cl_manual_delivery_open(gen_random_uuid(), current_date, current_date, ''x'', ''[]'')') LIKE '42501:%',
                     'anon sin funciones');
END $$;
RESET ROLE;


-- Entregas de prueba (conector en Pruebas): no consumen el periodo. Se pueden repetir, no cuentan para next_period ni
-- para el solape (restriccion EXCLUDE parcial WHERE NOT is_test) y una entrega real posterior del mismo periodo se
-- acepta. Siguen exigiendo un plan activo.
DO $$
DECLARE
  t  text := 'f0000000-0000-0000-0000-0000000000a4';
  v_now text := '2026-11-26 10:00+03';
  j1 jsonb; j2 jsonb; j3 jsonb; j jsonb; c jsonb; e text;
BEGIN
  UPDATE public.cl_feeds SET status = 'testing' WHERE id = t::uuid;
  j1 := pg_temp.op(t, '2026-11-02', '2026-11-02', pg_temp.sha(90), v_now);
  PERFORM pg_temp.ok((j1->>'is_test')::boolean AND j1->>'status' = 'pending_upload', 'prueba 1 abierta');
  PERFORM pg_temp.put(j1->>'file_path', 10);
  j := public.cl_delivery_complete_core(t::uuid, (j1->>'delivery_id')::uuid, 'api');
  PERFORM pg_temp.ok(j->>'status' = 'received', 'prueba 1 recibida: ' || j::text);
  -- Misma prueba con el mismo fichero: idempotente.
  j := pg_temp.op(t, '2026-11-02', '2026-11-02', pg_temp.sha(90), v_now);
  PERFORM pg_temp.ok((j->>'existing')::boolean AND j->>'delivery_id' = j1->>'delivery_id', 'prueba idempotente');
  -- Segunda prueba del mismo periodo con otro fichero: aceptada (no 409), y se completa sin rechazo por solape.
  j2 := pg_temp.op(t, '2026-11-02', '2026-11-02', pg_temp.sha(91), v_now);
  PERFORM pg_temp.ok((j2->>'is_test')::boolean AND NOT (j2->>'existing')::boolean
                     AND j2->>'delivery_id' <> j1->>'delivery_id', 'segunda prueba del mismo periodo aceptada');
  PERFORM pg_temp.put(j2->>'file_path', 10);
  j := public.cl_delivery_complete_core(t::uuid, (j2->>'delivery_id')::uuid, 'api');
  PERFORM pg_temp.ok(j->>'status' = 'received', 'segunda prueba recibida (sin solape): ' || j::text);
  PERFORM pg_temp.ok((SELECT status FROM public.cl_deliveries WHERE id = (j1->>'delivery_id')::uuid) = 'received',
                     'la primera prueba no se sustituye');
  -- next_period sigue proponiendo el periodo.
  c := public.cl_connector_config(t::uuid, v_now::timestamptz);
  PERFORM pg_temp.ok(c->'next_period'->>'period_start' = '2026-11-02', 'tras las pruebas sigue el 02/11: ' || (c->'next_period')::text);
  -- Una prueba en un periodo fuera del calendario o sin plan sigue fallando.
  e := pg_temp.raises(pg_temp.op_sql(t, '2026-12-05', '2026-12-05', pg_temp.sha(92), '2026-12-10 10:00+03'));
  PERFORM pg_temp.ok(e LIKE '22023:CL_NO_ACTIVE_PLAN%', 'prueba sin plan: ' || coalesce(e, 'ok'));

  -- Paso a Activo: la entrega real del mismo periodo (incluso con el mismo fichero que una prueba) es otra entrega.
  UPDATE public.cl_feeds SET status = 'active' WHERE id = t::uuid;
  j3 := pg_temp.op(t, '2026-11-02', '2026-11-02', pg_temp.sha(90), v_now);
  PERFORM pg_temp.ok(NOT (j3->>'is_test')::boolean AND NOT (j3->>'existing')::boolean
                     AND j3->>'delivery_id' NOT IN (j1->>'delivery_id', j2->>'delivery_id'), 'real aceptada tras pruebas');
  PERFORM pg_temp.put(j3->>'file_path', 10);
  j := public.cl_delivery_complete_core(t::uuid, (j3->>'delivery_id')::uuid, 'api');
  PERFORM pg_temp.ok(j->>'status' = 'received', 'real recibida: ' || j::text);
  c := public.cl_connector_config(t::uuid, v_now::timestamptz);
  PERFORM pg_temp.ok(c->'next_period'->>'period_start' = '2026-11-03', 'tras la real, el 03/11: ' || (c->'next_period')::text);
  -- Ahora el periodo real si esta consumido: otra real del 02/11 -> 409; una de prueba seguiria aceptandose.
  e := pg_temp.raises(pg_temp.op_sql(t, '2026-11-02', '2026-11-02', pg_temp.sha(93), v_now));
  PERFORM pg_temp.ok(e LIKE 'P0001:CL_PERIOD_ALREADY_DELIVERED%', 'segunda real: ' || coalesce(e, 'ok'));
  -- La restriccion EXCLUDE ignora las de prueba y vigila las reales.
  e := pg_temp.raises(format('UPDATE public.cl_deliveries SET status = ''received'', received_at = now()'
                             ' WHERE id = %L', (pg_temp.op(t, '2026-11-03', '2026-11-03', pg_temp.sha(94), v_now))->>'delivery_id'));
  PERFORM pg_temp.ok(e IS NULL, 'real del 03/11 sin solape: ' || coalesce(e, 'ok'));
  INSERT INTO public.cl_deliveries (account_id, feed_id, period_start, period_end, source, is_test, format, compression,
                                    file_path, sha256, status, received_at)
  VALUES ('a0000000-0000-0000-0000-000000000001', t::uuid, '2026-11-03', '2026-11-03', 'api', true, 'jsonl', 'none',
          'x/t/overlap-test.jsonl', pg_temp.sha(95), 'received', now());
  e := pg_temp.raises(format('INSERT INTO public.cl_deliveries (account_id, feed_id, period_start, period_end, source,'
         ' is_test, format, compression, file_path, sha256, status, received_at) VALUES (%L, %L, ''2026-11-03'','
         ' ''2026-11-03'', ''api'', false, ''jsonl'', ''none'', ''x/t/overlap-real.jsonl'', %L, ''received'', now())',
         'a0000000-0000-0000-0000-000000000001', t, pg_temp.sha(96)));
  PERFORM pg_temp.ok(e LIKE '23P01:%', 'dos reales solapadas -> 23P01: ' || coalesce(e, 'ok'));
  -- btree_gist vive en el esquema extensions (en remoto no estaba instalada: la instala la migracion) y la restriccion
  -- funciona aunque el search_path no incluya extensions.
  PERFORM pg_temp.ok((SELECT n.nspname FROM pg_extension x JOIN pg_namespace n ON n.oid = x.extnamespace
                       WHERE x.extname = 'btree_gist') = 'extensions', 'btree_gist en extensions');
  PERFORM set_config('search_path', 'public', true);
  e := pg_temp.raises(format('INSERT INTO public.cl_deliveries (account_id, feed_id, period_start, period_end, source,'
         ' is_test, format, compression, file_path, sha256, status, received_at) VALUES (%L, %L, ''2026-11-03'','
         ' ''2026-11-03'', ''api'', false, ''jsonl'', ''none'', ''x/t/overlap-real2.jsonl'', %L, ''received'', now())',
         'a0000000-0000-0000-0000-000000000001', t, pg_temp.sha(97)));
  PERFORM set_config('search_path', 'public, extensions', true);
  PERFORM pg_temp.ok(e LIKE '23P01:%', 'solape con search_path = public -> 23P01: ' || coalesce(e, 'ok'));
  UPDATE public.cl_feeds SET status = 'testing' WHERE id = t::uuid;
END $$;

ROLLBACK;
