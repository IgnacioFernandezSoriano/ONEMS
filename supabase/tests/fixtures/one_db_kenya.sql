-- Fixture para tests de business time: cuenta Kenya (zona Africa/Nairobi, UTC+3). Se incluye dentro de un BEGIN.
-- Uso: \ir fixtures/one_db_kenya.sql   (ruta relativa al fichero de test)
INSERT INTO public.accounts (id, name, slug, timezone) VALUES
  ('a0000000-0000-0000-0000-000000000003','Ken','ken','Africa/Nairobi');
