-- Deshacer en la lista de Allocation Plans (últimas 5 acciones por cuenta) y borrado de muestras por compensar.
--
-- Decisión de Ignacio (18/11/2026): red de seguridad para el Allocation Plan Manager. Un botón "Deshacer" en la
-- lista de Allocation Plans deshace la última acción; pulsando otra vez, la anterior; como máximo 5 pasos atrás.
-- La pila es POR CUENTA (un manager puede arreglar el error de otro). El balanceo queda fuera.
--
-- Cómo funciona:
--   * Las acciones de la lista que se pueden deshacer pasan por estas funciones (no por escrituras directas):
--       plan_action_update  -> cambiar en bloque (nodo origen/destino, fecha), cancelar en bloque, editar una fila
--       plan_action_delete  -> borrar en bloque envíos del plan y muestras por compensar (deferred_samples pending)
--       plan_action_create  -> crear un registro nuevo
--     Cada una, en la misma transacción, aplica el cambio y guarda en public.plan_undo_log la foto "antes" y la
--     foto "después" (tras el cambio, con el efecto de los disparadores incluido) de las filas que toca.
--   * plan_undo_last revierte la entrada más reciente de la cuenta fila a fila y la borra. Si una fila cambió
--     después de la acción (el bot la marcó enviada, otra persona la editó, el balanceo la movió o la borró),
--     esa fila no se toca y se informa en skipped / skipped_ids. Las demás sí se deshacen.
--   * Se guardan como mucho 5 entradas por cuenta: al registrar una nueva se borran las más antiguas.
--   * Marcar enviado / recibido NO entra (disparan la transferencia a one_db y avisos): el parche rechaza
--     status 'sent' y 'received'.
--
-- Sustituye a la función delete_deferred_samples de la misma rama (nunca se aplicó en la base): ahora ese
-- borrado es parte de plan_action_delete y queda en el diario.
--
-- Todas las funciones fijan TimeZone = UTC para que las fotos jsonb (fechas con zona) se escriban y se comparen
-- siempre igual, sea cual sea la zona de la sesión que llama.

-- ===================== Diario =====================
CREATE TABLE IF NOT EXISTS public.plan_undo_log (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  account_id      uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  user_id         uuid,
  user_name       text,
  action          text NOT NULL CHECK (action IN ('delete','update','cancel','edit','create')),
  n_rows          integer NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  before_details  jsonb NOT NULL DEFAULT '[]'::jsonb,
  after_details   jsonb NOT NULL DEFAULT '[]'::jsonb,
  before_deferred jsonb NOT NULL DEFAULT '[]'::jsonb
);
CREATE INDEX IF NOT EXISTS plan_undo_log_account_idx ON public.plan_undo_log (account_id, id DESC);

COMMENT ON TABLE public.plan_undo_log IS
  'Diario de deshacer de la lista de Allocation Plans: últimas 5 acciones por cuenta con la foto antes/después.';

ALTER TABLE public.plan_undo_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS plan_undo_log_select ON public.plan_undo_log;
CREATE POLICY plan_undo_log_select ON public.plan_undo_log
  FOR SELECT TO authenticated
  USING (account_id = public.current_user_account_id() OR public.is_superadmin());
-- Solo lectura para los usuarios: se escribe únicamente desde las funciones de abajo.
REVOKE ALL ON public.plan_undo_log FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.plan_undo_log TO authenticated;
GRANT ALL ON public.plan_undo_log TO service_role;

-- ===================== Ayudantes internos (sin permiso para usuarios) =====================

-- Comprueba que el usuario puede actuar sobre la cuenta (la suya o cualquiera si es superadmin).
CREATE OR REPLACE FUNCTION public.plan_undo_authorize(p_account_id uuid)
RETURNS void LANGUAGE plpgsql SET search_path = '' AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  IF p_account_id IS NULL
     OR NOT (p_account_id = public.current_user_account_id() OR public.is_superadmin()) THEN
    RAISE EXCEPTION 'Sin permiso sobre la cuenta %', p_account_id USING ERRCODE = 'insufficient_privilege';
  END IF;
END $$;

-- Cuenta única de un conjunto de ids; si mezclan cuentas, error. NULL si ninguno existe.
CREATE OR REPLACE FUNCTION public.plan_undo_account_of(p_detail_ids uuid[], p_deferred_ids uuid[])
RETURNS uuid LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
  v_accounts uuid[];
BEGIN
  SELECT array_agg(DISTINCT x.account_id) INTO v_accounts FROM (
    SELECT d.account_id FROM public.allocation_plan_details d WHERE d.id = ANY (p_detail_ids)
    UNION
    SELECT f.account_id FROM public.deferred_samples f WHERE f.id = ANY (p_deferred_ids)) x;
  IF cardinality(v_accounts) > 1 THEN
    RAISE EXCEPTION 'Las filas son de cuentas distintas' USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v_accounts[1];
END $$;

-- Candado por cuenta: acciones y deshacer de una misma cuenta van de una en una, así dos pulsaciones
-- simultáneas de Deshacer nunca deshacen la misma entrada.
CREATE OR REPLACE FUNCTION public.plan_undo_lock(p_account_id uuid)
RETURNS void LANGUAGE sql SET search_path = '' AS $$
  SELECT pg_advisory_xact_lock(hashtext('plan_undo:' || p_account_id::text));
$$;

-- Columnas de allocation_plan_details (en orden), sin las excluidas.
CREATE OR REPLACE FUNCTION public.plan_undo_detail_columns(p_exclude text[])
RETURNS text[] LANGUAGE sql STABLE SET search_path = '' AS $$
  SELECT coalesce(array_agg(a.attname::text ORDER BY a.attnum), '{}')
    FROM pg_catalog.pg_attribute a
   WHERE a.attrelid = 'public.allocation_plan_details'::regclass
     AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = ''
     AND NOT (a.attname::text = ANY (p_exclude));
$$;

-- Guarda una entrada y deja solo las 5 más recientes de la cuenta (orden por id: dentro de una misma
-- transacción created_at es igual para todas).
CREATE OR REPLACE FUNCTION public.plan_undo_record(p_account_id uuid, p_action text, p_n_rows integer,
  p_before_details jsonb, p_after_details jsonb, p_before_deferred jsonb)
RETURNS void LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
  v_name text;
BEGIN
  SELECT coalesce(nullif(p.full_name, ''), p.email) INTO v_name FROM public.profiles p WHERE p.id = auth.uid();
  INSERT INTO public.plan_undo_log (account_id, user_id, user_name, action, n_rows,
                                    before_details, after_details, before_deferred)
  VALUES (p_account_id, auth.uid(), v_name, p_action, p_n_rows,
          coalesce(p_before_details, '[]'), coalesce(p_after_details, '[]'), coalesce(p_before_deferred, '[]'));
  DELETE FROM public.plan_undo_log l
   WHERE l.account_id = p_account_id
     AND l.id NOT IN (SELECT k.id FROM public.plan_undo_log k WHERE k.account_id = p_account_id
                       ORDER BY k.id DESC LIMIT 5);
END $$;

-- Aplica una sentencia de restauración sobre un array de fotos ($1). Primero de una vez (rápido; los
-- disparadores por sentencia corren una sola vez); si choca con una restricción (p. ej. el nodo o el plan ya no
-- existen, o el balanceo creó el mismo id a la vez), repite fila a fila y devuelve los ids que no se pudieron.
-- Cualquier error (restricción, disparador que lanza un error, foto antigua que ya no encaja con el esquema)
-- solo hace saltar esa fila: si abortara el deshacer, la entrada quedaría atascada en lo alto de la pila y la
-- cuenta ya no podría deshacer nada más.
CREATE OR REPLACE FUNCTION public.plan_undo_apply(p_sql text, p_rows jsonb)
RETURNS uuid[] LANGUAGE plpgsql SET search_path = '' AS $$
DECLARE
  v_row jsonb;
  v_failed uuid[] := '{}';
BEGIN
  IF jsonb_array_length(p_rows) = 0 THEN
    RETURN v_failed;
  END IF;
  BEGIN
    EXECUTE p_sql USING p_rows;
    RETURN v_failed;
  EXCEPTION
    WHEN query_canceled THEN RAISE;  -- tiempo agotado / cancelación: abortar, no reintentar
    WHEN OTHERS THEN
    NULL;  -- se reintenta fila a fila para salvar las que sí se pueden
  END;
  FOR v_row IN SELECT x FROM jsonb_array_elements(p_rows) x LOOP
    BEGIN
      EXECUTE p_sql USING jsonb_build_array(v_row);
    EXCEPTION
      WHEN query_canceled THEN RAISE;
      WHEN OTHERS THEN
      RAISE WARNING 'plan_undo_apply: fila % no restaurada: % (%)', v_row->>'id', SQLERRM, SQLSTATE;
      v_failed := v_failed || (v_row->>'id')::uuid;
    END;
  END LOOP;
  RETURN v_failed;
END $$;

REVOKE ALL ON FUNCTION public.plan_undo_authorize(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.plan_undo_account_of(uuid[], uuid[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.plan_undo_lock(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.plan_undo_detail_columns(text[]) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.plan_undo_record(uuid, text, integer, jsonb, jsonb, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.plan_undo_apply(text, jsonb) FROM PUBLIC, anon, authenticated;

-- ===================== Acciones =====================

-- Cambiar en bloque / cancelar / editar una fila. p_patch = {columna: valor}. Devuelve filas cambiadas.
CREATE OR REPLACE FUNCTION public.plan_action_update(p_ids uuid[], p_patch jsonb, p_action text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET "TimeZone" = 'UTC' AS $$
DECLARE
  v_allowed text[] := public.plan_undo_detail_columns(ARRAY['id','account_id','created_at','updated_at']);
  v_bad text;
  v_set text;
  v_account uuid;
  v_ids uuid[];
  v_before jsonb;
  v_after jsonb;
  v_n integer;
BEGIN
  IF p_action IS NULL OR p_action NOT IN ('update','cancel','edit') THEN
    RAISE EXCEPTION 'Acción no válida: %', p_action;
  END IF;
  IF p_patch IS NULL OR jsonb_typeof(p_patch) <> 'object' OR p_patch = '{}'::jsonb THEN
    RAISE EXCEPTION 'Cambio vacío o no válido';
  END IF;
  SELECT k INTO v_bad FROM jsonb_object_keys(p_patch) k WHERE NOT (k = ANY (v_allowed)) LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Campo no permitido: %', v_bad;
  END IF;
  -- Marcar enviado / recibido no se hace por aquí (no se puede deshacer: dispara one_db y avisos).
  IF p_patch->>'status' IN ('sent','received') THEN
    RAISE EXCEPTION 'Marcar enviado o recibido no se hace con esta función';
  END IF;
  IF coalesce(cardinality(p_ids), 0) = 0 THEN
    RETURN 0;
  END IF;

  v_account := public.plan_undo_account_of(p_ids, '{}');
  IF v_account IS NULL THEN
    RETURN 0;
  END IF;
  PERFORM public.plan_undo_authorize(v_account);
  PERFORM public.plan_undo_lock(v_account);

  SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY d.id), '[]'), coalesce(array_agg(d.id), '{}')
    INTO v_before, v_ids
    FROM (SELECT * FROM public.allocation_plan_details x
           WHERE x.id = ANY (p_ids) AND x.account_id = v_account FOR UPDATE) d;

  SELECT string_agg(format('%I = r.%I', k, k), ', ') INTO v_set FROM jsonb_object_keys(p_patch) k;
  EXECUTE format('UPDATE public.allocation_plan_details t SET %s
                    FROM jsonb_populate_record(NULL::public.allocation_plan_details, $1) r
                   WHERE t.id = ANY ($2)', v_set)
    USING p_patch, v_ids;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN
    RETURN 0;
  END IF;

  -- Foto "después" tomada tras la sentencia: incluye lo que hayan cambiado los disparadores.
  SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY d.id), '[]') INTO v_after
    FROM public.allocation_plan_details d WHERE d.id = ANY (v_ids);

  PERFORM public.plan_undo_record(v_account, p_action, v_n, v_before, v_after, '[]');
  RETURN v_n;
END $$;

-- Borrar en bloque envíos del plan y muestras por compensar (solo 'pending': las 'reintroduced' son historial).
CREATE OR REPLACE FUNCTION public.plan_action_delete(p_detail_ids uuid[], p_deferred_ids uuid[])
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET "TimeZone" = 'UTC' AS $$
DECLARE
  v_detail_ids uuid[] := coalesce(p_detail_ids, '{}');
  v_deferred_ids uuid[] := coalesce(p_deferred_ids, '{}');
  v_account uuid;
  v_before_d jsonb;
  v_before_f jsonb;
  v_ids_d uuid[];
  v_ids_f uuid[];
  v_nd integer := 0;
  v_nf integer := 0;
BEGIN
  IF cardinality(v_detail_ids) = 0 AND cardinality(v_deferred_ids) = 0 THEN
    RETURN jsonb_build_object('details', 0, 'deferred', 0);
  END IF;

  v_account := public.plan_undo_account_of(v_detail_ids, v_deferred_ids);
  IF v_account IS NULL THEN
    RETURN jsonb_build_object('details', 0, 'deferred', 0);
  END IF;
  PERFORM public.plan_undo_authorize(v_account);
  PERFORM public.plan_undo_lock(v_account);

  SELECT coalesce(jsonb_agg(to_jsonb(d) ORDER BY d.id), '[]'), coalesce(array_agg(d.id), '{}')
    INTO v_before_d, v_ids_d
    FROM (SELECT * FROM public.allocation_plan_details x
           WHERE x.id = ANY (v_detail_ids) AND x.account_id = v_account FOR UPDATE) d;
  SELECT coalesce(jsonb_agg(to_jsonb(f) ORDER BY f.id), '[]'), coalesce(array_agg(f.id), '{}')
    INTO v_before_f, v_ids_f
    FROM (SELECT * FROM public.deferred_samples x
           WHERE x.id = ANY (v_deferred_ids) AND x.account_id = v_account AND x.status = 'pending' FOR UPDATE) f;

  DELETE FROM public.allocation_plan_details d WHERE d.id = ANY (v_ids_d);
  GET DIAGNOSTICS v_nd = ROW_COUNT;
  DELETE FROM public.deferred_samples f WHERE f.id = ANY (v_ids_f);
  GET DIAGNOSTICS v_nf = ROW_COUNT;

  IF v_nd + v_nf > 0 THEN
    PERFORM public.plan_undo_record(v_account, 'delete', v_nd + v_nf, v_before_d, '[]', v_before_f);
  END IF;
  RETURN jsonb_build_object('details', v_nd, 'deferred', v_nf);
END $$;

-- Crear un registro nuevo. p_row = {columna: valor}, con account_id obligatorio; lo que no venga toma el
-- valor por defecto de la tabla. Devuelve el id.
CREATE OR REPLACE FUNCTION public.plan_action_create(p_row jsonb)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET "TimeZone" = 'UTC' AS $$
DECLARE
  v_allowed text[] := public.plan_undo_detail_columns(ARRAY[]::text[]);
  v_bad text;
  v_cols text;
  v_vals text;
  v_account uuid;
  v_id uuid;
  v_after jsonb;
BEGIN
  IF p_row IS NULL OR jsonb_typeof(p_row) <> 'object' THEN
    RAISE EXCEPTION 'Registro no válido';
  END IF;
  SELECT k INTO v_bad FROM jsonb_object_keys(p_row) k WHERE NOT (k = ANY (v_allowed)) LIMIT 1;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'Campo no permitido: %', v_bad;
  END IF;
  v_account := (p_row->>'account_id')::uuid;
  IF v_account IS NULL THEN
    RAISE EXCEPTION 'Falta account_id';
  END IF;
  PERFORM public.plan_undo_authorize(v_account);
  PERFORM public.plan_undo_lock(v_account);

  SELECT string_agg(format('%I', k), ', '), string_agg(format('r.%I', k), ', ')
    INTO v_cols, v_vals FROM jsonb_object_keys(p_row) k;
  EXECUTE format('INSERT INTO public.allocation_plan_details (%s)
                  SELECT %s FROM jsonb_populate_record(NULL::public.allocation_plan_details, $1) r
                  RETURNING id', v_cols, v_vals)
    INTO v_id USING p_row;

  SELECT to_jsonb(d) INTO v_after FROM public.allocation_plan_details d WHERE d.id = v_id;
  PERFORM public.plan_undo_record(v_account, 'create', 1, '[]', jsonb_build_array(v_after), '[]');
  RETURN v_id;
END $$;

-- ===================== Deshacer =====================

-- Deshace la entrada más reciente de la cuenta y la quita de la pila.
-- p_expected_id = id de la entrada que el usuario vio y confirmó. Si lo alto de la pila ya no es esa entrada
-- (otro manager actuó o deshizo entretanto, o la pila está vacía), no cambia nada y lanza el error
-- SQLSTATE 'PU001' con mensaje 'plan_undo_changed: ...'; la pantalla lo traduce y recarga la entrada.
-- Devuelve {"action", "restored", "skipped", "skipped_ids"}.
CREATE OR REPLACE FUNCTION public.plan_undo_last(p_account_id uuid, p_expected_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' SET "TimeZone" = 'UTC' AS $$
DECLARE
  e public.plan_undo_log%ROWTYPE;
  v_set text;
  v_ok uuid[];          -- filas que siguen como las dejó la acción (o que no existen, en un borrado)
  v_ok_f uuid[];
  v_all uuid[];
  v_failed uuid[] := '{}';
  v_skipped uuid[];
  v_rows jsonb;
  v_restored integer := 0;
BEGIN
  PERFORM public.plan_undo_authorize(p_account_id);
  PERFORM public.plan_undo_lock(p_account_id);

  SELECT * INTO e FROM public.plan_undo_log l
   WHERE l.account_id = p_account_id ORDER BY l.id DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND OR p_expected_id IS NULL OR e.id <> p_expected_id THEN
    RAISE EXCEPTION 'plan_undo_changed: la última acción ya no es la % (ahora: %)', p_expected_id,
      CASE WHEN FOUND THEN e.id::text ELSE 'ninguna' END
      USING ERRCODE = 'PU001';
  END IF;

  IF e.action IN ('update','cancel','edit','create') THEN
    SELECT coalesce(array_agg((a->>'id')::uuid), '{}') INTO v_all FROM jsonb_array_elements(e.after_details) a;
    PERFORM 1 FROM public.allocation_plan_details d WHERE d.id = ANY (v_all) FOR UPDATE;
    -- Choque con la realidad: solo se tocan las filas idénticas a la foto "después" (create y update).
    -- updated_at no cuenta: el disparador update_updated_at lo pone a now() en cada UPDATE, también al
    -- deshacer, y entonces deshacer dos acciones seguidas sobre la misma fila saltaría siempre la segunda.
    SELECT coalesce(array_agg((a->>'id')::uuid), '{}') INTO v_ok
      FROM jsonb_array_elements(e.after_details) a
     WHERE EXISTS (SELECT 1 FROM public.allocation_plan_details d
                    WHERE d.id = (a->>'id')::uuid AND to_jsonb(d) - 'updated_at' = a - 'updated_at');

    IF e.action = 'create' THEN
      DELETE FROM public.allocation_plan_details d WHERE d.id = ANY (v_ok);
    ELSE
      SELECT string_agg(format('%I = r.%I', c, c), ', ') INTO v_set
        FROM unnest(public.plan_undo_detail_columns(ARRAY['id'])) c;
      SELECT coalesce(jsonb_agg(b), '[]') INTO v_rows
        FROM jsonb_array_elements(e.before_details) b WHERE (b->>'id')::uuid = ANY (v_ok);
      v_failed := public.plan_undo_apply(format(
        'UPDATE public.allocation_plan_details t SET %s
           FROM jsonb_populate_recordset(NULL::public.allocation_plan_details, $1) r
          WHERE t.id = r.id', v_set), v_rows);
    END IF;

  ELSIF e.action = 'delete' THEN
    SELECT coalesce(array_agg((b->>'id')::uuid), '{}') INTO v_all FROM jsonb_array_elements(e.before_details) b;
    SELECT v_all || coalesce(array_agg((b->>'id')::uuid), '{}') INTO v_all
      FROM jsonb_array_elements(e.before_deferred) b;
    -- Se recrea con su mismo id solo si no existe ya (p. ej. el balanceo no la ha vuelto a crear).
    SELECT coalesce(array_agg((b->>'id')::uuid), '{}'), coalesce(jsonb_agg(b), '[]') INTO v_ok, v_rows
      FROM jsonb_array_elements(e.before_details) b
     WHERE NOT EXISTS (SELECT 1 FROM public.allocation_plan_details d WHERE d.id = (b->>'id')::uuid);
    v_failed := public.plan_undo_apply(
      'INSERT INTO public.allocation_plan_details
       SELECT * FROM jsonb_populate_recordset(NULL::public.allocation_plan_details, $1)', v_rows);
    SELECT coalesce(array_agg((b->>'id')::uuid), '{}'), coalesce(jsonb_agg(b), '[]') INTO v_ok_f, v_rows
      FROM jsonb_array_elements(e.before_deferred) b
     WHERE NOT EXISTS (SELECT 1 FROM public.deferred_samples f WHERE f.id = (b->>'id')::uuid);
    v_failed := v_failed || public.plan_undo_apply(
      'INSERT INTO public.deferred_samples
       SELECT * FROM jsonb_populate_recordset(NULL::public.deferred_samples, $1)', v_rows);
    v_ok := v_ok || v_ok_f;
  END IF;

  SELECT coalesce(array_agg(x), '{}') INTO v_skipped
    FROM unnest(v_all) x WHERE NOT (x = ANY (v_ok)) OR x = ANY (v_failed);
  v_restored := cardinality(v_all) - cardinality(v_skipped);

  DELETE FROM public.plan_undo_log l WHERE l.id = e.id;
  RETURN jsonb_build_object('action', e.action, 'restored', v_restored,
                            'skipped', cardinality(v_skipped), 'skipped_ids', to_jsonb(v_skipped));
END $$;

REVOKE ALL ON FUNCTION public.plan_action_update(uuid[], jsonb, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.plan_action_delete(uuid[], uuid[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.plan_action_create(jsonb) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.plan_undo_last(uuid, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.plan_action_update(uuid[], jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.plan_action_delete(uuid[], uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.plan_action_create(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.plan_undo_last(uuid, bigint) TO authenticated;

COMMENT ON FUNCTION public.plan_action_update(uuid[], jsonb, text) IS
  'Lista de Allocation Plans: cambia/cancela/edita filas y lo apunta en el diario de deshacer de la cuenta.';
COMMENT ON FUNCTION public.plan_action_delete(uuid[], uuid[]) IS
  'Lista de Allocation Plans: borra envíos y muestras por compensar pending y lo apunta en el diario de deshacer.';
COMMENT ON FUNCTION public.plan_action_create(jsonb) IS
  'Lista de Allocation Plans: crea un registro y lo apunta en el diario de deshacer.';
COMMENT ON FUNCTION public.plan_undo_last(uuid, bigint) IS
  'Deshace la última acción de la cuenta en la lista de Allocation Plans; salta las filas que cambiaron después.';
