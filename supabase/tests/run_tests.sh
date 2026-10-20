#!/usr/bin/env bash
# Runner local: reconstruye onems_t (shim + migraciones) y ejecuta tests de supabase/tests.
# Uso: bash supabase/tests/run_tests.sh [test_name ...]   (sin args: todos los *.test.sql)
# Solo toca el Postgres portable local (127.0.0.1:5433); nunca la BD remota.
PG=/c/Users/fernandezi/pgportable/pgsql/bin
export PGPASSWORD=postgres
H=(-h 127.0.0.1 -p 5433 -U postgres)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG="$(mktemp)"

if ! "$PG/pg_isready.exe" "${H[@]}" >/dev/null 2>&1; then
  echo "Postgres local no responde. Arrancalo con:"
  echo "  \"$PG/pg_ctl.exe\" -D /c/Users/fernandezi/pgportable/data -l /c/Users/fernandezi/pgportable/pg.log -o \"-p 5433\" start"
  exit 2
fi

"$PG/psql.exe" "${H[@]}" -d postgres -v ON_ERROR_STOP=1 -q >"$LOG" 2>&1 <<SQL || { tail -n 15 "$LOG"; exit 2; }
DROP DATABASE IF EXISTS onems_t WITH (FORCE);
CREATE DATABASE onems_t;
ALTER DATABASE onems_t SET search_path TO public, extensions;
SQL

for f in "$ROOT/supabase/tests/00_bootstrap_supabase_shim.sql" "$ROOT"/supabase/migrations/*.sql; do
  if ! "$PG/psql.exe" "${H[@]}" -d onems_t -v ON_ERROR_STOP=1 -q -f "$f" >"$LOG" 2>&1; then
    echo "ERROR aplicando $(basename "$f"):"; tail -n 15 "$LOG"; exit 2
  fi
done

if [ $# -gt 0 ]; then
  TESTS=("$@")
else
  TESTS=(); for t in "$ROOT"/supabase/tests/*.test.sql; do b="$(basename "$t" .test.sql)"; TESTS+=("$b"); done
fi

pass=0; fail=0
for name in "${TESTS[@]}"; do
  name="${name%.test.sql}"
  file="$ROOT/supabase/tests/$name.test.sql"
  if [ ! -f "$file" ]; then echo "FAIL $name (no existe $file)"; fail=$((fail+1)); continue; fi
  if "$PG/psql.exe" "${H[@]}" -d onems_t -q -v ON_ERROR_STOP=1 -f "$file" >"$LOG" 2>&1; then
    echo "PASS $name"; pass=$((pass+1))
  else
    echo "FAIL $name"; tail -n 20 "$LOG"; fail=$((fail+1))
  fi
done
rm -f "$LOG"
echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
