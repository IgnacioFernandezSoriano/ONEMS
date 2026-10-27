-- Lectura de la politica de balanceo de una cuenta (complemento de rpc_set_account_balance_policy).
--
-- Problema: la politica de cuenta vive en account_config y su SELECT (RLS) solo deja ver la fila a quien tiene
-- cuenta propia (current_user_account_id() / profiles.account_id). Un superadmin no tiene account_id, asi que
-- la escritura por RPC funcionaba pero al releerla la pantalla veia "sin fila" y mostraba los valores por
-- defecto (la casilla POBOX parecia no marcarse). Esta funcion devuelve la politica de la cuenta con el mismo
-- guard que las demas RPC de politicas.

CREATE OR REPLACE FUNCTION public.rpc_get_account_balance_policy(p_account_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_date_policy text;
  v_pobox boolean;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_superadmin()
     AND p_account_id IS DISTINCT FROM (SELECT p.account_id FROM public.profiles p WHERE p.id = auth.uid()) THEN
    RAISE EXCEPTION 'No autorizado para esta cuenta' USING ERRCODE = '42501';
  END IF;

  SELECT ac.date_policy, ac.pobox_enabled INTO v_date_policy, v_pobox
    FROM public.account_config ac WHERE ac.account_id = p_account_id;

  -- Sin fila en account_config se aplican los valores por defecto de las columnas.
  RETURN jsonb_build_object('date_policy', COALESCE(v_date_policy, 'daily'),
                            'pobox_enabled', COALESCE(v_pobox, false));
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_get_account_balance_policy(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_account_balance_policy(uuid) TO authenticated, service_role;
