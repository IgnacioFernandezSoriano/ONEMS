#!/usr/bin/env bash
# Carrier simulator (Carrier Link v4) - automated end-to-end test. LOCAL ONLY: Postgres portable 127.0.0.1:5433,
# database onems_t, rebuilt from the repo migrations by .superpowers/sdd/runlocal.sh. Never touches the remote project.
#
#   1. rebuild onems_t; generate the carrier dataset (fixed seed); connector key (hash only in the DB); fixture.sql
#      (connector with deliveries on Monday and Thursday at 03:00, plan 2026-11-02..15 = ISO weeks W45 and W46);
#  1b. connector in Testing: two test deliveries of the first period (JSONL and CSV) are both processed, create no
#      samples and do not consume the period (next_period still 2026-11-02); then the connector goes Active;
#   2. first period with a TAMPERED file (sha256 does not match) -> delivery rejected CL_SHA256_MISMATCH, incident
#      delivery_rejected with a notice for the account and for the carrier;
#   3. the reference connector delivers every period in calendar order (jsonl, csv, jsonl, csv): GET /config ->
#      POST /deliveries -> PUT -> complete -> poll; check.py compares every answer with the ground truth and the DB;
#   4. API answers: replay of the first open (200, existing), same period with another file (409), period not in the
#      calendar (422), period without plan (422), unknown delivery (404), v3 route (410).
# SAVE_EXAMPLES=1 also refreshes tools/carrier-simulator/examples/ and docs/carrier-link/ejemplo/ from this run.
#
# Needs: Git Bash, python 3, deno (runs the real worker loader locally), the portable Postgres on 127.0.0.1:5433.
# Usage: bash tools/carrier-simulator/e2e/run.sh
# If interrupted during step 1: git checkout supabase/migrations/20261119100200_account_access_writes.sql
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$SIM/../.." && pwd)"
OUT="$SIM/out/e2e"
# psql: $PSQL, else the portable Postgres under the user's home (same default as the Python and Deno parts).
export PSQL="${PSQL:-$(cygpath -m "$HOME" 2>/dev/null || echo "$HOME")/pgportable/pgsql/bin/psql.exe}"
PSQL_CMD=("$PSQL" -h 127.0.0.1 -p 5433 -U postgres -d onems_t -v ON_ERROR_STOP=1 -q -X -At)
export PGPASSWORD=postgres
PY=(python -I)
winpath() { if command -v cygpath >/dev/null; then cygpath -m "$1"; else echo "$1"; fi; }

die() { echo "ERROR: $*" >&2; exit 1; }

echo "== 1. rebuild onems_t (baseline + migrations) with the local harness"
bash "$ROOT/.superpowers/sdd/runlocal.sh" cl_masters
(cd "$ROOT" && git diff --quiet -- supabase/migrations/20261119100200_account_access_writes.sql) \
  || die "runlocal.sh left 20261119100200_account_access_writes.sql modified"
rm -rf "$OUT"; mkdir -p "$OUT"
"${PY[@]}" "$SIM/sim.py" generate --seed e2e-2026 --from 2026-10-26 --to 2026-11-15 --as-of 2026-11-16T03:00 \
  --out "$OUT/dataset"
read -r HASH PREFIX < <("${PY[@]}" "$SIM/sim.py" keygen --out "$OUT/carrier_key.txt" | tr -d '\r')
"${PSQL_CMD[@]}" -v key_hash="$HASH" -v key_prefix="$PREFIX" -f "$HERE/fixture.sql"

WORKER="$(winpath "$HERE/local_worker.ts")"
cat > "$OUT/config.json" <<JSON
{"mode": "local", "key_file": "carrier_key.txt", "seed": "e2e-2026", "dataset_dir": "dataset", "out_dir": "runs",
 "formats": ["jsonl", "csv"],
 "local": {"process_cmd": ["deno", "run", "--quiet", "--allow-read", "--allow-run", "--allow-env", "$WORKER"]}}
JSON

echo "== 1b. connector in Testing: two test deliveries of the first period (JSON Lines, then CSV)"
sed 's/"out_dir": "runs"/"out_dir": "runs-test"/' "$OUT/config.json" > "$OUT/config-test.json"
"${PSQL_CMD[@]}" -c "UPDATE public.cl_feeds SET status = 'testing' WHERE id = 'c1517000-0000-4000-8000-0000000000f1'" >/dev/null
"${PY[@]}" "$SIM/sim.py" deliver --config "$OUT/config-test.json" --max 1 --format jsonl
mv "$OUT/runs-test/2026-11-02_2026-11-04" "$OUT/runs-test/1-jsonl"
"${PY[@]}" "$SIM/sim.py" deliver --config "$OUT/config-test.json" --max 1 --format csv
mv "$OUT/runs-test/2026-11-02_2026-11-04" "$OUT/runs-test/2-csv"
"${PY[@]}" "$HERE/check.py" testing "$OUT/runs-test"
"${PSQL_CMD[@]}" -c "UPDATE public.cl_feeds SET status = 'active' WHERE id = 'c1517000-0000-4000-8000-0000000000f1'" >/dev/null

echo "== 2. first period with a tampered file"
"${PY[@]}" "$SIM/sim.py" deliver --config "$OUT/config.json" --max 1 --tamper
"${PY[@]}" "$HERE/check.py" tampered "$OUT/runs"

echo "== 3. every period in calendar order"
"${PY[@]}" "$SIM/sim.py" deliver --config "$OUT/config.json"
"${PY[@]}" "$HERE/check.py" deliveries "$OUT/runs" "$OUT/dataset"

echo "== 4. API answers"
FIRST="$(ls -d "$OUT"/runs/*_*/ | grep -v tampered | sort | head -1)"
# API paths without the leading "/" (Git Bash would rewrite "/x" into a Windows path).
call() { "${PY[@]}" "$SIM/sim.py" call --config "$OUT/config.json" "$@" >/dev/null; }
call --method POST --path deliveries --body "$FIRST/02-open-request.json" --save "$OUT/replay-open.json"
"${PY[@]}" "$HERE/check.py" expect "$OUT/replay-open.json" 200 -
"${PY[@]}" -c "import json,sys; b=json.load(open(sys.argv[1])); b['sha256']='0'*64; json.dump(b, open(sys.argv[2],'w'))" \
  "$FIRST/02-open-request.json" "$OUT/other-file.json"
call --method POST --path deliveries --body "$OUT/other-file.json" --save "$OUT/already-delivered.json"
"${PY[@]}" "$HERE/check.py" expect "$OUT/already-delivered.json" 409 CL_PERIOD_ALREADY_DELIVERED
"${PY[@]}" -c "import json,sys; b=json.load(open(sys.argv[1])); b.update(period_start='2026-11-16', period_end=sys.argv[3]); json.dump(b, open(sys.argv[2],'w'))" \
  "$FIRST/02-open-request.json" "$OUT/not-in-calendar.json" 2026-11-17
call --method POST --path deliveries --body "$OUT/not-in-calendar.json" --save "$OUT/not-in-calendar.resp.json"
"${PY[@]}" "$HERE/check.py" expect "$OUT/not-in-calendar.resp.json" 422 CL_PERIOD_NOT_IN_CALENDAR
"${PY[@]}" -c "import json,sys; b=json.load(open(sys.argv[1])); b.update(period_start='2026-11-16', period_end=sys.argv[3]); json.dump(b, open(sys.argv[2],'w'))" \
  "$FIRST/02-open-request.json" "$OUT/no-plan.json" 2026-11-18
call --method POST --path deliveries --body "$OUT/no-plan.json" --save "$OUT/no-plan.resp.json"
"${PY[@]}" "$HERE/check.py" expect "$OUT/no-plan.resp.json" 422 CL_NO_ACTIVE_PLAN
call --method GET --path deliveries/00000000-0000-4000-8000-000000000000 --save "$OUT/not-found.json"
"${PY[@]}" "$HERE/check.py" expect "$OUT/not-found.json" 404 CL_DELIVERY_NOT_FOUND
call --method GET --path demands --save "$OUT/gone.json"
"${PY[@]}" "$HERE/check.py" expect "$OUT/gone.json" 410 CL_ENDPOINT_GONE
call --method GET --path config --save "$OUT/config-after.json"
"${PY[@]}" "$HERE/check.py" expect "$OUT/config-after.json" 200 -

if [ "${SAVE_EXAMPLES:-}" = 1 ]; then
  for EX in "$SIM/examples" "$ROOT/docs/carrier-link/ejemplo"; do
    mkdir -p "$EX"; find "$EX" -maxdepth 1 -type f ! -name .gitattributes -delete   # keeps .gitattributes (byte-exact files)
    TAMP="$(ls -d "$OUT"/runs/*-tampered/ | head -1)"
    SECOND="$(ls -d "$OUT"/runs/*_*/ | grep -v tampered | sort | sed -n 2p)"
    cp "$FIRST/01-get-config.json"          "$EX/01-get-config.json"
    cp "$FIRST/delivery.jsonl"              "$EX/02-delivery-2026-11-02_2026-11-04.jsonl"
    cp "$FIRST/manifest.json"               "$EX/02-delivery-2026-11-02_2026-11-04.manifest.json"
    cp "$FIRST/02-open-request.json"        "$EX/03-open-request.json"
    cp "$FIRST/03-open-response.json"       "$EX/04-open-response.json"
    cp "$FIRST/04-upload-response.json"     "$EX/05-upload-response.json"
    cp "$FIRST/05-complete-response.json"   "$EX/06-complete-response.json"
    cp "$FIRST/06-status.json"              "$EX/07-status-processed.json"
    cp "$SECOND/delivery.csv"               "$EX/08-delivery-2026-11-05_2026-11-08.csv"
    cp "$SECOND/06-status.json"             "$EX/09-status-processed-csv.json"
    cp "$TAMP/05-complete-response.json"    "$EX/10-tampered-complete-response.json"
    cp "$TAMP/06-status.json"               "$EX/11-tampered-status-rejected.json"
    cp "$OUT/replay-open.json"              "$EX/12-replay-open-existing.json"
    cp "$OUT/already-delivered.json"        "$EX/13-error-already-delivered.json"
    cp "$OUT/not-in-calendar.resp.json"     "$EX/14-error-not-in-calendar.json"
    cp "$OUT/no-plan.resp.json"             "$EX/15-error-no-active-plan.json"
    cp "$OUT/not-found.json"                "$EX/16-error-delivery-not-found.json"
    cp "$OUT/gone.json"                     "$EX/17-error-v3-route-gone.json"
    cp "$OUT/config-after.json"             "$EX/18-get-config-after.json"
  done
  echo "examples refreshed in $SIM/examples and docs/carrier-link/ejemplo"
fi
echo "CARRIER SIMULATOR E2E: PASS"
