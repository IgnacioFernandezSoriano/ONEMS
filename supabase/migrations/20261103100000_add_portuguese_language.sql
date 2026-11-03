-- Añade el portugués (pt) a los idiomas permitidos de cuentas y panelistas.
-- profiles.preferred_language no tiene restricción, así que no necesita cambios.

ALTER TABLE public.accounts DROP CONSTRAINT IF EXISTS accounts_default_language_check;
ALTER TABLE public.accounts ADD CONSTRAINT accounts_default_language_check
  CHECK ((default_language)::text = ANY (ARRAY['en','es','fr','ar','pt']::text[]));

ALTER TABLE public.panelists DROP CONSTRAINT IF EXISTS panelists_language_check;
ALTER TABLE public.panelists ADD CONSTRAINT panelists_language_check
  CHECK ((language)::text = ANY (ARRAY['en','es','fr','ar','pt']::text[]));

-- update_panelist_contact_v2 valida el idioma con una lista fija: se reescribe
-- la función viva cambiando solo esa lista (conserva permisos y el resto del cuerpo).
DO $$
DECLARE
  v_def text;
BEGIN
  v_def := pg_get_functiondef('public.update_panelist_contact_v2(uuid,text,text,text,text,text,text,text,text)'::regprocedure);
  IF position($q$NOT IN ('en','es','fr','ar')$q$ in v_def) = 0 THEN
    RAISE EXCEPTION 'update_panelist_contact_v2: lista de idiomas no encontrada';
  END IF;
  v_def := replace(v_def, $q$NOT IN ('en','es','fr','ar')$q$, $q$NOT IN ('en','es','fr','ar','pt')$q$);
  EXECUTE v_def;
END $$;
