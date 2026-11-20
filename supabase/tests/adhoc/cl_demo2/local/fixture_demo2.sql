-- LOCAL ONLY (Postgres portable 127.0.0.1:5433, database onems_t). Never run against the remote project.
-- Mimics the LIVE DEMO2 masters read on 2026-11-20 (inspect/0*.sql): same ids, names, codes (including the trailing
-- spaces of the carrier codes), postal centers and the A STANDARD delivery standards (4 days, equivalence 0).
-- Adds panelist one_db rows for DEMO2 and for a second account, so "panelist rows unchanged" can be checked.
\set ON_ERROR_STOP on
BEGIN;
INSERT INTO public.accounts (id, name, slug, timezone) VALUES
  ('f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'DEMO2', 'DEMO2', 'Europe/Madrid'),
  ('a0000000-0000-0000-0000-0000000000ff', 'OTHER', 'OTHER', 'Africa/Nairobi');
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('9649a4da-cb22-4d70-802b-0ce28bea9187', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'East', 'E'),
  ('6bca6b48-843e-45cb-bcc5-3127c53aca00', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'West', 'W');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('9ebc9d84-e121-42bf-a163-e8726448b796', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '9649a4da-cb22-4d70-802b-0ce28bea9187', 'Baltimore', 'BAL'),
  ('4e6b443c-a1c4-4533-9bf9-d2d67a0f405d', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '6bca6b48-843e-45cb-bcc5-3127c53aca00', 'Los Angeles', 'LA'),
  ('f86f46c1-98dd-4ec1-9cab-d435856c3125', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '9649a4da-cb22-4d70-802b-0ce28bea9187', 'New York', 'NY'),
  ('a47bbac3-0edb-46a5-8bd0-cb51dd70200d', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '9649a4da-cb22-4d70-802b-0ce28bea9187', 'Philadelphia', 'PHL'),
  ('b6d002e9-2c03-482b-9efb-0abaedd637f0', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '6bca6b48-843e-45cb-bcc5-3127c53aca00', 'Sacramento', 'SAC');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('856b4a5c-1716-4110-ac5e-0d7c909b9237', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'CARRIER A ', 'Carrier A'),
  ('5ea9f7ed-a96c-4f3c-b849-05dc80e3ca67', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'CARRIER B ', 'Carrier B');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('a42e2120-8909-4a7a-abad-b14822ddc3ce', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '856b4a5c-1716-4110-ac5e-0d7c909b9237', 'A EXPRESS', 'A EXPRESS', 24),
  ('8325a692-7e1c-40a6-9a54-59527d19634f', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '856b4a5c-1716-4110-ac5e-0d7c909b9237', 'A STANDARD', 'A STANDARD', 3),
  ('288a5c97-7a99-42a7-810c-84e793cb3f13', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '5ea9f7ed-a96c-4f3c-b849-05dc80e3ca67', 'B STANDARD', 'B STANDARD', 4);
INSERT INTO public.postal_centers (id, account_id, code, name, city, city_id) VALUES
  ('c395d565-e731-4d93-baf9-383a15d59568', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'BAL-LC', 'Baltimore Processing Center', 'Baltimore', '9ebc9d84-e121-42bf-a163-e8726448b796'),
  ('c374fe70-78a8-4fe5-9eca-dd715e90f09d', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'LA-LC', 'LA Local Processing Center', 'Los Angeles', '4e6b443c-a1c4-4533-9bf9-d2d67a0f405d'),
  ('3cb1d5b8-2785-4d66-9a7a-6ce24909b1fc', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'NY-LC', 'NY Local Processing Center', 'New York', 'f86f46c1-98dd-4ec1-9cab-d435856c3125'),
  ('5c1ef79d-c57d-41fa-aa2d-f38d9611ea2a', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'NY-RC', 'NY Regional Distribution Hub', 'New York', 'f86f46c1-98dd-4ec1-9cab-d435856c3125'),
  ('117f06f9-5ed5-4e40-b104-5e8f0baa8884', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'PHL-HUB', 'Philadelphia Regional Hub', 'Philadelphia', 'a47bbac3-0edb-46a5-8bd0-cb51dd70200d');
INSERT INTO public.readers (id, account_id, postal_center_id, reader_id, name, type) VALUES
  ('9be04ca4-ff22-4e29-a036-3d3135961029', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'c395d565-e731-4d93-baf9-383a15d59568', 'BAL-LC-ENTRY', 'Baltimore Processing Center - Entry', 'Entry'),
  ('41978558-8650-403e-9289-0638913ece79', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '5c1ef79d-c57d-41fa-aa2d-f38d9611ea2a', 'NY-RC-ENTRY', 'NY Regional Distribution Hub - Entry', 'Entry');
-- A STANDARD standards among Baltimore / New York (live ids), 4 days, no equivalence yet. Like the live account,
-- there is no A STANDARD standard to or from Philadelphia.
INSERT INTO public.delivery_standards (id, account_id, carrier_id, product_id, origin_city_id, destination_city_id, standard_time, time_unit) VALUES
  ('8afdb952-be52-450b-ac44-323f9c2973e3', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '856b4a5c-1716-4110-ac5e-0d7c909b9237', '8325a692-7e1c-40a6-9a54-59527d19634f', 'f86f46c1-98dd-4ec1-9cab-d435856c3125', '9ebc9d84-e121-42bf-a163-e8726448b796', 4, 'days'),
  ('79c2d399-1e46-44bd-b6d5-799af726ef03', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '856b4a5c-1716-4110-ac5e-0d7c909b9237', '8325a692-7e1c-40a6-9a54-59527d19634f', '9ebc9d84-e121-42bf-a163-e8726448b796', 'f86f46c1-98dd-4ec1-9cab-d435856c3125', 4, 'days'),
  ('6bbb6995-1165-4d88-a791-08ab6a0f9061', 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', '856b4a5c-1716-4110-ac5e-0d7c909b9237', '8325a692-7e1c-40a6-9a54-59527d19634f', '4e6b443c-a1c4-4533-9bf9-d2d67a0f405d', 'f86f46c1-98dd-4ec1-9cab-d435856c3125', 4, 'days');
-- Panelist E2E rows (DEMO2 and another account): must stay untouched by the whole test.
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name, sent_at, received_at, source_data_snapshot)
SELECT 'f4d823d2-93e6-4755-9a89-9da87e7fa86e', 'P' || g, 'Generated Plan - A STANDARD via Carrier A', 'Carrier A', 'A STANDARD',
       CASE WHEN g % 2 = 0 THEN 'Baltimore' ELSE 'New York' END, CASE WHEN g % 2 = 0 THEN 'New York' ELSE 'Baltimore' END,
       timestamptz '2026-02-02 09:00+01' + make_interval(days => g), timestamptz '2026-02-04 12:00+01' + make_interval(days => g + g % 3)
       , '{}'::jsonb
  FROM generate_series(1, 12) g;
INSERT INTO public.one_db (account_id, tag_id, plan_name, carrier_name, product_name, origin_city_name, destination_city_name, sent_at, received_at, source_data_snapshot)
SELECT 'a0000000-0000-0000-0000-0000000000ff', 'K' || g, 'Other plan', 'Other carrier', 'Other product', 'Nairobi', 'Mombasa',
       timestamptz '2026-10-05 09:00+03' + make_interval(days => g), timestamptz '2026-10-07 12:00+03' + make_interval(days => g)
       , '{}'::jsonb
  FROM generate_series(1, 5) g;
UPDATE public.one_db o SET on_time_delivery = public.one_db_on_time(o.business_transit_hours, o.business_transit_days, 4, 'days')
 WHERE o.account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e';
COMMIT;
