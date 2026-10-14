# Runbook de despliegue — RPC `list_reroute_candidates` (subsistema C)

**Proyecto destino:** `onems-dev` — ref **`sehbnpgzqljrsqimwyuz`** (la única BD del proyecto).
**Todo por el dashboard web de Supabase.** Ejecuta los pasos **en orden**. En un momento de poca actividad.

> ⚠️ Antes de nada: en el dashboard, arriba a la izquierda, **confirma que el proyecto
> seleccionado es `onems-dev`** (ref `sehbnpgzqljrsqimwyuz`). Si no, cámbialo. No sigas hasta verlo.

---

## Paso 1 — Migración: RPC de solo lectura (SQL Editor)

1. Dashboard → **SQL Editor** → **New query**.
2. Abre en el repo el fichero
   `supabase/migrations/20260805114233_list_reroute_candidates.sql`,
   **copia TODO su contenido** y pégalo en el editor.
3. Pulsa **Run**.
4. Debe decir *Success. No rows returned*. Crea la RPC `list_reroute_candidates` de solo lectura,
   que devuelve candidatos de reencaminado (nodos activos de la misma ciudad, con disponibilidad
   evaluada en la fecha de la muestra).

## Paso 2 — Verificación rápida (SQL Editor)

Pega y ejecuta esto. Debe salir `ok = 1`:

```sql
select count(*) as ok from pg_proc where proname = 'list_reroute_candidates';  -- ok = 1
```

---

## Nota sobre el historial de migraciones (opcional)

Como aplicas por el SQL Editor (no por el CLI), la tabla `supabase_migrations.schema_migrations`
no registra esta versión. Si en el futuro usas el CLI de Supabase, regístrala para que no
intente reaplicarla:

```sql
insert into supabase_migrations.schema_migrations (version) values ('20260805114233')
on conflict do nothing;
```
