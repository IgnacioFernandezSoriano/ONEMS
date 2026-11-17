-- ============================================================
-- Analisis de casos: el panelista se reconoce por su codigo o su Telegram — 2026-11-17
-- ============================================================
-- Antes el codigo solo coincidia escrito EXACTO y como palabra suelta («PAN-KEN-047»): «KEN-047»,
-- «PAN KEN 047», «(PAN-KEN-047)» o «PAN-KEN-047.» no encontraban a nadie. El Telegram del panelista
-- (numero o @usuario, columna panelists.telegram_id) no se buscaba nunca. Ahora:
--   * by_id (nuevo): el texto contiene el codigo del panelista (se ignoran mayusculas, guiones, espacios y
--     signos; vale sin el prefijo «PAN»: «KEN-047», «KEN047») o su Telegram (el numero exacto, o el @usuario
--     escrito con @ o con guion bajo). Si hay alguno by_id, solo salen esos, primero.
--   * by_name: como antes (todas las palabras en el nombre) pero sin tener en cuenta tildes ni signos
--     pegados a las palabras («Kyalo,»). Un by_id tambien es by_name (compatibilidad con el agente).
--   * parciales y etiqueta: sin cambios.
-- El filtro por cuenta (p_account) no cambia. Misma firma: CREATE OR REPLACE. Forward-only.
-- ============================================================

CREATE OR REPLACE FUNCTION ops_case._fold(p text)
RETURNS text LANGUAGE sql IMMUTABLE SET search_path = '' AS $$
  SELECT translate(lower(COALESCE(p, '')), 'áàâäãåéèêëíìîïóòôöõúùûüñçýÿ', 'aaaaaaeeeeiiiiooooouuuuncyy')
$$;

CREATE OR REPLACE FUNCTION ops_case._find(p_name text, p_tag text, p_account uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_words text[]; v_loose text[]; v_toks text[]; v_keys text[]; v_users text[]; v_digits text[];
  v_norm text; v_out jsonb;
BEGIN
  -- palabras sin tildes y sin signos pegados por fuera («(Kyalo),» -> «kyalo»)
  v_words := ARRAY(SELECT x FROM (SELECT btrim(w, '.,;:!?¡¿()[]{}"''«»') AS x
                                    FROM regexp_split_to_table(ops_case._fold(btrim(COALESCE(p_name, ''))), '\s+') w) s
                    WHERE length(x) >= 2);
  -- para la coincidencia parcial solo cuentan palabras de 4+ letras que no sean numeros (evita «de», «que»…)
  v_loose := ARRAY(SELECT w FROM unnest(v_words) w WHERE length(w) >= 4 AND w !~ '^[0-9]+$');
  -- trozos alfanumericos seguidos, unidos de 1 a 4: «PAN KEN 047» -> PANKEN047, KEN047, …
  v_toks := ARRAY(SELECT t FROM regexp_split_to_table(upper(COALESCE(p_name, '')), '[^A-Z0-9]+') t WHERE t <> '');
  v_keys := ARRAY(SELECT DISTINCT array_to_string(v_toks[i:j], '')
                    FROM generate_series(1, cardinality(v_toks)) i,
                         generate_series(i, LEAST(i + 3, cardinality(v_toks))) j);
  -- @usuario de Telegram: escrito con @, o con guion bajo (los nombres de usuario lo llevan a menudo)
  v_users := ARRAY(SELECT lower(ltrim(m[1], '@'))
                     FROM regexp_matches(COALESCE(p_name, ''), '(@?[A-Za-z][A-Za-z0-9_]{3,31})', 'g') m
                    WHERE m[1] LIKE '@%' OR m[1] LIKE '%\_%');
  -- numero de Telegram: 6+ cifras seguidas
  v_digits := ARRAY(SELECT m[1] FROM regexp_matches(COALESCE(p_name, ''), '([0-9]{6,})', 'g') m);
  v_norm := CASE WHEN btrim(COALESCE(p_tag, '')) = '' THEN NULL ELSE public.normalize_tag(p_tag) END;

  WITH tagged AS (
    SELECT d.id AS did, d.account_id, d.origin_panelist_id, d.destination_panelist_id, d.origin_node_id, d.destination_node_id
      FROM public.allocation_plan_details d
     WHERE v_norm IS NOT NULL AND d.tag_id IS NOT NULL AND public.normalize_tag(d.tag_id) = v_norm),
  tag_pan AS (
    SELECT t.origin_panelist_id AS pid FROM tagged t WHERE t.origin_panelist_id IS NOT NULL
    UNION SELECT t.destination_panelist_id FROM tagged t WHERE t.destination_panelist_id IS NOT NULL
    UNION SELECT p.id FROM tagged t JOIN public.panelists p ON p.account_id = t.account_id AND p.node_id = t.origin_node_id
           WHERE t.origin_panelist_id IS NULL
    UNION SELECT p.id FROM tagged t JOIN public.panelists p ON p.account_id = t.account_id AND p.node_id = t.destination_node_id
           WHERE t.destination_panelist_id IS NULL
    UNION SELECT r.panelist_id FROM public.receipt_case r WHERE v_norm IS NOT NULL AND r.tag_norm = v_norm),
  pan AS (
    SELECT p.*, regexp_replace(upper(COALESCE(p.panelist_code, '')), '[^A-Z0-9]', '', 'g') AS ckey,
           lower(ltrim(btrim(COALESCE(p.telegram_id, '')), '@')) AS tg
      FROM public.panelists p
     WHERE p.status = 'active' AND (p_account IS NULL OR p.account_id = p_account)),
  base AS (
    SELECT p.id, p.panelist_code, p.name, a.name AS account, btrim(c.name) AS city,
           ((p.ckey <> '' AND p.ckey = ANY (v_keys))
             OR (length(regexp_replace(p.ckey, '^PAN', '')) >= 5 AND regexp_replace(p.ckey, '^PAN', '') = ANY (v_keys))
             OR (p.tg ~ '^[0-9]{6,}$' AND p.tg = ANY (v_digits))
             OR (p.tg <> '' AND p.tg !~ '^[0-9]+$' AND p.tg = ANY (v_users))) AS by_id,
           (cardinality(v_words) > 0
             AND NOT EXISTS (SELECT 1 FROM unnest(v_words) w WHERE position(w IN ops_case._fold(p.name)) = 0)) AS all_words,
           (SELECT count(*) FROM unnest(v_loose) w WHERE position(w IN ops_case._fold(p.name)) > 0)::int AS hits,
           (p.id IN (SELECT pid FROM tag_pan)) AS by_tag
      FROM pan p
      JOIN public.accounts a ON a.id = p.account_id
      LEFT JOIN public.nodes n ON n.id = p.node_id
      LEFT JOIN public.cities c ON c.id = n.city_id),
  cand AS (SELECT b.*, (b.by_id OR b.all_words) AS by_name, (NOT (b.by_id OR b.all_words) AND b.hits > 0) AS partial
             FROM base b),
  sel AS (SELECT * FROM cand
           WHERE CASE WHEN EXISTS (SELECT 1 FROM cand c2 WHERE c2.by_id) THEN by_id
                      WHEN EXISTS (SELECT 1 FROM cand c2 WHERE c2.by_name) THEN by_name
                      ELSE (by_tag OR partial) END
           ORDER BY by_id DESC, (by_name AND by_tag) DESC, by_name DESC, (partial AND by_tag) DESC, by_tag DESC,
                    hits DESC, panelist_code
           LIMIT 10)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('panelist_id', s.id, 'code', s.panelist_code, 'name', s.name,
           'account', s.account, 'city', s.city, 'by_id', s.by_id, 'by_name', s.by_name, 'by_tag', s.by_tag,
           'partial', s.partial)
           ORDER BY s.by_id DESC, (s.by_name AND s.by_tag) DESC, s.by_name DESC, (s.partial AND s.by_tag) DESC,
                    s.by_tag DESC, s.hits DESC, s.panelist_code), '[]'::jsonb)
    INTO v_out FROM sel s;
  RETURN v_out;
END $$;

REVOKE ALL ON FUNCTION ops_case._fold(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION ops_case._find(text, text, uuid) FROM PUBLIC, anon, authenticated;
