-- Test: reserva de avisos (pending_panelist_notifications) y aviso inmediato fail-open.
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.fail_if(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

BEGIN;
\ir fixtures/incident_city.sql
DO $$
DECLARE v_acc uuid; v_pan uuid; n int;
BEGIN
  SELECT p.account_id, p.id INTO v_acc, v_pan FROM panelists p ORDER BY p.id LIMIT 1;
  UPDATE panelists SET telegram_id = '4004', status = 'active' WHERE id = v_pan;

  -- 1) inserta un aviso del responsable: el trigger no falla aunque no haya secretos en Vault
  INSERT INTO panelist_notification(account_id, panelist_id, kind, payload)
  VALUES (v_acc, v_pan, 'manager_notice', '{"body":"hola"}');
  -- recordatorio aplazado (no debe salir todavia) y uno ya vencido
  INSERT INTO panelist_notification(account_id, panelist_id, kind, payload, send_after)
  VALUES (v_acc, v_pan, 'receipt_reminder', '{"reason":"pobox_absent_no_visit","local_date":"x1"}', now() + interval '3 hours'),
         (v_acc, v_pan, 'receipt_reminder', '{"reason":"not_sent_cancelled","local_date":"x2"}', now() - interval '1 minute');

  SELECT count(*) INTO n FROM pending_panelist_notifications(50);
  PERFORM pg_temp.fail_if(n <> 2, 'primera ronda debe reservar 2 (aviso + recordatorio vencido), salio ' || n);

  -- 2) segunda ronda inmediata: nada (ya reservadas)
  SELECT count(*) INTO n FROM pending_panelist_notifications(50);
  PERFORM pg_temp.fail_if(n <> 0, 'segunda ronda debe reservar 0, salio ' || n);

  -- 3) reserva caducada (>10 min) vuelve a salir; enviadas no
  UPDATE panelist_notification SET claimed_at = now() - interval '11 minutes' WHERE kind = 'manager_notice';
  UPDATE panelist_notification SET status = 'sent' WHERE kind = 'receipt_reminder' AND send_after < now();
  SELECT count(*) INTO n FROM pending_panelist_notifications(50);
  PERFORM pg_temp.fail_if(n <> 1, 'reserva caducada debe volver a salir (1), salio ' || n);

  -- 4) la fila devuelta trae telegram y entregable
  UPDATE panelist_notification SET claimed_at = NULL WHERE kind = 'manager_notice';
  PERFORM pg_temp.fail_if(NOT EXISTS (SELECT 1 FROM pending_panelist_notifications(50) x
                                       WHERE x.kind = 'manager_notice' AND x.entregable AND x.telegram_id = '4004'),
                          'fila de aviso sin telegram/entregable');
END $$;
ROLLBACK;

-- 5) permisos
DO $$
BEGIN
  PERFORM pg_temp.fail_if(has_function_privilege('authenticated', 'public.pending_panelist_notifications(int)', 'EXECUTE'),
                          'authenticated no debe poder reservar avisos');
  PERFORM pg_temp.fail_if(NOT has_function_privilege('service_role', 'public.pending_panelist_notifications(int)', 'EXECUTE'),
                          'service_role debe poder reservar avisos');
END $$;

SELECT 'panelist_notice_push OK';
