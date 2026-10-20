-- Incidencias de indisponibilidad: puerta de entrada para n8n / integraciones y aviso "recibido" de altas web.
--   (1) tg_enqueue_unavailability_received: AFTER INSERT en panelist_unavailability. Solo altas desde la web
--       (auth.uid() NOT NULL) y activas -> aviso 'unavailability_received' al panelista. Best-effort, acotado por
--       cuenta, respeta onems.suppress_notifications. Las altas por n8n (service role, auth.uid() NULL) no
--       encolan: n8n contesta en linea con el resultado de declare_panelist_unavailability.
--   (2) declare_panelist_unavailability: valida, detecta solape (devuelve el error en vez de lanzar) e inserta;
--       el trigger de la baja ejecuta el motor en la misma sentencia. Solo service_role.

-- (1)
CREATE OR REPLACE FUNCTION public.tg_enqueue_unavailability_received()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  BEGIN
    IF auth.uid() IS NOT NULL AND NEW.status = 'active'
       AND COALESCE(current_setting('onems.suppress_notifications', true), '') <> 'on' THEN
      INSERT INTO panelist_notification (account_id, panelist_id, kind, payload)
      SELECT NEW.account_id, p.id, 'unavailability_received',
             jsonb_build_object('unavailability_id', NEW.id, 'start_date', NEW.start_date, 'end_date', NEW.end_date)
        FROM panelists p
       WHERE p.id = NEW.panelist_id AND p.account_id = NEW.account_id;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'tg_enqueue_unavailability_received: aviso omitido para la baja %: %', NEW.id, SQLERRM;
  END;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS enqueue_unavailability_received_trigger ON public.panelist_unavailability;
CREATE TRIGGER enqueue_unavailability_received_trigger
  AFTER INSERT ON public.panelist_unavailability
  FOR EACH ROW EXECUTE FUNCTION public.tg_enqueue_unavailability_received();

-- (2)
-- Errores, en este orden: panelist_not_found (no existe O no esta 'active'), no_date, bad_reason,
-- end_before_start, in_past (start < hoy local del panelista), too_long (> 90 dias, ambos extremos incluidos),
-- overlap (+ ov_start / ov_end de la baja activa que solapa). Nunca lanza por validacion.
CREATE OR REPLACE FUNCTION public.declare_panelist_unavailability(
  p_panelist_id uuid,
  p_start_date date,
  p_end_date date,
  p_reason text DEFAULT 'other',
  p_notes text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pan record;
  v_today date;
  v_ov record;
  v_id uuid;
  v_inc text;
  v_affected integer;
  v_pending integer;
BEGIN
  SELECT p.id, p.account_id, p.status INTO v_pan FROM panelists p WHERE p.id = p_panelist_id;
  -- Guarda: un panelista que no esta activo no puede declarar bajas (se trata como no encontrado).
  IF NOT FOUND OR v_pan.status IS DISTINCT FROM 'active' THEN
    RETURN jsonb_build_object('ok', false, 'error_code', 'panelist_not_found');
  END IF;
  IF p_start_date IS NULL OR p_end_date IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error_code', 'no_date');
  END IF;
  IF p_reason IS NULL OR p_reason NOT IN ('vacation','sick_leave','personal','training','other','materials') THEN
    RETURN jsonb_build_object('ok', false, 'error_code', 'bad_reason');
  END IF;
  IF p_end_date < p_start_date THEN
    RETURN jsonb_build_object('ok', false, 'error_code', 'end_before_start');
  END IF;
  v_today := panelist_local_today(p_panelist_id);
  IF p_start_date < v_today THEN
    RETURN jsonb_build_object('ok', false, 'error_code', 'in_past');
  END IF;
  IF p_end_date - p_start_date + 1 > 90 THEN
    RETURN jsonb_build_object('ok', false, 'error_code', 'too_long');
  END IF;

  SELECT u.start_date, u.end_date INTO v_ov
    FROM panelist_unavailability u
   WHERE u.panelist_id = p_panelist_id AND u.status = 'active'
     AND u.start_date <= p_end_date AND u.end_date >= p_start_date
   ORDER BY u.start_date, u.id
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error_code', 'overlap',
                              'ov_start', v_ov.start_date, 'ov_end', v_ov.end_date);
  END IF;

  INSERT INTO panelist_unavailability (account_id, panelist_id, start_date, end_date, reason, notes, status)
  VALUES (v_pan.account_id, p_panelist_id, p_start_date, p_end_date, p_reason, p_notes, 'active')
  RETURNING id INTO v_id;

  -- El trigger AFTER INSERT ya ejecuto el motor en esta misma sentencia.
  SELECT u.incident_status INTO v_inc FROM panelist_unavailability u WHERE u.id = v_id;
  SELECT count(*) FILTER (WHERE pr.status <> 'info'), count(*) FILTER (WHERE pr.status = 'pending')
    INTO v_affected, v_pending
    FROM panelist_reassignment_proposal pr WHERE pr.unavailability_id = v_id;

  RETURN jsonb_build_object('ok', true, 'unavailability_id', v_id,
                            'start_date', p_start_date, 'end_date', p_end_date,
                            'days', p_end_date - p_start_date + 1,
                            'affected_samples', v_affected, 'pending_samples', v_pending,
                            'incident_status', v_inc);
END;
$$;

REVOKE ALL ON FUNCTION public.declare_panelist_unavailability(uuid, date, date, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.declare_panelist_unavailability(uuid, date, date, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.tg_enqueue_unavailability_received() FROM PUBLIC, anon, authenticated;
