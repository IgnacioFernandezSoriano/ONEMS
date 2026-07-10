# Release a producción — ONEMS — 2026-07-10

Lleva `develop` (31 commits) a prod (`main`). Ejecución **manual por dashboard**
(sin acceso automatizado a prod). Marca cada casilla al completarla.

## ⚠️ ACTUALIZACIÓN (tras pre-flight): UNA SOLA BD COMPARTIDA
ONEMS tiene **un único proyecto Supabase** `sehbnpgzqljrsqimwyuz` (onems-dev).
"prod/dev" = **solo la rama de git + el deploy de frontend** (main y develop
apuntan a la MISMA base). El pre-flight reveló que la BD **ya está casi al día**
(la mayoría de migraciones se aplicaron a mano contra esta base). Por tanto el
plan de 8 pasos de abajo se **colapsa a 2 acciones reales**:

1. **Delta de BD** (5 migraciones idempotentes) → `2026-07-10-prod-db-delta.sql`
   - Solo estaban desfasadas: `normalize_provider_tag` y `consolidate_rfid_events`.
   - Ya AL DÍA / hechos: monitoring (schema+rol+password), cron jobid 4, landing,
     scope filter, incidents unknown_tag, índice readers, y el fix
     `prevent_account_id_change` (ya arreglado en la base).
2. **Merge `develop` → `main` + push** (Paso 7) → despliega el frontend nuevo.

Los pasos 3, 4, 5, 6 de abajo (edge function, Vault, cron, password) **NO hacen
falta**: ya están en la base. Se dejan documentados por si algún día hay un prod
separado.

- Único project-ref: `sehbnpgzqljrsqimwyuz`

## Alcance
- 16 migraciones (15 de features + 1 fix `prevent_account_id_change`)
- 1 edge function: `rfid-provider-poll`
- 1 cron (30 min) + baja del ETL-only de 15 min
- 1 rol `monitoring_reader` (password out-of-band)
- Merge `develop` → `main` (dispara deploy de frontend)

## Orden REAL (no es orden de timestamp)
1. Pre-flight (solo lectura) en prod
2. Aplicar 15 migraciones + fix (Grupo A, idempotentes)
3. Desplegar edge function `rfid-provider-poll` + secrets
4. Crear secrets en Vault
5. Aplicar migración del cron (Grupo B) — **la última**
6. Password del rol `monitoring_reader`
7. Merge `develop` → `main` + push
8. Verificación (smoke test)

---

## Paso 1 — PRE-FLIGHT (solo lectura, no cambia nada)

### Query A — metadatos (siempre seguro de ejecutar)
```sql
with c as (
  select 1 ord, 'ext:pg_cron'                       k, case when exists(select 1 from pg_extension where extname='pg_cron') then 'yes' else 'NO' end v
  union all select 2, 'ext:pg_net',                    case when exists(select 1 from pg_extension where extname='pg_net') then 'yes' else 'NO' end
  union all select 3, 'ext:supabase_vault',            case when exists(select 1 from pg_extension where extname='supabase_vault') then 'yes' else 'NO' end
  union all select 4, 'col:panelists.city_id',         case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='panelists' and column_name='city_id') then 'yes' else 'NO' end
  union all select 5, 'col:panelists.address_city',    case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='panelists' and column_name='address_city') then 'yes' else 'NO' end
  union all select 6, 'col:readers.deleted_at',        case when exists(select 1 from information_schema.columns where table_schema='public' and table_name='readers' and column_name='deleted_at') then 'yes' else 'NO' end
  union all select 7, 'obj:schema monitoring',         case when exists(select 1 from information_schema.schemata where schema_name='monitoring') then 'YA EXISTE' else 'no' end
  union all select 8, 'obj:role monitoring_reader',    case when exists(select 1 from pg_roles where rolname='monitoring_reader') then 'YA EXISTE' else 'no' end
  union all select 9, 'obj:table rfid_provider_reads', case when exists(select 1 from information_schema.tables where table_schema='public' and table_name='rfid_provider_reads') then 'YA EXISTE' else 'no' end
  union all select 10,'obj:fn normalize_provider_tag', case when exists(select 1 from pg_proc where proname='normalize_provider_tag') then 'YA EXISTE' else 'no' end
  union all select 11,'obj:fn resolve_provider_reads', case when exists(select 1 from pg_proc where proname='resolve_provider_reads') then 'YA EXISTE' else 'no' end
  union all select 12,'fn:prevent_account_id_change tiene NEW.role', case when exists(select 1 from pg_proc where proname='prevent_account_id_change' and pg_get_functiondef(oid) like '%NEW.role%') then 'SI (revisar)' else 'no' end
)
select k as chequeo, v as resultado from c order by ord;
```

### Query B — duplicados de reader_id (ejecuta SOLO si A dice `col:readers.deleted_at = yes`)
```sql
-- Debe devolver 0 filas. Si devuelve filas, hay que deduplicar (soft-delete) antes del Paso 2.
select reader_id, count(*) as activos
from public.readers
where deleted_at is null
group by reader_id
having count(*) > 1;
```
Si `readers.deleted_at` = NO, avísame: `readers_reader_id_unique` asume soft-delete.

### Query C — cron actual (ejecuta SOLO si A dice `ext:pg_cron = yes`)
```sql
select jobid, jobname, schedule, active from cron.job order by jobid;
```

**Pega aquí los resultados de A, B y C antes de seguir.**

---

## Paso 2 — Migraciones Grupo A (aplicar en este orden)
Pegar el contenido de cada `.sql` en el SQL Editor, en orden. Todas idempotentes.
1. `20260611000000_panelist_city_normalization.sql`  *(backfill de datos)*
2. `20260611120000_rfid_provider_landing.sql`
3. `20260611120100_normalize_provider_tag.sql`
4. `20260611120200_resolve_provider_reads.sql`
5. `20260611120250_readers_reader_id_unique.sql`  *(requiere Query B = 0 filas)*
6. `20260612100000_monitoring_contract.sql`
7. `20260612100100_monitoring_reader_role.sql`
8. `20260616120000_readers_superadmin_write_policies.sql`
9. `20260616123000_normalize_provider_tag_upu_element.sql`
10. `20260616130000_fix_pipeline_ambiguous_column.sql`
11. `20260616130100_incidents_allow_unknown_tag.sql`
12. `20260616130200_consolidate_capture_non_onedb.sql`
13. `20260616140000_fix_pipeline_assembly_read.sql`
14. `20260616140100_consolidate_unconsolidated_flag.sql`
15. `20260616150000_resolve_provider_reads_scope_filter.sql`
16. `20260709120000_fix_prevent_account_id_change_no_role.sql`  *(el fix)*

> Tras el pre-flight genero un **script consolidado** en orden para pegar de una vez.

---

## Paso 3 — Edge function `rfid-provider-poll`
- Desplegar la función a prod (dashboard → Edge Functions, o CLI si se autoriza).
- Secrets de la función (Settings → Edge Functions → Secrets):
  - `RFID_PROVIDER_API_URL` = `__________`
  - `RFID_PROVIDER_API_KEY` = `__________`
  - `CRON_SECRET` = `__________` (genera uno aleatorio; se reutiliza en Vault)

## Paso 4 — Secrets en Vault
```sql
select vault.create_secret('https://<PROD_REF>.supabase.co/functions/v1/rfid-provider-poll', 'rfid_poll_function_url');
select vault.create_secret('<EL_MISMO_CRON_SECRET_DEL_PASO_3>', 'rfid_poll_cron_secret');
```

## Paso 5 — Migración del cron (la ÚLTIMA)
- Aplicar `20260611120300_rfid_poll_cron.sql`.
- Desengancha `rfid-pipeline-every-15min` (si existe) y crea `rfid-provider-poll-every-30min`.
- Si faltan los secrets del Vault, **aborta sin dañar nada** (transaccional).

## Paso 6 — Password del rol monitoring_reader
```sql
ALTER ROLE monitoring_reader WITH LOGIN PASSWORD '<secret-generado>';
```
Entregar el password a la plataforma externa por canal seguro.

## Paso 7 — Merge a main
```bash
git checkout main && git pull
git merge develop            # develop ya contiene todo lo de main; merge limpio
git push origin main         # dispara deploy del frontend
git checkout develop
```

## Paso 8 — Verificación (smoke test en prod)
- [ ] Login OK
- [ ] Country Topology: editar un nodo y guardar (Update) → persiste  *(valida el fix del trigger)*
- [ ] Materials / Carriers: un Update cualquiera → persiste
- [ ] Panelists: dropdown de ciudad scopeado a cuenta; residencia = city_id
- [ ] Readers Management (superadmin): escritura OK
- [ ] `select * from monitoring.health;` responde
- [ ] `select jobname, active from cron.job;` muestra `rfid-provider-poll-every-30min` activo
- [ ] Esperar un ciclo (30 min) y revisar `rfid_provider_reads` / `rfid_ingest_state`
