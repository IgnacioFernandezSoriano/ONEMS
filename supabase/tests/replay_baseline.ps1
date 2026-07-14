# ============================================================
# replay_baseline.ps1 — valida el baseline de prod en el Postgres portable local
# ============================================================
# BD limpia (onems_base) -> bootstrap-shim -> baseline. Para en el primer error.
# NO toca produccion.
# ============================================================
$ErrorActionPreference = "Continue"
$PGBIN = "C:\Users\fernandezi\pgportable\pgsql\bin"
$env:PGPASSWORD = "postgres"
$H="127.0.0.1"; $P="5433"; $U="postgres"; $DB="onems_base"
$REPO = "c:\Users\fernandezi\projects\ONEMS"
$SHIM = Join-Path $REPO "supabase\tests\00_bootstrap_supabase_shim.sql"
$BASE = Join-Path $REPO "supabase\migrations\00000000000000_baseline_prod_schema.sql"

function psqlAdmin($sql) { & (Join-Path $PGBIN "psql.exe") -h $H -p $P -U $U -d postgres -v ON_ERROR_STOP=1 -c $sql }
function psqlFile($file) { & (Join-Path $PGBIN "psql.exe") -h $H -p $P -U $U -d $DB -v ON_ERROR_STOP=1 -q -f $file 2>&1 }

Write-Host "== BD limpia $DB ==" -ForegroundColor Cyan
psqlAdmin "DROP DATABASE IF EXISTS $DB WITH (FORCE);" | Out-Null
psqlAdmin "CREATE DATABASE $DB;" | Out-Null
psqlAdmin ('ALTER DATABASE ' + $DB + ' SET search_path TO public, extensions;') | Out-Null

Write-Host "== shim ==" -ForegroundColor Cyan
$o = psqlFile $SHIM
if ($LASTEXITCODE -ne 0) { Write-Host "SHIM FALLO:" -ForegroundColor Red; $o; exit 1 }

Write-Host "== baseline ==" -ForegroundColor Cyan
$o = psqlFile $BASE
if ($LASTEXITCODE -ne 0) {
  Write-Host "BASELINE FALLO:" -ForegroundColor Red
  $o | Select-Object -Last 30
  exit 1
}
Write-Host "BASELINE aplico sin error." -ForegroundColor Green
Write-Host ""
Write-Host "== conteos local vs prod-esperado ==" -ForegroundColor Cyan
& (Join-Path $PGBIN "psql.exe") -h $H -p $P -U $U -d $DB -c @"
select
 (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r') as tablas,
 (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='v') as vistas,
 (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public') as funcs,
 (select count(*) from pg_policies where schemaname='public') as policies,
 (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and not t.tgisinternal) as triggers;
"@
Write-Host "Prod esperado: tablas 60 . vistas 15 . funcs 92 . policies 262 . triggers 74" -ForegroundColor Yellow
