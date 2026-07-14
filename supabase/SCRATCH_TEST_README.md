# Probar la reconstrucción de la BD en scratch LOCAL (Opción A)

Objetivo: verificar que el repo (`supabase/migrations/`, incluida la catch-up
`20260714000000_catchup_orphan_objects.sql`) reconstruye la BD desde cero, **sin
tocar producción** (`sehbnpgzqljrsqimwyuz`).

El "entorno scratch" es la **BD local en Docker** que levanta Supabase. `db reset`
va SIEMPRE contra esa BD local. Producción es intocable porque **nunca hacemos
`link`**.

---

## Requisitos (una vez)

1. **Docker Desktop** instalado y corriendo. (Es el único prerrequisito que faltaba.)
2. Node/npx ya lo tienes (`node-portable`). La CLI de Supabase se ejecuta con `npx`.

Ya hecho por Claude: `supabase init` → creó `supabase/config.toml`
(project_id `ONEMS`, Postgres `major_version = 17`, que coincide con prod 17.6).

---

## Pasos

Desde la raíz del repo (`c:\Users\fernandezi\projects\ONEMS`), en PowerShell:

```powershell
# 1. Levanta el stack local (Postgres + Auth + Storage...) en Docker
npx supabase start

# 2. Reconstruye la BD local: replay de TODAS las migraciones + seed
npx supabase db reset
```

- `db reset` DROPa la BD **local**, corre las migraciones en orden y luego el seed
  (`seed.sql`, configurado en `config.toml [db.seed]`).
- Si termina **sin error** → el repo reconstruye la BD completa. ✅
- Al terminar de trastear: `npx supabase stop` (apaga los contenedores).

---

## Cómo comprobar que TODO funciona (verificación en 4 niveles)

### Nivel 0 — el reset no da error
Si `npx supabase db reset` termina con `Finished ... reset` y **exit code 0**, las
129 migraciones + la catch-up + el seed aplicaron sin fallo. Es la primera señal.

### Nivel 1 — conteos rápidos
El Postgres local corre dentro del contenedor `supabase_db_ONEMS`. No necesitas
psql en tu máquina: lo usas DENTRO del contenedor con `docker exec`.

```powershell
docker exec -i supabase_db_ONEMS psql -U postgres -d postgres -c "
  select
    (select count(*) from information_schema.tables  where table_schema='public' and table_type='BASE TABLE') as tablas,
    (select count(*) from information_schema.views   where table_schema='public') as vistas,
    (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and prokind='f') as funcs;"
```
Esperado (igual que prod): **tablas 60 · vistas 15 · funcs 92**.

### Nivel 2 — diff EXACTO contra producción (la prueba de verdad)
`_prod_schema_snapshot.txt` es la firma real de prod (503 líneas: tablas, vistas,
funciones con args, policies, triggers), capturada por Claude. Sacamos la misma
firma de LOCAL y las comparamos:

```powershell
# 1. genera la firma local (objetos del esquema public) usando el script versionado
docker exec -i supabase_db_ONEMS psql -U postgres -d postgres -t -A -f - `
  < supabase\tests\verify_catchup.sql `
  | Sort-Object `
  | Set-Content -Encoding utf8 supabase\tests\_local_schema_snapshot.txt

# 2. compara local vs prod. Si NO imprime nada => esquema idéntico ✅
Compare-Object `
  (Get-Content supabase\tests\_prod_schema_snapshot.txt) `
  (Get-Content supabase\tests\_local_schema_snapshot.txt)
```
- `Compare-Object` sin salida = **paridad total**: el repo reconstruye prod.
- Líneas con `=>` = están en local pero no en prod (raro).
- Líneas con `<=` = **faltan en local** → algo de la catch-up (o una migración) no
  aplicó. Ese es exactamente el objeto a investigar.

### Nivel 3 — smoke test de la app
`npx supabase start` imprime `API URL` (http://127.0.0.1:54321) y una `anon key`
local. Apunta el frontend a esas dos variables (en un `.env.local` de prueba) y
levanta la app: login, un par de pantallas que usen las tablas nuevas
(stock/materiales, SLA, diagnosis). Si cargan datos sin error 500/relación
inexistente, el esquema local sirve a la app igual que prod.

> Nota: en local las tablas están **vacías** (salvo lo que cree `seed.sql`), así que
> valida que las pantallas *cargan* y las queries *no rompen*, no que haya datos.

---

## ⚠️ Seguridad — NO tocar producción

- **NUNCA** ejecutes `npx supabase link --project-ref sehbnpgzqljrsqimwyuz` seguido
  de `db reset`/`db push`. Eso sí iría contra la base viva.
- En scratch local (`supabase start` + `db reset`) es **imposible** romper prod:
  todo ocurre en Docker, en tu máquina.

---

## 🔧 Remediación pendiente (hacer DURANTE el reset local, no a ciegas)

La auditoría del 2026-07-14 (aplicando las migraciones a un scratch) destapó
reset-breakers reales. Dos ya se arreglaron; el resto necesita el bucle
`fix → db reset → ver siguiente error → repetir`, por eso NO se tocaron a ciegas.

**Ya arreglado (seguro, sin riesgo):**
- ✅ `generate_epcis_test_data.sql` movido a `supabase/tests/adhoc/` (eran datos de
  prueba con error de sintaxis, no esquema).
- ✅ `fix_detect_missing_exits.sql` renombrado a
  `20260709130000_fix_detect_missing_exits.sql` (necesitaba prefijo de timestamp).

**Pendiente (requiere reset local para verificar cada cambio):**
1. `20260210120000_consolidation_functions_part2.sql`: usa `timestamp` (palabra
   reservada) como nombre de columna en 3 funciones → error de sintaxis. Prod la
   tiene como `"timestamp"` (con comillas). Fix: reemplazar las 3 funciones por su
   definición real de prod (`pg_get_functiondef`) o entrecomillar cada `timestamp`.
2. Migraciones "rework" que hacen `CREATE OR REPLACE FUNCTION` cambiando el tipo de
   retorno SIN `DROP` previo → `ERROR 42P13` en un reset limpio. Afecta a:
   `20260211000003_fix_reconstruct_return_types`, `20260211000004_fix_find_applicable_sla_types`,
   `20260211010002/020001_update_pipeline_with_assembly`, `20260211020000_assemble_journeys_adapted`,
   `20260211030001_calculate_working_hours_adapted`, `20260211030002_update_calculate_adjusted_time`.
   Fix: añadir `DROP FUNCTION IF EXISTS <nombre>(<args viejos>);` antes del CREATE.
3. `20260612100100_monitoring_reader_role.sql`: asume el esquema `monitoring` ya
   creado (`3F000: schema "monitoring" does not exist`). Verificar orden/creación.
4. La catch-up `20260714000000` NO se pudo validar (fallo en cascada por lo anterior);
   su contenido es DDL exacto de prod, pero confírmala en el reset limpio.

> Método correcto: `npx supabase db reset` → falla en la migración X → arreglas X →
> repites. En pocas iteraciones el reset pasa entero. Hacerlo así (con verificación)
> evita reintroducir divergencias con prod.

---

## 🪤 Trampas conocidas del repo (pueden hacer fallar el reset)

Detectadas al auditar `supabase/migrations/`. Si `db reset` falla, mira aquí primero:

1. **Archivos sin convención de nombre** — la CLI ordena los `.sql`
   lexicográficamente; los que empiezan por letra ordenan DESPUÉS de los que
   empiezan por dígito, así que corren **al final, incluso después de la catch-up**:
   - `fix_detect_missing_exits.sql`  → parche suelto sin timestamp.
   - `generate_epcis_test_data.sql`  → **datos de prueba**, no esquema; quizá no
     quieras que corra en un reset. Considera renombrarlo fuera de `migrations/`
     o moverlo a `seed`.

2. **Números de migración duplicados** (`008`, `011`, `021`, `022`, `202`) — dos
   archivos compiten por el mismo paso. En un reset corren los dos en orden
   alfabético; si uno reemplazaba al otro, podría dar error de "ya existe".

3. **Objetos droppeados en prod** que alguna migración intermedia crea y otra
   posterior elimina (p.ej. `account_reporting_config`, `get_city_classification`).
   El reset los crea y luego los borra: es correcto, pero genera ruido.

4. Si una migración antigua asume un objeto creado a mano en prod (y que ahora
   solo existe en la catch-up), el orden importa: la catch-up corre penúltima
   (antes solo de los dos archivos con nombre de letra). Si algo la necesita antes,
   habrá que reordenar.

---

## Si el reset pasa limpio

El repo ya vuelve a ser fuente de verdad reproducible. Siguientes pasos opcionales:
- Commitear la catch-up + este README + `config.toml`.
- Archivar las ~7 migraciones "muertas" (cosmético).
- Mover `generate_epcis_test_data.sql` fuera de `migrations/`.
