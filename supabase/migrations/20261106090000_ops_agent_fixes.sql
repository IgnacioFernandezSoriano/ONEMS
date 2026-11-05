-- ============================================================
-- Agente de operaciones, fase 3: reparaciones de datos autorizadas (R1-R3) — 2026-11-06
-- ============================================================
-- Requiere 20261105160000_ops_agent_test_fixtures.sql (token del agente, ops_test._check) y
-- 20261105200000_ops_operational_checks.sql (ops_test_checks, que aqui se amplia).
--
-- Lista cerrada de reparaciones que el agente puede aplicar tras autorizacion del responsable por Telegram.
-- Cada una es una funcion SECURITY DEFINER protegida con el token del agente (como ops_test_*), solo actua
-- sobre la cuenta/panelista/ciudad que resuelve de sus argumentos, guarda copia de lo que toca en
-- ops_fix.log y (salvo R1) tiene su deshacer, que solo deshace lo que sigue como lo dejo.
--   R1 desatascar conversacion: borra panelist_context del telegram del panelista. Sin deshacer.
--   R2 asignar nodo: panelists.node_id del unico nodo activo de su ciudad y cuenta (y solo si ese nodo no
--      tiene ya un panelista activo: idx_panelists_node_unique lo impide).
--   R3 rellenar dias sin envio de una ciudad POBOX: rpc_balance_city_v2(ciudad, hoy, fin_del_plan, true, hoy),
--      con copia completa de las filas que escribe el balanceo (allocation_plan_details pendientes de la
--      ciudad, deferred_samples de la ciudad y la fila de cities).
-- ops_test_checks anade panelist_no_node y stuck_context (avisos que llevan a R2 y R1).
-- Cada *_apply recibe p_expected (lo que el responsable vio en la vista previa: R1 {"contexts": [...]},
-- R2 {"node": "N-7"}, R3 {"moves": [...]}), lo vuelve a calcular dentro de la misma transaccion y, si no
-- coincide, falla con 'ops_fix: ha cambiado desde la propuesta' sin cambiar nada.
-- Cuentas por accounts.name; panelistas por panelists.panelist_code (la tabla no tiene auto_id). Si un nombre
-- o codigo no identifica exactamente una fila, no se hace nada.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS ops_fix;
REVOKE ALL ON SCHEMA ops_fix FROM PUBLIC, anon, authenticated;

CREATE TABLE IF NOT EXISTS ops_fix.log (
  id bigserial PRIMARY KEY,
  kind text NOT NULL CHECK (kind IN ('r1', 'r2', 'r3')),
  account_id uuid NOT NULL,
  target text NOT NULL,
  before jsonb,
  after jsonb,
  applied_at timestamptz NOT NULL DEFAULT now(),
  undone_at timestamptz
);
REVOKE ALL ON ALL TABLES IN SCHEMA ops_fix FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA ops_fix FROM PUBLIC, anon, authenticated;

-- ---------- internas ----------
CREATE OR REPLACE FUNCTION ops_fix._account(p_name text)
RETURNS uuid LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_ids uuid[];
BEGIN
  v_ids := ARRAY(SELECT a.id FROM public.accounts a WHERE a.name = p_name);
  IF cardinality(v_ids) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: la cuenta "%" no existe o no es unica', p_name;
  END IF;
  RETURN v_ids[1];
END $$;

CREATE OR REPLACE FUNCTION ops_fix._panelist(p_code text)
RETURNS public.panelists LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_n int; v_p public.panelists;
BEGIN
  SELECT count(*) INTO v_n FROM public.panelists p WHERE p.panelist_code = p_code;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ops_fix: el panelista "%" no existe o el codigo esta en mas de una cuenta', p_code;
  END IF;
  SELECT * INTO v_p FROM public.panelists p WHERE p.panelist_code = p_code;
  RETURN v_p;
END $$;

-- Nodos POBOX sin envio el proximo dia laborable (la lista pobox_no_send de ops_test_checks, sin cambios).
CREATE OR REPLACE FUNCTION ops_fix._pobox_no_send()
RETURNS TABLE (account_id uuid, account text, city_id uuid, city text, node text, day date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH acc AS (
    SELECT a.id, a.name,
           (SELECT g::date FROM generate_series((now() AT TIME ZONE COALESCE(a.timezone, 'UTC'))::date + 1,
                                               (now() AT TIME ZONE COALESCE(a.timezone, 'UTC'))::date + 14,
                                               interval '1 day') g
             WHERE public.is_account_working_day(a.id, g::date) ORDER BY g LIMIT 1) AS d
      FROM public.accounts a),
  nod AS (
    SELECT acc.id AS account_id, acc.name AS account, c.id AS city_id, c.name AS city, n.auto_id AS node,
           n.id AS node_id, acc.d
      FROM public.nodes n
      JOIN public.cities c ON c.id = n.city_id
      JOIN acc ON acc.id = n.account_id
     WHERE n.status = 'active' AND acc.d IS NOT NULL
       AND COALESCE((SELECT e.pobox_enabled FROM public.effective_city_policy(c.id) e), false)
       AND (SELECT count(*) FROM public.nodes n2 WHERE n2.city_id = c.id AND n2.status = 'active') = 1
       AND EXISTS (SELECT 1 FROM public.panelists p WHERE p.node_id = n.id AND p.status = 'active'
                     AND NOT EXISTS (SELECT 1 FROM public.panelist_unavailability u
                                      WHERE u.panelist_id = p.id AND u.status = 'active'
                                        AND acc.d BETWEEN u.start_date AND u.end_date)))
  SELECT nod.account_id, nod.account, nod.city_id, nod.city, nod.node, nod.d
    FROM nod
   WHERE NOT EXISTS (SELECT 1 FROM public.allocation_plan_details x
                      WHERE x.origin_node_id = nod.node_id AND x.fecha_programada = nod.d AND x.status <> 'cancelled');
$$;

-- Restaurar una fila completa desde su copia jsonb (to_jsonb), por id. Modo update | insert | delete.
CREATE OR REPLACE FUNCTION ops_fix._put(p_tbl regclass, p_row jsonb, p_mode text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_cols text; v_rcols text;
BEGIN
  SELECT string_agg(quote_ident(a.attname), ', ' ORDER BY a.attnum),
         string_agg('r.' || quote_ident(a.attname), ', ' ORDER BY a.attnum)
    INTO v_cols, v_rcols
    FROM pg_catalog.pg_attribute a
   WHERE a.attrelid = p_tbl AND a.attnum > 0 AND NOT a.attisdropped AND a.attgenerated = '' AND a.attidentity <> 'a';
  IF p_mode = 'update' THEN
    EXECUTE format('UPDATE %s t SET (%s) = (SELECT %s FROM pg_catalog.jsonb_populate_record(NULL::%s, $1) r) '
                   'WHERE t.id = ($1->>''id'')::uuid', p_tbl, v_cols, v_rcols, p_tbl) USING p_row;
  ELSIF p_mode = 'insert' THEN
    EXECUTE format('INSERT INTO %s (%s) SELECT %s FROM pg_catalog.jsonb_populate_record(NULL::%s, $1) r',
                   p_tbl, v_cols, v_rcols, p_tbl) USING p_row;
  ELSIF p_mode = 'delete' THEN
    EXECUTE format('DELETE FROM %s t WHERE t.id = ($1->>''id'')::uuid', p_tbl) USING p_row;
  ELSE
    RAISE EXCEPTION 'ops_fix: modo % desconocido', p_mode;
  END IF;
END $$;

-- R3: el envio tiene filas enlazadas (incidencias, material, lecturas, recepciones, propuestas de reasignacion).
-- Borrarlo las borraria en cascada o las dejaria huerfanas; el deshacer no lo toca (como el balanceo, que no
-- aparta al registro envios con incidencias, material o lecturas).
CREATE OR REPLACE FUNCTION ops_fix._apd_has_links(p_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT EXISTS (SELECT 1 FROM public.material_hold m WHERE m.allocation_plan_detail_id = p_id)
      OR EXISTS (SELECT 1 FROM public.shipment_incident si WHERE si.parcel_id = p_id)
      OR EXISTS (SELECT 1 FROM public.panelist_reassignment_proposal rp WHERE rp.allocation_plan_detail_id = p_id)
      OR EXISTS (SELECT 1 FROM public.panelist_incident pi WHERE pi.allocation_plan_detail_id = p_id)
      OR EXISTS (SELECT 1 FROM public.one_db o WHERE o.allocation_detail_id = p_id)
      OR EXISTS (SELECT 1 FROM public.receipt_case rc WHERE rc.detail_id = p_id);
$$;

-- R3: ciudad (de la cuenta), "hoy" local de la cuenta y fin del plan. Solo si hoy sale en pobox_no_send.
-- fin_del_plan = el mayor allocation_plans.end_date de los planes con envios pendientes de la ciudad que
-- aun no han terminado.
CREATE OR REPLACE FUNCTION ops_fix._r3_target(p_account text, p_city text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_acc uuid; v_ids uuid[]; v_city uuid; v_name text; v_today date; v_end date;
BEGIN
  v_acc := ops_fix._account(p_account);
  v_ids := ARRAY(SELECT c.id FROM public.cities c WHERE c.account_id = v_acc AND btrim(c.name) = btrim(p_city));
  IF cardinality(v_ids) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: la ciudad "%" no existe en la cuenta "%" o no es unica', p_city, p_account;
  END IF;
  v_city := v_ids[1];
  SELECT btrim(c.name) INTO v_name FROM public.cities c WHERE c.id = v_city;
  SELECT (now() AT TIME ZONE COALESCE(a.timezone, 'UTC'))::date INTO v_today FROM public.accounts a WHERE a.id = v_acc;
  IF NOT EXISTS (SELECT 1 FROM ops_fix._pobox_no_send() x WHERE x.city_id = v_city AND x.account_id = v_acc) THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (la ciudad % no sale hoy en pobox_no_send)', v_name;
  END IF;
  SELECT max(pl.end_date) INTO v_end
    FROM public.allocation_plan_details a
    JOIN public.nodes n ON n.id = a.origin_node_id AND n.city_id = v_city AND n.account_id = v_acc
    JOIN public.allocation_plans pl ON pl.id = a.plan_id AND pl.account_id = v_acc
   WHERE a.account_id = v_acc AND a.status = 'pending' AND pl.end_date >= v_today;
  IF v_end IS NULL THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (la ciudad % no tiene envios pendientes en un plan en curso)', v_name;
  END IF;
  RETURN jsonb_build_object('account_id', v_acc, 'city_id', v_city, 'city', v_name, 'today', v_today, 'plan_end', v_end);
END $$;

-- R3: copia completa (to_jsonb) de todo lo que puede escribir el balanceo en la ciudad. Con p_prev (la copia
-- de antes) incluye tambien esas mismas filas aunque ya no esten pendientes o hayan desaparecido.
CREATE OR REPLACE FUNCTION ops_fix._r3_snapshot(p_account uuid, p_city uuid, p_prev jsonb DEFAULT NULL)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT jsonb_build_object(
    'apd', COALESCE((SELECT jsonb_object_agg(a.id::text, to_jsonb(a.*)) FROM public.allocation_plan_details a
                      WHERE a.account_id = p_account
                        AND ((a.status = 'pending'
                              AND a.origin_node_id IN (SELECT n.id FROM public.nodes n
                                                        WHERE n.city_id = p_city AND n.account_id = p_account))
                             OR COALESCE(p_prev->'apd' ? a.id::text, false))), '{}'::jsonb),
    'ds', COALESCE((SELECT jsonb_object_agg(d.id::text, to_jsonb(d.*)) FROM public.deferred_samples d
                     WHERE d.account_id = p_account AND d.origin_city_id = p_city
                       AND (d.status = 'pending' OR COALESCE(p_prev->'ds' ? d.id::text, false))), '{}'::jsonb),
    'city', (SELECT to_jsonb(c.*) FROM public.cities c WHERE c.id = p_city AND c.account_id = p_account));
$$;

-- R3: envios que cambian entre dos copias (antes -> despues).
CREATE OR REPLACE FUNCTION ops_fix._r3_moves(p_before jsonb, p_after jsonb)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  WITH k AS (SELECT jsonb_object_keys(p_before->'apd') AS id UNION SELECT jsonb_object_keys(p_after->'apd')),
  ch AS (SELECT k.id, p_before->'apd'->k.id AS b, p_after->'apd'->k.id AS a FROM k
          WHERE (p_before->'apd'->k.id) IS DISTINCT FROM (p_after->'apd'->k.id))
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
           'id', ch.id,
           'tag_id', COALESCE(ch.a->>'tag_id', ch.b->>'tag_id'),
           'from', ch.b->>'fecha_programada',
           'to', ch.a->>'fecha_programada',
           'from_node', (SELECT n.auto_id FROM public.nodes n WHERE n.id = (ch.b->>'origin_node_id')::uuid),
           'to_node', (SELECT n.auto_id FROM public.nodes n WHERE n.id = (ch.a->>'origin_node_id')::uuid),
           'kind', CASE WHEN ch.b IS NULL THEN 'created'
                        WHEN ch.a IS NULL THEN 'to_registry'
                        WHEN ch.a->>'fecha_programada' IS DISTINCT FROM ch.b->>'fecha_programada'
                          OR ch.a->>'origin_node_id' IS DISTINCT FROM ch.b->>'origin_node_id' THEN 'moved'
                        ELSE 'changed' END)
         ORDER BY COALESCE(ch.a->>'fecha_programada', ch.b->>'fecha_programada'), ch.id), '[]'::jsonb)
    FROM ch;
$$;

-- R3: forma comparable de una lista de movimientos (la de la vista previa y la de apply): cada envio con su
-- id, de que dia sale y a que dia va, en orden fijo. Un envio que crea el balanceo tiene un id nuevo en cada
-- calculo, asi que de esos solo cuentan los dias.
CREATE OR REPLACE FUNCTION ops_fix._r3_key(p_moves jsonb)
RETURNS jsonb LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT COALESCE(jsonb_agg(o ORDER BY o::text), '[]'::jsonb)
    FROM (SELECT jsonb_build_object('id', CASE WHEN m->>'kind' = 'created' THEN NULL ELSE m->>'id' END,
                                    'from', m->>'from', 'to', m->>'to') AS o
            FROM jsonb_array_elements(COALESCE(p_moves, '[]'::jsonb)) m) s;
$$;

-- ---------- R1: desatascar la conversacion de un panelista ----------
CREATE OR REPLACE FUNCTION ops_fix._r1_panelist(p_code text)
RETURNS public.panelists LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_p public.panelists;
BEGIN
  v_p := ops_fix._panelist(p_code);
  IF v_p.telegram_id IS NULL OR btrim(v_p.telegram_id) = '' THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (el panelista % no tiene telegram)', p_code;
  END IF;
  -- panelist_context no lleva cuenta: si otro panelista usa el mismo telegram, borrar le afectaria.
  IF EXISTS (SELECT 1 FROM public.panelists p WHERE p.telegram_id = v_p.telegram_id AND p.id <> v_p.id) THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (el telegram de % lo usa tambien otro panelista)', p_code;
  END IF;
  RETURN v_p;
END $$;

-- Lo que ensena la vista previa de R1 (y lo que apply compara con p_expected->'contexts').
CREATE OR REPLACE FUNCTION ops_fix._r1_contexts(p_telegram_id text)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = '' AS $$
  SELECT COALESCE((SELECT jsonb_agg(jsonb_build_object('context_type', x.context_type, 'created_at', x.created_at)
                                    ORDER BY x.created_at, x.id)
                     FROM public.panelist_context x WHERE x.telegram_id = p_telegram_id), '[]'::jsonb);
$$;

CREATE OR REPLACE FUNCTION public.ops_fix_r1_preview(p_token text, p_panelist_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_p public.panelists;
BEGIN
  PERFORM ops_test._check(p_token);
  v_p := ops_fix._r1_panelist(p_panelist_code);
  RETURN jsonb_build_object(
    'panelist', v_p.panelist_code,
    'account', (SELECT a.name FROM public.accounts a WHERE a.id = v_p.account_id),
    'contexts', ops_fix._r1_contexts(v_p.telegram_id));
END $$;

CREATE OR REPLACE FUNCTION public.ops_fix_r1_apply(p_token text, p_panelist_code text, p_expected jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_p public.panelists; v_before jsonb; v_n int; v_log bigint;
BEGIN
  PERFORM ops_test._check(p_token);
  v_p := ops_fix._r1_panelist(p_panelist_code);
  PERFORM 1 FROM public.panelist_context x WHERE x.telegram_id = v_p.telegram_id FOR UPDATE;
  IF ops_fix._r1_contexts(v_p.telegram_id) IS DISTINCT FROM p_expected->'contexts' THEN
    RAISE EXCEPTION 'ops_fix: ha cambiado desde la propuesta';
  END IF;
  SELECT COALESCE(jsonb_agg(to_jsonb(x.*) ORDER BY x.id), '[]'::jsonb) INTO v_before
    FROM public.panelist_context x WHERE x.telegram_id = v_p.telegram_id;
  DELETE FROM public.panelist_context x WHERE x.telegram_id = v_p.telegram_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  INSERT INTO ops_fix.log (kind, account_id, target, before, after)
  VALUES ('r1', v_p.account_id, v_p.panelist_code, v_before, '[]'::jsonb)
  RETURNING id INTO v_log;
  RETURN jsonb_build_object('log_id', v_log, 'deleted', v_n);
END $$;

-- ---------- R2: asignar nodo a un panelista sin nodo ----------
CREATE OR REPLACE FUNCTION ops_fix._r2_check(p_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_p public.panelists; v_city text; v_nodes uuid[];
BEGIN
  v_p := ops_fix._panelist(p_code);
  IF v_p.status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (el panelista % no esta activo)', p_code;
  END IF;
  IF v_p.node_id IS NOT NULL THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (el panelista % ya tiene nodo)', p_code;
  END IF;
  SELECT btrim(c.name) INTO v_city FROM public.cities c WHERE c.id = v_p.city_id AND c.account_id = v_p.account_id;
  IF v_city IS NULL THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (el panelista % no tiene ciudad de su cuenta)', p_code;
  END IF;
  v_nodes := ARRAY(SELECT n.id FROM public.nodes n
                    WHERE n.city_id = v_p.city_id AND n.account_id = v_p.account_id AND n.status = 'active');
  IF cardinality(v_nodes) <> 1 THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (la ciudad % tiene % nodos activos)', v_city, cardinality(v_nodes);
  END IF;
  -- Un nodo solo puede tener un panelista activo (indice idx_panelists_node_unique).
  IF EXISTS (SELECT 1 FROM public.panelists p WHERE p.node_id = v_nodes[1] AND p.status = 'active') THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (el nodo de % ya tiene un panelista activo)', v_city;
  END IF;
  RETURN jsonb_build_object(
    'panelist_id', v_p.id, 'account_id', v_p.account_id, 'node_id', v_nodes[1],
    'panelist', v_p.panelist_code,
    'account', (SELECT a.name FROM public.accounts a WHERE a.id = v_p.account_id),
    'city', v_city,
    'node', (SELECT n.auto_id FROM public.nodes n WHERE n.id = v_nodes[1]));
END $$;

CREATE OR REPLACE FUNCTION public.ops_fix_r2_preview(p_token text, p_panelist_code text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v jsonb;
BEGIN
  PERFORM ops_test._check(p_token);
  v := ops_fix._r2_check(p_panelist_code);
  RETURN jsonb_build_object('panelist', v->'panelist', 'account', v->'account', 'city', v->'city', 'node', v->'node');
END $$;

CREATE OR REPLACE FUNCTION public.ops_fix_r2_apply(p_token text, p_panelist_code text, p_expected jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE v jsonb; v_n int; v_log bigint;
BEGIN
  PERFORM ops_test._check(p_token);
  PERFORM 1 FROM public.panelists p WHERE p.panelist_code = p_panelist_code FOR UPDATE;
  v := ops_fix._r2_check(p_panelist_code);
  IF (v->>'node') IS DISTINCT FROM (p_expected->>'node') THEN
    RAISE EXCEPTION 'ops_fix: ha cambiado desde la propuesta';
  END IF;
  UPDATE public.panelists p SET node_id = (v->>'node_id')::uuid, updated_at = now()
   WHERE p.id = (v->>'panelist_id')::uuid AND p.account_id = (v->>'account_id')::uuid AND p.node_id IS NULL;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'ops_fix: el panelista % cambio mientras se aplicaba; no toco nada', p_panelist_code;
  END IF;
  INSERT INTO ops_fix.log (kind, account_id, target, before, after)
  VALUES ('r2', (v->>'account_id')::uuid, v->>'panelist',
          jsonb_build_object('panelist_id', v->'panelist_id', 'node_id', NULL),
          jsonb_build_object('panelist_id', v->'panelist_id', 'node_id', v->'node_id', 'node', v->'node'))
  RETURNING id INTO v_log;
  RETURN jsonb_build_object('log_id', v_log, 'node', v->'node');
END $$;

CREATE OR REPLACE FUNCTION public.ops_fix_r2_undo(p_token text, p_log_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE l ops_fix.log; v_n int;
BEGIN
  PERFORM ops_test._check(p_token);
  SELECT * INTO l FROM ops_fix.log x WHERE x.id = p_log_id FOR UPDATE;
  IF NOT FOUND OR l.kind <> 'r2' THEN
    RAISE EXCEPTION 'ops_fix: el registro % no es un arreglo R2', p_log_id;
  END IF;
  IF l.undone_at IS NOT NULL THEN
    RAISE EXCEPTION 'ops_fix: el arreglo % ya se deshizo', p_log_id;
  END IF;
  -- Solo si el nodo sigue siendo el que puso R2.
  UPDATE public.panelists p SET node_id = NULL, updated_at = now()
   WHERE p.id = (l.after->>'panelist_id')::uuid AND p.account_id = l.account_id
     AND p.node_id = (l.after->>'node_id')::uuid;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE ops_fix.log x SET undone_at = now() WHERE x.id = l.id;
  RETURN jsonb_build_object('restored', v_n,
                            'skipped', CASE WHEN v_n = 0 THEN jsonb_build_array(l.after->>'panelist_id') ELSE '[]'::jsonb END);
END $$;

-- ---------- R3: rellenar dias sin envio de una ciudad POBOX ----------
-- La vista previa simula la aplicacion en una subtransaccion que siempre se deshace: asi devuelve, envio a
-- envio, exactamente lo que haria la aplicacion (con p_apply_changes = false el balanceo solo da recuentos
-- agregados por nodo y dia). Tambien llama al balanceo sin aplicar, como resumen.
CREATE OR REPLACE FUNCTION public.ops_fix_r3_preview(p_token text, p_account text, p_city text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE t jsonb; v_acc uuid; v_city uuid; v_today date; v_res jsonb; v_b jsonb; v_a jsonb; v_moves jsonb;
BEGIN
  PERFORM ops_test._check(p_token);
  t := ops_fix._r3_target(p_account, p_city);
  v_acc := (t->>'account_id')::uuid; v_city := (t->>'city_id')::uuid; v_today := (t->>'today')::date;

  v_res := public.rpc_balance_city_v2(v_city, v_today, (t->>'plan_end')::date, false, v_today);
  IF NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'ops_fix: no aplicable (el balanceo responde: %)', COALESCE(v_res->>'error', 'sin detalle');
  END IF;

  BEGIN
    v_b := ops_fix._r3_snapshot(v_acc, v_city);
    PERFORM public.rpc_balance_city_v2(v_city, v_today, (t->>'plan_end')::date, true, v_today);
    v_a := ops_fix._r3_snapshot(v_acc, v_city, v_b);
    v_moves := ops_fix._r3_moves(v_b, v_a);
    RAISE EXCEPTION 'ops_fix: simulacion' USING ERRCODE = 'OFSIM';
  EXCEPTION WHEN SQLSTATE 'OFSIM' THEN
    NULL;   -- todo lo escrito en la simulacion se deshace aqui
  END;

  RETURN jsonb_build_object('city', t->'city', 'from', t->'today', 'to', t->'plan_end',
                            'moves', v_moves, 'count', jsonb_array_length(v_moves),
                            'summary', jsonb_build_object('movements_count', v_res->'movements_count',
                                                          'pobox', v_res->'pobox', 'deferred', v_res->'deferred'));
END $$;

CREATE OR REPLACE FUNCTION public.ops_fix_r3_apply(p_token text, p_account text, p_city text, p_expected jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE t jsonb; v_acc uuid; v_city uuid; v_today date; v_res jsonb; v_b jsonb; v_a jsonb; v_moves jsonb; v_log bigint;
BEGIN
  PERFORM ops_test._check(p_token);
  -- Mismo candado por ciudad que el balanceo: la copia de antes no se cruza con otro balanceo.
  t := ops_fix._r3_target(p_account, p_city);
  v_acc := (t->>'account_id')::uuid; v_city := (t->>'city_id')::uuid; v_today := (t->>'today')::date;
  PERFORM pg_advisory_xact_lock(hashtext(v_city::text));

  v_b := ops_fix._r3_snapshot(v_acc, v_city);
  v_res := public.rpc_balance_city_v2(v_city, v_today, (t->>'plan_end')::date, true, v_today);
  IF NOT COALESCE((v_res->>'success')::boolean, false) THEN
    RAISE EXCEPTION 'ops_fix: el balanceo fallo: %', v_res->>'error';
  END IF;
  v_a := ops_fix._r3_snapshot(v_acc, v_city, v_b);
  v_moves := ops_fix._r3_moves(v_b, v_a);
  -- lo que hace ahora el balanceo debe ser exactamente lo que se enseno; si no, se deshace todo (es la
  -- misma transaccion) y no queda nada escrito
  IF p_expected IS NULL OR NOT (p_expected ? 'moves') OR jsonb_typeof(p_expected->'moves') <> 'array'
     OR ops_fix._r3_key(v_moves) IS DISTINCT FROM ops_fix._r3_key(p_expected->'moves') THEN
    RAISE EXCEPTION 'ops_fix: ha cambiado desde la propuesta';
  END IF;

  INSERT INTO ops_fix.log (kind, account_id, target, before, after)
  VALUES ('r3', v_acc, t->>'city', v_b, v_a)
  RETURNING id INTO v_log;
  RETURN jsonb_build_object('log_id', v_log, 'moves', v_moves, 'count', jsonb_array_length(v_moves));
END $$;

-- Deshacer R3: cada fila que cambio vuelve a su copia de antes solo si su estado actual es exactamente el que
-- dejo R3 (la copia de despues) y, si es un envio, no tiene filas enlazadas (ops_fix._apd_has_links); si no, se
-- salta y se devuelve su id. Una anotacion del registro y el envio
-- que la enlaza se saltan juntos. Orden: anotaciones, envios, ciudad.
CREATE OR REPLACE FUNCTION public.ops_fix_r3_undo(p_token text, p_log_id bigint)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = '' AS $$
DECLARE l ops_fix.log; v_city uuid; r record; v_cur jsonb;
        v_skip text[] := '{}'; v_ok_apd text[] := '{}'; v_ok_ds text[] := '{}'; v_n int := 0; v_link text;
BEGIN
  PERFORM ops_test._check(p_token);
  SELECT * INTO l FROM ops_fix.log x WHERE x.id = p_log_id FOR UPDATE;
  IF NOT FOUND OR l.kind <> 'r3' THEN
    RAISE EXCEPTION 'ops_fix: el registro % no es un arreglo R3', p_log_id;
  END IF;
  IF l.undone_at IS NOT NULL THEN
    RAISE EXCEPTION 'ops_fix: el arreglo % ya se deshizo', p_log_id;
  END IF;
  v_city := (l.before->'city'->>'id')::uuid;
  PERFORM pg_advisory_xact_lock(hashtext(v_city::text));

  -- envios que cambiaron
  FOR r IN
    WITH k AS (SELECT jsonb_object_keys(l.before->'apd') AS id UNION SELECT jsonb_object_keys(l.after->'apd'))
    SELECT k.id, l.before->'apd'->k.id AS b, l.after->'apd'->k.id AS a FROM k
     WHERE (l.before->'apd'->k.id) IS DISTINCT FROM (l.after->'apd'->k.id)
  LOOP
    SELECT to_jsonb(x.*) INTO v_cur FROM public.allocation_plan_details x
     WHERE x.id = r.id::uuid AND x.account_id = l.account_id FOR UPDATE;
    IF NOT FOUND THEN v_cur := NULL; END IF;
    -- se salta si cambio desde R3 o si (existiendo) ya tiene filas enlazadas
    IF v_cur IS DISTINCT FROM r.a OR (v_cur IS NOT NULL AND ops_fix._apd_has_links(r.id::uuid)) THEN
      v_skip := v_skip || r.id;
    ELSE
      v_ok_apd := v_ok_apd || r.id;
    END IF;
  END LOOP;

  -- anotaciones del registro que cambiaron (se saltan tambien si su envio enlazado se salta)
  FOR r IN
    WITH k AS (SELECT jsonb_object_keys(l.before->'ds') AS id UNION SELECT jsonb_object_keys(l.after->'ds'))
    SELECT k.id, l.before->'ds'->k.id AS b, l.after->'ds'->k.id AS a FROM k
     WHERE (l.before->'ds'->k.id) IS DISTINCT FROM (l.after->'ds'->k.id)
  LOOP
    SELECT to_jsonb(x.*) INTO v_cur FROM public.deferred_samples x
     WHERE x.id = r.id::uuid AND x.account_id = l.account_id FOR UPDATE;
    IF NOT FOUND THEN v_cur := NULL; END IF;
    IF v_cur IS DISTINCT FROM r.a
       OR COALESCE(r.a->>'reintroduced_detail_id', r.b->>'reintroduced_detail_id') = ANY (v_skip)
       OR COALESCE(r.a->'row_snapshot'->>'id', r.b->'row_snapshot'->>'id') = ANY (v_skip) THEN
      v_skip := v_skip || r.id;
      -- su envio enlazado tampoco se toca
      FOREACH v_link IN ARRAY ARRAY[r.a->>'reintroduced_detail_id', r.b->>'reintroduced_detail_id',
                                    r.a->'row_snapshot'->>'id', r.b->'row_snapshot'->>'id'] LOOP
        IF v_link = ANY (v_ok_apd) THEN
          v_ok_apd := array_remove(v_ok_apd, v_link);
          v_skip := v_skip || v_link;
        END IF;
      END LOOP;
    ELSE
      v_ok_ds := v_ok_ds || r.id;
    END IF;
  END LOOP;

  -- aplicar: anotaciones
  FOR r IN SELECT k AS id, l.before->'ds'->k AS b, l.after->'ds'->k AS a FROM unnest(v_ok_ds) k LOOP
    PERFORM ops_fix._put('public.deferred_samples'::regclass, COALESCE(r.b, r.a),
                         CASE WHEN r.b IS NULL THEN 'delete' WHEN r.a IS NULL THEN 'insert' ELSE 'update' END);
    v_n := v_n + 1;
  END LOOP;
  -- aplicar: envios
  FOR r IN SELECT k AS id, l.before->'apd'->k AS b, l.after->'apd'->k AS a FROM unnest(v_ok_apd) k LOOP
    PERFORM ops_fix._put('public.allocation_plan_details'::regclass, COALESCE(r.b, r.a),
                         CASE WHEN r.b IS NULL THEN 'delete' WHEN r.a IS NULL THEN 'insert' ELSE 'update' END);
    v_n := v_n + 1;
  END LOOP;
  -- ciudad (contador de rotacion del balanceo)
  IF (l.before->'city') IS DISTINCT FROM (l.after->'city') THEN
    SELECT to_jsonb(c.*) INTO v_cur FROM public.cities c WHERE c.id = v_city AND c.account_id = l.account_id FOR UPDATE;
    IF v_cur IS DISTINCT FROM l.after->'city' THEN
      v_skip := v_skip || v_city::text;
    ELSE
      UPDATE public.cities c SET balance_rotation_offset = (l.before->'city'->>'balance_rotation_offset')::int
       WHERE c.id = v_city AND c.account_id = l.account_id;
    END IF;
  END IF;

  UPDATE ops_fix.log x SET undone_at = now() WHERE x.id = l.id;
  RETURN jsonb_build_object('restored', v_n, 'skipped', to_jsonb(v_skip));
END $$;

-- ---------- ops_test_checks: + panelist_no_node y stuck_context ----------
-- pobox_no_send y no_receipts quedan exactamente igual que en 20261105200000_ops_operational_checks.sql.
--   panelist_no_node: panelistas activos con telegram y sin nodo (llevan a R2).
--   stuck_context:    panelistas activos con alguna fila de panelist_context de hace mas de 24 h (llevan a R1).
-- De los panelistas solo el codigo.
CREATE OR REPLACE FUNCTION public.ops_test_checks(p_token text)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE v_pobox jsonb; v_recv jsonb; v_nonode jsonb; v_stuck jsonb;
BEGIN
  PERFORM ops_test._check(p_token);

  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', x.account, 'city', btrim(x.city), 'node', x.node,
                                               'day', x.day::text) ORDER BY x.account, x.city), '[]'::jsonb)
    INTO v_pobox
    FROM ops_fix._pobox_no_send() x;

  WITH w AS (
    SELECT a.name AS account, c.id AS city_id, c.name AS city, count(*) AS waiting, min(d.sent_at) AS oldest,
           max(a.timezone) AS tz
      FROM public.allocation_plan_details d
      JOIN public.nodes n ON n.id = d.destination_node_id
      JOIN public.cities c ON c.id = n.city_id
      JOIN public.accounts a ON a.id = d.account_id
     WHERE d.status = 'sent' AND d.sent_at < now() - interval '5 days' AND d.sent_at > now() - interval '30 days'
     GROUP BY a.name, c.id, c.name
    HAVING count(*) >= 3)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', w.account, 'city', btrim(w.city), 'waiting', w.waiting,
                                               'oldest', ((w.oldest AT TIME ZONE COALESCE(w.tz, 'UTC'))::date)::text)
                            ORDER BY w.account, w.waiting DESC), '[]'::jsonb)
    INTO v_recv
    FROM w
   WHERE NOT EXISTS (SELECT 1 FROM public.allocation_plan_details r
                       JOIN public.nodes rn ON rn.id = r.destination_node_id
                      WHERE rn.city_id = w.city_id AND r.received_at > now() - interval '7 days');

  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', a.name, 'panelist', p.panelist_code, 'city', btrim(c.name))
                            ORDER BY a.name, p.panelist_code), '[]'::jsonb)
    INTO v_nonode
    FROM public.panelists p
    JOIN public.accounts a ON a.id = p.account_id
    LEFT JOIN public.cities c ON c.id = p.city_id AND c.account_id = p.account_id
   WHERE p.status = 'active' AND p.node_id IS NULL
     AND p.telegram_id IS NOT NULL AND btrim(p.telegram_id) <> '';

  SELECT COALESCE(jsonb_agg(jsonb_build_object('account', s.account, 'panelist', s.panelist,
                                               'since', to_char(s.since AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI"Z"'))
                            ORDER BY s.account, s.since), '[]'::jsonb)
    INTO v_stuck
    FROM (SELECT a.name AS account, p.panelist_code AS panelist, min(x.created_at) AS since
            FROM public.panelists p
            JOIN public.accounts a ON a.id = p.account_id
            JOIN public.panelist_context x ON x.telegram_id = p.telegram_id
           WHERE p.status = 'active'
           GROUP BY a.name, p.panelist_code
          HAVING min(x.created_at) < now() - interval '24 hours') s;

  RETURN jsonb_build_object('pobox_no_send', v_pobox, 'no_receipts', v_recv,
                            'panelist_no_node', v_nonode, 'stuck_context', v_stuck);
END $$;

-- ---------- permisos ----------
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA ops_fix FROM PUBLIC, anon, authenticated;
DO $$
DECLARE f regprocedure;
BEGIN
  FOR f IN SELECT p.oid::regprocedure FROM pg_proc p
            WHERE p.pronamespace = 'public'::regnamespace AND p.proname LIKE 'ops\_fix\_%' LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', f);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', f);
  END LOOP;
END $$;
REVOKE ALL ON FUNCTION public.ops_test_checks(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_test_checks(text) TO anon;
