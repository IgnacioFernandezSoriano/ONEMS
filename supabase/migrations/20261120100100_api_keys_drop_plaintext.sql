-- Retira la clave en claro: key_hash pasa a obligatorio y se elimina api_key.
-- Antes, vuelca a hash cualquier fila insertada por la web antigua durante la ventana de despliegue.
SELECT public.api_keys_backfill_hash();
DROP TRIGGER IF EXISTS api_keys_sync_hash ON public.api_keys;
DROP FUNCTION IF EXISTS public.api_keys_sync_hash();

ALTER TABLE public.api_keys ALTER COLUMN key_hash SET NOT NULL;
DROP FUNCTION public.api_keys_backfill_hash();
ALTER TABLE public.api_keys DROP COLUMN api_key;

-- Las claves solo se crean/desactivan con api_key_issue / api_key_deactivate (SECURITY DEFINER);
-- ninguna escritura directa sobre la tabla desde la web. RLS (lectura) se mantiene.
REVOKE INSERT, UPDATE, DELETE ON public.api_keys FROM anon, authenticated;
