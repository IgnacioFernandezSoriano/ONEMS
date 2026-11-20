#!/usr/bin/env bash
# Carrier Link: end-to-end synthetic test on DEMO2 (f4d823d2-93e6-4755-9a89-9da87e7fa86e).
# Project sehbnpgzqljrsqimwyuz is PRODUCTION. Every phase that writes refuses to run unless
#   CONFIRM_REMOTE=sehbnpgzqljrsqimwyuz
# is set in the environment (one owner confirmation per phase). Read-only phases use `db query --read-only`.
#
# Usage: bash supabase/tests/adhoc/cl_demo2/run.sh <phase>
#   inspect        read-only look at the live DEMO2 masters (inspect/*.sql)
#   setup          WRITES  baseline (read-only) + 10_points_feed + 20_plan + carrier key (hash only) + 30_emit
#   demands        GET  /carrier-link-ingest/demands             -> out/demands.json
#   gen [suffix]   build out/batch.json from out/demands.json (latest open demand), default suffix 01
#   dryrun         POST /carrier-link-ingest/batches?dry_run=true (generates the batch if missing)
#   activate-feed  WRITES  connector testing -> active (the Edge Function refuses real batches while testing)
#   ingest         POST /carrier-link-ingest/batches (real: ingest + draw + one_db)
#   check          read-only verification (expectations + unchanged panelist data)
#   undo-test      WRITES  cl_undo_batch on the batch + asserts; re-emit (30_emit); GET demands; new batch (suffix 02);
#                  POST real; check  -> the demo data is back (new seed, same counts)
#   cleanup        WRITES  removes everything the test created (also needs CONFIRM_CLEANUP=yes). NOT part of the demo.
#   local-sim      everything above against the LOCAL Postgres 127.0.0.1:5433 (onems_t), Edge Function emulated
#
# CL_TARGET=local runs a single phase against the local onems_t instead of the remote project.
set -euo pipefail

REF=sehbnpgzqljrsqimwyuz
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
REL=supabase/tests/adhoc/cl_demo2
TARGET="${CL_TARGET:-remote}"
OUT="$HERE/out"; [ "$TARGET" = local ] && OUT="$HERE/out/local"
mkdir -p "$OUT"
URL="https://$REF.supabase.co/functions/v1/carrier-link-ingest"
FEED=c1de2000-0000-4000-8000-0000000000f1
PY=(python -I "$HERE/util.py")
PSQL=(/c/Users/fernandezi/pgportable/pgsql/bin/psql.exe -h 127.0.0.1 -p 5433 -U postgres -d onems_t -v ON_ERROR_STOP=1 -q -X)
export PGPASSWORD=postgres

die() { echo "ERROR: $*" >&2; exit 1; }

need_confirm() {
  [ "$TARGET" = local ] && return 0
  [ "${CONFIRM_REMOTE:-}" = "$REF" ] || die "remote write refused: set CONFIRM_REMOTE=$REF after the owner confirms this phase ($1)"
}

# Read-only SQL file -> raw output on stdout.
rq() {
  if [ "$TARGET" = local ]; then "${PSQL[@]}" -At -f "$HERE/$1"
  else (cd "$ROOT" && npx -y supabase@latest db query --remote="$REF" --read-only --output-format json -f "$REL/$1"); fi
}
# Writing SQL file (path relative to this folder) -> raw output on stdout.
rw() {
  need_confirm "$1"
  echo ">> write $1 ($TARGET)" >&2
  if [ "$TARGET" = local ]; then "${PSQL[@]}" -At -f "$HERE/$1"
  else (cd "$ROOT" && npx -y supabase@latest db query --remote="$REF" --yes --output-format json -f "$REL/$1"); fi
}
show() { "${PY[@]}" rows; }   # pretty rows (remote JSON) / pass-through (local)
showw() { if [ "$TARGET" = local ]; then cat; else "${PY[@]}" rows; fi; }
one() { if [ "$TARGET" = local ]; then cat; else "${PY[@]}" one; fi; }

baseline() {
  if [ -s "$OUT/baseline.json" ]; then echo "baseline kept: $OUT/baseline.json"; return; fi
  rq check/c00_baseline.sql | one > "$OUT/baseline.json"
  echo "baseline: $(cat "$OUT/baseline.json")"
}

keyrow() {
  read -r HASH PREFIX < <("${PY[@]}" keygen "$OUT" | tr -d '\r')
  "${PY[@]}" render "$HERE/40_key.sql.tmpl" "$OUT/40_key.sql" "$HASH" "$PREFIX"
  local rel="out/40_key.sql"; [ "$TARGET" = local ] && rel="out/local/40_key.sql"
  rw "$rel" | showw
  echo "carrier key stored only in $OUT/carrier_key.txt (git-ignored); DB keeps sha256 + prefix $PREFIX"
}

# ---------------------------------------------------------------- Edge Function (remote) or its emulation (local)
get_demands() {
  if [ "$TARGET" = local ]; then
    { rq check/c50_open_demands.sql; echo 200; } > "$OUT/demands.http"
  else
    [ -s "$OUT/carrier_key_header.txt" ] || die "no key: run setup first"
    curl -sS -X GET "$URL/demands" -H @"$OUT/carrier_key_header.txt" -w '\n%{http_code}' > "$OUT/demands.http"
  fi
  "${PY[@]}" http "$OUT/demands.http" || die "GET /demands failed"
  sed '$d' "$OUT/demands.http" > "$OUT/demands.json"
}

# Local emulation of carrier-link-ingest POST /batches (index.ts): feed checks, cl_ingest_batch, then (real batch
# still 'validated') cl_sample_stratum per stratum of the summary and cl_finish_batch, each in its own transaction.
sim_post() {
  local dry="$1" file st ing bst sid samp="[]" fin
  file="$(cygpath -m "$2")"
  st=$("${PSQL[@]}" -At -c "SELECT status FROM public.cl_feeds WHERE id = '$FEED'")
  if [ "$st" = paused ]; then echo '{"success":false,"error":"CL_FEED_PAUSED"}'; echo 403; return; fi
  if [ "$st" = testing ] && [ "$dry" = false ]; then echo '{"success":false,"error":"CL_FEED_TESTING_DRY_RUN_ONLY"}'; echo 403; return; fi
  ing=$("${PSQL[@]}" -At -c "SELECT public.cl_ingest_batch('$FEED', pg_read_file('$file')::jsonb, $dry)")
  if [ "$dry" = true ] || [ "$(echo "$ing" | "${PY[@]}" get status)" != validated ]; then echo "{\"ingest\": $ing}"; echo 200; return; fi
  bst=$("${PSQL[@]}" -At -c "SELECT status FROM public.cl_batches WHERE id = '$(echo "$ing" | "${PY[@]}" get batch)'")
  if [ "$bst" != validated ]; then echo "{\"ingest\": $ing}"; echo 200; return; fi
  for sid in $(echo "$ing" | "${PY[@]}" strata | tr -d '\r'); do
    samp=$(python -I -c "import json,sys; a=json.loads(sys.argv[1]); a.append(json.loads(sys.argv[2])); print(json.dumps(a))" \
           "$samp" "$("${PSQL[@]}" -At -c "SELECT public.cl_sample_stratum('$(echo "$ing" | "${PY[@]}" get batch)', '$sid')")")
  done
  fin=$("${PSQL[@]}" -At -c "SELECT public.cl_finish_batch('$(echo "$ing" | "${PY[@]}" get batch)')")
  echo "{\"ingest\": $ing, \"sampling\": $samp, \"finish\": $fin}"; echo 200
}

post_batch() {   # $1 = true|false (dry run), $2 = response name
  [ "$1" = true ] || need_confirm "POST batch ($2)"
  [ -s "$OUT/batch.json" ] || gen_batch 01
  if [ "$TARGET" = local ]; then
    sim_post "$1" "$OUT/batch.json" > "$OUT/$2.http"
  else
    [ -s "$OUT/carrier_key_header.txt" ] || die "no key: run setup first"
    local q=""; [ "$1" = true ] && q="?dry_run=true"
    curl -sS -X POST "$URL/batches$q" -H @"$OUT/carrier_key_header.txt" -H 'Content-Type: application/json' \
         --data-binary @"$OUT/batch.json" -w '\n%{http_code}' > "$OUT/$2.http"
  fi
  "${PY[@]}" http "$OUT/$2.http" || die "POST /batches failed"
  sed '$d' "$OUT/$2.http" > "$OUT/$2.json"
}

gen_batch() {
  [ -s "$OUT/demands.json" ] || get_demands
  python -I "$HERE/gen_batch.py" "$OUT/demands.json" "$OUT/batch.json" --demand latest --suffix "${1:-01}"
}

check() {
  [ -s "$OUT/baseline.json" ] || die "no baseline ($OUT/baseline.json): it is taken by setup"
  rq check/c10_summary.sql | one > "$OUT/summary.json"
  echo "--- samples (c20)"; rq check/c20_samples.sql | showw
  echo "--- alerts (c30)"; rq check/c30_alerts.sql | showw
  echo "--- sampling runs / rejected readings (c40)"; rq check/c40_runs_rejects.sql | showw
  echo "--- summary (c10)"; python -I -c "import json,sys; d=json.load(open(sys.argv[1])); d.pop('expect',None); print(json.dumps(d, indent=1, ensure_ascii=False))" "$OUT/summary.json"
  echo "--- expectations"; "${PY[@]}" verify "$OUT/baseline.json" "$OUT/summary.json"
}

phase() {
  case "$1" in
    inspect) for f in "$HERE"/inspect/*.sql; do echo "=== $(basename "$f")"; rq "inspect/$(basename "$f")" | show; done ;;
    setup)
      need_confirm setup
      baseline
      rw 10_points_feed.sql | showw
      rw 20_plan.sql | showw
      keyrow
      # Last on purpose: re-running setup after the emission stops here (GUARD: no pending quota), nothing written.
      rw 30_emit.sql | showw ;;
    demands) get_demands ;;
    gen) gen_batch "${2:-01}" ;;
    dryrun) post_batch true dryrun ;;
    activate-feed) need_confirm activate-feed; rw 50_activate_feed.sql | showw ;;
    ingest) post_batch false ingest ;;
    check) check ;;
    undo-test)
      need_confirm undo-test
      if [ "$TARGET" != local ]; then
        free=$(rq check/c60_slot_free.sql | one)
        echo "emit slot: $free"
        echo "$free" | grep -q '"slot_free": true' \
          || die "the DEMO plan already has a demand in this local hour: run undo-test after the next o'clock (the re-emission would be refused and the demo data would stay undone)"
      fi
      rw 60_undo.sql | showw
      echo "--- after undo (expectations are expected to FAIL here: no samples)"
      rq check/c10_summary.sql | one | python -I -c "import json,sys; d=json.load(sys.stdin); print(json.dumps({k: d[k] for k in ('demands','batches','quotas','samples_active','onedb_carrier','obtained','panelist_rows_demo2')}, ensure_ascii=False))"
      rw 30_emit.sql | showw
      rm -f "$OUT/demands.json" "$OUT/batch.json"
      get_demands
      gen_batch 02
      post_batch false ingest_after_undo
      check ;;
    cleanup)
      need_confirm cleanup
      [ "$TARGET" = local ] || [ "${CONFIRM_CLEANUP:-}" = yes ] || die "cleanup also needs CONFIRM_CLEANUP=yes"
      rw 90_cleanup.sql | showw
      rm -f "$OUT/carrier_key.txt" "$OUT/carrier_key_header.txt" "$OUT/40_key.sql" ;;
    local-sim)
      export CL_TARGET=local
      # setup and undo-test run within the same hour here: let 30_emit.sql use an earlier free hour (local only).
      export PGOPTIONS="-c cl_demo.allow_past_slot=on"
      rm -rf "$HERE/out/local"
      echo "== rebuild onems_t (baseline + migrations) with the local harness"
      bash "$ROOT/.superpowers/sdd/runlocal.sh" cl_masters
      [ -z "$(cd "$ROOT" && git status --porcelain supabase/migrations)" ] || die "runlocal.sh left supabase/migrations modified"
      "${PSQL[@]}" -f "$HERE/local/fixture_demo2.sql"
      for p in setup demands gen dryrun activate-feed ingest check undo-test cleanup; do
        echo; echo "################ local: $p"; bash "$HERE/run.sh" "$p"
      done
      echo; echo "################ local: leftovers after cleanup"
      "${PSQL[@]}" -At -c "SELECT (SELECT count(*) FROM public.cl_feeds) + (SELECT count(*) FROM public.cl_plans) + (SELECT count(*) FROM public.cl_demands)
                                 + (SELECT count(*) FROM public.cl_batches) + (SELECT count(*) FROM public.cl_samples) + (SELECT count(*) FROM public.cl_alerts)
                                 + (SELECT count(*) FROM public.cl_field_mappings) + (SELECT count(*) FROM public.cl_value_mappings)
                                 + (SELECT count(*) FROM public.cl_extra_fields) + (SELECT count(*) FROM public.api_keys WHERE feed_id IS NOT NULL)
                                 + (SELECT count(*) FROM public.readers WHERE capture_source = 'carrier_scan')
                                 + (SELECT count(*) FROM public.one_db WHERE source = 'carrier')
                                 + (SELECT count(*) FROM public.delivery_standards WHERE cl_last_mile_time <> 0)" \
        | { read -r n; n="${n//$'\r'/}"; echo "leftover rows: $n"; [ "$n" = 0 ] || die "cleanup left $n rows"; }
      echo "LOCAL SIMULATION: PASS" ;;
    *) sed -n '2,25p' "$0"; exit 2 ;;
  esac
}

phase "$@"
