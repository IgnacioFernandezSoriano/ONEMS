-- Borrar muestras por compensar desde la lista de Allocation Plans.
--
-- Decisión de Ignacio (18/11/2026): si el Allocation Plan Manager decide borrar algo, aunque sea una muestra
-- del registro de compensación (deferred_samples), debe poder hacerlo. Caso real: un producto que de momento
-- no se envía (Kenya, Express 6 h) seguía con muestras pendientes de compensar.
--
-- La tabla sigue sin permiso directo de escritura para los usuarios: se borra solo con esta función, que
-- únicamente toca anotaciones 'pending' de la cuenta del usuario (o de cualquiera si es superadmin), las
-- mismas que la lista enseña. Las 'reintroduced' son historial y no se tocan. Devuelve cuántas borró.

CREATE OR REPLACE FUNCTION public.delete_deferred_samples(p_ids uuid[])
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_n integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'No autenticado';
  END IF;
  DELETE FROM public.deferred_samples d
   WHERE d.id = ANY (p_ids)
     AND d.status = 'pending'
     AND (d.account_id = public.current_user_account_id() OR public.is_superadmin());
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END $$;

REVOKE ALL ON FUNCTION public.delete_deferred_samples(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_deferred_samples(uuid[]) TO authenticated;

COMMENT ON FUNCTION public.delete_deferred_samples(uuid[]) IS
  'Borra muestras por compensar (deferred_samples pending) de la cuenta del usuario; las usa la lista de Allocation Plans.';
