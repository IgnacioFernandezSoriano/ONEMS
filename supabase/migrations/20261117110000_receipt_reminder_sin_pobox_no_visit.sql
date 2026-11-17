-- 2026-11-17: el aviso posterior 'pobox_absent_no_visit' repetia al mismo panelista lo que ya le dice el bot
-- al registrar la recepcion (revision de mensajes con Ignacio). Se deja de encolar; el caso se sigue registrando
-- igual y el gestor lo ve en ONEMS. Los demas avisos (ok_typo_fixed, not_sent_cancelled, wrong_city_cancelled)
-- no cambian.
CREATE OR REPLACE FUNCTION public.enqueue_receipt_reminder(p_case_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c public.receipt_case%ROWTYPE;
  v_tz text;
  v_n int;
  v_id uuid;
BEGIN
  SELECT * INTO c FROM public.receipt_case WHERE id = p_case_id;
  IF NOT FOUND OR c.culprit_panelist_id IS NULL
     OR c.reason NOT IN ('ok_typo_fixed', 'not_sent_cancelled', 'wrong_city_cancelled')
     OR c.status NOT IN ('fixed', 'compensated') THEN
    RETURN NULL;
  END IF;

  SELECT a.timezone INTO v_tz FROM public.accounts a WHERE a.id = c.account_id;
  v_tz := COALESCE(v_tz, 'UTC');

  SELECT count(*) INTO v_n
    FROM public.receipt_case rc
   WHERE rc.culprit_panelist_id = c.culprit_panelist_id
     AND rc.reason = c.reason
     AND (rc.first_attempt_at >= now() - interval '7 days' OR rc.id = c.id);

  INSERT INTO public.panelist_notification (account_id, panelist_id, kind, payload, send_after, case_id)
  VALUES (c.account_id, c.culprit_panelist_id, 'receipt_reminder',
          jsonb_build_object('reason', c.reason,
                             'tag', COALESCE(c.tag_norm, c.tag_raw),
                             'local_date', ((now() AT TIME ZONE v_tz)::date)::text,
                             'escalated', v_n >= 3,
                             'case_id', c.id),
          public.receipt_send_after(c.account_id, now()),
          c.id)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;
