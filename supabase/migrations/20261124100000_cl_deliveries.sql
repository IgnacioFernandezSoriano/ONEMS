-- Carrier Link v4, tarea 1: modelo de entrega completa por periodo (spec 2026-11-19-carrier-link-design.md, v4:
-- R24-R28, D19-D23). El carrier sube, por periodo de entrega (de diario a semanal), un fichero con TODOS los envios
-- completos del periodo; ONEMS lo valida, cuenta, sortea su propia muestra y vacia la zona de paso (tareas 2-3).
-- Auditorias APLAZADAS (responsable 23/11): solo se guardan los totales de control declarados.
--
-- Contenido:
--   cl_deliveries        una fila por entrega (periodo, fichero, huella sha256, totales declarados, estado, recuentos).
--   cl_delivery_strata   recuento por estrato (cuota ruta x semana ISO) de cada entrega: poblacion, cuota, elegidos, semilla.
--   cl_delivery_rows     zona de paso UNLOGGED (una lectura por fila, columnas estandar + extras permitidos). Solo la
--                        usa el proceso en segundo plano; nadie tiene privilegios sobre ella.
--   cl_samples.delivery_id / cl_alerts.delivery_id   traza de la entrega en lo elegido y en las alertas.
--   bucket privado 'cl-deliveries' (ruta <account_id>/<feed_id>/<delivery_id>.<ext>) y politicas de storage.objects.
--   cl_connector_config(feed)                 configuracion para la Edge Function (service_role).
--   cl_delivery_open / cl_delivery_complete   abrir una entrega (valida periodo y calendario, idempotente por
--                                             sha256 + periodo) y marcarla recibida cuando el fichero ya esta subido
--                                             (service_role); cl_manual_delivery_open / _complete para la web.
--
-- Estados de una entrega:
--   pending_upload -> received -> processing -> processed
--                                           \-> failed (reanudable: failed -> processing) / rejected
--   pending_upload -> rejected (CL_SUPERSEDED: otra entrega del mismo periodo con otro fichero; CL_FILE_TOO_LARGE)
--   processed y rejected son finales. Cuentan como "entregado" received, processing, processed y failed.
--
-- Fechas: period_start / period_end son fechas locales de la CUENTA (las mismas con las que cl_ingest_batch decide
-- end_out_of_period). El calendario del conector (emit_days, emit_hour, emit_timezone; ahora "dias de entrega") define
-- los periodos: una entrega el dia D cubre desde el dia de entrega anterior hasta D-1 (diaria: D-1; semanal el lunes:
-- lunes..domingo anteriores; lunes y jueves: jue..dom y lun..mie). emit_hour es la hora local esperada (para due_at).
-- Forward-only. No toca cl_ingest_batch, demandas ni la carga manual por lotes (20261123100000).

-- ================================================================ 1. tablas
CREATE TABLE public.cl_deliveries (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id      uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  feed_id         uuid NOT NULL REFERENCES public.cl_feeds(id) ON DELETE CASCADE,
  period_start    date NOT NULL,
  period_end      date NOT NULL,
  source          text NOT NULL CHECK (source IN ('api','manual')),
  created_by      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  is_test         boolean NOT NULL DEFAULT false,   -- conector en prueba al abrirla (D2): se valida y cuenta, no se muestrea
  format          text NOT NULL CHECK (format IN ('jsonl','csv')),
  compression     text NOT NULL CHECK (compression IN ('gzip','none')),
  file_path       text NOT NULL UNIQUE,              -- nombre del objeto en el bucket cl-deliveries
  file_bytes      bigint,
  file_deleted_at timestamptz,                       -- el fichero se borra tras N dias; se conserva la huella
  sha256          text NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
  control_totals  jsonb NOT NULL DEFAULT '[]',       -- declarados por el carrier (sin comparar: auditorias aplazadas)
  status          text NOT NULL DEFAULT 'pending_upload'
                  CHECK (status IN ('pending_upload','received','processing','processed','failed','rejected')),
  progress        jsonb NOT NULL DEFAULT '{}',       -- cursor del proceso en segundo plano (reanudable)
  rows_total      bigint,
  rows_rejected   bigint,
  shipments_total bigint,                            -- envios distintos en el fichero
  shipments_valid bigint,                            -- envios completos y validos (poblacion total)
  shipments_drawn bigint,
  rejected_reasons jsonb,                            -- { motivo: n }
  error           text,
  created_at      timestamptz NOT NULL DEFAULT now(),
  received_at     timestamptz,
  processing_started_at timestamptz,
  finished_at     timestamptz,
  CONSTRAINT cl_deliveries_period_valid CHECK (period_start <= period_end AND period_end - period_start < 7)
);
CREATE INDEX cl_deliveries_account_idx ON public.cl_deliveries (account_id);
CREATE INDEX cl_deliveries_feed_period_idx ON public.cl_deliveries (feed_id, period_end);
CREATE INDEX cl_deliveries_created_by_idx ON public.cl_deliveries (created_by);
-- Idempotencia: el mismo fichero para el mismo periodo es una sola entrega (salvo si se rechazo: se puede reintentar).
CREATE UNIQUE INDEX cl_deliveries_idem_uidx ON public.cl_deliveries (feed_id, period_start, period_end, sha256)
  WHERE status <> 'rejected';
-- R25: la zona de paso contiene como maximo una entrega -> una sola entrega 'processing' en toda la base.
CREATE UNIQUE INDEX cl_deliveries_one_processing_uidx ON public.cl_deliveries ((true)) WHERE status = 'processing';
-- Cola del proceso en segundo plano.
CREATE INDEX cl_deliveries_queue_idx ON public.cl_deliveries (received_at) WHERE status IN ('received','failed');

CREATE TABLE public.cl_delivery_strata (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id         uuid NOT NULL REFERENCES public.accounts(id) ON DELETE CASCADE,
  delivery_id        uuid NOT NULL REFERENCES public.cl_deliveries(id) ON DELETE CASCADE,
  quota_id           uuid NOT NULL,   -- cl_plan_quotas.id (sin FK, como cl_batch_scans: la entrega conserva su traza)
  population         integer NOT NULL DEFAULT 0 CHECK (population >= 0),
  quota_for_delivery integer NOT NULL DEFAULT 0 CHECK (quota_for_delivery >= 0),
  selected           integer NOT NULL DEFAULT 0 CHECK (selected >= 0),
  seed               text NOT NULL DEFAULT encode(gen_random_bytes(16), 'hex'),   -- sorteo md5(seed || item_id)
  created_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (delivery_id, quota_id)
);
CREATE INDEX cl_delivery_strata_quota_idx ON public.cl_delivery_strata (quota_id);

-- Zona de paso. UNLOGGED: no pasa por el WAL (rapida para millones de filas) y se vacia sola tras una caida; el
-- proceso tiene que detectarlo (filas cargadas < progress) y recargar el fichero. Sin FK ni disparadores (coste por
-- fila); la PK (delivery_id, row_no) hace idempotente la recarga de un trozo (ON CONFLICT DO NOTHING).
-- Lista cerrada de columnas: nada de datos personales; extra solo lleva campos de cl_extra_fields.
CREATE UNLOGGED TABLE public.cl_delivery_rows (
  delivery_id   uuid NOT NULL,
  row_no        bigint NOT NULL,      -- numero de fila en el fichero (1..n)
  item_id       text,                 -- valores del carrier ya con los nombres estandar (equivalencias de campo)
  product       text,
  scan_at_raw   text,
  place_ref     text,
  mode_ref      text,
  extra         jsonb,
  product_id    uuid,                 -- derivados por el proceso (equivalencias de valor, puntos, fecha)
  scan_at       timestamptz,
  reader_id     uuid,
  resolved_mode text,
  row_reason    text,
  PRIMARY KEY (delivery_id, row_no)
);
CREATE INDEX cl_delivery_rows_item_idx ON public.cl_delivery_rows (delivery_id, item_id);

-- Traza de la entrega en lo elegido y en sus alertas.
ALTER TABLE public.cl_samples ADD COLUMN delivery_id uuid REFERENCES public.cl_deliveries(id) ON DELETE RESTRICT;
ALTER TABLE public.cl_alerts  ADD COLUMN delivery_id uuid REFERENCES public.cl_deliveries(id) ON DELETE CASCADE;
CREATE INDEX cl_samples_delivery_idx ON public.cl_samples (delivery_id);
CREATE INDEX cl_alerts_delivery_idx  ON public.cl_alerts (delivery_id);

-- ================================================================ 2. misma cuenta (generico, 20261120110250)
CREATE TRIGGER cl_same_account BEFORE INSERT OR UPDATE ON public.cl_deliveries
  FOR EACH ROW EXECUTE FUNCTION public.cl_check_same_account('feed_id', 'cl_feeds');
CREATE TRIGGER cl_same_account BEFORE INSERT OR UPDATE ON public.cl_delivery_strata
  FOR EACH ROW EXECUTE FUNCTION public.cl_check_same_account('delivery_id', 'cl_deliveries', 'quota_id', 'cl_plan_quotas');
-- cl_samples y cl_alerts: mismas listas que 20261120110200 + delivery_id.
DROP TRIGGER cl_same_account ON public.cl_samples;
CREATE TRIGGER cl_same_account BEFORE INSERT OR UPDATE ON public.cl_samples
  FOR EACH ROW EXECUTE FUNCTION public.cl_check_same_account(
    'plan_id', 'cl_plans', 'quota_id', 'cl_plan_quotas', 'batch_id', 'cl_batches', 'carrier_id', 'carriers',
    'product_id', 'products', 'start_reader_id', 'readers', 'end_reader_id', 'readers', 'origin_city_id', 'cities',
    'destination_city_id', 'cities', 'delivery_id', 'cl_deliveries');
DROP TRIGGER cl_same_account ON public.cl_alerts;
CREATE TRIGGER cl_same_account BEFORE INSERT OR UPDATE ON public.cl_alerts
  FOR EACH ROW EXECUTE FUNCTION public.cl_check_same_account(
    'plan_id', 'cl_plans', 'batch_id', 'cl_batches', 'quota_id', 'cl_plan_quotas', 'delivery_id', 'cl_deliveries');

-- ================================================================ 3. transiciones de estado e inmutables
CREATE OR REPLACE FUNCTION public.cl_deliveries_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path = public, extensions
AS $$
BEGIN
  IF (NEW.account_id, NEW.feed_id, NEW.period_start, NEW.period_end, NEW.source, NEW.is_test, NEW.format,
      NEW.compression, NEW.file_path, NEW.sha256, NEW.control_totals, NEW.created_at)
     IS DISTINCT FROM
     (OLD.account_id, OLD.feed_id, OLD.period_start, OLD.period_end, OLD.source, OLD.is_test, OLD.format,
      OLD.compression, OLD.file_path, OLD.sha256, OLD.control_totals, OLD.created_at) THEN
    RAISE EXCEPTION 'CL_DELIVERY_IMMUTABLE: identity fields of a delivery cannot change' USING ERRCODE = '22023';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status AND NOT (
       (OLD.status = 'pending_upload' AND NEW.status IN ('received','rejected'))
    OR (OLD.status = 'received'       AND NEW.status IN ('processing','failed','rejected'))
    OR (OLD.status = 'processing'     AND NEW.status IN ('processed','failed','rejected'))
    OR (OLD.status = 'failed'         AND NEW.status IN ('processing','rejected'))) THEN
    RAISE EXCEPTION 'CL_DELIVERY_BAD_TRANSITION: % -> %', OLD.status, NEW.status USING ERRCODE = '22023';
  END IF;
  RETURN NEW;
END $$;
REVOKE ALL ON FUNCTION public.cl_deliveries_guard() FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER cl_deliveries_guard BEFORE UPDATE ON public.cl_deliveries
  FOR EACH ROW EXECUTE FUNCTION public.cl_deliveries_guard();

-- ================================================================ 4. privilegios y RLS
-- Leen: superadmin o la cuenta activa con View en cl_monitor o cl_connectors. Nadie escribe directamente
-- (ni service_role): solo funciones SECURITY DEFINER. La zona de paso no se concede a nadie.
ALTER TABLE public.cl_deliveries      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cl_delivery_strata ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cl_delivery_rows   ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cl_deliveries, public.cl_delivery_strata, public.cl_delivery_rows
  FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.cl_deliveries, public.cl_delivery_strata TO authenticated, service_role;

CREATE POLICY cl_deliveries_select_access ON public.cl_deliveries FOR SELECT TO authenticated
  USING ((SELECT public.is_superadmin())
         OR (account_id = (SELECT public.current_user_account_id())
             AND (SELECT public.has_any_access(public.current_user_account_id(), 'view', 'cl_monitor', 'cl_connectors'))));
CREATE POLICY cl_delivery_strata_select_access ON public.cl_delivery_strata FOR SELECT TO authenticated
  USING ((SELECT public.is_superadmin())
         OR (account_id = (SELECT public.current_user_account_id())
             AND (SELECT public.has_any_access(public.current_user_account_id(), 'view', 'cl_monitor', 'cl_connectors'))));

-- ================================================================ 5. helpers internos
-- Topes del conector (cl_feeds.config, editable en Conectores) con valores por defecto y limites duros.
CREATE OR REPLACE FUNCTION public.cl_delivery_limits(p_config jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path = public, extensions
AS $$
  SELECT jsonb_build_object(
    'max_file_bytes', CASE WHEN jsonb_typeof(p_config->'max_file_bytes') = 'number'
                            AND (p_config->>'max_file_bytes')::numeric BETWEEN 1 AND 524288000
                           THEN trunc((p_config->>'max_file_bytes')::numeric)::bigint ELSE 524288000 END,
    'max_rows', CASE WHEN jsonb_typeof(p_config->'max_rows') = 'number'
                      AND (p_config->>'max_rows')::numeric BETWEEN 1 AND 50000000
                     THEN trunc((p_config->>'max_rows')::numeric)::bigint ELSE 5000000 END,
    'file_retention_days', CASE WHEN jsonb_typeof(p_config->'file_retention_days') = 'number'
                                 AND (p_config->>'file_retention_days')::numeric BETWEEN 1 AND 3650
                                THEN trunc((p_config->>'file_retention_days')::numeric)::integer ELSE 30 END,
    'max_control_totals', 10000)
$$;

-- Zona de las fechas de periodo: la de la cuenta si es valida, si no UTC (igual que cl_ingest_batch).
CREATE OR REPLACE FUNCTION public.cl_account_date_tz(p_account_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT COALESCE((SELECT a.timezone FROM public.accounts a
                    WHERE a.id = p_account_id AND a.timezone IS NOT NULL
                      AND public.cl_is_valid_timezone(a.timezone)), 'UTC')
$$;

-- Periodo del calendario que contiene p_date: desde el ultimo dia de entrega <= p_date hasta el dia anterior al
-- siguiente dia de entrega > p_date. p_days = isodow (1 = lunes) de los dias de entrega (no vacio).
CREATE OR REPLACE FUNCTION public.cl_delivery_aligned_period(p_days smallint[], p_date date,
                                                             OUT period_start date, OUT period_end date)
 LANGUAGE sql
 IMMUTABLE
 SET search_path = public, extensions
AS $$
  SELECT (SELECT max(p_date - i) FROM generate_series(0, 6) i
           WHERE extract(isodow FROM p_date - i)::smallint = ANY (p_days)),
         (SELECT min(p_date + i) FROM generate_series(1, 7) i
           WHERE extract(isodow FROM p_date + i)::smallint = ANY (p_days)) - 1
$$;

-- Proximo periodo a entregar: el siguiente al ultimo entregado (received/processing/processed/failed) o, sin
-- entregas, el que contiene el inicio del primer plan activo del conector. NULL si ya no queda plan por cubrir.
-- No rellena huecos anteriores (las entregas que faltan son cosa de alertas, tarea posterior).
CREATE OR REPLACE FUNCTION public.cl_delivery_next_period(p_feed_id uuid, p_now timestamptz)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_feed public.cl_feeds;
  v_first date;
  v_last  date;
  v_anchor date;
  v_last_end date;
  v_p record;
  v_start date;
  v_today date;
BEGIN
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF v_feed.id IS NULL THEN RETURN NULL; END IF;
  SELECT min(p.start_date), max(p.end_date) INTO v_first, v_last
    FROM public.cl_plans p
   WHERE p.feed_id = p_feed_id AND p.carrier_id = v_feed.carrier_id AND p.status = 'active';
  IF v_first IS NULL THEN RETURN NULL; END IF;
  SELECT max(d.period_end) INTO v_last_end
    FROM public.cl_deliveries d
   WHERE d.feed_id = p_feed_id AND d.status IN ('received','processing','processed','failed');
  v_anchor := COALESCE(v_last_end + 1, v_first);
  IF v_anchor > v_last THEN RETURN NULL; END IF;
  SELECT * INTO v_p FROM public.cl_delivery_aligned_period(v_feed.emit_days, v_anchor);
  v_start := GREATEST(v_p.period_start, v_anchor);   -- tras un cambio de calendario, sin solaparse con lo entregado
  v_today := (p_now AT TIME ZONE public.cl_account_date_tz(v_feed.account_id))::date;
  RETURN jsonb_build_object(
    'period_start', v_start,
    'period_end', v_p.period_end,
    'due_at', ((v_p.period_end + 1) + make_interval(hours => v_feed.emit_hour))
                AT TIME ZONE public.cl_effective_tz(v_feed.account_id, v_feed.id),
    'deliverable', v_p.period_end < v_today);
END $$;

-- Resumen de una entrega (lo devuelven abrir / completar; la tarea 3 lo usa para GET /deliveries/{id}).
CREATE OR REPLACE FUNCTION public.cl_delivery_summary(p_delivery_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT jsonb_build_object(
    'delivery_id', d.id, 'feed_id', d.feed_id, 'status', d.status, 'is_test', d.is_test, 'source', d.source,
    'period_start', d.period_start, 'period_end', d.period_end, 'format', d.format, 'compression', d.compression,
    'file_path', d.file_path, 'file_bytes', d.file_bytes, 'sha256', d.sha256,
    'rows_total', d.rows_total, 'rows_rejected', d.rows_rejected, 'shipments_total', d.shipments_total,
    'shipments_valid', d.shipments_valid, 'shipments_drawn', d.shipments_drawn,
    'rejected_reasons', d.rejected_reasons, 'error', d.error,
    'created_at', d.created_at, 'received_at', d.received_at, 'finished_at', d.finished_at)
    FROM public.cl_deliveries d WHERE d.id = p_delivery_id
$$;

-- Permiso de la web: devuelve el conector o 42501 CL_FORBIDDEN (igual para ajeno, inexistente, NULL o sin Edit).
CREATE OR REPLACE FUNCTION public.cl_delivery_authorize_manual(p_feed_id uuid)
 RETURNS public.cl_feeds
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE v_feed public.cl_feeds;
BEGIN
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF v_feed.id IS NULL
     OR NOT (public.is_superadmin()
             OR (v_feed.account_id = public.current_user_account_id()
                 AND public.has_any_access(v_feed.account_id, 'edit', 'cl_connectors'))) THEN
    RAISE EXCEPTION 'CL_FORBIDDEN' USING ERRCODE = '42501';
  END IF;
  RETURN v_feed;
END $$;

-- ================================================================ 6. abrir una entrega
-- Orden: forma de la peticion, conector (pausado), idempotencia (mismo fichero y periodo -> la misma entrega, con
-- existing = true, en cualquier estado salvo rejected), periodo cerrado, ya entregado (solape con una entrega
-- received/processing/processed/failed: CL_PERIOD_ALREADY_DELIVERED), calendario, plan activo. Una entrega
-- pending_upload del mismo periodo con otro fichero queda rejected (CL_SUPERSEDED).
CREATE OR REPLACE FUNCTION public.cl_delivery_open_core(
  p_feed_id uuid, p_period_start date, p_period_end date, p_sha256 text, p_control_totals jsonb,
  p_format text, p_compression text, p_source text, p_user uuid, p_now timestamptz)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_feed   public.cl_feeds;
  v_sha    text := lower(btrim(p_sha256));
  v_limits jsonb;
  v_id     uuid;
  v_today  date;
  v_al     record;
  v_expect date;
  v_other  public.cl_deliveries;
BEGIN
  IF p_feed_id IS NULL OR p_period_start IS NULL OR p_period_end IS NULL OR p_sha256 IS NULL THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: period_start, period_end and sha256 are required' USING ERRCODE = '22023';
  END IF;
  IF v_sha !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: sha256 must be 64 hexadecimal characters' USING ERRCODE = '22023';
  END IF;
  IF p_format IS NULL OR p_format NOT IN ('jsonl','csv') THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: format must be jsonl or csv' USING ERRCODE = '22023';
  END IF;
  IF p_compression IS NULL OR p_compression NOT IN ('gzip','none') THEN
    RAISE EXCEPTION 'CL_BAD_REQUEST: compression must be gzip or none' USING ERRCODE = '22023';
  END IF;
  IF p_period_start > p_period_end THEN
    RAISE EXCEPTION 'CL_BAD_PERIOD: period_start is after period_end' USING ERRCODE = '22023';
  END IF;

  -- Totales de control: lista cerrada de claves (sin datos personales). Se guardan tal cual; no se comparan.
  IF p_control_totals IS NULL OR jsonb_typeof(p_control_totals) <> 'array' THEN
    RAISE EXCEPTION 'CL_BAD_CONTROL_TOTALS: control_totals must be an array' USING ERRCODE = '22023';
  END IF;
  IF jsonb_array_length(p_control_totals) > 10000
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(p_control_totals) e
                 WHERE jsonb_typeof(e) <> 'object'
                    OR EXISTS (SELECT 1 FROM jsonb_object_keys(e) k
                                WHERE k NOT IN ('place_ref','mode_ref','product','delivered'))
                    OR jsonb_typeof(e->'place_ref') IS DISTINCT FROM 'string'
                    OR length(e->>'place_ref') NOT BETWEEN 1 AND 200
                    OR (e ? 'mode_ref' AND jsonb_typeof(e->'mode_ref') NOT IN ('string','null'))
                    OR length(e->>'mode_ref') > 200
                    OR (e ? 'product' AND jsonb_typeof(e->'product') NOT IN ('string','null'))
                    OR length(e->>'product') > 200
                    OR CASE WHEN jsonb_typeof(e->'delivered') = 'number'
                            THEN (e->>'delivered')::numeric < 0
                              OR (e->>'delivered')::numeric > 2147483647
                              OR (e->>'delivered')::numeric <> trunc((e->>'delivered')::numeric)
                            ELSE true END) THEN
    RAISE EXCEPTION 'CL_BAD_CONTROL_TOTALS: each total is {place_ref, mode_ref?, product?, delivered} (max 10000)'
      USING ERRCODE = '22023';
  END IF;

  -- El bloqueo del conector serializa dos aperturas simultaneas (idempotencia y solapes).
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = p_feed_id FOR UPDATE;
  IF v_feed.id IS NULL THEN
    RAISE EXCEPTION 'CL_FEED_NOT_FOUND' USING ERRCODE = '22023';
  END IF;
  IF v_feed.status = 'paused' THEN
    RAISE EXCEPTION 'CL_FEED_PAUSED: the connector is paused' USING ERRCODE = '22023';
  END IF;
  v_limits := public.cl_delivery_limits(v_feed.config);

  -- Idempotencia.
  SELECT d.* INTO v_other FROM public.cl_deliveries d
   WHERE d.feed_id = p_feed_id AND d.period_start = p_period_start AND d.period_end = p_period_end
     AND d.sha256 = v_sha AND d.status <> 'rejected';
  IF v_other.id IS NOT NULL THEN
    RETURN public.cl_delivery_summary(v_other.id)
           || jsonb_build_object('existing', true, 'max_file_bytes', v_limits->'max_file_bytes');
  END IF;

  v_today := (p_now AT TIME ZONE public.cl_account_date_tz(v_feed.account_id))::date;
  IF p_period_end >= v_today THEN
    RAISE EXCEPTION 'CL_PERIOD_NOT_CLOSED: the period ends on % (local date today %)', p_period_end, v_today
      USING ERRCODE = '22023';
  END IF;

  SELECT d.* INTO v_other FROM public.cl_deliveries d
   WHERE d.feed_id = p_feed_id AND d.status IN ('received','processing','processed','failed')
     AND d.period_start <= p_period_end AND d.period_end >= p_period_start
   ORDER BY d.period_start LIMIT 1;
  IF v_other.id IS NOT NULL THEN
    RAISE EXCEPTION 'CL_PERIOD_ALREADY_DELIVERED: % to % overlaps delivery % (% to %, %)', p_period_start, p_period_end,
      v_other.id, v_other.period_start, v_other.period_end, v_other.status USING ERRCODE = 'P0001';
  END IF;

  -- Calendario: el dia siguiente al fin es dia de entrega; el inicio es el dia de entrega anterior (o el dia
  -- siguiente a lo ya entregado, si el calendario cambio a mitad de periodo).
  IF NOT (extract(isodow FROM p_period_end + 1)::smallint = ANY (v_feed.emit_days)) THEN
    RAISE EXCEPTION 'CL_PERIOD_NOT_IN_CALENDAR: % is not the day before a delivery day', p_period_end
      USING ERRCODE = '22023';
  END IF;
  SELECT * INTO v_al FROM public.cl_delivery_aligned_period(v_feed.emit_days, p_period_end);
  SELECT GREATEST(v_al.period_start, max(d.period_end) + 1) INTO v_expect
    FROM public.cl_deliveries d
   WHERE d.feed_id = p_feed_id AND d.status IN ('received','processing','processed','failed')
     AND d.period_end >= v_al.period_start AND d.period_end < p_period_end;
  v_expect := COALESCE(v_expect, v_al.period_start);
  IF p_period_start <> v_expect THEN
    RAISE EXCEPTION 'CL_PERIOD_NOT_IN_CALENDAR: the period ending % must start on %', p_period_end, v_expect
      USING ERRCODE = '22023';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.cl_plans p
                  WHERE p.feed_id = p_feed_id AND p.carrier_id = v_feed.carrier_id AND p.status = 'active'
                    AND p.start_date <= p_period_end AND p.end_date >= p_period_start) THEN
    RAISE EXCEPTION 'CL_NO_ACTIVE_PLAN: no active plan of this connector covers % to %', p_period_start, p_period_end
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.cl_deliveries d SET status = 'rejected', error = 'CL_SUPERSEDED', finished_at = now()
   WHERE d.feed_id = p_feed_id AND d.status = 'pending_upload'
     AND d.period_start <= p_period_end AND d.period_end >= p_period_start;

  v_id := gen_random_uuid();
  INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, created_by, is_test,
                                    format, compression, file_path, sha256, control_totals)
  VALUES (v_id, v_feed.account_id, p_feed_id, p_period_start, p_period_end, p_source, p_user,
          v_feed.status = 'testing', p_format, p_compression,
          v_feed.account_id || '/' || p_feed_id || '/' || v_id || '.' || p_format
            || CASE WHEN p_compression = 'gzip' THEN '.gz' ELSE '' END,
          v_sha, p_control_totals);
  RETURN public.cl_delivery_summary(v_id)
         || jsonb_build_object('existing', false, 'max_file_bytes', v_limits->'max_file_bytes');
END $$;

-- ================================================================ 7. completar (fichero subido)
-- Idempotente: una entrega que ya no esta pending_upload devuelve su resumen. Sin objeto en el bucket:
-- CL_FILE_NOT_UPLOADED. Mayor que el tope: rejected (CL_FILE_TOO_LARGE). La huella se comprueba al procesar.
CREATE OR REPLACE FUNCTION public.cl_delivery_complete_core(p_feed_id uuid, p_delivery_id uuid, p_source text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_d     public.cl_deliveries;
  v_feed  public.cl_feeds;
  v_bytes bigint;
  v_found boolean;
BEGIN
  SELECT d.* INTO v_d FROM public.cl_deliveries d
   WHERE d.id = p_delivery_id AND d.feed_id = p_feed_id AND d.source = p_source
   FOR UPDATE;
  IF v_d.id IS NULL THEN
    RAISE EXCEPTION 'CL_DELIVERY_NOT_FOUND' USING ERRCODE = '22023';
  END IF;
  IF v_d.status <> 'pending_upload' THEN
    RETURN public.cl_delivery_summary(v_d.id);
  END IF;
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF v_feed.status = 'paused' THEN
    RAISE EXCEPTION 'CL_FEED_PAUSED: the connector is paused' USING ERRCODE = '22023';
  END IF;

  SELECT true, (o.metadata->>'size')::bigint INTO v_found, v_bytes
    FROM storage.objects o
   WHERE o.bucket_id = 'cl-deliveries' AND o.name = v_d.file_path;
  IF v_found IS NULL THEN
    RAISE EXCEPTION 'CL_FILE_NOT_UPLOADED: upload the file before completing the delivery' USING ERRCODE = '22023';
  END IF;

  IF v_bytes > (public.cl_delivery_limits(v_feed.config)->>'max_file_bytes')::bigint THEN
    UPDATE public.cl_deliveries d SET status = 'rejected', error = 'CL_FILE_TOO_LARGE', file_bytes = v_bytes,
           finished_at = now()
     WHERE d.id = v_d.id;
  ELSE
    UPDATE public.cl_deliveries d SET status = 'received', file_bytes = v_bytes, received_at = now()
     WHERE d.id = v_d.id;
  END IF;
  RETURN public.cl_delivery_summary(v_d.id);
END $$;

-- ================================================================ 8. puntos de entrada
-- Edge Function (service_role; p_feed_id sale de la clave del conector, nunca del cuerpo).
CREATE OR REPLACE FUNCTION public.cl_delivery_open(
  p_feed_id uuid, p_period_start date, p_period_end date, p_sha256 text, p_control_totals jsonb,
  p_format text DEFAULT 'jsonl', p_compression text DEFAULT 'gzip')
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT public.cl_delivery_open_core(p_feed_id, p_period_start, p_period_end, p_sha256, p_control_totals,
                                      p_format, p_compression, 'api', NULL, now())
$$;

CREATE OR REPLACE FUNCTION public.cl_delivery_complete(p_feed_id uuid, p_delivery_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$ SELECT public.cl_delivery_complete_core(p_feed_id, p_delivery_id, 'api') $$;

-- Web (Conectores, subida manual): Edit en cl_connectors de la cuenta del conector, o superadmin.
CREATE OR REPLACE FUNCTION public.cl_manual_delivery_open(
  p_feed_id uuid, p_period_start date, p_period_end date, p_sha256 text, p_control_totals jsonb,
  p_format text DEFAULT 'jsonl', p_compression text DEFAULT 'gzip')
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.cl_delivery_authorize_manual(p_feed_id);
  RETURN public.cl_delivery_open_core(p_feed_id, p_period_start, p_period_end, p_sha256, p_control_totals,
                                      p_format, p_compression, 'manual', auth.uid(), now());
END $$;

CREATE OR REPLACE FUNCTION public.cl_manual_delivery_complete(p_feed_id uuid, p_delivery_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = public, extensions
AS $$
BEGIN
  PERFORM public.cl_delivery_authorize_manual(p_feed_id);
  RETURN public.cl_delivery_complete_core(p_feed_id, p_delivery_id, 'manual');
END $$;

-- ================================================================ 9. configuracion del conector (GET /config)
-- Lo que el carrier necesita para preparar la entrega, con sus propios codigos. Sin datos personales.
CREATE OR REPLACE FUNCTION public.cl_connector_config(p_feed_id uuid, p_now timestamptz DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
DECLARE
  v_feed   public.cl_feeds;
  v_n      integer;
  v_fields jsonb;
  v_last   jsonb;
BEGIN
  SELECT f.* INTO v_feed FROM public.cl_feeds f WHERE f.id = p_feed_id;
  IF v_feed.id IS NULL THEN
    RAISE EXCEPTION 'CL_FEED_NOT_FOUND' USING ERRCODE = '22023';
  END IF;
  v_n := cardinality(v_feed.emit_days);

  SELECT jsonb_build_object(
           'item_id',   (SELECT jsonb_build_object('field', m.carrier_field) FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'item_id'),
           'product',   (SELECT jsonb_build_object('field', m.carrier_field) FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'product'),
           'scan_at',   (SELECT jsonb_build_object('field', m.carrier_field, 'format', m.format, 'timezone', m.timezone)
                           FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'scan_at'),
           'place_ref', (SELECT jsonb_build_object('field', m.carrier_field) FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'place_ref'),
           'mode_ref',  (SELECT jsonb_build_object('field', m.carrier_field) FROM public.cl_field_mappings m
                          WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id AND m.standard_field = 'mode_ref'))
    INTO v_fields;

  SELECT jsonb_build_object('delivery_id', d.id, 'period_start', d.period_start, 'period_end', d.period_end,
                            'status', d.status)
    INTO v_last
    FROM public.cl_deliveries d
   WHERE d.feed_id = p_feed_id
   ORDER BY d.period_end DESC, d.created_at DESC LIMIT 1;

  RETURN jsonb_build_object(
    'schema_version', '4.0',
    'connector', jsonb_build_object('id', v_feed.id, 'name', v_feed.name, 'status', v_feed.status,
                                    'carrier', (SELECT c.code FROM public.carriers c WHERE c.id = v_feed.carrier_id)),
    'date_timezone', public.cl_account_date_tz(v_feed.account_id),
    'calendar', jsonb_build_object(
       'delivery_days', to_jsonb(v_feed.emit_days),
       'delivery_hour', v_feed.emit_hour,
       'timezone', public.cl_effective_tz(v_feed.account_id, v_feed.id),
       'deliveries_per_week', v_n,
       'frequency', CASE v_n WHEN 7 THEN 'daily' WHEN 1 THEN 'weekly' ELSE 'several_per_week' END),
    'fields', v_fields,
    'mapping_complete', jsonb_typeof(v_fields->'item_id') = 'object' AND jsonb_typeof(v_fields->'scan_at') = 'object'
                        AND jsonb_typeof(v_fields->'place_ref') = 'object',
    'extra_fields', COALESCE((SELECT jsonb_agg(x.carrier_field ORDER BY x.carrier_field)
                                FROM public.cl_extra_fields x
                               WHERE x.account_id = v_feed.account_id AND x.carrier_id = v_feed.carrier_id), '[]'::jsonb),
    'include_all_scans', COALESCE((SELECT bool_or(p.feed_diagnosis) FROM public.cl_plans p
                                    WHERE p.feed_id = p_feed_id AND p.carrier_id = v_feed.carrier_id
                                      AND p.status = 'active'), false),
    'plans', COALESCE((SELECT jsonb_agg(jsonb_build_object('product', pr.code, 'start_date', p.start_date,
                                                           'end_date', p.end_date, 'include_all_scans', p.feed_diagnosis)
                                        ORDER BY p.start_date, pr.code)
                         FROM public.cl_plans p JOIN public.products pr ON pr.id = p.product_id
                        WHERE p.feed_id = p_feed_id AND p.carrier_id = v_feed.carrier_id AND p.status = 'active'),
                      '[]'::jsonb),
    'products', COALESCE((SELECT jsonb_agg(jsonb_build_object('code', z.code, 'carrier_codes', z.cc) ORDER BY z.code)
                            FROM (SELECT pr.code,
                                         COALESCE((SELECT jsonb_agg(m.carrier_value ORDER BY m.carrier_value)
                                                     FROM public.cl_value_mappings m
                                                    WHERE m.account_id = v_feed.account_id AND m.carrier_id = v_feed.carrier_id
                                                      AND m.kind = 'product' AND m.onems_value = pr.code),
                                                  jsonb_build_array(pr.code)) AS cc
                                    FROM public.products pr
                                   WHERE pr.id IN (SELECT p.product_id FROM public.cl_plans p
                                                    WHERE p.feed_id = p_feed_id AND p.carrier_id = v_feed.carrier_id
                                                      AND p.status = 'active')) z), '[]'::jsonb),
    'points', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                  'place_ref', r.carrier_place_ref, 'mode_ref', r.carrier_mode_ref,
                                  'role', CASE r.e2e_role WHEN 'none' THEN 'intermediate' ELSE r.e2e_role END,
                                  'city_id', pc.city_id, 'city', ci.name)
                                ORDER BY r.carrier_place_ref, r.carrier_mode_ref NULLS FIRST)
                          FROM public.readers r
                          LEFT JOIN public.postal_centers pc ON pc.id = r.postal_center_id
                          LEFT JOIN public.cities ci ON ci.id = pc.city_id
                         WHERE r.account_id = v_feed.account_id AND r.capture_source = 'carrier_scan'
                           AND r.carrier_id = v_feed.carrier_id AND r.deleted_at IS NULL
                           AND r.is_active IS NOT FALSE), '[]'::jsonb),
    'next_period', public.cl_delivery_next_period(p_feed_id, p_now),
    'last_delivery', v_last,
    'formats', jsonb_build_object('format', jsonb_build_array('jsonl','csv'),
                                  'compression', jsonb_build_array('gzip','none')),
    'limits', public.cl_delivery_limits(v_feed.config));
END $$;

-- ================================================================ 10. bucket privado y politicas de Storage
-- El conector sube con una URL firmada que crea la Edge Function con service_role (no pasa por estas politicas).
-- Una persona con Edit en cl_connectors sube a mano SOLO al objeto de una entrega manual suya pending_upload
-- (la ruta la decide cl_manual_delivery_open). Leen el fichero quienes ven la entrega. Nadie lo cambia ni borra
-- desde la web: sin politicas UPDATE / DELETE (el borrado por retencion lo hace el proceso con la API de Storage).
CREATE OR REPLACE FUNCTION public.cl_delivery_can_upload(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.cl_deliveries d
     WHERE d.file_path = p_name AND d.status = 'pending_upload' AND d.source = 'manual'
       AND (public.is_superadmin()
            OR (d.account_id = public.current_user_account_id()
                AND public.has_any_access(d.account_id, 'edit', 'cl_connectors'))))
$$;

CREATE OR REPLACE FUNCTION public.cl_delivery_can_read(p_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path = public, extensions
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.cl_deliveries d
     WHERE d.file_path = p_name
       AND (public.is_superadmin()
            OR (d.account_id = public.current_user_account_id()
                AND public.has_any_access(d.account_id, 'view', 'cl_connectors', 'cl_monitor'))))
$$;

DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NOT NULL THEN
    INSERT INTO storage.buckets (id, name, public, file_size_limit)
    VALUES ('cl-deliveries', 'cl-deliveries', false, 524288000)
    ON CONFLICT (id) DO UPDATE SET public = false, file_size_limit = EXCLUDED.file_size_limit;
  END IF;
  IF to_regclass('storage.objects') IS NOT NULL THEN
    DROP POLICY IF EXISTS cl_deliveries_manual_upload ON storage.objects;
    CREATE POLICY cl_deliveries_manual_upload ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id = 'cl-deliveries' AND public.cl_delivery_can_upload(name));
    DROP POLICY IF EXISTS cl_deliveries_read ON storage.objects;
    CREATE POLICY cl_deliveries_read ON storage.objects FOR SELECT TO authenticated
      USING (bucket_id = 'cl-deliveries' AND public.cl_delivery_can_read(name));
  END IF;
END $$;

-- ================================================================ 11. grants de funciones
REVOKE ALL ON FUNCTION public.cl_delivery_limits(jsonb) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_account_date_tz(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_aligned_period(smallint[], date) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_next_period(uuid, timestamptz) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_summary(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_authorize_manual(uuid) FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_open_core(uuid, date, date, text, jsonb, text, text, text, uuid, timestamptz)
  FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.cl_delivery_complete_core(uuid, uuid, text) FROM PUBLIC, anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.cl_delivery_open(uuid, date, date, text, jsonb, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_delivery_complete(uuid, uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.cl_connector_config(uuid, timestamptz) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cl_delivery_open(uuid, date, date, text, jsonb, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.cl_delivery_complete(uuid, uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.cl_connector_config(uuid, timestamptz) TO service_role;

REVOKE ALL ON FUNCTION public.cl_manual_delivery_open(uuid, date, date, text, jsonb, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cl_manual_delivery_complete(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_manual_delivery_open(uuid, date, date, text, jsonb, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cl_manual_delivery_complete(uuid, uuid) TO authenticated;

-- Las politicas de storage.objects las evalua el rol del usuario.
REVOKE ALL ON FUNCTION public.cl_delivery_can_upload(text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.cl_delivery_can_read(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cl_delivery_can_upload(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cl_delivery_can_read(text) TO authenticated;
