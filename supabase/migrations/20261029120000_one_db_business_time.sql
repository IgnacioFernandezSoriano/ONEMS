-- Business time del E2E: horas y dias laborables en la HORA LOCAL de la cuenta.
--
-- Hasta ahora los dias laborables se contaban sobre el instante en UTC, de modo que un envio de Kenya
-- (UTC+3) registrado a las 23:30 UTC ya caia en "el dia siguiente" cuando en Nairobi seguia siendo el mismo
-- dia. Esta migracion se construye por secciones.
-- Seccion 1:
--   * calculate_business_hours(inicio, fin, cuenta): horas laborables entre dos instantes, repartidas por
--     dia local; solo suman los dias laborables de la cuenta (is_account_working_day: weekly_schedule +
--     non_working_days; sin cuenta => lunes-viernes). Redondeo a 2 decimales; 0 si fin < inicio; NULL si
--     alguna entrada es NULL.
--   * calculate_business_days (misma firma que antes): cuenta los dias laborables locales d con
--     fecha_local(inicio) <= d < fecha_local(fin); 0 si fin < inicio.
--   * Zona = accounts.timezone de la cuenta; sin cuenta => 'UTC'.

CREATE OR REPLACE FUNCTION public.calculate_business_hours(
  p_start timestamptz, p_end timestamptz, p_account_id uuid)
RETURNS numeric
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE
  v_tz    text;
  v_ini   timestamp;
  v_fin   timestamp;
  v_d     timestamp;
  v_total numeric := 0;
BEGIN
  IF p_start IS NULL OR p_end IS NULL THEN RETURN NULL; END IF;
  IF p_end < p_start THEN RETURN 0; END IF;

  v_tz  := COALESCE((SELECT timezone FROM accounts WHERE id = p_account_id), 'UTC');
  v_ini := p_start AT TIME ZONE v_tz;
  v_fin := p_end   AT TIME ZONE v_tz;

  FOR v_d IN SELECT generate_series(date_trunc('day', v_ini), date_trunc('day', v_fin), interval '1 day') LOOP
    IF (p_account_id IS NOT NULL AND is_account_working_day(p_account_id, v_d::date))
       OR (p_account_id IS NULL AND extract(isodow FROM v_d) <= 5) THEN
      v_total := v_total + GREATEST(0,
        extract(epoch FROM (LEAST(v_fin, v_d + interval '1 day') - GREATEST(v_ini, v_d))) / 3600.0);
    END IF;
  END LOOP;

  RETURN ROUND(v_total, 2);
END $$;

CREATE OR REPLACE FUNCTION public.calculate_business_days(
  p_start_date timestamptz, p_end_date timestamptz, p_account_id uuid DEFAULT NULL::uuid)
RETURNS integer
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE
  v_tz    text;
  v_ini   date;
  v_fin   date;
  v_d     date;
  v_count integer := 0;
BEGIN
  IF p_start_date IS NULL OR p_end_date IS NULL THEN RETURN NULL; END IF;
  IF p_end_date < p_start_date THEN RETURN 0; END IF;

  v_tz  := COALESCE((SELECT timezone FROM accounts WHERE id = p_account_id), 'UTC');
  v_ini := (p_start_date AT TIME ZONE v_tz)::date;
  v_fin := (p_end_date   AT TIME ZONE v_tz)::date;

  FOR v_d IN SELECT d::date FROM generate_series(v_ini, v_fin - 1, interval '1 day') d LOOP
    IF (p_account_id IS NOT NULL AND is_account_working_day(p_account_id, v_d))
       OR (p_account_id IS NULL AND extract(isodow FROM v_d) <= 5) THEN
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END $$;
