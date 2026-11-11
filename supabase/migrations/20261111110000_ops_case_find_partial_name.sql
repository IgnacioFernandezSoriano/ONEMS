-- ============================================================
-- Analisis de casos: busqueda por nombre flexible — 2026-11-11
-- ============================================================
-- Antes, un nombre solo coincidia si TODAS las palabras escritas estaban en el nombre del panelista: «Samwel
-- Mettet» no encontraba a «Samwel». Ahora:
--   * coincidencia completa (todas las palabras, o el codigo exacto: 20261111100000) -> by_name, como antes;
--     si hay alguna, solo salen esas;
--   * si no hay ninguna completa, salen tambien las PARCIALES (alguna palabra de 4+ letras, que no sea un
--     numero, esta en el nombre) junto con las de etiqueta, ordenadas por cuantas palabras coinciden.
--     Llevan by_name = false y partial = true: el agente nunca elige solas a esas, siempre pregunta.
-- El filtro por cuenta (p_account) no cambia. Misma firma: CREATE OR REPLACE. Forward-only.
-- ============================================================

CREATE OR REPLACE FUNCTION ops_case._find(p_name text, p_tag text, p_account uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = '' AS $$
DECLARE
  v_words text[]; v_loose text[]; v_norm text; v_out jsonb;
BEGIN
  v_words := ARRAY(SELECT w FROM regexp_split_to_table(lower(btrim(COALESCE(p_name, ''))), '\s+') w WHERE length(w) >= 2);
  -- para la coincidencia parcial solo cuentan palabras de 4+ letras que no sean numeros (evita «de», «que»…)
  v_loose := ARRAY(SELECT w FROM unnest(v_words) w WHERE length(w) >= 4 AND w !~ '^[0-9]+$');
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
  base AS (
    SELECT p.id, p.panelist_code, p.name, a.name AS account, btrim(c.name) AS city,
           (cardinality(v_words) > 0 AND (
              NOT EXISTS (SELECT 1 FROM unnest(v_words) w WHERE position(w IN lower(p.name)) = 0)
              OR lower(btrim(p.panelist_code)) = ANY (v_words))) AS by_name,
           (SELECT count(*) FROM unnest(v_loose) w WHERE position(w IN lower(p.name)) > 0)::int AS hits,
           (p.id IN (SELECT pid FROM tag_pan)) AS by_tag
      FROM public.panelists p
      JOIN public.accounts a ON a.id = p.account_id
      LEFT JOIN public.nodes n ON n.id = p.node_id
      LEFT JOIN public.cities c ON c.id = n.city_id
     WHERE p.status = 'active' AND (p_account IS NULL OR p.account_id = p_account)),
  cand AS (SELECT b.*, (NOT b.by_name AND b.hits > 0) AS partial FROM base b),
  sel AS (SELECT * FROM cand
           WHERE CASE WHEN EXISTS (SELECT 1 FROM cand c2 WHERE c2.by_name) THEN by_name ELSE (by_tag OR partial) END
           ORDER BY (by_name AND by_tag) DESC, by_name DESC, (partial AND by_tag) DESC, by_tag DESC, hits DESC,
                    panelist_code
           LIMIT 10)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('panelist_id', s.id, 'code', s.panelist_code, 'name', s.name,
           'account', s.account, 'city', s.city, 'by_name', s.by_name, 'by_tag', s.by_tag, 'partial', s.partial)
           ORDER BY (s.by_name AND s.by_tag) DESC, s.by_name DESC, (s.partial AND s.by_tag) DESC, s.by_tag DESC,
                    s.hits DESC, s.panelist_code), '[]'::jsonb)
    INTO v_out FROM sel s;
  RETURN v_out;
END $$;

REVOKE ALL ON FUNCTION ops_case._find(text, text, uuid) FROM PUBLIC, anon, authenticated;
