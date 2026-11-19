-- Claves de API E2E protegidas: se guardan hasheadas (SHA-256), con nombre, ámbito y caducidad.
-- La columna api_key (texto claro) pasa a nullable; se elimina en una migración posterior.
-- Forward-only. No contiene ninguna clave real.

ALTER TABLE public.api_keys
  ADD COLUMN IF NOT EXISTS key_hash   text,
  ADD COLUMN IF NOT EXISTS key_prefix text,
  ADD COLUMN IF NOT EXISTS name       text,
  ADD COLUMN IF NOT EXISTS scope      text NOT NULL DEFAULT 'onedb_read',
  ADD COLUMN IF NOT EXISTS feed_id    uuid,
  ADD COLUMN IF NOT EXISTS expires_at timestamptz;

ALTER TABLE public.api_keys ALTER COLUMN api_key DROP NOT NULL;

ALTER TABLE public.api_keys DROP CONSTRAINT IF EXISTS api_keys_scope_check;
ALTER TABLE public.api_keys
  ADD CONSTRAINT api_keys_scope_check CHECK (scope IN ('onedb_read', 'carrier_feed'));
ALTER TABLE public.api_keys DROP CONSTRAINT IF EXISTS api_keys_key_hash_key;
ALTER TABLE public.api_keys ADD CONSTRAINT api_keys_key_hash_key UNIQUE (key_hash);

-- Backfill interno e idempotente: solo filas con clave en claro y sin hash.
CREATE OR REPLACE FUNCTION public.api_keys_backfill_hash()
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  UPDATE public.api_keys
     SET key_hash   = encode(digest(api_key, 'sha256'), 'hex'),
         key_prefix = left(api_key, 12),
         name       = coalesce(name, 'Clave ' || left(api_key, 12))
   WHERE api_key IS NOT NULL AND key_hash IS NULL;
$$;
REVOKE ALL ON FUNCTION public.api_keys_backfill_hash() FROM PUBLIC, anon, authenticated;

SELECT public.api_keys_backfill_hash();

-- Ventana de despliegue: la web antigua inserta filas con solo api_key (sin key_hash).
-- Este trigger completa hash, prefijo y nombre; se elimina en la migración siguiente.
CREATE OR REPLACE FUNCTION public.api_keys_sync_hash()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = public, extensions
AS $$
BEGIN
  IF NEW.api_key IS NOT NULL THEN
    NEW.key_hash   := encode(digest(NEW.api_key, 'sha256'), 'hex');
    NEW.key_prefix := left(NEW.api_key, 12);
    NEW.name       := COALESCE(NEW.name, 'Clave ' || NEW.key_prefix);
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.api_keys_sync_hash() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS api_keys_sync_hash ON public.api_keys;
CREATE TRIGGER api_keys_sync_hash
  BEFORE INSERT OR UPDATE OF api_key ON public.api_keys
  FOR EACH ROW EXECUTE FUNCTION public.api_keys_sync_hash();

-- Gestionan las claves: superadmin (personal de UPU) o el UPU Account Manager de la cuenta.
CREATE OR REPLACE FUNCTION public.is_upu_account_manager(p_account_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT auth.uid() IS NOT NULL AND p_account_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.account_user_role r
     WHERE r.account_id = p_account_id AND r.user_id = auth.uid() AND r.role = 'upu_account_manager')
$$;
REVOKE ALL ON FUNCTION public.is_upu_account_manager(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_upu_account_manager(uuid) TO authenticated;


-- Emisión: devuelve la clave en claro una sola vez; solo se guarda su hash.
CREATE OR REPLACE FUNCTION public.api_key_issue(
  p_account_id uuid,
  p_name text,
  p_scope text DEFAULT 'onedb_read',
  p_feed_id uuid DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL)
 RETURNS TABLE (id uuid, api_key text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_key text;
  v_id  uuid;
BEGIN
  IF NOT (public.is_superadmin() OR public.is_upu_account_manager(p_account_id)) THEN
    RAISE EXCEPTION 'No autorizado para gestionar claves de API en esta cuenta' USING ERRCODE = '42501';
  END IF;
  IF p_name IS NULL OR btrim(p_name) = '' OR length(btrim(p_name)) > 80 THEN
    RAISE EXCEPTION 'El nombre de la clave es obligatorio (máx. 80 caracteres)' USING ERRCODE = '22023';
  END IF;
  IF p_expires_at IS NOT NULL AND p_expires_at <= now() THEN
    RAISE EXCEPTION 'La fecha de caducidad debe ser futura' USING ERRCODE = '22023';
  END IF;
  IF p_scope IS NULL OR p_scope NOT IN ('onedb_read', 'carrier_feed') THEN
    RAISE EXCEPTION 'Ámbito de clave no válido: %', p_scope USING ERRCODE = '22023';
  END IF;

  v_key := 'onems_' || encode(gen_random_bytes(24), 'hex');
  INSERT INTO public.api_keys (account_id, key_hash, key_prefix, name, scope, feed_id, expires_at, created_by)
  VALUES (p_account_id, encode(digest(v_key, 'sha256'), 'hex'), left(v_key, 12), btrim(p_name), p_scope,
          p_feed_id, p_expires_at, auth.uid())
  RETURNING public.api_keys.id INTO v_id;

  RETURN QUERY SELECT v_id, v_key;
END $$;
REVOKE ALL ON FUNCTION public.api_key_issue(uuid, text, text, uuid, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.api_key_issue(uuid, text, text, uuid, timestamptz) TO authenticated;

-- Resolución (edge function, service_role): clave -> cuenta/ámbito si está activa y no caducada.
CREATE OR REPLACE FUNCTION public.api_key_resolve(p_key text)
 RETURNS TABLE (id uuid, account_id uuid, scope text, feed_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT k.id, k.account_id, k.scope, k.feed_id
    FROM public.api_keys k
   WHERE k.key_hash = encode(digest(p_key, 'sha256'), 'hex')
     AND k.is_active
     AND (k.expires_at IS NULL OR k.expires_at > now());
$$;
REVOKE ALL ON FUNCTION public.api_key_resolve(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.api_key_resolve(text) TO service_role;

-- Desactivación: misma regla que la emisión; es la única vía de escritura sobre la tabla desde la web.
CREATE OR REPLACE FUNCTION public.api_key_deactivate(p_key_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_account uuid;
BEGIN
  SELECT k.account_id INTO v_account FROM public.api_keys k WHERE k.id = p_key_id;
  IF v_account IS NULL OR NOT (public.is_superadmin() OR public.is_upu_account_manager(v_account)) THEN
    RAISE EXCEPTION 'No autorizado para gestionar claves de API en esta cuenta' USING ERRCODE = '42501';
  END IF;
  UPDATE public.api_keys SET is_active = false WHERE id = p_key_id;
END $$;
REVOKE ALL ON FUNCTION public.api_key_deactivate(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.api_key_deactivate(uuid) TO authenticated;
