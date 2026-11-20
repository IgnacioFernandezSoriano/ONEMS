#!/usr/bin/env bash
# Carrier Link volume test (Task 10b). LOCAL ONLY: Postgres portable 127.0.0.1:5433, database onems_t, rebuilt from
# the repo migrations by .superpowers/sdd/runlocal.sh. Never touches the remote project.
#
# Scale (owner, 2026-11-20): 30 cities / 870 routes, 1 carrier, 5 products = 5 active plans of 15,000 samples/year
# sharing one connector, oversampling 5 (~290 samples and ~1,450 candidates per weekly demand).
#
# Steps:
#   1. rebuild onems_t (baseline + migrations) and load fixture.sql;
#   2. quotas: gen_quotas.py (port of generateClQuotas) -> cl_plan_set_quotas + cl_plan_activate per plan (timed);
#   3. RUNS weekly runs (default 3; run k = ISO week k of 2026, p_now = Wednesday 06:05 Nairobi):
#        a. cl_emit_due_demands(p_now) once for the 5 plans (timed; demand payload sizes);
#        b. for EVERY plan: gen_batch.py builds the carrier batch(es) for its demand (<= 5,000 rows each) and each batch
#           is processed exactly like carrier-link-ingest POST /batches: cl_ingest_batch(feed, batch, false), then
#           cl_sample_stratum(batch, stratum) once per stratum of the summary, then cl_finish_batch(batch); every
#           call is its own statement/transaction, timed with clock_timestamp();
#   4. DB growth (rows and table sizes) and summarize.py -> out/results.md.
#
# Usage: bash supabase/tests/adhoc/cl_volume/run.sh            (RUNS=2 bash ... for two runs)
# If interrupted during step 1: git checkout supabase/migrations/20261119100200_account_access_writes.sql
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
OUT="$HERE/out"
RUNS="${RUNS:-3}"
FEED=c1f00000-0000-4000-8000-0000000000f1
PSQL=(/c/Users/fernandezi/pgportable/pgsql/bin/psql.exe -h 127.0.0.1 -p 5433 -U postgres -d onems_t -v ON_ERROR_STOP=1 -q -X)
export PGPASSWORD=postgres

die() { echo "ERROR: $*" >&2; exit 1; }
win() { cygpath -m "$1"; }
plan_id() { echo "c1f00000-0000-4000-8000-0000000000a$1"; }

rm -rf "$OUT"; mkdir -p "$OUT"

echo "== 1. rebuild onems_t (baseline + migrations) with the local harness"
bash "$ROOT/.superpowers/sdd/runlocal.sh" cl_masters
[ -z "$(cd "$ROOT" && git status --porcelain supabase/migrations)" ] || die "runlocal.sh left supabase/migrations modified"
"${PSQL[@]}" -At -f "$HERE/fixture.sql"

echo "== 2. quotas (cl_plan_set_quotas + cl_plan_activate)"
python -I "$HERE/gen_quotas.py" "$OUT"
for i in 1 2 3 4 5; do
  f="$OUT/quotas_p$i.json"
  "${PSQL[@]}" -At >> "$OUT/quotas.jsonl" <<SQL
CREATE TEMP TABLE vol_in AS SELECT pg_read_file('$(win "$f")')::jsonb AS p;
SELECT clock_timestamp() AS t0 \gset
SELECT public.cl_plan_set_quotas('$(plan_id $i)', (SELECT p FROM vol_in)) AS n \gset
SELECT extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000 AS set_ms, clock_timestamp() AS t0 \gset
SELECT public.cl_plan_activate('$(plan_id $i)') AS act \gset
SELECT json_build_object('plan', $i, 'cells', :n, 'json_bytes', $(wc -c < "$f"), 'set_quotas_ms', round(:set_ms, 1),
                         'activate_ms', round((extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000)::numeric, 1));
SQL
done
cat "$OUT/quotas.jsonl"

# One POST /batches, emulated statement by statement (index.ts). $1 run, $2 plan, $3 batch number, $4 manifest.
post_batch() {
  local run="$1" plan="$2" n="$3" man="$4" file sql sid
  file=$(python -I -c "import json,sys; print(json.load(open(sys.argv[1]))['batches'][int(sys.argv[2])-1]['file'])" "$man" "$n")
  sql="$OUT/run$run/p$plan/post_$n.sql"
  {
    echo "CREATE TEMP TABLE vol_t (phase text, stratum text, ms numeric);"
    echo "CREATE TEMP TABLE vol_in AS SELECT pg_read_file('$(win "$file")')::jsonb AS p;"
    echo "SELECT clock_timestamp() AS t0 \\gset"
    echo "SELECT public.cl_ingest_batch('$FEED', (SELECT p FROM vol_in), false) AS ing \\gset"
    echo "INSERT INTO vol_t VALUES ('ingest', NULL, extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000);"
    echo "SELECT :'ing'::jsonb->>'batch' AS batch, :'ing'::jsonb->>'status' AS ist \\gset"
    # Stratum ids in summary order (= batch order, as summaryStratumIds(ingest) in the Edge Function).
    python -I -c "import json,sys; print('\n'.join(json.load(open(sys.argv[1]))['batches'][int(sys.argv[2])-1]['strata']))" "$man" "$n" \
      | tr -d '\r' | while read -r sid; do
        echo "SELECT clock_timestamp() AS t0 \\gset"
        echo "SELECT public.cl_sample_stratum(:'batch', '$sid') AS r \\gset"
        echo "INSERT INTO vol_t VALUES ('sample', '$sid', extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000);"
      done
    echo "SELECT clock_timestamp() AS t0 \\gset"
    echo "SELECT public.cl_finish_batch(:'batch') AS fin \\gset"
    echo "INSERT INTO vol_t VALUES ('finish', NULL, extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000);"
    cat <<SQL
SELECT json_build_object(
  'run', $run, 'plan', $plan, 'post', $n,
  'rows', (SELECT sum(jsonb_array_length(e->'rows')) FROM vol_in, jsonb_array_elements(p->'strata') e),
  'bytes', $(python -I -c "import json,sys; print(json.load(open(sys.argv[1]))['batches'][int(sys.argv[2])-1]['bytes'])" "$man" "$n"),
  'ingest_status', :'ist', 'demand_status', :'fin'::jsonb->>'demand_status',
  'strata', (SELECT count(*) FROM vol_t WHERE phase = 'sample'),
  'ingest_ms', (SELECT round(ms, 1) FROM vol_t WHERE phase = 'ingest'),
  'sampling_ms', (SELECT round(sum(ms), 1) FROM vol_t WHERE phase = 'sample'),
  'sampling_max_ms', (SELECT round(max(ms), 1) FROM vol_t WHERE phase = 'sample'),
  'sampling_p50_ms', (SELECT round(percentile_cont(0.5) WITHIN GROUP (ORDER BY ms)::numeric, 1) FROM vol_t WHERE phase = 'sample'),
  'finish_ms', (SELECT round(ms, 1) FROM vol_t WHERE phase = 'finish'),
  'candidates_valid', (SELECT sum((e->>'candidates_valid')::int) FROM jsonb_array_elements(:'ing'::jsonb->'strata') e),
  'samples_required', (SELECT sum(r.samples_required) FROM public.cl_sampling_runs r WHERE r.batch_id = :'batch'),
  'samples_selected', (SELECT sum(r.samples_selected) FROM public.cl_sampling_runs r WHERE r.batch_id = :'batch'),
  'one_db_rows', (SELECT count(*) FROM public.one_db o JOIN public.cl_samples s ON s.id = o.cl_sample_id WHERE s.batch_id = :'batch'));
SQL
  } > "$sql"
  "${PSQL[@]}" -At -f "$sql" | tee -a "$OUT/posts.jsonl"
}

echo "== 3. weekly runs: $RUNS"
for run in $(seq 1 "$RUNS"); do
  mkdir -p "$OUT/run$run"
  echo "---- run $run: emit"
  "${PSQL[@]}" -At <<SQL | tee -a "$OUT/emit.jsonl"
SELECT (timestamptz '2026-01-07 06:05:00+03' + interval '7 days' * ($run - 1))::text AS pnow \gset
SELECT clock_timestamp() AS t0 \gset
SELECT public.cl_emit_due_demands(:'pnow'::timestamptz) AS n \gset
SELECT json_build_object('run', $run, 'p_now', :'pnow', 'demands', :n,
  'emit_ms', round((extract(epoch FROM clock_timestamp() - :'t0'::timestamptz) * 1000)::numeric, 1),
  'emit_failed_alerts', (SELECT count(*) FROM public.cl_alerts WHERE alert_type = 'emit_failed'),
  'per_demand', (SELECT json_agg(json_build_object('plan', right(d.plan_id::text, 1)::int,
                         'strata', jsonb_array_length(d.payload->'strata'),
                         'samples_required', (SELECT sum((s->>'samples_required')::int) FROM jsonb_array_elements(d.payload->'strata') s),
                         'candidates_requested', (SELECT sum((s->>'candidates_requested')::int) FROM jsonb_array_elements(d.payload->'strata') s),
                         'payload_bytes', octet_length(d.payload::text)) ORDER BY d.plan_id)
                   FROM public.cl_demands d WHERE d.feed_id = '$FEED' AND d.requested_at = :'pnow'::timestamptz));
SQL
  for i in 1 2 3 4 5; do
    d="$OUT/run$run/p$i"; mkdir -p "$d"
    "${PSQL[@]}" -At -c "SELECT payload FROM public.cl_demands WHERE plan_id = '$(plan_id $i)' AND status = 'open'
                          ORDER BY requested_at DESC LIMIT 1" > "$d/demand.json"
    [ -s "$d/demand.json" ] || die "run $run: plan $i has no open demand"
    python -I "$HERE/gen_batch.py" "$d/demand.json" "$d" --suffix "r$run"
    nb=$(python -I -c "import json,sys; print(len(json.load(open(sys.argv[1]))['batches']))" "$d/manifest.json")
    for n in $(seq 1 "$nb"); do post_batch "$run" "$i" "$n" "$d/manifest.json"; done
  done
done

echo "== 4. DB growth"
"${PSQL[@]}" -At > "$OUT/growth.json" <<SQL
SELECT json_build_object(
  'posts', (SELECT count(*) FROM public.cl_batches WHERE account_id = 'c1f00000-0000-4000-8000-000000000001'),
  'demands', (SELECT count(*) FROM public.cl_demands WHERE account_id = 'c1f00000-0000-4000-8000-000000000001'),
  'tables', (SELECT json_object_agg(t.name, json_build_object('rows', t.n, 'total_bytes', pg_total_relation_size(('public.' || t.name)::regclass)))
               FROM (VALUES
                 ('cl_batches',      (SELECT count(*) FROM public.cl_batches)),
                 ('cl_batch_scans',  (SELECT count(*) FROM public.cl_batch_scans)),
                 ('cl_samples',      (SELECT count(*) FROM public.cl_samples)),
                 ('cl_sample_scans', (SELECT count(*) FROM public.cl_sample_scans)),
                 ('cl_sampling_runs',(SELECT count(*) FROM public.cl_sampling_runs)),
                 ('cl_alerts',       (SELECT count(*) FROM public.cl_alerts)),
                 ('cl_demands',      (SELECT count(*) FROM public.cl_demands)),
                 ('cl_plan_quotas',  (SELECT count(*) FROM public.cl_plan_quotas)),
                 ('one_db',          (SELECT count(*) FROM public.one_db WHERE source = 'carrier'))) t(name, n)),
  'one_db_all_rows', (SELECT count(*) FROM public.one_db),
  'alerts_by_type', (SELECT json_object_agg(alert_type, n) FROM (SELECT alert_type, count(*) AS n FROM public.cl_alerts GROUP BY 1) x));
SQL
cat "$OUT/growth.json"

echo "== 5. summary"
python -I "$HERE/summarize.py" "$OUT" | tee "$OUT/results.md"
