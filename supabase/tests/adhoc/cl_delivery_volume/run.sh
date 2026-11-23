#!/usr/bin/env bash
# Volumen de la tarea 2 (v4). SOLO LOCAL (Postgres portable 127.0.0.1:5433); nunca la base remota.
# Requiere onems_t recien construida (bash .superpowers/sdd/runlocal.sh <algun test>). Copia onems_t en onems_vol,
# carga fixture.sql (2.000.000 filas en la zona de paso) y ejecuta los pasos de la base uno a uno; cada SELECT es su
# propia transaccion, igual que entre los COMMIT de cl_delivery_process_run. Mide cada paso. Despues mide
# cl_delivery_load_rows con lotes de 10.000 filas (lo que manda el worker). Borra onems_vol al terminar.
#   bash supabase/tests/adhoc/cl_delivery_volume/run.sh [filas_por_paso]   (por defecto 100000)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHUNK="${1:-100000}"
P=/c/Users/fernandezi/pgportable/pgsql/bin/psql.exe
export PGPASSWORD=postgres
C=(-h 127.0.0.1 -p 5433 -U postgres -v ON_ERROR_STOP=1 -q -X -At)
"$P" "${C[@]}" -d postgres -c "DROP DATABASE IF EXISTS onems_vol WITH (FORCE)" -c "CREATE DATABASE onems_vol TEMPLATE onems_t"
trap '"$P" "${C[@]}" -d postgres -c "DROP DATABASE IF EXISTS onems_vol WITH (FORCE)"' EXIT

t0=$(date +%s%N)
"$P" "${C[@]}" -d onems_vol -f "$HERE/fixture.sql"
echo "fixture (2M filas por generate_series): $(( ($(date +%s%N) - t0) / 1000000 )) ms"

STEPS="$(mktemp)"
{ echo '\timing on'; for i in $(seq 1 300); do echo "SELECT public.cl_process_delivery(NULL, $CHUNK);"; done; } > "$STEPS"
t0=$(date +%s%N)
"$P" "${C[@]}" -d onems_vol -f "$STEPS" | awk '
  /^Time:/ { ms = $2; if (phase != "idle") { n++; tot += ms; if (ms > max) { max = ms; maxp = phase };
             cnt[phase]++; sum[phase] += ms; if (ms > pmax[phase]) pmax[phase] = ms } ; next }
  { phase = $1 }
  END { for (p in cnt) printf "  %-9s pasos %3d  total %9.0f ms  max %8.0f ms\n", p, cnt[p], sum[p], pmax[p];
        printf "TOTAL %d pasos, %.0f ms; paso mas largo %.0f ms (%s)\n", n, tot, max, maxp }'
echo "reloj: $(( ($(date +%s%N) - t0) / 1000000 )) ms"
rm -f "$STEPS"

"$P" "${C[@]}" -d onems_vol -c "SELECT status, rows_total, rows_rejected, shipments_total, shipments_valid, shipments_drawn, rejected_reasons FROM public.cl_deliveries WHERE id = 'de000000-0000-0000-0000-0000000000f1'"
"$P" "${C[@]}" -d onems_vol -c "SELECT 'staging rows/items', (SELECT count(*) FROM public.cl_delivery_rows), (SELECT count(*) FROM public.cl_delivery_items)"
"$P" "${C[@]}" -d onems_vol -c "SELECT 'strata', count(*), sum(population), sum(quota_for_delivery), sum(selected) FROM public.cl_delivery_strata"
"$P" "${C[@]}" -d onems_vol -c "SELECT 'quotas', status, count(*) FROM public.cl_plan_quotas WHERE account_id = 'a0000000-0000-0000-0000-0000000000f1' GROUP BY status ORDER BY status"
"$P" "${C[@]}" -d onems_vol -c "SELECT 'samples/one_db', (SELECT count(*) FROM public.cl_samples WHERE delivery_id = 'de000000-0000-0000-0000-0000000000f1'), (SELECT count(*) FROM public.one_db WHERE source = 'carrier')"

# Carga: 5 lotes de 10.000 filas por cl_delivery_load_rows (otra entrega, en fase load).
"$P" "${C[@]}" -d onems_vol -c "INSERT INTO public.cl_deliveries (id, account_id, feed_id, period_start, period_end, source, format, compression, file_path, file_bytes, sha256, status, received_at) VALUES ('de000000-0000-0000-0000-0000000000f2','a0000000-0000-0000-0000-0000000000f1','f0000000-0000-0000-0000-0000000000f1','2026-11-17','2026-11-23','api','jsonl','none','vol/f/d2.jsonl', 300000000, repeat('b', 64), 'received', now())" \
     -c "SELECT 'claim ' || (public.cl_delivery_worker_claim('token-vol-0001')->>'action')"
LOAD="$(mktemp)"
{ echo '\timing on'
  for b in 0 1 2 3 4; do
    echo "SELECT public.cl_delivery_load_rows('de000000-0000-0000-0000-0000000000f2', 'token-vol-0001', $((b*1000000)), (SELECT jsonb_agg(jsonb_build_object('n', $((b*10000)) + g, 'r', jsonb_build_object('trk', 'TRK' || lpad(g::text, 9, '0'), 'svc', 'EXP', 'ts', '2026-11-18 08:00', 'office', 'P1', 'name', 'Persona'))) FROM generate_series(1, 10000) g), jsonb_build_object('offset', $(((b+1)*1000000)), 'rows', $(((b+1)*10000)), 'sha', NULL, 'sha_offset', $(((b+1)*1000000)), 'header', NULL))->>'stop';"
  done; } > "$LOAD"
"$P" "${C[@]}" -d onems_vol -f "$LOAD" | grep '^Time' | sed 's/^/  load_rows 10k: /'
rm -f "$LOAD"
