# Runbook de despliegue — Motor de reasignación por baja (subsistema B)

**Proyecto destino:** `onems-dev` — ref **`sehbnpgzqljrsqimwyuz`** (la única BD del proyecto).
**Todo por el dashboard web de Supabase.** Ejecuta los pasos **en orden**. En un momento de poca actividad.

> ⚠️ Antes de nada: en el dashboard, arriba a la izquierda, **confirma que el proyecto
> seleccionado es `onems-dev`** (ref `sehbnpgzqljrsqimwyuz`). Si no, cámbialo. No sigas hasta verlo.

---

## Paso 1 — Migración 1/3: esquema (SQL Editor)

1. Dashboard → **SQL Editor** → **New query**.
2. Abre en el repo el fichero
   `supabase/migrations/20260804120000_reassignment_proposals_schema.sql`,
   **copia TODO su contenido** y pégalo en el editor.
3. Pulsa **Run**.
4. Debe decir *Success. No rows returned*. Crea la tabla `panelist_reassignment_proposal`,
   la columna `review_status` y **quita el trigger automático** de reasignación.

## Paso 2 — Migración 2/3: motor `generate` (SQL Editor)

1. **New query**.
2. Copia TODO el contenido de
   `supabase/migrations/20260804120500_generate_reassignment_proposals.sql` y pégalo.
3. **Run** → *Success*.
4. Esto crea la RPC `generate_reassignment_proposals` **y** re-crea la función
   `get_panelist_for_node` con el arreglo de tipos (mejora un bug latente del baseline).

## Paso 3 — Migración 3/3: RPCs `apply` + bulk (SQL Editor)

1. **New query**.
2. Copia TODO el contenido de
   `supabase/migrations/20260804121000_apply_reassignment_proposals.sql` y pégalo.
3. **Run** → *Success*.

## Paso 4 — Verificación rápida (SQL Editor)

Pega y ejecuta esto. Deben salir las 4 filas indicadas:

```sql
-- 1) La tabla existe
select 'tabla' as check, count(*) as ok
from information_schema.tables
where table_schema='public' and table_name='panelist_reassignment_proposal';   -- ok = 1

-- 2) La columna review_status existe
select 'review_status' as check, count(*) as ok
from information_schema.columns
where table_schema='public' and table_name='panelist_unavailability'
  and column_name='review_status';                                              -- ok = 1

-- 3) El trigger automático YA NO existe
select 'trigger_fuera' as check, count(*) as ok
from pg_trigger where tgname='reassign_on_unavailability_trigger';              -- ok = 0

-- 4) Las 3 RPCs existen
select 'rpcs' as check, count(*) as ok
from pg_proc
where proname in ('generate_reassignment_proposals',
                  'apply_reassignment_proposal',
                  'apply_reassignment_proposals_bulk');                          -- ok = 3
```

## Paso 5 — Edge Function `propose-reassignments`

1. Dashboard → **Edge Functions** → **Deploy a new function** (o **Create function**).
2. Nombre exacto: **`propose-reassignments`**.
3. Abre `supabase/functions/propose-reassignments/index.ts` en el repo, copia TODO y pégalo
   en el editor de la función (reemplazando la plantilla por defecto).
4. **Deploy**.
5. No hay que configurar secretos: `SUPABASE_URL` y `SUPABASE_ANON_KEY` los inyecta Supabase
   automáticamente en el runtime de las edge functions.

## Paso 6 — Frontend (cuando quieras)

El frontend nuevo (que dispara el motor al crear una baja) está en `develop` **sin pushear**.
Cuando hagas `git push` de `develop`, el auto-deploy publica el frontend. Hazlo **después** de
los pasos 1-5 para que el hook no llame a una función/tablas que aún no existan.

---

## Prueba end-to-end (opcional, recomendable)

Tras el Paso 5, en la app (como manager de una cuenta con allocation plan activo):
1. Crea una **baja temporal** de un panelista que tenga muestras en el rango de fechas.
2. En la BD, comprueba que se generaron propuestas:
   ```sql
   select affected_role, suggested_action, count(*)
   from public.panelist_reassignment_proposal
   where unavailability_id = '<id_de_la_baja>'
   group by 1,2;
   ```
   (La pantalla del manager para revisarlas/confirmarlas es el **subsistema C**, aún por construir.
   De momento las propuestas se ven en BD; el plan **no se muta** hasta que exista C y se confirme.)

---

## Rollback

**Solo revertir el comportamiento** (volver a la reasignación automática de antes) — la función
`reassign_on_unavailability()` se conservó, así que basta recrear el trigger:

```sql
CREATE TRIGGER reassign_on_unavailability_trigger
AFTER INSERT OR UPDATE ON public.panelist_unavailability
FOR EACH ROW EXECUTE FUNCTION reassign_on_unavailability();
```

**Revertir todo** (quitar el motor por completo):

```sql
DROP FUNCTION IF EXISTS public.apply_reassignment_proposals_bulk(uuid);
DROP FUNCTION IF EXISTS public.apply_reassignment_proposal(uuid, text, uuid, date);
DROP FUNCTION IF EXISTS public.generate_reassignment_proposals(uuid);
DROP TABLE IF EXISTS public.panelist_reassignment_proposal;
ALTER TABLE public.panelist_unavailability DROP COLUMN IF EXISTS review_status;
-- (y, si quieres, recrear el trigger como arriba)
```
> El fix de `get_panelist_for_node` es una mejora; se puede dejar aunque se revierta el resto.

---

## Nota sobre el historial de migraciones (opcional)

Como aplicas por el SQL Editor (no por el CLI), la tabla `supabase_migrations.schema_migrations`
no registra estas 3 versiones. Si en el futuro usas el CLI de Supabase, regístralas para que no
intente reaplicarlas:

```sql
insert into supabase_migrations.schema_migrations (version) values
  ('20260804120000'), ('20260804120500'), ('20260804121000')
on conflict do nothing;
```
