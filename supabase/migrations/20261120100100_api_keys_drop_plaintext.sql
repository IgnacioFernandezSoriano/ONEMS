-- Retira la clave en claro: key_hash pasa a obligatorio y se elimina api_key.
ALTER TABLE public.api_keys ALTER COLUMN key_hash SET NOT NULL;
DROP FUNCTION public.api_keys_backfill_hash();
ALTER TABLE public.api_keys DROP COLUMN api_key;
