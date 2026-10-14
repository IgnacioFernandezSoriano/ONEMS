-- RPC de solo lectura: candidatos de reencaminado para una muestra y un rol.
-- Devuelve los nodos de la misma ciudad que el nodo actual del rol (distintos de él,
-- activos), con is_available evaluado en la fecha de la muestra. NO filtra los no
-- disponibles: la UI los muestra deshabilitados. No muta nada.
CREATE OR REPLACE FUNCTION public.list_reroute_candidates(p_detail_id uuid, p_role text)
RETURNS TABLE(node_id uuid, node_name text, city_id uuid, is_available boolean)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id uuid;
  v_current_node uuid;
  v_city_id uuid;
  v_date date;
  v_actor uuid := auth.uid();
  v_actor_account uuid;
BEGIN
  IF p_role NOT IN ('origin','destination') THEN
    RAISE EXCEPTION 'Invalid role %, expected origin or destination', p_role;
  END IF;

  SELECT apd.account_id,
         CASE WHEN p_role = 'origin' THEN apd.origin_node_id ELSE apd.destination_node_id END,
         apd.fecha_programada
    INTO v_account_id, v_current_node, v_date
  FROM allocation_plan_details apd
  WHERE apd.id = p_detail_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Detail % not found', p_detail_id; END IF;

  -- Guarda multi-tenant: usuario autenticado solo su cuenta; superadmin / service-role (NULL) pasan.
  IF v_actor IS NOT NULL AND NOT is_superadmin() THEN
    SELECT account_id INTO v_actor_account FROM profiles WHERE id = v_actor;
    IF v_actor_account IS DISTINCT FROM v_account_id THEN
      RAISE EXCEPTION 'Cross-tenant access denied';
    END IF;
  END IF;

  SELECT n.city_id INTO v_city_id FROM nodes n WHERE n.id = v_current_node;

  RETURN QUERY
  SELECT n.id, n.auto_id::text, n.city_id, is_node_available(n.id, v_date)
  FROM nodes n
  WHERE n.city_id = v_city_id
    AND n.id <> v_current_node
    AND n.status = 'active'
  ORDER BY n.auto_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.list_reroute_candidates(uuid, text) TO authenticated;
