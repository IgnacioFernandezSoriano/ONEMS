-- Carrier Link: lint de pg-safeupdate. La API de Supabase (PostgREST) carga pg-safeupdate: todo UPDATE o DELETE sin
-- WHERE propio falla con 21000 ("UPDATE requires a WHERE clause"). El Postgres local no lo tiene, asi que los tests de
-- comportamiento no lo detectan (caso 20261120110900). Este test revisa el codigo de todas las funciones public.cl_*:
-- cada UPDATE / DELETE necesita un WHERE en su mismo nivel de parentesis (no cuenta el WHERE de una subconsulta).
-- No son sentencias: FOR [NO KEY] UPDATE, ON CONFLICT ... DO UPDATE, ON UPDATE / ON DELETE (DDL), OR UPDATE (triggers).
\set ON_ERROR_STOP on
SET client_min_messages = error;

CREATE OR REPLACE FUNCTION pg_temp.ok(p_cond boolean, p_msg text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_cond IS NOT TRUE THEN RAISE EXCEPTION 'FAIL: %', p_msg; END IF; END $$;

-- Sentencias UPDATE / DELETE sin WHERE propio en p_src (devuelve un extracto de cada una).
-- Fichas en orden: comentarios, literales ('..', "..", $tag$..$tag$), palabras, parentesis y ';'. Comentarios y literales
-- se consumen enteros (lo que haya dentro no cuenta) y se descartan; cada ficha guarda su profundidad de parentesis.
CREATE OR REPLACE FUNCTION pg_temp.lint_unsafe(p_src text) RETURNS SETOF text LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  tok text[] := ARRAY[]::text[];
  dep int[] := ARRAY[]::int[];
  m record;
  d int := 0;
  k int;
  j int;
  v_prev text;
  v_safe boolean;
BEGIN
  FOR m IN SELECT x[1] AS t
             FROM regexp_matches(p_src,
                    $r$(--[^\n]*|/\*([^*]|\*+[^*/])*\*+/|'([^']|'')*'|"([^"]|"")*"|\$([A-Za-z_]*)\$([^$]|\$[^$])*?\$\5\$|[A-Za-z_][A-Za-z0-9_$]*|[();])$r$,
                    'g') r(x) LOOP
    CONTINUE WHEN left(m.t, 1) IN ('-', '/', '''', '"', '$');
    IF m.t = ')' THEN d := d - 1; END IF;
    tok := tok || lower(m.t); dep := dep || d;
    IF m.t = '(' THEN d := d + 1; END IF;
  END LOOP;

  FOR k IN 1 .. COALESCE(array_length(tok, 1), 0) LOOP
    CONTINUE WHEN tok[k] NOT IN ('update', 'delete');
    v_prev := CASE WHEN k > 1 THEN tok[k - 1] END;
    CONTINUE WHEN v_prev IN ('for', 'key', 'do', 'on', 'or', 'of');
    v_safe := false;
    j := k + 1;
    WHILE j <= array_length(tok, 1) LOOP
      EXIT WHEN tok[j] = ';' AND dep[j] <= dep[k];
      EXIT WHEN tok[j] = ')' AND dep[j] < dep[k];
      IF tok[j] = 'where' AND dep[j] = dep[k] THEN v_safe := true; EXIT; END IF;
      j := j + 1;
    END LOOP;
    IF NOT v_safe THEN
      RETURN NEXT array_to_string(tok[k:LEAST(k + 6, array_length(tok, 1))], ' ');
    END IF;
  END LOOP;
END $$;

-- Hallazgos en las funciones public.cl_*.
CREATE OR REPLACE FUNCTION pg_temp.lint_findings() RETURNS TABLE (fn text, stmt text) LANGUAGE sql AS $$
  SELECT p.oid::regprocedure::text, u
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   CROSS JOIN LATERAL pg_temp.lint_unsafe(p.prosrc) u
   WHERE n.nspname = 'public' AND p.proname LIKE 'cl\_%' AND p.prolang IN (SELECT l.oid FROM pg_language l WHERE l.lanname IN ('plpgsql', 'sql'))
$$;

-- ===================================================================== 1. el lint distingue casos seguros e inseguros
DO $$
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM pg_temp.lint_unsafe($s$
    UPDATE t SET a = 1 WHERE true;
    DELETE FROM t WHERE id = 1;
    SELECT * FROM t FOR UPDATE;
    SELECT * FROM t FOR NO KEY UPDATE;
    INSERT INTO t VALUES (1) ON CONFLICT (id) DO UPDATE SET a = excluded.a;
    INSERT INTO t VALUES (1) ON CONFLICT (id) DO UPDATE SET a = excluded.a WHERE t.a IS NULL;
    WITH v AS (UPDATE t SET a = 2 WHERE b RETURNING id) SELECT count(*) FROM v;
    UPDATE t SET a = 'UPDATE x' WHERE id = 2;  -- DELETE FROM t
    RAISE EXCEPTION 'UPDATE requires a WHERE clause';
    UPDATE t SET (a, b) = (SELECT 1, 2 FROM u WHERE u.id = t.id) WHERE t.c;
    UPDATE t SET a = x.a FROM (SELECT a FROM u WHERE u.k) x WHERE x.a = t.a;
  $s$)) = 0, 'casos seguros: sin hallazgos');
  PERFORM pg_temp.ok((SELECT count(*) FROM pg_temp.lint_unsafe($s$
    UPDATE t SET a = 1;
    DELETE FROM t;
    UPDATE t SET a = (SELECT b FROM u WHERE u.id = 1);
    WITH v AS (UPDATE t SET a = 2 RETURNING id) SELECT count(*) FROM v WHERE true;
    DELETE FROM t USING u /* WHERE */;
  $s$)) = 5, 'casos inseguros: 5 hallazgos');
END $$;

-- ===================================================================== 2. fixture negativa: las 3 sentencias corregidas en 20261120110900
-- Copia literal de los 3 UPDATE sin WHERE que tenia cl_ingest_batch (20261120110700) dentro de una funcion cl_*
-- temporal: el lint sobre las funciones reales debe senalarlos (y solo a ellos).
BEGIN;
CREATE FUNCTION public.cl_zz_lint_fixture(v_plan public.cl_plans, f_product text) RETURNS void LANGUAGE plpgsql AS $f$
BEGIN
  IF f_product IS NULL THEN
    UPDATE pg_temp.cl_ingest_rows SET product_id = v_plan.product_id;
  END IF;

  -- 6. Motivo por lectura.
  UPDATE pg_temp.cl_ingest_rows t SET row_reason = CASE
      WHEN t.oversize THEN 'bad_value'
      WHEN t.scan_at IS NULL   THEN 'bad_timestamp'
      WHEN t.product_id IS NULL THEN 'unknown_product'
      WHEN t.reader_id IS NULL THEN 'unknown_reading_point'
    END;

  UPDATE pg_temp.cl_ingest_cands c SET
         n_end  = (SELECT count(*) FROM pg_temp.cl_ingest_rows t
                    WHERE t.stratum_id = c.stratum_id AND t.item_id = c.item_id AND t.row_reason IS NULL AND t.is_end),
         end_at = (SELECT max(t.scan_at) FROM pg_temp.cl_ingest_rows t
                    WHERE t.stratum_id = c.stratum_id AND t.item_id = c.item_id AND t.row_reason IS NULL AND t.is_end
                      AND t.r_ord IS DISTINCT FROM c.start_r_ord);
END $f$;
DO $$
DECLARE v_n int; v_list text;
BEGIN
  SELECT count(*), string_agg(fn || ': ' || stmt, E'\n') INTO v_n, v_list FROM pg_temp.lint_findings();
  PERFORM pg_temp.ok(v_n = 3 AND NOT EXISTS (SELECT 1 FROM pg_temp.lint_findings() WHERE fn NOT LIKE 'cl_zz_lint_fixture(%'),
                     'la fixture da exactamente 3 hallazgos: ' || COALESCE(v_list, '(ninguno)'));
END $$;
ROLLBACK;

-- ===================================================================== 3. las funciones cl_* reales pasan
DO $$
DECLARE v_list text;
BEGIN
  PERFORM pg_temp.ok((SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                       WHERE n.nspname = 'public' AND p.proname LIKE 'cl\_%') >= 20, 'hay funciones cl_* que revisar');
  SELECT string_agg(fn || ': ' || stmt, E'\n') INTO v_list FROM pg_temp.lint_findings();
  PERFORM pg_temp.ok(v_list IS NULL, E'UPDATE/DELETE sin WHERE en funciones cl_*:\n' || COALESCE(v_list, ''));
END $$;

\echo cl_safeupdate_lint: OK
