#!/usr/bin/env bash
# Carrier simulator - automated end-to-end test. LOCAL ONLY: Postgres portable 127.0.0.1:5433, database onems_t,
# rebuilt from the repo migrations by .superpowers/sdd/runlocal.sh. Never touches the remote project.
#
#   1. rebuild onems_t; generate the carrier dataset (fixed seed); connector key (hash only in the DB); fixture.sql;
#   2. emit the demand with cl_emit_due_demands('2026-11-19 06:05+03') (weeks 2026-W45/W46 are due);
#   3. connector in local mode, row limit 100 (several batches): dry run -> check.py dry;
#   4. same demand, real batches (ingest + draw + one_db) -> check.py real;
#   5. replay of batch 01 (same batch_id) -> stored summary, nothing sampled again;
#   6. a new batch_id for the now fulfilled demand -> HTTP 409 CL_DEMAND_NOT_OPEN.
# SAVE_EXAMPLES=1 also refreshes tools/carrier-simulator/examples/ from this run (worked example of the manual).
#
# Usage: bash tools/carrier-simulator/e2e/run.sh
# If interrupted during step 1: git checkout supabase/migrations/20261119100200_account_access_writes.sql
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$SIM/../.." && pwd)"
OUT="$SIM/out/e2e"
PSQL=(/c/Users/fernandezi/pgportable/pgsql/bin/psql.exe -h 127.0.0.1 -p 5433 -U postgres -d onems_t -v ON_ERROR_STOP=1 -q -X -At)
export PGPASSWORD=postgres
PY=(python -I)

die() { echo "ERROR: $*" >&2; exit 1; }

echo "== 1. rebuild onems_t (baseline + migrations) with the local harness"
bash "$ROOT/.superpowers/sdd/runlocal.sh" cl_masters
(cd "$ROOT" && git diff --quiet -- supabase/migrations) || die "runlocal.sh left supabase/migrations modified"
rm -rf "$OUT"; mkdir -p "$OUT"
"${PY[@]}" "$SIM/sim.py" generate --seed e2e-2026 --from 2026-10-26 --to 2026-11-15 --as-of 2026-11-19T06:00 \
  --out "$OUT/dataset"
read -r HASH PREFIX < <("${PY[@]}" "$SIM/sim.py" keygen --out "$OUT/carrier_key.txt" | tr -d '\r')
"${PSQL[@]}" -v key_hash="$HASH" -v key_prefix="$PREFIX" -f "$HERE/fixture.sql"

echo "== 2. emit the demand"
n=$("${PSQL[@]}" -c "SELECT public.cl_emit_due_demands(timestamptz '2026-11-19 06:05:00+03')" | tr -d '\r')
[ "$n" = 1 ] || die "expected 1 demand, got $n"

cat > "$OUT/config.json" <<'JSON'
{"mode": "local", "key_file": "carrier_key.txt", "seed": "e2e-2026", "dataset_dir": "dataset", "out_dir": "runs",
 "dry_run": true, "max_rows": 100}
JSON

echo "== 3. dry run"
"${PY[@]}" "$SIM/sim.py" run --config "$OUT/config.json" --dry-run
RUN="$(ls -d "$OUT"/runs/*/ | head -1)"
cp "$OUT/runs/get-demands.json" "$OUT/get-demands.before.json"
"${PY[@]}" "$HERE/check.py" dry "$RUN" "$OUT/dataset"

echo "== 4. real batches"
"${PY[@]}" "$SIM/sim.py" run --config "$OUT/config.json" --real
"${PY[@]}" "$HERE/check.py" real "$RUN" "$OUT/dataset"

echo "== 5. replay of batch 01"
"${PY[@]}" "$SIM/sim.py" post --config "$OUT/config.json" --real --file "$RUN/batch-01.json" --save "$OUT/replay.json" >/dev/null
"${PY[@]}" "$HERE/check.py" replay "$RUN" "$OUT/replay.json"

echo "== 6. new batch for the fulfilled demand"
"${PY[@]}" -c "import json,sys; b=json.load(open(sys.argv[1])); b['batch_id'] += '-late'; json.dump(b, open(sys.argv[2], 'w'))" \
  "$RUN/batch-01.json" "$OUT/late-batch.json"
"${PY[@]}" "$SIM/sim.py" post --config "$OUT/config.json" --real --file "$OUT/late-batch.json" --save "$OUT/late.json" >/dev/null \
  && die "a batch for a closed demand was accepted"
"${PY[@]}" "$HERE/check.py" expect "$OUT/late.json" 409 CL_DEMAND_NOT_OPEN

if [ "${SAVE_EXAMPLES:-}" = 1 ]; then
  EX="$SIM/examples"
  rm -f "$EX"/*.json; mkdir -p "$EX"
  last=$(ls "$RUN"/response-*.json | grep -v dry_run | sort | tail -1)
  cp "$OUT/get-demands.before.json"   "$EX/01-get-demands.json"
  cp "$RUN/batch-01.json"             "$EX/02-batch-01.json"
  cp "$RUN/response-01.dry_run.json"  "$EX/03-response-01-dry-run.json"
  cp "$RUN/response-01.json"          "$EX/04-response-01.json"
  cp "$last"                          "$EX/05-response-last-batch.json"
  cp "$OUT/replay.json"               "$EX/06-response-replay-batch-01.json"
  cp "$OUT/late.json"                 "$EX/07-response-demand-not-open.json"
  cp "$RUN/manifest.json"             "$EX/08-connector-manifest.json"
  echo "examples refreshed in $EX"
fi
echo "CARRIER SIMULATOR E2E: PASS"
