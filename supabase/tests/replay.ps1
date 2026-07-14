# ============================================================
# replay.ps1 — reproduce supabase/migrations en el Postgres portable local
# ============================================================
# Recrea una BD limpia (onems_test), aplica el bootstrap-shim y corre TODAS las
# migraciones en orden, parando en el PRIMER error (bucle fix -> replay -> repetir).
#
# Uso:
#   powershell -File supabase\tests\replay.ps1
#
# Requiere el Postgres portable arrancado en 127.0.0.1:5433 (ver README).
# NO toca producción: es una BD local en tu máquina.
# ============================================================
# Continue (no Stop): psql emite NOTICE por stderr y en PS5.1 eso dispararia un
# error terminante. Gestionamos el exito con $LASTEXITCODE a mano.
$ErrorActionPreference = "Continue"
$PGBIN = "C:\Users\fernandezi\pgportable\pgsql\bin"
$env:PGPASSWORD = "postgres"
$H = "127.0.0.1"; $P = "5433"; $U = "postgres"
$DB = "onems_test"
$REPO = "c:\Users\fernandezi\projects\ONEMS"
$MIG  = Join-Path $REPO "supabase\migrations"
$SHIM = Join-Path $REPO "supabase\tests\00_bootstrap_supabase_shim.sql"

function psqlAdmin($sql) {
  & (Join-Path $PGBIN "psql.exe") -h $H -p $P -U $U -d postgres -v ON_ERROR_STOP=1 -c $sql
}
function psqlFile($file) {
  & (Join-Path $PGBIN "psql.exe") -h $H -p $P -U $U -d $DB -v ON_ERROR_STOP=1 -q -f $file 2>&1
}

Write-Host "== Recreando BD limpia $DB ==" -ForegroundColor Cyan
psqlAdmin "DROP DATABASE IF EXISTS $DB WITH (FORCE);" | Out-Null
psqlAdmin "CREATE DATABASE $DB;" | Out-Null
# Supabase incluye 'extensions' en el search_path por defecto (uuid_generate_v4, etc.)
psqlAdmin ('ALTER DATABASE ' + $DB + ' SET search_path TO public, extensions;') | Out-Null

Write-Host "== Aplicando bootstrap-shim ==" -ForegroundColor Cyan
$out = psqlFile $SHIM
if ($LASTEXITCODE -ne 0) { Write-Host "SHIM FALLO:" -ForegroundColor Red; $out; exit 1 }
Write-Host "   shim OK" -ForegroundColor Green

# Migraciones en orden lexicográfico (como hace la CLI de Supabase)
$files = Get-ChildItem $MIG -Filter *.sql | Sort-Object Name
Write-Host "== Reproduciendo $($files.Count) migraciones ==" -ForegroundColor Cyan
$i = 0
foreach ($f in $files) {
  $i++
  $out = psqlFile $f.FullName
  if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "############################################################" -ForegroundColor Red
    Write-Host "FALLO en migracion #$i : $($f.Name)" -ForegroundColor Red
    Write-Host "############################################################" -ForegroundColor Red
    $out | Select-Object -Last 25
    Write-Host ""
    Write-Host ">> Arregla '$($f.Name)' y vuelve a correr replay.ps1" -ForegroundColor Yellow
    exit 1
  }
  Write-Host ("  [{0,3}/{1}] OK  {2}" -f $i, $files.Count, $f.Name) -ForegroundColor DarkGreen
}
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "TODAS las $($files.Count) migraciones aplicaron sin error." -ForegroundColor Green
Write-Host "El repo reconstruye la BD desde cero. Gap cerrado." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
