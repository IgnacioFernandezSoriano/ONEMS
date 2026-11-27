-- Carrier Link v4.1, tarea 8: control de incidencias de Carrier Link con avisos por correo (spec v4.1, R29-R32,
-- D24-D28). Forward-only; no se ha aplicado en ninguna base remota.
--
-- Tipos (una incidencia ABIERTA por conector y tipo, R32: lo nuevo se anade a su lista de periodos):
--   missing_delivery   pasa la hora de entrega del calendario + margen (config.missing_grace_hours, def. 6) y no hay
--                      entrega del periodo -> se abre / se anade el periodo. Se cierra sola con la primera entrega que
--                      se reciba, del periodo que sea (R31). Vigila cl_housekeeping (cada hora).
--   delivery_rejected  entrega rechazada por el fichero (huella, tamano, formato, filas...) o tras 3 fallos. Se cierra
--                      sola cuando todos sus periodos se han procesado bien.
--   high_rejection     la entrega procesada tiene la alerta rejected_ratio (> 20 % de envios invalidos, tarea 2). Se
--                      cierra sola con la siguiente entrega procesada sin esa alerta.
--   unknown_data       la entrega procesada tiene alertas unknown_product / unknown_reading_point. Se anade solo si hay
--                      valores nuevos. Se cierra sola (cl_housekeeping) cuando todos estan dados de alta.
--   quota_unfilled     una semana se liquida como 'unfilled'. Solo se cierra a mano.
-- Avisos (D26): cola cl_notifications -> Edge Function carrier-link-notify (Resend). Uno por apertura y uno por cada
-- anadido nuevo; destinatarios: usuarios de la cuenta con rol account_manager o do_coordinator y, solo en missing_delivery,
-- delivery_rejected y high_rejection, el correo de avisos del carrier del conector (carriers.notification_email, en el
-- maestro de carriers, decision del responsable 23/11; sin el, no hay correo
-- al carrier). Las direcciones se fijan al encolar (un aviso = una direccion, recipient_email; ronda 1 de la tarea 8).
-- D27: una semana pendiente con falta > 0 se liquida igualmente 3 dias tras su final si la entrega que debia cubrirla
-- esta vencida (hora de entrega + margen) y no llego.
-- Permiso nuevo cl_incidents: SOLO en la cuenta DEMO2 (no va en access_template; ver seccion 9).

-- Bloqueos (revision final I2): ALTER TABLE carriers (ACCESS EXCLUSIVE y un escaneo por el CHECK; carriers la leen el
-- ETL RFID, el bot n8n y la web), CREATE TRIGGER en cl_plan_quotas (viva desde v3: SHARE ROW EXCLUSIVE) y una fila en
-- access_option, hasta el COMMIT. lock_timeout de 5 s: si algo tiene esas tablas, la migracion falla enseguida en vez de
-- quedarse en cola bloqueando a todos detras; se reintenta mas tarde (entre dos pasadas del poll RFID). Aplicar en UNA
-- transaccion.
SET LOCAL lock_timeout = '5s';

-- ================================================================ 1. correo del carrier (maestro) y margen del conector
-- Correo de avisos del carrier (decision del responsable 23/11: en el maestro de carriers, no en el conector). Opcional;
-- un solo correo. Los avisos de los tipos del carrier de cualquier conector de ese carrier van aqui.
ALTER TABLE public.carriers
  ADD COLUMN notification_email text,
  ADD CONSTRAINT carriers_notification_email_valid CHECK (
    notification_email IS NULL
    OR (length(notification_email) <= 254
        AND notification_email ~ '^[^@[:space:],;<>"]+@[^@[:space:],;<>"]+\.[^@[:space:],;<>"]+$'));

-- Margen (horas) tras la hora de entrega antes de dar el periodo por no recibido: config.missing_grace_hours (0..168),
-- por defecto 6 (D25).
CREATE OR REPLACE FUNCTION public.cl_feed_missing_grace_hours(p_config jsonb)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path = public, extensions
AS $$
  SELECT CASE WHEN jsonb_typeof(p_config->'missing_grace_hours') = 'number'
                   AND (p_config->>'missing_grace_hours')::numeric BETWEEN 0 AND 168
              THEN trunc((p_config->>'missing_grace_hours')::numeric)::integer ELSE 6 END
$$;

-- ================================================================ 2. tablas
CREATE TABLE public.cl_incidents (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id    uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  feed_id       uuid NOT NULL REFERENCES public.cl_feeds(id) ON DELETE CASCADE,
  plan_id       uuid REFERENCES public.cl_plans(id) ON DELETE SET NULL,   -- quota_unfilled; NULL en los de conector
  incident_type text NOT NULL CHECK (incident_type IN ('missing_delivery','delivery_rejected','high_rejection',
                                                       'unknown_data','quota_unfilled')),
  status        text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved')),
  -- Lista de lo afectado, en orden de deteccion: [{key, period_start, period_end, detected_at, ...recuentos}]
  periods       jsonb NOT NULL DEFAULT '[]' CHECK (jsonb_typeof(periods) = 'array'),
  details       jsonb NOT NULL DEFAULT '{}' CHECK (jsonb_typeof(details) = 'object'),  -- unknown_data: products, points
  assignee_id   uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  notes         text CHECK (notes IS NULL OR length(notes) <= 4000),
  closed_how    text CHECK (closed_how IN ('manual','auto')),
  closed_by     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  closed_at     timestamptz,
  opened_at     timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cl_incidents_closed_shape CHECK ((status = 'resolved') = (closed_how IS NOT NULL AND closed_at IS NOT NULL))
);
-- R32: una sola incidencia abierta (open / in_progress) por conector y tipo.
CREATE UNIQUE INDEX cl_incidents_open_uidx ON public.cl_incidents (feed_id, incident_type) WHERE status <> 'resolved';
CREATE INDEX cl_incidents_account_idx ON public.cl_incidents (account_id, opened_at DESC);
CREATE INDEX cl_incidents_plan_idx ON public.cl_incidents (plan_id);
CREATE INDEX cl_incidents_assignee_idx ON public.cl_incidents (assignee_id);

CREATE TABLE public.cl_notifications (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id      uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  incident_id     uuid NOT NULL REFERENCES public.cl_incidents(id) ON DELETE CASCADE,
  recipient_kind  text NOT NULL CHECK (recipient_kind IN ('account_manager','carrier')),
  -- Un aviso = un correo a UNA direccion (ronda 1: nadie ve las direcciones de los demas). NULL solo en el registro
  -- 'skipped' de una cuenta sin destinatarios. Sin grants: solo lo leen las funciones (la pantalla no lo ve).
  recipient_email text CHECK (recipient_email IS NULL OR length(recipient_email) <= 254),
  event           text NOT NULL CHECK (event IN ('opened','appended')),
  periods         jsonb NOT NULL CHECK (jsonb_typeof(periods) = 'array'),   -- lo nuevo que anuncia este aviso
  status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sending','sent','failed','skipped')),
  attempts        integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  next_attempt_at timestamptz NOT NULL DEFAULT now(),
  lease_token     text,
  lease_until     timestamptz,
  last_error      text CHECK (last_error IS NULL OR last_error ~ '^[A-Z0-9_]{1,40}$'),   -- solo codigos
  provider_id     text CHECK (provider_id IS NULL OR provider_id ~ '^[A-Za-z0-9_-]{1,100}$'),
  created_at      timestamptz NOT NULL DEFAULT now(),
  sent_at         timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT cl_notifications_lease_shape CHECK ((status = 'sending') = (lease_token IS NOT NULL AND lease_until IS NOT NULL)),
  CONSTRAINT cl_notifications_recipient_shape CHECK (recipient_email IS NOT NULL OR status = 'skipped')
);

-- Periodos de un conector ya avisados como no recibidos (ronda 1 de la revision): cada periodo se avisa como mucho UNA
-- vez, pase lo que pase con las incidencias (cierre al recibir, rechazo posterior, entregas atrasadas).
CREATE TABLE public.cl_missing_notified (
  account_id   uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  feed_id      uuid NOT NULL REFERENCES public.cl_feeds(id) ON DELETE CASCADE,
  period_start date NOT NULL,
  period_end   date NOT NULL,
  notified_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (feed_id, period_start, period_end)
);
CREATE INDEX cl_missing_notified_account_idx ON public.cl_missing_notified (account_id);
CREATE INDEX cl_notifications_incident_idx ON public.cl_notifications (incident_id, created_at);
CREATE INDEX cl_notifications_account_idx ON public.cl_notifications (account_id);
CREATE INDEX cl_notifications_queue_idx ON public.cl_notifications (created_at) WHERE status IN ('pending','sending');

CREATE TRIGGER cl_same_account BEFORE INSERT OR UPDATE ON public.cl_incidents
  FOR EACH ROW EXECUTE FUNCTION public.cl_check_same_account('feed_id', 'cl_feeds', 'plan_id', 'cl_plans');
CREATE TRIGGER cl_same_account BEFORE INSERT OR UPDATE ON public.cl_notifications
  FOR EACH ROW EXECUTE FUNCTION public.cl_check_same_account('incident_id', 'cl_incidents');
CREATE TRIGGER cl_same_account BEFORE INSERT OR UPDATE ON public.cl_missing_notified
  FOR EACH ROW EXECUTE FUNCTION public.cl_check_same_account('feed_id', 'cl_feeds');

-- RLS: lectura de la propia cuenta con View en cl_incidents (o superadmin). Sin escritura directa: solo funciones.
-- cl_notifications: sin politicas ni privilegios (los correos no se guardan; el detalle sale por cl_incident_get).
ALTER TABLE public.cl_incidents     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cl_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cl_missing_notified ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cl_incidents, public.cl_notifications, public.cl_missing_notified
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.cl_incidents TO authenticated;
CREATE POLICY cl_incidents_select_access ON public.cl_incidents FOR SELECT TO authenticated
  USING ((SELECT public.is_superadmin())
         OR (account_id = (SELECT public.current_user_account_id())
             AND (SELECT public.has_any_access(public.current_user_account_id(), 'view', 'cl_incidents'))));

-- ================================================================ 3. nucleo: anotar, avisar, cerrar
-- Tipos cuyo problema es del carrier (aviso tambien a carriers.notification_email).
CREATE OR REPLACE FUNCTION public.cl_incident_is_carrier_side(p_type text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path = public, extensions
AS $$ SELECT p_type IN ('missing_delivery','delivery_rejected','high_rejection') $$;

-- Destinatarios (decision del responsable 23/11): 'account_manager' = usuarios con rol 'account_manager' o
-- 'do_coordinator' en account_user_role de la cuenta (correo de profiles); 'carrier' = carriers.notification_email
-- del carrier del conector. En minusculas y sin repetir.
CREATE OR REPLACE FUNCTION public.cl_incident_recipients(p_account_id uuid, p_feed_id uuid, p_kind text)
 RETURNS SETOF text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT lower(btrim(p.email))
    FROM public.account_user_role r JOIN public.profiles p ON p.id = r.user_id
   WHERE p_kind = 'account_manager' AND r.account_id = p_account_id
     AND r.role IN ('account_manager','do_coordinator')
     AND p.email ~ '^[^@[:space:],;<>"]+@[^@[:space:],;<>"]+\.[^@[:space:],;<>"]+$'
  UNION
  SELECT lower(btrim(c.notification_email))
    FROM public.cl_feeds f JOIN public.carriers c ON c.id = f.carrier_id
   WHERE p_kind = 'carrier' AND f.id = p_feed_id AND f.account_id = p_account_id AND c.notification_email IS NOT NULL
$$;

-- Encola UN aviso (un correo) por direccion: siempre la cuenta (AM + DO); el carrier solo si el tipo es suyo y su
-- carrier tiene notification_email (sin correo: nada al carrier y ningun error). Una cuenta sin destinatarios deja un
-- registro 'skipped' (CL_NO_RECIPIENT) para que la pantalla lo vea. Las direcciones se fijan al encolar: cada correo
-- tiene su propio estado y su propia clave de idempotencia (el id del aviso).
CREATE OR REPLACE FUNCTION public.cl_incident_enqueue(p_incident_id uuid, p_event text, p_entries jsonb,
                                                      p_now timestamptz DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_inc   public.cl_incidents;
  v_kind  text;
  v_n     integer;
  v_total integer := 0;
BEGIN
  SELECT i.* INTO v_inc FROM public.cl_incidents i WHERE i.id = p_incident_id;
  IF v_inc.id IS NULL THEN RETURN 0; END IF;
  FOREACH v_kind IN ARRAY CASE WHEN public.cl_incident_is_carrier_side(v_inc.incident_type)
                               THEN ARRAY['account_manager','carrier'] ELSE ARRAY['account_manager'] END LOOP
    INSERT INTO public.cl_notifications (account_id, incident_id, recipient_kind, recipient_email, event, periods,
                                         created_at, next_attempt_at, updated_at)
    SELECT v_inc.account_id, v_inc.id, v_kind, e, p_event, p_entries, p_now, p_now, p_now
      FROM public.cl_incident_recipients(v_inc.account_id, v_inc.feed_id, v_kind) e;
    GET DIAGNOSTICS v_n = ROW_COUNT;
    IF v_n = 0 AND v_kind = 'account_manager' THEN
      INSERT INTO public.cl_notifications (account_id, incident_id, recipient_kind, recipient_email, event, periods,
                                           status, last_error, created_at, next_attempt_at, updated_at)
      VALUES (v_inc.account_id, v_inc.id, v_kind, NULL, p_event, p_entries, 'skipped', 'CL_NO_RECIPIENT',
              p_now, p_now, p_now);
    END IF;
    v_total := v_total + v_n;
  END LOOP;
  RETURN v_total;
END $$;

-- Anota en la incidencia abierta del (conector, tipo) las entradas cuya 'key' aun no esta; la abre si no hay ninguna
-- (R32). Encola UN aviso con lo nuevo (event opened / appended). Nada nuevo -> nada (idempotente: repetir la misma
-- deteccion cada hora no vuelve a avisar). p_details se fusiona en details. Devuelve el id de la incidencia.
CREATE OR REPLACE FUNCTION public.cl_incident_record(p_account_id uuid, p_feed_id uuid, p_plan_id uuid, p_type text,
                                                     p_entries jsonb, p_details jsonb DEFAULT NULL,
                                                     p_now timestamptz DEFAULT now())
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_inc    public.cl_incidents;
  v_new    jsonb;
  v_opened boolean := false;
BEGIN
  IF p_feed_id IS NULL OR p_entries IS NULL OR jsonb_typeof(p_entries) <> 'array' OR jsonb_array_length(p_entries) = 0 THEN
    RETURN NULL;
  END IF;
  SELECT i.* INTO v_inc FROM public.cl_incidents i
   WHERE i.feed_id = p_feed_id AND i.incident_type = p_type AND i.status <> 'resolved'
     FOR UPDATE;
  IF v_inc.id IS NULL THEN
    INSERT INTO public.cl_incidents (account_id, feed_id, plan_id, incident_type, opened_at, updated_at)
    VALUES (p_account_id, p_feed_id, p_plan_id, p_type, p_now, p_now)
    ON CONFLICT (feed_id, incident_type) WHERE status <> 'resolved' DO NOTHING
    RETURNING * INTO v_inc;
    IF v_inc.id IS NULL THEN
      SELECT i.* INTO v_inc FROM public.cl_incidents i
       WHERE i.feed_id = p_feed_id AND i.incident_type = p_type AND i.status <> 'resolved'
         FOR UPDATE;
    ELSE
      v_opened := true;
    END IF;
  END IF;

  SELECT COALESCE(jsonb_agg(x.e || jsonb_build_object('detected_at', p_now) ORDER BY x.ord), '[]'::jsonb) INTO v_new
    FROM (SELECT DISTINCT ON (e->>'key') e, ord
            FROM jsonb_array_elements(p_entries) WITH ORDINALITY t(e, ord)
           WHERE e->>'key' IS NOT NULL
             AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_inc.periods) o WHERE o->>'key' = e->>'key')
           ORDER BY e->>'key', ord) x;
  IF jsonb_array_length(v_new) = 0 THEN
    RETURN v_inc.id;
  END IF;

  UPDATE public.cl_incidents i
     SET periods = i.periods || v_new,
         details = i.details || COALESCE(p_details, '{}'::jsonb),
         plan_id = COALESCE(i.plan_id, p_plan_id),
         updated_at = p_now
   WHERE i.id = v_inc.id;
  PERFORM public.cl_incident_enqueue(v_inc.id, CASE WHEN v_opened THEN 'opened' ELSE 'appended' END, v_new, p_now);
  RETURN v_inc.id;
END $$;

-- Cierra una incidencia (si no lo esta). Los avisos aun pendientes de ella ya no se envian (skipped).
CREATE OR REPLACE FUNCTION public.cl_incident_close_core(p_incident_id uuid, p_how text, p_user uuid,
                                                         p_note text DEFAULT NULL, p_now timestamptz DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_n integer;
BEGIN
  UPDATE public.cl_incidents i
     SET status = 'resolved', closed_how = p_how, closed_by = p_user, closed_at = p_now, updated_at = p_now,
         notes = COALESCE(p_note, i.notes)
   WHERE i.id = p_incident_id AND i.status <> 'resolved';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n = 0 THEN RETURN false; END IF;
  UPDATE public.cl_notifications n SET status = 'skipped', last_error = 'CL_INCIDENT_CLOSED', updated_at = p_now
   WHERE n.incident_id = p_incident_id AND n.status = 'pending';
  RETURN true;
END $$;

-- Cierre automatico de la incidencia abierta de un (conector, tipo).
CREATE OR REPLACE FUNCTION public.cl_incident_auto_close(p_feed_id uuid, p_type text, p_now timestamptz DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_id uuid;
BEGIN
  SELECT i.id INTO v_id FROM public.cl_incidents i
   WHERE i.feed_id = p_feed_id AND i.incident_type = p_type AND i.status <> 'resolved'
     FOR UPDATE;
  IF v_id IS NULL THEN RETURN false; END IF;
  RETURN public.cl_incident_close_core(v_id, 'auto', NULL, NULL, p_now);
END $$;

-- unknown_data: ?estan ya dados de alta todos los productos y puntos anotados? (mismas reglas que el paso resolve de
-- la tarea 2: producto por equivalencia o por codigo; punto vivo del carrier con lugar + modo exacto o sin modo).
CREATE OR REPLACE FUNCTION public.cl_incident_unknown_registered(p_incident_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements_text(COALESCE(i.details->'products', '[]'::jsonb)) v(code)
            WHERE NOT EXISTS (SELECT 1 FROM public.cl_value_mappings m
                                JOIN public.products p ON p.account_id = m.account_id AND p.carrier_id = m.carrier_id
                                                      AND p.code = m.onems_value
                               WHERE m.account_id = i.account_id AND m.carrier_id = f.carrier_id
                                 AND m.kind = 'product' AND m.carrier_value = v.code)
              AND NOT EXISTS (SELECT 1 FROM public.products p
                               WHERE p.account_id = i.account_id AND p.carrier_id = f.carrier_id AND p.code = v.code))
     AND NOT EXISTS (
           SELECT 1 FROM jsonb_array_elements(COALESCE(i.details->'points', '[]'::jsonb)) pt
            -- Un punto sin lugar no se puede dar de alta (ni lo produce el paso resolve: seria missing_field): no
            -- bloquea el cierre (ronda 1).
            WHERE COALESCE(btrim(pt->>'place_ref'), '') <> ''
              AND NOT EXISTS (SELECT 1 FROM public.readers r
                               WHERE r.account_id = i.account_id AND r.capture_source = 'carrier_scan'
                                 AND r.carrier_id = f.carrier_id AND r.deleted_at IS NULL AND r.is_active IS NOT FALSE
                                 AND r.carrier_place_ref = pt->>'place_ref'
                                 AND (r.carrier_mode_ref IS NULL OR r.carrier_mode_ref IS NOT DISTINCT FROM pt->>'mode_ref')))
    FROM public.cl_incidents i JOIN public.cl_feeds f ON f.id = i.feed_id
   WHERE i.id = p_incident_id
$$;

-- ================================================================ 4. senales de las entregas y de las cuotas
-- Codigos de rechazo que son del fichero del carrier (o de sus 3 fallos). No cuentan: CL_SUPERSEDED (lo sustituyo
-- otra), CL_PERIOD_ALREADY_DELIVERED (carrera de apertura) ni CL_UPLOAD_EXPIRED (nunca subio: lo vigila
-- missing_delivery).
CREATE OR REPLACE FUNCTION public.cl_incident_rejection_codes()
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
 SET search_path = public, extensions
AS $$
  SELECT ARRAY['CL_SHA256_MISMATCH','CL_FILE_TOO_LARGE','CL_TOO_MANY_ROWS','CL_RECORD_TOO_LONG','CL_BAD_ENCODING',
               'CL_BAD_CSV_HEADER','CL_COMPRESSION_UNSUPPORTED','CL_FILE_MISSING','CL_MAPPING_INCOMPLETE',
               'CL_RETRIES_EXHAUSTED']
$$;

-- Disparador en cl_deliveries (misma transaccion que el cambio de estado). Las entregas de prueba (is_test) no abren
-- ni cierran nada.
--   received  -> cierra missing_delivery (R31: la primera entrega que llegue, sea del periodo que sea).
--   rejected  -> delivery_rejected (si el codigo es del fichero / de los 3 fallos).
--   processed -> cierra delivery_rejected si todos sus periodos ya se procesaron bien; high_rejection si la entrega
--                tiene la alerta rejected_ratio (si no, lo cierra); unknown_data con los valores nuevos de las
--                alertas unknown_product / unknown_reading_point (las alertas se escriben en finish, antes).
CREATE OR REPLACE FUNCTION public.cl_deliveries_incidents()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_code   text;
  v_key    text := NEW.period_start::text || '/' || NEW.period_end::text;
  v_inc    public.cl_incidents;
  v_ratio  jsonb;
  v_prods  jsonb;
  v_points jsonb;
  v_newp   jsonb;
  v_newq   jsonb;
BEGIN
  IF NEW.is_test THEN RETURN NULL; END IF;

  IF NEW.status = 'received' THEN
    PERFORM public.cl_incident_auto_close(NEW.feed_id, 'missing_delivery');

  ELSIF NEW.status = 'rejected' THEN
    v_code := split_part(COALESCE(NEW.error, ''), ' ', 1);
    IF v_code = ANY (public.cl_incident_rejection_codes()) THEN
      PERFORM public.cl_incident_record(NEW.account_id, NEW.feed_id, NULL, 'delivery_rejected',
        jsonb_build_array(jsonb_build_object('key', v_key, 'period_start', NEW.period_start,
                                             'period_end', NEW.period_end, 'error', v_code)));
    END IF;

  ELSIF NEW.status = 'processed' THEN
    -- delivery_rejected: cerrada cuando cada periodo anotado tiene una entrega real procesada que lo cubre.
    SELECT i.* INTO v_inc FROM public.cl_incidents i
     WHERE i.feed_id = NEW.feed_id AND i.incident_type = 'delivery_rejected' AND i.status <> 'resolved' FOR UPDATE;
    IF v_inc.id IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_inc.periods) e
                        WHERE NOT EXISTS (SELECT 1 FROM public.cl_deliveries d
                                           WHERE d.feed_id = NEW.feed_id AND d.status = 'processed' AND NOT d.is_test
                                             AND d.period_start <= (e->>'period_end')::date
                                             AND d.period_end >= (e->>'period_start')::date)) THEN
      PERFORM public.cl_incident_close_core(v_inc.id, 'auto', NULL);
    END IF;

    -- high_rejection.
    SELECT a.details INTO v_ratio FROM public.cl_alerts a
     WHERE a.delivery_id = NEW.id AND a.alert_type = 'rejected_ratio' ORDER BY a.created_at LIMIT 1;
    IF v_ratio IS NOT NULL THEN
      PERFORM public.cl_incident_record(NEW.account_id, NEW.feed_id, NULL, 'high_rejection',
        jsonb_build_array(jsonb_build_object('key', v_key, 'period_start', NEW.period_start, 'period_end', NEW.period_end,
                                             'rejected', v_ratio->'rejected', 'shipments', v_ratio->'shipments',
                                             'ratio', v_ratio->'ratio')));
    ELSE
      PERFORM public.cl_incident_auto_close(NEW.feed_id, 'high_rejection');
    END IF;

    -- unknown_data: solo los valores que la incidencia abierta aun no tiene.
    SELECT COALESCE(jsonb_agg(DISTINCT v), '[]'::jsonb) INTO v_prods
      FROM public.cl_alerts a, jsonb_array_elements(COALESCE(a.details->'values', '[]'::jsonb)) v
     WHERE a.delivery_id = NEW.id AND a.alert_type = 'unknown_product' AND jsonb_typeof(v) = 'string';
    SELECT COALESCE(jsonb_agg(DISTINCT jsonb_build_object('place_ref', v->'place_ref', 'mode_ref', v->'mode_ref')), '[]'::jsonb)
      INTO v_points
      FROM public.cl_alerts a, jsonb_array_elements(COALESCE(a.details->'points', '[]'::jsonb)) v
     WHERE a.delivery_id = NEW.id AND a.alert_type = 'unknown_reading_point' AND jsonb_typeof(v) = 'object';
    IF jsonb_array_length(v_prods) + jsonb_array_length(v_points) > 0 THEN
      SELECT i.* INTO v_inc FROM public.cl_incidents i
       WHERE i.feed_id = NEW.feed_id AND i.incident_type = 'unknown_data' AND i.status <> 'resolved' FOR UPDATE;
      SELECT COALESCE(jsonb_agg(v), '[]'::jsonb) INTO v_newp FROM jsonb_array_elements(v_prods) v
       WHERE NOT COALESCE(v_inc.details->'products', '[]'::jsonb) @> jsonb_build_array(v);
      SELECT COALESCE(jsonb_agg(v), '[]'::jsonb) INTO v_newq FROM jsonb_array_elements(v_points) v
       WHERE NOT COALESCE(v_inc.details->'points', '[]'::jsonb) @> jsonb_build_array(v);
      IF jsonb_array_length(v_newp) + jsonb_array_length(v_newq) > 0 THEN
        PERFORM public.cl_incident_record(NEW.account_id, NEW.feed_id, NULL, 'unknown_data',
          jsonb_build_array(jsonb_build_object('key', 'delivery:' || NEW.id::text, 'period_start', NEW.period_start,
                                               'period_end', NEW.period_end, 'products', jsonb_array_length(v_newp),
                                               'points', jsonb_array_length(v_newq))),
          jsonb_build_object('products', COALESCE(v_inc.details->'products', '[]'::jsonb) || v_newp,
                             'points', COALESCE(v_inc.details->'points', '[]'::jsonb) || v_newq));
      END IF;
    END IF;
  END IF;
  RETURN NULL;
END $$;

CREATE TRIGGER cl_deliveries_incidents AFTER UPDATE OF status ON public.cl_deliveries
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.cl_deliveries_incidents();

-- Disparador en cl_plan_quotas: una semana que se liquida 'unfilled' (cl_settle_quota) de un plan con conector abre /
-- anade quota_unfilled (clave = la cuota). Solo se cierra a mano.
CREATE OR REPLACE FUNCTION public.cl_plan_quotas_incidents()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_feed uuid;
BEGIN
  SELECT p.feed_id INTO v_feed FROM public.cl_plans p WHERE p.id = NEW.plan_id;
  IF v_feed IS NULL THEN RETURN NULL; END IF;
  PERFORM public.cl_incident_record(NEW.account_id, v_feed, NEW.plan_id, 'quota_unfilled',
    jsonb_build_array(jsonb_build_object('key', 'quota:' || NEW.id::text, 'quota_id', NEW.id,
                                         'period_start', NEW.period_start, 'period_end', NEW.period_end,
                                         'missing', GREATEST(NEW.samples_planned + NEW.samples_carried_in
                                                             - NEW.samples_obtained, 0))));
  RETURN NULL;
END $$;

CREATE TRIGGER cl_plan_quotas_incidents AFTER UPDATE OF status ON public.cl_plan_quotas
  FOR EACH ROW WHEN (NEW.status = 'unfilled' AND OLD.status IS DISTINCT FROM 'unfilled')
  EXECUTE FUNCTION public.cl_plan_quotas_incidents();

-- ================================================================ 5. vigilancia del calendario (missing_delivery)
-- Hora limite de un periodo del calendario que termina en p_period_end: (dia siguiente + emit_hour) en la zona del
-- conector, mas el margen.
CREATE OR REPLACE FUNCTION public.cl_incident_period_deadline(p_feed public.cl_feeds, p_period_end date)
 RETURNS timestamptz
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT (((p_period_end + 1) + make_interval(hours => p_feed.emit_hour))
            AT TIME ZONE public.cl_effective_tz(p_feed.account_id, p_feed.id))
         + make_interval(hours => public.cl_feed_missing_grace_hours(p_feed.config))
$$;

-- Periodos vencidos sin entrega de un conector activo: desde el siguiente a lo ya entregado (cl_delivery_next_period,
-- que salta los huecos entre planes) mientras su hora limite haya pasado; solo los que solapan un plan activo.
-- Ronda 1 de la revision: un periodo se avisa como no recibido COMO MUCHO UNA VEZ (cl_missing_notified, aparte del
-- ciclo de las incidencias: una entrega recibida cierra la incidencia, R31, pero lo ya avisado no se vuelve a avisar
-- aunque esa entrega se rechace despues o el carrier se ponga al dia de lo atrasado; esto incluye lo de una incidencia
-- cerrada a mano). Tampoco es "no recibido" un periodo con una incidencia delivery_rejected (abierta o cerrada) ni con
-- una entrega received/processing/failed. Lo nuevo va a la incidencia abierta (o a una nueva) con UN aviso por
-- ejecucion (normalmente un periodo; varios solo si el job no corrio a su hora).
CREATE OR REPLACE FUNCTION public.cl_incident_check_missing(p_feed public.cl_feeds, p_now timestamptz DEFAULT now())
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_np      jsonb;
  v_start   date;
  v_end     date;
  v_key     text;
  v_entries jsonb := '[]'::jsonb;
  i         integer;
BEGIN
  IF p_feed.status <> 'active' THEN RETURN 0; END IF;
  v_np := public.cl_delivery_next_period(p_feed.id, p_now);
  IF v_np IS NULL THEN RETURN 0; END IF;
  v_start := (v_np->>'period_start')::date;
  v_end := (v_np->>'period_end')::date;
  FOR i IN 1 .. 400 LOOP
    EXIT WHEN public.cl_incident_period_deadline(p_feed, v_end) > p_now;
    v_key := v_start::text || '/' || v_end::text;
    IF EXISTS (SELECT 1 FROM public.cl_plans p
                WHERE p.feed_id = p_feed.id AND p.carrier_id = p_feed.carrier_id AND p.status = 'active'
                  AND p.start_date <= v_end AND p.end_date >= v_start)
       AND NOT EXISTS (SELECT 1 FROM public.cl_missing_notified m
                        WHERE m.feed_id = p_feed.id AND m.period_start = v_start AND m.period_end = v_end)
       AND NOT EXISTS (SELECT 1 FROM public.cl_incidents x, jsonb_array_elements(x.periods) e
                        WHERE x.feed_id = p_feed.id AND x.incident_type = 'delivery_rejected'
                          AND (e->>'period_start')::date <= v_end AND (e->>'period_end')::date >= v_start)
       AND NOT EXISTS (SELECT 1 FROM public.cl_deliveries d       -- una entrega de prueba nunca cubre el periodo
                        WHERE d.feed_id = p_feed.id AND NOT d.is_test AND d.status IN ('received','processing','failed')
                          AND d.period_start <= v_end AND d.period_end >= v_start) THEN
      v_entries := v_entries || jsonb_build_array(jsonb_build_object('key', v_key, 'period_start', v_start,
                                                                     'period_end', v_end));
    END IF;
    v_start := v_end + 1;
    SELECT a.period_end INTO v_end FROM public.cl_delivery_aligned_period(p_feed.emit_days, v_start) a;
  END LOOP;
  IF jsonb_array_length(v_entries) = 0 THEN RETURN 0; END IF;
  INSERT INTO public.cl_missing_notified (account_id, feed_id, period_start, period_end, notified_at)
  SELECT p_feed.account_id, p_feed.id, (e->>'period_start')::date, (e->>'period_end')::date, p_now
    FROM jsonb_array_elements(v_entries) e
  ON CONFLICT DO NOTHING;
  PERFORM public.cl_incident_record(p_feed.account_id, p_feed.id, NULL, 'missing_delivery', v_entries, NULL, p_now);
  RETURN jsonb_array_length(v_entries);
END $$;

-- ================================================================ 6. cl_settle_quota con cierre definitivo (D27)
-- cl_settle_quota(uuid, p_final): copia literal de la version de 20261124200100 con un solo cambio: con p_final la
-- rama v3 "volver a pedir" (pending) no se aplica (una semana vencida sin entrega se liquida con lo que haya; el deficit
-- va al arrastre de siempre o queda unfilled). cl_settle_quota(uuid) sigue igual para sus llamadores (p_final = false).
CREATE OR REPLACE FUNCTION public.cl_settle_quota(p_quota_id uuid, p_final boolean)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_q     public.cl_plan_quotas;
  v_falta integer;
  v_pop   bigint;
  v_recv  bigint;
  v_ids   uuid[];
  v_n     integer;
  v_last  uuid;
  v_known boolean;
  v_v4    boolean;
BEGIN
  SELECT * INTO v_q FROM public.cl_plan_quotas WHERE id = p_quota_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'CL_QUOTA_NOT_FOUND: quota not found' USING ERRCODE = '22023';
  END IF;
  IF v_q.status <> 'open' THEN
    RETURN v_q.status;
  END IF;

  v_falta := v_q.samples_planned + v_q.samples_carried_in - v_q.samples_obtained;
  IF v_falta <= 0 THEN
    UPDATE public.cl_plan_quotas SET status = 'fulfilled' WHERE id = p_quota_id;
    RETURN 'fulfilled';
  END IF;

  v_v4 := EXISTS (SELECT 1 FROM public.cl_delivery_strata s JOIN public.cl_deliveries d ON d.id = s.delivery_id
                   WHERE s.quota_id = p_quota_id AND NOT d.is_test AND d.status IN ('processing','processed'));

  IF NOT v_v4 AND NOT p_final THEN
    -- Ultima poblacion informada: la del sorteo del estrato en la ULTIMA demanda que lo pidio (un estrato se entrega
    -- una sola vez por demanda). Sin sorteo en esa demanda (caducada sin respuesta) la poblacion es desconocida -> se
    -- vuelve a pedir mientras demands_count < 3.
    SELECT d.id INTO v_last
      FROM public.cl_demands d
     WHERE d.plan_id = v_q.plan_id
       AND d.payload->'strata' @> jsonb_build_array(jsonb_build_object('stratum_id', p_quota_id))
     ORDER BY d.seq DESC   -- D4: orden de emision (requested_at puede venir de un p_now explicito anterior)
     LIMIT 1;
    SELECT r.population_size INTO v_pop
      FROM public.cl_sampling_runs r JOIN public.cl_batches b ON b.id = r.batch_id
     WHERE b.demand_id = v_last AND r.stratum_id = p_quota_id
     ORDER BY r.executed_at DESC, r.created_at DESC, r.id DESC
     LIMIT 1;
    v_known := FOUND;
    -- Candidatos distintos recibidos en los lotes de las demandas del plan (cualquier estado de lectura), sin contar
    -- los lotes deshechos ni rechazados.
    SELECT count(DISTINCT s.item_id) INTO v_recv
      FROM public.cl_batch_scans s
     WHERE s.batch_id IN (SELECT b.id FROM public.cl_batches b JOIN public.cl_demands d ON d.id = b.demand_id
                           WHERE d.plan_id = v_q.plan_id AND b.status NOT IN ('undone', 'rejected'))
       AND s.stratum_id = p_quota_id
       AND s.item_id IS NOT NULL;

    IF (NOT v_known OR v_pop IS NULL OR v_pop > v_recv) AND v_q.demands_count < 3 THEN
      UPDATE public.cl_plan_quotas SET status = 'pending' WHERE id = p_quota_id;
      RETURN 'pending';
    END IF;
  END IF;

  -- Destinos posibles: se bloquean (orden por id) y despues se eligen con su estado ya bloqueado.
  PERFORM 1 FROM public.cl_plan_quotas q
   WHERE q.plan_id = v_q.plan_id AND q.origin_city_id = v_q.origin_city_id
     AND q.destination_city_id = v_q.destination_city_id
     AND q.status = 'pending' AND q.period_start > v_q.period_start
   ORDER BY q.id
     FOR UPDATE;

  -- El mes mas temprano con cuotas pending posteriores: el mismo mes si lo hay, si no el siguiente que tenga alguna.
  WITH c AS (
    SELECT q.id, q.period_start, date_trunc('month', q.period_start) AS m
      FROM public.cl_plan_quotas q
     WHERE q.plan_id = v_q.plan_id AND q.origin_city_id = v_q.origin_city_id
       AND q.destination_city_id = v_q.destination_city_id
       AND q.status = 'pending' AND q.period_start > v_q.period_start
  )
  SELECT array_agg(c.id ORDER BY c.period_start, c.id) INTO v_ids
    FROM c WHERE c.m = (SELECT min(m) FROM c);

  IF v_ids IS NULL THEN
    UPDATE public.cl_plan_quotas SET status = 'unfilled' WHERE id = p_quota_id;
    PERFORM public.cl_raise_alert(v_q.plan_id, p_quota_id, 'quota_unfilled', 'high',
      jsonb_build_object('missing', v_falta, 'samples_planned', v_q.samples_planned,
                         'samples_carried_in', v_q.samples_carried_in, 'samples_obtained', v_q.samples_obtained,
                         'demands_count', v_q.demands_count));
    RETURN 'unfilled';
  END IF;

  v_n := cardinality(v_ids);
  UPDATE public.cl_plan_quotas q
     SET samples_carried_in = q.samples_carried_in + v_falta / v_n + CASE WHEN x.ord <= v_falta % v_n THEN 1 ELSE 0 END
    FROM unnest(v_ids) WITH ORDINALITY x(id, ord)
   WHERE q.id = x.id;
  UPDATE public.cl_plan_quotas SET status = 'carried' WHERE id = p_quota_id;
  RETURN 'carried';
END $$;

CREATE OR REPLACE FUNCTION public.cl_settle_quota(p_quota_id uuid)
 RETURNS text
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$ SELECT public.cl_settle_quota(p_quota_id, false) $$;

-- ================================================================ 7. cl_housekeeping + tarea 8
-- Copia de la version de 20261124200200 (ronda 2) con tres anadidos, sin otro job:
--   d) unknown_data: se cierra sola cuando todos sus productos y puntos estan dados de alta (no toca cuotas).
--   e) en el bloque de cada conector, ya bloqueado (FOR UPDATE SKIP LOCKED y sin entregas en vuelo, como antes):
--      vigilancia del calendario (missing_delivery) para conectores activos.
--   f) en el punto "TAREA 8" (D27): semanas pending con falta > 0, 3 dias tras su final, cuya entrega debia llegar ya
--      (hora limite del periodo que contiene el fin de semana) y no llego -> pending -> open -> cl_settle_quota(final).
--      Solo conectores no 'testing' (en prueba no hay entregas reales). El 'unfilled' que resulte abre quota_unfilled
--      por el disparador de cl_plan_quotas.
--   g) (revision final, T2-m12) entrega atascada: sigue en 'processing' mas de 2 h desde que se tomo este intento
--      (progress.claimed_at; si falta, processing_started_at) -> UNA alerta delivery_stuck de severidad alta por entrega
--      (cl_delivery_alert deduplica). Hay UNA sola entrega en proceso en toda la base: atascada, frena la cola de todas
--      las cuentas. Los arriendos caducados ya cuentan intentos (3 -> rechazo terminal); esto avisa del resto (p. ej. la
--      limpieza que falla cada minuto). No se muestra al carrier (cl_delivery_status filtra los tipos).
-- El orden de bloqueo no cambia: conector -> candado del sorteo -> cuotas por id.
CREATE OR REPLACE FUNCTION public.cl_housekeeping(p_now timestamptz DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  r           record;
  v_feed      record;
  v_f         public.cl_feeds;
  v_today     date;
  v_qid       uuid;
  v_settled   integer := 0;
  v_closed    integer := 0;
  v_n         integer;
  v_tz_alerts integer := 0;
  v_skipped   integer := 0;
  v_missing   integer := 0;
  v_late      integer := 0;
  v_unknown   integer := 0;
  v_stuck     integer := 0;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('cl_housekeeping'));

  -- g) entrega atascada en processing (sin bloquear la entrega: solo lee y anade una alerta).
  FOR r IN SELECT d.id, d.progress->>'phase' AS phase, COALESCE((d.progress->>'attempts')::integer, 0) AS attempts,
                  COALESCE((d.progress->>'claimed_at')::timestamptz, d.processing_started_at) AS since
             FROM public.cl_deliveries d
            WHERE d.status = 'processing'
              AND COALESCE((d.progress->>'claimed_at')::timestamptz, d.processing_started_at) < p_now - interval '2 hours'
              AND NOT EXISTS (SELECT 1 FROM public.cl_alerts a WHERE a.delivery_id = d.id AND a.alert_type = 'delivery_stuck')
  LOOP
    PERFORM public.cl_delivery_alert(r.id, NULL, NULL, 'delivery_stuck', 'high',
                                     jsonb_build_object('phase', r.phase, 'attempts', r.attempts, 'processing_since', r.since));
    v_stuck := v_stuck + 1;
  END LOOP;

  -- b) zona horaria invalida (una alerta mientras no se descarte). No toca cuotas ni planes.
  FOR r IN SELECT p.id, f.emit_timezone, a.timezone AS account_tz
             FROM public.cl_plans p
             JOIN public.accounts a ON a.id = p.account_id
             LEFT JOIN public.cl_feeds f ON f.id = p.feed_id
            WHERE p.status = 'active'
            ORDER BY p.created_at, p.id
  LOOP
    IF r.emit_timezone IS NULL AND r.account_tz IS NOT NULL AND NOT public.cl_is_valid_timezone(r.account_tz)
       AND NOT EXISTS (SELECT 1 FROM public.cl_alerts x WHERE x.plan_id = r.id AND x.alert_type = 'invalid_timezone'
                                                        AND x.status <> 'dismissed') THEN
      PERFORM public.cl_raise_alert(r.id, NULL, 'invalid_timezone', 'medium',
                                    jsonb_build_object('account_timezone', r.account_tz, 'used', 'UTC'));
      v_tz_alerts := v_tz_alerts + 1;
    END IF;
  END LOOP;

  -- d) unknown_data ya dados de alta.
  FOR r IN SELECT i.id FROM public.cl_incidents i
            WHERE i.incident_type = 'unknown_data' AND i.status <> 'resolved' ORDER BY i.id
  LOOP
    IF public.cl_incident_unknown_registered(r.id) AND public.cl_incident_close_core(r.id, 'auto', NULL, NULL, p_now) THEN
      v_unknown := v_unknown + 1;
    END IF;
  END LOOP;

  -- a), c), e) y f), POR CONECTOR (ronda 2 de la revision). Orden de bloqueo del proceso de entregas: conector FOR
  -- UPDATE (SKIP LOCKED: si una entrega lo tiene, se reintenta en la siguiente hora), luego candado del sorteo y cuotas
  -- por id. Un conector con una entrega en vuelo (received, processing o failed, que siempre se reintenta: el fallo
  -- terminal la deja rejected) no se liquida ni cierra ni se vigila: su transfer ya pudo sumar samples_obtained y un
  -- abort lo restaria (y la entrega recibida ya cerro su missing_delivery).
  -- Planes sin conector (feed_id NULL): no tienen entregas; se tratan sin bloqueo de conector (sin e ni f).
  FOR v_feed IN SELECT DISTINCT p.feed_id, p.account_id, p.carrier_id
                  FROM public.cl_plans p WHERE p.status = 'active'
                 ORDER BY p.feed_id NULLS LAST, p.account_id, p.carrier_id
  LOOP
    BEGIN
      v_f := NULL;
      IF v_feed.feed_id IS NOT NULL THEN
        SELECT f.* INTO v_f FROM public.cl_feeds f WHERE f.id = v_feed.feed_id FOR UPDATE SKIP LOCKED;
        IF NOT FOUND THEN v_skipped := v_skipped + 1; CONTINUE; END IF;
        -- Solo las entregas reales en vuelo frenan la liquidacion (las de prueba no tocan cuotas).
        IF EXISTS (SELECT 1 FROM public.cl_deliveries d
                    WHERE d.feed_id = v_feed.feed_id AND NOT d.is_test
                      AND d.status IN ('received','processing','failed')) THEN
          v_skipped := v_skipped + 1;
          CONTINUE;
        END IF;
        -- e) entregas no recibidas.
        v_missing := v_missing + public.cl_incident_check_missing(v_f, p_now);
      END IF;

      PERFORM pg_advisory_xact_lock(hashtext('cl_sample:' || v_feed.account_id::text || ':' || v_feed.carrier_id::text));

      FOR r IN SELECT p.id, p.account_id, p.feed_id, p.close_lag_days FROM public.cl_plans p
                WHERE p.status = 'active' AND p.feed_id IS NOT DISTINCT FROM v_feed.feed_id
                  AND p.account_id = v_feed.account_id AND p.carrier_id = v_feed.carrier_id
                ORDER BY p.id
      LOOP
        v_today := (p_now AT TIME ZONE public.cl_effective_tz(r.account_id, r.feed_id))::date;

        -- a) semanas vencidas sin nada que pedir.
        FOR v_qid IN SELECT q.id FROM public.cl_plan_quotas q
                      WHERE q.plan_id = r.id AND q.status = 'pending'
                        AND q.period_end + r.close_lag_days <= v_today
                        AND q.samples_planned + q.samples_carried_in - q.samples_obtained <= 0
                      ORDER BY q.id
                        FOR UPDATE
        LOOP
          UPDATE public.cl_plan_quotas q SET status = 'open' WHERE q.id = v_qid AND q.status = 'pending';
          PERFORM public.cl_settle_quota(v_qid);
          v_settled := v_settled + 1;
        END LOOP;

        -- TAREA 8 / f) D27: semanas vencidas con falta > 0 que ninguna entrega cubrio (3 dias tras el fin de la semana
        -- y la entrega que debia cubrir su ultimo dia ya vencida). Se liquidan con lo que haya.
        IF v_f.id IS NOT NULL AND v_f.status <> 'testing' THEN
          FOR v_qid IN SELECT q.id FROM public.cl_plan_quotas q
                        WHERE q.plan_id = r.id AND q.status = 'pending'
                          AND q.period_end + 3 <= v_today
                          AND q.samples_planned + q.samples_carried_in - q.samples_obtained > 0
                          AND public.cl_incident_period_deadline(
                                v_f, (SELECT a.period_end FROM public.cl_delivery_aligned_period(v_f.emit_days, q.period_end) a))
                              <= p_now
                        ORDER BY q.id
                          FOR UPDATE
          LOOP
            UPDATE public.cl_plan_quotas q SET status = 'open' WHERE q.id = v_qid AND q.status = 'pending';
            PERFORM public.cl_settle_quota(v_qid, true);
            v_late := v_late + 1;
          END LOOP;
        END IF;

        -- c) cierre del plan.
        UPDATE public.cl_plans p SET status = 'closed'
         WHERE p.id = r.id AND p.status = 'active'
           AND p.end_date + p.close_lag_days < v_today
           AND NOT EXISTS (SELECT 1 FROM public.cl_plan_quotas q WHERE q.plan_id = p.id AND q.status IN ('pending','open'));
        GET DIAGNOSTICS v_n = ROW_COUNT;
        v_closed := v_closed + v_n;
      END LOOP;
    EXCEPTION WHEN OTHERS THEN
      PERFORM public.cl_raise_alert(p.id, NULL, 'housekeeping_failed', 'high', jsonb_build_object('sqlstate', SQLSTATE))
         FROM public.cl_plans p
        WHERE p.status = 'active' AND p.feed_id IS NOT DISTINCT FROM v_feed.feed_id
          AND p.account_id = v_feed.account_id AND p.carrier_id = v_feed.carrier_id;
    END;
  END LOOP;

  RETURN jsonb_build_object('quotas_settled', v_settled, 'plans_closed', v_closed, 'timezone_alerts', v_tz_alerts,
                            'feeds_skipped', v_skipped, 'missing_periods', v_missing, 'late_weeks_settled', v_late,
                            'unknown_closed', v_unknown, 'stuck_alerts', v_stuck);
END $$;
REVOKE ALL ON FUNCTION public.cl_housekeeping(timestamptz) FROM PUBLIC, anon, authenticated, service_role;

-- ================================================================ 8. funciones de la pantalla (tarea 5)
-- Todas: SECURITY DEFINER, authenticated. Permitido: superadmin, o la cuenta activa del usuario con View (lectura) /
-- Edit (cambios) en cl_incidents. Lo demas (otra cuenta, sin derecho, inexistente, NULL): el mismo 42501 CL_FORBIDDEN.
CREATE OR REPLACE FUNCTION public.cl_incident_authorize(p_incident_id uuid, p_level text)
 RETURNS public.cl_incidents
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v public.cl_incidents;
BEGIN
  SELECT i.* INTO v FROM public.cl_incidents i WHERE i.id = p_incident_id;
  -- COALESCE(..., false): sin cuenta activa la comparacion da NULL; se niega igual (revision final I1).
  IF v.id IS NULL
     OR NOT COALESCE(public.is_superadmin()
                     OR (v.account_id = public.current_user_account_id()
                         AND public.has_any_access(v.account_id, p_level, 'cl_incidents')), false) THEN
    RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  RETURN v;
END $$;

-- Lista paginada (limite 1..1000, por defecto 100). Filtros opcionales: estado, tipo, conector.
-- Devuelve {total, limit, offset, items: [{id, incident_type, status, feed_id, feed_name, plan_id, periods_count,
-- last_period: {period_start, period_end}, assignee_id, assignee_name, opened_at, updated_at, closed_at, closed_how}]}.
CREATE OR REPLACE FUNCTION public.cl_incidents_list(p_account_id uuid, p_status text DEFAULT NULL,
                                                    p_type text DEFAULT NULL, p_feed_id uuid DEFAULT NULL,
                                                    p_limit integer DEFAULT 100, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 1000);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total  bigint;
  v_items  jsonb;
BEGIN
  IF NOT public.is_superadmin()
     AND (p_account_id IS NULL
          OR p_account_id IS DISTINCT FROM public.current_user_account_id()
          OR NOT public.has_any_access(p_account_id, 'view', 'cl_incidents')) THEN
    RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  IF (p_status IS NOT NULL AND p_status NOT IN ('open','in_progress','resolved','unresolved'))
     OR (p_type IS NOT NULL AND p_type NOT IN ('missing_delivery','delivery_rejected','high_rejection','unknown_data',
                                               'quota_unfilled')) THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: invalid filter' USING ERRCODE = '22023';
  END IF;

  SELECT count(*) INTO v_total FROM public.cl_incidents i
   WHERE i.account_id = p_account_id
     AND (p_status IS NULL OR (p_status = 'unresolved' AND i.status <> 'resolved') OR i.status = p_status)
     AND (p_type IS NULL OR i.incident_type = p_type)
     AND (p_feed_id IS NULL OR i.feed_id = p_feed_id);

  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.ord), '[]'::jsonb) INTO v_items
    FROM (SELECT row_number() OVER (ORDER BY (i.status = 'resolved'), i.updated_at DESC, i.id) AS ord,
                 jsonb_build_object(
                   'id', i.id, 'incident_type', i.incident_type, 'status', i.status,
                   'feed_id', i.feed_id, 'feed_name', f.name, 'plan_id', i.plan_id,
                   'periods_count', jsonb_array_length(i.periods),
                   'last_period', CASE WHEN jsonb_array_length(i.periods) > 0 THEN
                                    jsonb_build_object('period_start', i.periods->-1->'period_start',
                                                       'period_end', i.periods->-1->'period_end') END,
                   'assignee_id', i.assignee_id, 'assignee_name', pr.full_name,
                   'opened_at', i.opened_at, 'updated_at', i.updated_at, 'closed_at', i.closed_at,
                   'closed_how', i.closed_how) AS j
            FROM public.cl_incidents i
            JOIN public.cl_feeds f ON f.id = i.feed_id
            LEFT JOIN public.profiles pr ON pr.id = i.assignee_id
           WHERE i.account_id = p_account_id
             AND (p_status IS NULL OR (p_status = 'unresolved' AND i.status <> 'resolved') OR i.status = p_status)
             AND (p_type IS NULL OR i.incident_type = p_type)
             AND (p_feed_id IS NULL OR i.feed_id = p_feed_id)
           ORDER BY (i.status = 'resolved'), i.updated_at DESC, i.id
           LIMIT v_limit OFFSET v_offset) x;

  RETURN jsonb_build_object('total', v_total, 'limit', v_limit, 'offset', v_offset, 'items', v_items);
END $$;

-- Detalle: la incidencia entera (periodos, detalles, notas) + sus avisos (destinatario por tipo, estado, intentos,
-- fechas; nunca direcciones de correo ni errores internos).
CREATE OR REPLACE FUNCTION public.cl_incident_get(p_incident_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v public.cl_incidents := public.cl_incident_authorize(p_incident_id, 'view');
BEGIN
  RETURN (
    SELECT jsonb_build_object(
             'id', v.id, 'account_id', v.account_id, 'incident_type', v.incident_type, 'status', v.status,
             'feed_id', v.feed_id, 'feed_name', f.name, 'carrier_notified', (SELECT c.notification_email IS NOT NULL FROM public.carriers c WHERE c.id = f.carrier_id)
                                                                       AND public.cl_incident_is_carrier_side(v.incident_type),
             'plan_id', v.plan_id, 'plan_name', pl.plan_name,
             'periods', v.periods, 'details', v.details, 'notes', v.notes,
             'assignee_id', v.assignee_id, 'assignee_name', pa.full_name,
             'closed_how', v.closed_how, 'closed_by', v.closed_by, 'closed_by_name', pc.full_name, 'closed_at', v.closed_at,
             'opened_at', v.opened_at, 'updated_at', v.updated_at,
             'notifications', (SELECT COALESCE(jsonb_agg(jsonb_build_object(
                                        'recipient_kind', n.recipient_kind, 'event', n.event, 'status', n.status,
                                        'attempts', n.attempts, 'periods_count', jsonb_array_length(n.periods),
                                        'created_at', n.created_at, 'sent_at', n.sent_at)
                                      ORDER BY n.created_at, n.recipient_kind), '[]'::jsonb)
                                 FROM public.cl_notifications n WHERE n.incident_id = v.id))
      FROM public.cl_feeds f
      LEFT JOIN public.cl_plans pl ON pl.id = v.plan_id
      LEFT JOIN public.profiles pa ON pa.id = v.assignee_id
      LEFT JOIN public.profiles pc ON pc.id = v.closed_by
     WHERE f.id = v.feed_id);
END $$;

-- Cambia estado (open / in_progress), responsable y/o nota. NULL = no tocar; p_clear_assignee quita el responsable;
-- p_note '' borra la nota. El responsable debe ser de la cuenta. Una incidencia resuelta no se edita
-- (22023 CL_INCIDENT_CLOSED). Devuelve el detalle.
CREATE OR REPLACE FUNCTION public.cl_incident_update(p_incident_id uuid, p_status text DEFAULT NULL,
                                                     p_assignee_id uuid DEFAULT NULL, p_note text DEFAULT NULL,
                                                     p_clear_assignee boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v public.cl_incidents := public.cl_incident_authorize(p_incident_id, 'edit');
BEGIN
  SELECT i.* INTO v FROM public.cl_incidents i WHERE i.id = v.id FOR UPDATE;
  IF v.status = 'resolved' THEN
    RAISE EXCEPTION 'CL_INCIDENT_CLOSED' USING ERRCODE = '22023';
  END IF;
  IF p_status IS NOT NULL AND p_status NOT IN ('open','in_progress') THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: status must be open or in_progress' USING ERRCODE = '22023';
  END IF;
  IF p_note IS NOT NULL AND length(p_note) > 4000 THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: note too long' USING ERRCODE = '22023';
  END IF;
  IF p_assignee_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_assignee_id AND p.account_id = v.account_id)
     AND NOT EXISTS (SELECT 1 FROM public.account_user_role r WHERE r.user_id = p_assignee_id AND r.account_id = v.account_id) THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: assignee is not a member of the account' USING ERRCODE = '22023';
  END IF;
  UPDATE public.cl_incidents i
     SET status = COALESCE(p_status, i.status),
         assignee_id = CASE WHEN p_clear_assignee THEN NULL ELSE COALESCE(p_assignee_id, i.assignee_id) END,
         notes = CASE WHEN p_note IS NULL THEN i.notes ELSE NULLIF(p_note, '') END,
         updated_at = now()
   WHERE i.id = v.id;
  RETURN public.cl_incident_get(v.id);
END $$;

-- Cierre a mano (cualquier tipo; quota_unfilled solo se cierra asi). Idempotente: ya resuelta -> devuelve el detalle.
CREATE OR REPLACE FUNCTION public.cl_incident_close(p_incident_id uuid, p_note text DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v public.cl_incidents := public.cl_incident_authorize(p_incident_id, 'edit');
BEGIN
  IF p_note IS NOT NULL AND length(p_note) > 4000 THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: note too long' USING ERRCODE = '22023';
  END IF;
  SELECT i.* INTO v FROM public.cl_incidents i WHERE i.id = v.id FOR UPDATE;
  IF v.status <> 'resolved' THEN
    PERFORM public.cl_incident_close_core(v.id, 'manual', auth.uid(), NULLIF(p_note, ''), now());
  END IF;
  RETURN public.cl_incident_get(v.id);
END $$;

-- ================================================================ 9. permiso cl_incidents: SOLO DEMO2
-- Se registra como las demas cl_* (catalogo), pero NO va en access_template: las cuentas nuevas y un
-- account_access_reset (que copia la plantilla) no lo reciben. Kenya, Senegal, AGENT y el resto no lo tienen.
-- Se concede solo en DEMO2 (f4d823d2-93e6-4755-9a89-9da87e7fa86e) con los niveles de cl_monitor (AM y UPU Edit, APM
-- y DO View). OJO: un account_access_reset en DEMO2 lo quita; para devolverlo: SELECT public.cl_incidents_grant_demo2();
INSERT INTO public.access_option (key, menu_group, sort) VALUES ('cl_incidents', 'carrier_link', 157)
ON CONFLICT (key) DO NOTHING;   -- re-ejecutable (la concesion a DEMO2 tambien: ON CONFLICT DO NOTHING)

CREATE OR REPLACE FUNCTION public.cl_incidents_grant_demo2()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_n integer;
BEGIN
  INSERT INTO public.account_access (account_id, role, option, level)
  SELECT a.id, x.role, 'cl_incidents', x.level
    FROM public.accounts a
   CROSS JOIN (VALUES ('account_manager','edit'), ('upu_account_manager','edit'),
                      ('allocation_plan_manager','view'), ('do_coordinator','view')) x(role, level)
   WHERE a.id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e'
  ON CONFLICT DO NOTHING;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;
REVOKE ALL ON FUNCTION public.cl_incidents_grant_demo2() FROM PUBLIC, anon, authenticated, service_role;
SELECT public.cl_incidents_grant_demo2();

-- ================================================================ 10. cola de avisos (Edge Function carrier-link-notify)
-- Reclama hasta p_limit avisos debidos (pending con next_attempt_at vencido, o sending con el arriendo caducado) con un
-- arriendo de p_lease_seconds para p_token. Cada aviso (= un correo a una direccion) reclamado suma un intento. Con 5
-- intentos y el arriendo caducado -> failed. Devuelve [{notification_id, recipient_kind, to: [direccion], language, incident_type,
-- event, connector, periods: [{period_start, period_end, recuentos}], open_periods}]: sin ids internos, codigos de
-- error ni datos de envios.
CREATE OR REPLACE FUNCTION public.cl_notify_claim(p_token text, p_limit integer DEFAULT 20,
                                                  p_lease_seconds integer DEFAULT 300, p_now timestamptz DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_n     record;
  v_items jsonb := '[]'::jsonb;
BEGIN
  IF p_token IS NULL OR p_token !~ '^[A-Za-z0-9-]{8,100}$' THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: invalid token' USING ERRCODE = '22023';
  END IF;
  UPDATE public.cl_notifications n
     SET status = 'failed', last_error = COALESCE(n.last_error, 'CL_LEASE_EXPIRED'), lease_token = NULL,
         lease_until = NULL, updated_at = p_now
   WHERE n.status = 'sending' AND n.lease_until < p_now AND n.attempts >= 5;
  -- Incidencia ya cerrada (revision final, T8-M2): lo que quedaba pendiente o en un envio que murio no sale despues
  -- del cierre (cl_incident_close_core ya salta los pending; aqui, los 'sending' con el arriendo caducado).
  UPDATE public.cl_notifications n
     SET status = 'skipped', last_error = 'CL_INCIDENT_CLOSED', lease_token = NULL, lease_until = NULL, updated_at = p_now
    FROM public.cl_incidents i
   WHERE i.id = n.incident_id AND i.status = 'resolved'
     AND ((n.status = 'pending' AND n.next_attempt_at <= p_now) OR (n.status = 'sending' AND n.lease_until < p_now));

  FOR v_n IN SELECT n.id, n.recipient_kind, n.recipient_email, n.event, n.periods, i.incident_type, i.periods AS all_periods,
                    f.name AS connector, a.default_language
               FROM public.cl_notifications n
               JOIN public.cl_incidents i ON i.id = n.incident_id
               JOIN public.cl_feeds f ON f.id = i.feed_id
               JOIN public.accounts a ON a.id = n.account_id
              WHERE ((n.status = 'pending' AND n.next_attempt_at <= p_now)
                  OR (n.status = 'sending' AND n.lease_until < p_now))
                AND i.status <> 'resolved'
              ORDER BY n.created_at, n.id
              LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100)
                FOR UPDATE OF n SKIP LOCKED
  LOOP
    UPDATE public.cl_notifications n
       SET status = 'sending', attempts = n.attempts + 1, lease_token = p_token,
           lease_until = p_now + make_interval(secs => LEAST(GREATEST(COALESCE(p_lease_seconds, 300), 30), 3600)),
           updated_at = p_now
     WHERE n.id = v_n.id;
    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'notification_id', v_n.id, 'recipient_kind', v_n.recipient_kind, 'to', jsonb_build_array(v_n.recipient_email),
      'language', lower(COALESCE(v_n.default_language, 'en')), 'incident_type', v_n.incident_type,
      'event', v_n.event, 'connector', v_n.connector, 'open_periods', jsonb_array_length(v_n.all_periods),
      'periods', (SELECT COALESCE(jsonb_agg(jsonb_strip_nulls(jsonb_build_object(
                           'period_start', e->'period_start', 'period_end', e->'period_end',
                           'rejected', e->'rejected', 'shipments', e->'shipments', 'ratio', e->'ratio',
                           'products', e->'products', 'points', e->'points', 'missing', e->'missing'))
                         ORDER BY ord), '[]'::jsonb)
                    FROM jsonb_array_elements(v_n.periods) WITH ORDINALITY t(e, ord))));
  END LOOP;
  RETURN v_items;
END $$;

-- Resultado del envio. Solo cuenta si el aviso sigue 'sending' con ESE token (si no: 'lost', sin cambios). ok -> sent.
-- Fallo con la incidencia ya cerrada -> skipped (CL_INCIDENT_CLOSED, no se reintenta).
-- Fallo: p_final o 5 intentos -> failed; si no, pending con espera (5 min x intentos). p_error: solo un codigo
-- (^[A-Z0-9_]{1,40}$), otro texto -> CL_SEND_ERROR. Devuelve el estado resultante.
CREATE OR REPLACE FUNCTION public.cl_notify_result(p_notification_id uuid, p_token text, p_ok boolean,
                                                   p_error text DEFAULT NULL, p_final boolean DEFAULT false,
                                                   p_provider_id text DEFAULT NULL, p_now timestamptz DEFAULT now())
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v   public.cl_notifications;
  v_s text;
BEGIN
  SELECT n.* INTO v FROM public.cl_notifications n WHERE n.id = p_notification_id FOR UPDATE;
  IF v.id IS NULL OR v.status <> 'sending' OR v.lease_token IS DISTINCT FROM p_token THEN
    RETURN 'lost';
  END IF;
  IF p_ok THEN
    v_s := 'sent';
    UPDATE public.cl_notifications n
       SET status = 'sent', sent_at = p_now, lease_token = NULL, lease_until = NULL, last_error = NULL,
           provider_id = CASE WHEN p_provider_id ~ '^[A-Za-z0-9_-]{1,100}$' THEN p_provider_id END, updated_at = p_now
     WHERE n.id = v.id;
  ELSIF EXISTS (SELECT 1 FROM public.cl_incidents i WHERE i.id = v.incident_id AND i.status = 'resolved') THEN
    -- Fallo de un envio cuya incidencia se cerro mientras tanto: no se reintenta (revision final, T8-M2).
    v_s := 'skipped';
    UPDATE public.cl_notifications n
       SET status = 'skipped', lease_token = NULL, lease_until = NULL, last_error = 'CL_INCIDENT_CLOSED', updated_at = p_now
     WHERE n.id = v.id;
  ELSE
    v_s := CASE WHEN COALESCE(p_final, false) OR v.attempts >= 5 THEN 'failed' ELSE 'pending' END;
    UPDATE public.cl_notifications n
       SET status = v_s, lease_token = NULL, lease_until = NULL,
           last_error = CASE WHEN p_error ~ '^[A-Z0-9_]{1,40}$' THEN p_error ELSE 'CL_SEND_ERROR' END,
           next_attempt_at = p_now + make_interval(mins => 5 * v.attempts), updated_at = p_now
     WHERE n.id = v.id;
  END IF;
  RETURN v_s;
END $$;

-- Cada minuto (pg_cron): si hay avisos debidos, llama a la Edge Function por pg_net. URL y secreto en Vault:
-- cl_notify_url (https://<ref>.supabase.co/functions/v1/carrier-link-notify) y cl_notify_secret (= variable
-- CL_NOTIFY_SECRET de la funcion). Sin secretos: no llama.
CREATE OR REPLACE FUNCTION public.cl_notify_kick(p_now timestamptz DEFAULT now())
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_url    text;
  v_secret text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.cl_notifications n
                  WHERE (n.status = 'pending' AND n.next_attempt_at <= p_now)
                     OR (n.status = 'sending' AND n.lease_until < p_now)) THEN
    RETURN false;
  END IF;
  IF to_regclass('vault.decrypted_secrets') IS NULL THEN RETURN false; END IF;
  SELECT s.decrypted_secret INTO v_url FROM vault.decrypted_secrets s WHERE s.name = 'cl_notify_url';
  SELECT s.decrypted_secret INTO v_secret FROM vault.decrypted_secrets s WHERE s.name = 'cl_notify_secret';
  IF v_url IS NULL OR v_secret IS NULL THEN RETURN false; END IF;
  PERFORM net.http_post(url := v_url, body := '{}'::jsonb,
                        headers := jsonb_build_object('Content-Type', 'application/json', 'x-cl-notify-secret', v_secret),
                        timeout_milliseconds := 5000);
  RETURN true;
END $$;

-- ================================================================ 11. privilegios
REVOKE ALL ON FUNCTION public.cl_feed_missing_grace_hours(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_is_carrier_side(text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_enqueue(uuid, text, jsonb, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_record(uuid, uuid, uuid, text, jsonb, jsonb, timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_close_core(uuid, text, uuid, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_auto_close(uuid, text, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_unknown_registered(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_rejection_codes() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_deliveries_incidents() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_plan_quotas_incidents() FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_period_deadline(public.cl_feeds, date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_check_missing(public.cl_feeds, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_settle_quota(uuid, boolean) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_settle_quota(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_authorize(uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_recipients(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_notify_kick(timestamptz) FROM PUBLIC, anon, authenticated, service_role;

-- Pantalla (authenticated).
REVOKE ALL ON FUNCTION public.cl_incidents_list(uuid, text, text, uuid, integer, integer) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_get(uuid) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_update(uuid, text, uuid, text, boolean) FROM PUBLIC, anon, service_role;
REVOKE ALL ON FUNCTION public.cl_incident_close(uuid, text) FROM PUBLIC, anon, service_role;
GRANT EXECUTE ON FUNCTION public.cl_incidents_list(uuid, text, text, uuid, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cl_incident_get(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cl_incident_update(uuid, text, uuid, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cl_incident_close(uuid, text) TO authenticated;

-- Edge Function carrier-link-notify (service_role).
REVOKE ALL ON FUNCTION public.cl_notify_claim(text, integer, integer, timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_notify_result(uuid, text, boolean, text, boolean, text, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cl_notify_claim(text, integer, integer, timestamptz) TO service_role;
GRANT EXECUTE ON FUNCTION public.cl_notify_result(uuid, text, boolean, text, boolean, text, timestamptz) TO service_role;

-- ================================================================ 12. pg_cron (idempotente)
DO $$
BEGIN
  IF to_regclass('cron.job') IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'cl-notify-kick') THEN
      PERFORM cron.unschedule('cl-notify-kick');
    END IF;
    PERFORM cron.schedule('cl-notify-kick', '* * * * *', 'SELECT public.cl_notify_kick();');
  END IF;
END $$;
