-- Prueba de volumen de la tarea 2 (v4): 2.000.000 filas en la zona de paso (400.000 envios x 5 lecturas) de una
-- entrega semanal martes 10/11 .. lunes 16/11 (cruza W46/W47). 10 ciudades con un punto 'both' cada una y 1 punto
-- intermedio; 90 rutas x 2 semanas = 180 cuotas de 10. Las filas se insertan directamente (generate_series) en la
-- base local onems_vol (copia de onems_t). Nunca en la remota.
INSERT INTO public.accounts (id, name, slug, timezone) VALUES ('a0000000-0000-0000-0000-0000000000f1','VOL','vol','Africa/Nairobi');
INSERT INTO public.regions (id, account_id, name, code) VALUES ('e0000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-0000000000f1','R','R');
INSERT INTO public.cities (id, account_id, region_id, name, code)
SELECT ('c0000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, 'a0000000-0000-0000-0000-0000000000f1',
       'e0000000-0000-0000-0000-0000000000f1', 'City' || g, 'C' || g FROM generate_series(0, 9) g;
INSERT INTO public.carriers (id, account_id, code, name) VALUES ('ca000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-0000000000f1','CA','Carrier');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-0000000000f1','ca000000-0000-0000-0000-0000000000f1','PR','Prod',48);
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id)
SELECT ('d0000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid, 'a0000000-0000-0000-0000-0000000000f1',
       'PC' || g, 'PC' || g, 'City' || g, ('c0000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid
  FROM generate_series(0, 9) g;
INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role)
SELECT 'a0000000-0000-0000-0000-0000000000f1', ('d0000000-0000-0000-0000-0000000000' || lpad(g::text, 2, '0'))::uuid,
       'P' || g, 'Entry', 'carrier_scan', 'ca000000-0000-0000-0000-0000000000f1', 'P' || g, NULL, 'both'
  FROM generate_series(0, 9) g;
INSERT INTO public.readers (account_id, postal_center_id, name, type, capture_source, carrier_id, carrier_place_ref, carrier_mode_ref, e2e_role)
VALUES ('a0000000-0000-0000-0000-0000000000f1', NULL, 'HUB', 'Entry', 'carrier_scan', 'ca000000-0000-0000-0000-0000000000f1', 'HUB', NULL, 'none');
INSERT INTO public.cl_feeds (id, account_id, carrier_id, name, status, emit_days, emit_hour) VALUES
  ('f0000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-0000000000f1','ca000000-0000-0000-0000-0000000000f1','F','active','{2}',3);
INSERT INTO public.cl_field_mappings (account_id, carrier_id, standard_field, carrier_field, format, timezone) VALUES
  ('a0000000-0000-0000-0000-0000000000f1','ca000000-0000-0000-0000-0000000000f1','item_id','trk',NULL,NULL),
  ('a0000000-0000-0000-0000-0000000000f1','ca000000-0000-0000-0000-0000000000f1','product','svc',NULL,NULL),
  ('a0000000-0000-0000-0000-0000000000f1','ca000000-0000-0000-0000-0000000000f1','scan_at','ts','YYYY-MM-DD HH24:MI','Africa/Nairobi'),
  ('a0000000-0000-0000-0000-0000000000f1','ca000000-0000-0000-0000-0000000000f1','place_ref','office',NULL,NULL);
INSERT INTO public.cl_value_mappings (account_id, carrier_id, kind, carrier_value, onems_value) VALUES
  ('a0000000-0000-0000-0000-0000000000f1','ca000000-0000-0000-0000-0000000000f1','product','EXP','PR');
INSERT INTO public.cl_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date, status, feed_id) VALUES
  ('90000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-0000000000f1','P','ca000000-0000-0000-0000-0000000000f1','cb000000-0000-0000-0000-0000000000f1',1800,'2026-11-09','2026-11-22','active','f0000000-0000-0000-0000-0000000000f1');
INSERT INTO public.cl_plan_quotas (account_id, plan_id, origin_city_id, destination_city_id, iso_year, iso_week, period_start, period_end, samples_planned)
SELECT 'a0000000-0000-0000-0000-0000000000f1', '90000000-0000-0000-0000-0000000000f1',
       ('c0000000-0000-0000-0000-0000000000' || lpad(o::text, 2, '0'))::uuid, ('c0000000-0000-0000-0000-0000000000' || lpad(d::text, 2, '0'))::uuid,
       2026, w, CASE w WHEN 46 THEN date '2026-11-09' ELSE date '2026-11-16' END,
       CASE w WHEN 46 THEN date '2026-11-15' ELSE date '2026-11-22' END, 10
  FROM generate_series(0, 9) o, generate_series(0, 9) d, (VALUES (46), (47)) x(w) WHERE o <> d;

INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, format, compression,
                                  file_path, file_bytes, sha256, status, received_at, processing_started_at, rows_total, progress)
VALUES ('de000000-0000-0000-0000-0000000000f1','a0000000-0000-0000-0000-0000000000f1','f0000000-0000-0000-0000-0000000000f1',
        '2026-11-10','2026-11-16','api','jsonl','none','vol/f/d.jsonl', 300000000, repeat('a', 64), 'processing', now(), now(),
        2000000, jsonb_build_object('phase', 'resolve', 'cursor', 0, 'attempts', 1,
                                    'load', jsonb_build_object('offset', 300000000, 'rows', 2000000)));

-- 400.000 envios: origen o = i % 10 y destino distinto; salida un dia del 9 al 15/11, 3 lecturas en HUB y llegada
-- 1 o 2 dias despues (algunas fuera del periodo: end_out_of_period). Orden de filas = orden del fichero.
INSERT INTO public.cl_delivery_rows (delivery_id, row_no, item_id, product, scan_at_raw, place_ref)
SELECT 'de000000-0000-0000-0000-0000000000f1', (i - 1) * 5 + k + 1, 'TRK' || lpad(i::text, 9, '0'), 'EXP',
       to_char(timestamp '2026-11-09 08:00' + make_interval(days => i % 7, hours => k * 6 + (i % 2) * 24), 'YYYY-MM-DD HH24:MI'),
       CASE k WHEN 0 THEN 'P' || (i % 10) WHEN 4 THEN 'P' || ((i % 10 + 1 + (i / 10) % 9) % 10) ELSE 'HUB' END
  FROM generate_series(1, 400000) i, generate_series(0, 4) k;
ANALYZE public.cl_delivery_rows;
