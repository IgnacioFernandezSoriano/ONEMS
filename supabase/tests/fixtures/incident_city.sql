-- Fixture comun para tests de incidencias de indisponibilidad (se incluye dentro de un BEGIN del test).
-- Uso: \ir fixtures/incident_city.sql   (ruta relativa al fichero de test)
-- Sin muestras ni bajas: cada test inserta las suyas. No activa el JWT.
INSERT INTO public.accounts (id, name, slug) VALUES
  ('a0000000-0000-0000-0000-000000000001','Acc','acc'),
  ('a0000000-0000-0000-0000-000000000002','Acc2','acc2');
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Reg','R1');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City1','C1'),
  ('c2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City2','C2');
-- C1: N1, N2, N3 ; C2: N4
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N1'),
  ('b2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N2'),
  ('b3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N3'),
  ('b4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N4');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language, address_country) VALUES
  ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','P1','Pan1','p1@t.l','1','b1000000-0000-0000-0000-000000000001','active','en','KENYA'),
  ('e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','P2','Pan2','p2@t.l','2','b2000000-0000-0000-0000-000000000002','active','en',NULL),
  ('e3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','P3','Pan3','p3@t.l','3','b3000000-0000-0000-0000-000000000003','active','en',NULL),
  ('e4000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000001','P4','Pan4','p4@t.l','4','b4000000-0000-0000-0000-000000000004','active','en',NULL);
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','CA','Carrier');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR','Prod',48);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Mar27','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2027-03-01','2027-03-31'),
  ('cc000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','Apr27','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2027-04-01','2027-04-30');
-- Actores: 99 (cuenta 1) y 98 (cuenta 2)
INSERT INTO auth.users (id, email) VALUES
  ('99000000-0000-0000-0000-000000000099','actor@t.l'),
  ('98000000-0000-0000-0000-000000000098','actor2@t.l');
INSERT INTO public.profiles (id, email, full_name, role, account_id) VALUES
  ('99000000-0000-0000-0000-000000000099','actor@t.l','Actor','user','a0000000-0000-0000-0000-000000000001'),
  ('98000000-0000-0000-0000-000000000098','actor2@t.l','Actor2','user','a0000000-0000-0000-0000-000000000002');
-- Fase 3 (20261119100200_account_access_writes.sql): escribir exige Edit en la matriz de la cuenta.
-- Los actores 99 (A1) y 98 (A2) son upu_account_manager de su cuenta (Edit en todas las opciones de gestión).
-- Los tests de la propia matriz lo desactivan con \set fixture_sin_roles 1 antes del \ir.
\if :{?fixture_sin_roles}
\else
INSERT INTO public.account_user_role (account_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001','99000000-0000-0000-0000-000000000099','upu_account_manager'),
  ('a0000000-0000-0000-0000-000000000002','98000000-0000-0000-0000-000000000098','upu_account_manager');
\endif
