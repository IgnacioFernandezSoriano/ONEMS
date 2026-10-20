# Runbook de despliegue — Incidencias de indisponibilidad con resolución automática

**Proyecto destino:** `onems-dev` — ref **`sehbnpgzqljrsqimwyuz`** (la única BD del proyecto).
**Diseño:** `docs/superpowers/specs/2026-10-20-incidencias-indisponibilidad-resolucion-automatica-design.md`
**Plan:** `docs/superpowers/plans/2026-10-20-incidencias-indisponibilidad-1-base-datos.md`

> Antes de aplicar nada: confirmar que el proyecto es `onems-dev` (`sehbnpgzqljrsqimwyuz`) y
> pedir la confirmación explícita del responsable. Este runbook NO se ejecuta solo.

---

## 1. Qué cambia (en lenguaje claro)

Hasta ahora, cuando se daba de baja a un panelista, el sistema generaba propuestas y el manager
tenía que revisarlas una a una. Con este cambio:

- El sistema **resuelve solo** las muestras afectadas siempre que pueda: primero intenta
  **retrasar la fecha** de la muestra hasta que el panelista vuelva; si no cabe, la **pasa a otro
  nodo de la misma ciudad**; si tampoco, la deja **pendiente para el manager** con una sugerencia.
- Las muestras ya enviadas (`sent`/`received`) **no se tocan**: solo se informa.
- Se crea una **cola de avisos** (`panelist_notification`) para avisar al panelista de los cambios de
  la semana en curso. En este despliegue solo se crea la cola; Telegram/n8n la consumirán después.
- Se añade la función `declare_panelist_unavailability` para que n8n/Telegram pueda declarar bajas.
- Se reemplaza el motor antiguo (`generate_reassignment_proposals`) por el nuevo
  (`resolve_unavailability_incident`).

## 2. Migraciones, en este orden exacto

| # | Fichero (en `supabase/migrations/`) | Qué hace |
|---|---|---|
| 1 | `20261020130000_incident_schema` | Columnas y estados nuevos, tabla de avisos, `confirmed` pasa a `manager_resolved` |
| 2 | `20261020130100_incident_helpers` | Funciones auxiliares (carga por nodo, buscar fecha/nodo, encolar avisos, aplicar cambio) |
| 3 | `20261020130200_resolve_unavailability_incident` | Motor nuevo (el antiguo sigue existiendo hasta la 5) |
| 4 | `20261020130300_incident_manager_rpcs` | Funciones del manager (`suggest_for_week`, `apply_manager_decision`, `set_incident_resolution`); la función antigua `apply_reassignment_proposal` recalcula el estado y guarda la fecha original |
| 5 | `20261020130400_incident_triggers` | El trigger de la baja pasa a usar el motor nuevo y **borra el motor antiguo**; refresco por cambios del plan; guardas de la baja (no reactivar, no editar fechas); borrado de bajas y de muestras |
| 6 | `20261020130500_declare_panelist_unavailability` | Alta de bajas desde n8n y aviso "recibido" en altas web |
| 7 | `20261020130600_incident_backfill` | Puesta al día de las bajas existentes (sin avisos) |

> Ningún punto intermedio deja un trigger llamando a una función inexistente (el motor antiguo se borra
> en la 5, justo después de quitar el trigger que lo usaba). Aun así, las **siete se aplican en una sola
> sesión, seguidas y en orden**.

## 3. Cómo se aplican

Con la herramienta MCP `supabase-onems` → `apply_migration`, **una llamada por fichero**, usando como
`name` el nombre del fichero sin `.sql` (p. ej. `20261020130000_incident_schema`) y como `query` el
contenido completo del fichero. Tras cada una, ejecutar su verificación (sección 5) antes de pasar a
la siguiente. Si una falla: parar y avisar (ver sección 6).

**Instrucción al aplicar (NO está dentro de los ficheros):** para la **1 (`130000`)** y la **5
(`130400`)**, anteponer al `query` la línea `SET lock_timeout = '10s';`. Ambas toman bloqueos fuertes
sobre `allocation_plan_details` (la 1 añade una columna con `ALTER TABLE ... ADD COLUMN`; la 5 crea
triggers en esa tabla). El ETL escribe cada 30 minutos: **no aplicar a las :00 ni a las :30** (mejor
hacia :10–:20 o :40–:50). Si da error de `lock timeout`, no ha cambiado nada: esperar un minuto y
reintentar la misma migración.

## 4. Comprobaciones ANTES de aplicar (solo lectura)

```sql
-- Bajas activas vigentes (las que procesará la puesta al día) y cuántas muestras tocan
select u.id, p.name, u.start_date, u.end_date, u.reason, u.review_status,
       (select count(*) from allocation_plan_details a
         where a.account_id = u.account_id
           and (a.origin_node_id = p.node_id or a.destination_node_id = p.node_id)
           and a.status in ('pending','notified','sent','received')
           and a.fecha_programada between u.start_date and u.end_date) as muestras_afectadas
from panelist_unavailability u join panelists p on p.id = u.panelist_id
where u.status = 'active' and u.end_date >= current_date
order by u.start_date;

-- Propuestas existentes por estado ('confirmed' pasará a 'manager_resolved')
select status, count(*) from panelist_reassignment_proposal group by 1 order by 1;

-- El CHECK de motivos ya admite 'materials' (lo puso la migración 20260807100000)
select pg_get_constraintdef(oid) as definicion
  from pg_constraint where conname = 'panelist_unavailability_reason_check';
-- esperado: la definición contiene 'materials'

-- Estado actual: el motor antiguo existe, el nuevo no
select to_regprocedure('generate_reassignment_proposals(uuid)') as motor_antiguo,
       to_regprocedure('resolve_unavailability_incident(uuid,numeric,numeric)') as motor_nuevo;

-- Los CHECK que la migración 1 sustituye existen con ese nombre (si no, la 1 falla)
select conname from pg_constraint
 where conname in ('prp_status_check','prp_final_action_check') order by 1;   -- 2 filas

-- Nada de este despliegue existe ya (todo debe salir NULL / false)
select to_regprocedure('declare_panelist_unavailability(uuid,date,date,text,text)') as declare_fn,
       to_regprocedure('tg_refresh_incidents_on_plan_change()')                     as refresh_fn,
       to_regclass('panelist_notification')                                         as tabla_avisos,
       exists (select 1 from information_schema.columns
                where table_schema = 'public' and table_name = 'allocation_plan_details'
                  and column_name = 'original_fecha_programada')                    as col_fecha_original;
```

Si falta alguno de los dos CHECK, o si **cualquiera** de los cuatro objetos de la última consulta ya
existe, **parar y avisar al responsable/controlador**: la base no está en el estado esperado.

Lo visto el 2026-10-20 (solo lectura): 2 bajas vigentes (Petet y Nancy, ver sección 7), 12 propuestas
antiguas todas en `dismissed` (ninguna `confirmed`), motor antiguo presente y nuevo ausente. La tabla
`panelist_notification` aún no existe.

Si el CHECK de motivos **no** contiene `'materials'`, **parar**: la migración 6 (`130500`) ya no lo
amplía (se quitó para no bloquear la tabla), y `declare_panelist_unavailability` rechazaría ese motivo.
Hay que aplicar antes la migración `20260807100000` (o confirmar con el responsable).

## 5. Verificación DESPUÉS de cada migración (solo lectura)

**Tras 1 (`130000`):**
```sql
select to_regclass('public.panelist_notification') is not null as tabla_avisos,
       (select count(*) from information_schema.columns
         where table_name='panelist_unavailability'
           and column_name in ('incident_status','auto_summary','final_resolution','resolved_at')) as cols_baja; -- true, 4
select incident_status, count(*) from panelist_unavailability group by 1 order by 1;
select count(*) from panelist_reassignment_proposal where status = 'confirmed';   -- 0
```
**Tras 2 (`130100`):**
```sql
select to_regprocedure('public.panelist_local_today(uuid)') is not null as a,
       to_regprocedure('public.incident_enqueue_plan_change(uuid,text,date,date,uuid)') is not null as b;  -- true, true
select proname from pg_proc where pronamespace='public'::regnamespace and proname like 'incident\_%' order by 1;
```
**Tras 3 (`130200`):**
```sql
select to_regprocedure('public.resolve_unavailability_incident(uuid,numeric,numeric)') is not null as motor_nuevo,
       to_regprocedure('public.generate_reassignment_proposals(uuid)') is not null as motor_antiguo_sigue;  -- true, true
```

**Tras 4 (`130300`):**
```sql
select proname from pg_proc where pronamespace='public'::regnamespace
 and proname in ('suggest_for_week','apply_manager_decision','set_incident_resolution','apply_reassignment_proposal')
 order by 1;   -- 4 filas
```
**Tras 5 (`130400`):**
```sql
select tgname from pg_trigger where not tgisinternal and tgname in
 ('generate_proposals_on_unavailability_trigger','check_unavailability_panelist_account',
  'revert_on_unavailability_delete','refresh_incidents_on_plan_insert','refresh_incidents_on_plan_update',
  'recompute_incidents_on_plan_delete') order by 1;   -- 6 filas
select to_regprocedure('public.tg_unavailability_incident()') is not null as func_trigger_baja,
       to_regprocedure('public.generate_reassignment_proposals(uuid)') is null as motor_antiguo_borrado;   -- true, true
```
**Tras 6 (`130500`):**
```sql
select to_regprocedure('public.declare_panelist_unavailability(uuid,date,date,text,text)') is not null as declare_ok;  -- true
select count(*) from pg_trigger where tgname = 'enqueue_unavailability_received_trigger' and not tgisinternal;       -- 1
```
**Tras 7 (`130600`, la puesta al día):**
```sql
select incident_status, count(*) from panelist_unavailability group by 1 order by 1;   -- ninguna activa vigente en 'new'
select p.name, u.incident_status, u.auto_summary
  from panelist_unavailability u join panelists p on p.id = u.panelist_id
 where u.status = 'active' and u.end_date >= current_date;
select status, final_action, count(*) from panelist_reassignment_proposal group by 1,2 order by 1,2;
select count(*) from panelist_notification;    -- DEBE ser 0 (la puesta al día no manda avisos)
```
La propia migración 7 falla (`RAISE EXCEPTION`) si queda alguna baja activa vigente en `new`.

## 6. Rollback por migración

`apply_migration` ejecuta **cada fichero en una sola transacción**: si un fichero falla, no queda nada
de ese fichero a medias (se deshace entero). Lo que puede quedar es la cadena aplicada hasta el fichero
anterior; en ese caso, arreglar y seguir hacia delante o deshacer según lo de abajo.

Orden inverso. Revisar antes de ejecutar y pedir confirmación.

- **7 (`130600`):** los datos que cambia **no se revierten solos**. Cada muestra movida queda registrada
  en `allocation_plan_details` (`original_fecha_programada`, `original_origin_node_id`,
  `original_destination_node_id`) y con `reassignment_reason='panelist_unavailable'`, así que se puede
  deshacer a mano muestra a muestra desde ahí. Las líneas creadas se borran con
  `delete from panelist_reassignment_proposal where unavailability_id in (...)` y el estado de la baja con
  `update panelist_unavailability set incident_status='new', auto_summary=null, resolved_at=null where id in (...)`.
- **6 (`130500`):** `drop function public.declare_panelist_unavailability(uuid,date,date,text,text);`
  `drop trigger enqueue_unavailability_received_trigger on public.panelist_unavailability;`
  `drop function public.tg_enqueue_unavailability_received();`
- **5 (`130400`):** los triggers `check_unavailability_panelist_account` (guardas de la baja),
  `revert_on_unavailability_delete`, `refresh_incidents_on_plan_insert`, `refresh_incidents_on_plan_update` y
  `recompute_incidents_on_plan_delete` los **crea esta migración** (no existían antes), así que se deshacen con
  `drop trigger` (más sus funciones `tg_unavailability_check_panelist_account`, `tg_unavailability_delete`,
  `tg_refresh_incidents_on_plan_change`, `tg_recompute_incidents_on_plan_delete`, `incident_enqueue_revert`,
  `incident_revert_unavailability`). El trigger `generate_proposals_on_unavailability_trigger` **sí existía**
  antes: la migración lo borra y lo vuelve a crear apuntando a `tg_unavailability_incident()`. Esta migración
  también **borra el motor antiguo** `generate_reassignment_proposals`. Para restaurar el comportamiento anterior
  hay que recrear el motor antiguo (migración `20260804120500`), la función original
  `tg_generate_proposals_on_unavailability` y el trigger tal como estaban en `20260806120000` y `20260806140000`.
  Es preferible arreglar hacia delante.
- **4 (`130300`):** `drop function` de `suggest_for_week`, `apply_manager_decision`, `set_incident_resolution`;
  `apply_reassignment_proposal` se restaura con la versión anterior (migración `20260804121000`); devolver
  `grant execute` a `authenticated` sobre `apply_reassignment_proposals_bulk(uuid)` y a `anon` sobre
  `list_reroute_candidates(uuid,text)` si se quisiera el estado anterior exacto.
- **3 (`130200`):** `drop function` de `resolve_unavailability_incident`, `incident_suggest`,
  `incident_recompute_status`, `incident_find_node_for_sample` (el motor antiguo sigue ahí: esta migración ya
  no lo borra).
- **2 (`130100`):** `drop function` de las `incident_*` y `panelist_local_today`.
- **1 (`130000`):** esta migración también redefine `apply_reassignment_proposal` (cierra en
  `manager_resolved`): restaurar la definición anterior de `20260804121000` (coherente con la 4). Quitar las columnas nuevas (`incident_status`, `auto_summary`, `final_resolution`,
  `resolved_at` en la baja; `resolution_note`, `applied_at` en la propuesta; `original_fecha_programada`
  en el plan), `drop table panelist_notification` y restaurar los CHECK anteriores. Las propuestas
  `confirmed` convertidas a `manager_resolved` ya no se distinguen.

## 7. Resultado esperado de la puesta al día — KENYA NO SE TOCA

> **Decisión del responsable (2026-10-20): "deja a KENYA sin cambiar".** La migración 7 **excluye la
> cuenta KENYA** (`c4fe92f1-7673-41ae-9ed9-4b82d198be08`): no ejecuta el motor sobre sus bajas y **no
> cambia ninguna fila del plan de KENYA**. Hoy KENYA es la única cuenta con bajas vigentes (Nancy Weru
> 29/11–5/12 con 15 muestras afectadas; Petet Lokui Lokaale 16–20/11 con 8), así que la puesta al día
> **no cambia ningún dato del plan**: solo marca como `resolved` las bajas antiguas (canceladas o ya
> pasadas) que se quedaron en `new`.

Qué queda en KENYA tras aplicar:
- Nancy Weru: `incident_status='new'`, 0 líneas. Petet: `resolved` (ya estaba revisada).
- Ninguna muestra movida, ningún aviso.

Importante: **desde ahora, cualquier cambio de FECHA o de NODO en el plan de KENYA que caiga dentro de
esas bajas hace que el motor procese la baja afectada** (es el refresco automático por cambios del plan,
spec 5.6). Si quieres que KENYA siga totalmente quieto hasta decidirlo, no apliques ni muevas planes de
KENYA hasta entonces.

Para procesar KENYA más adelante (cuando se decida), por baja:
`select public.resolve_unavailability_incident('<id de la baja>');` (mueve muestras reales; los avisos de
la semana en curso sí se mandarían, así que mejor hacerlo con calma y avisando).

## 8. Qué NO hace este despliegue

- No manda avisos por cambios antiguos (la puesta al día va con los avisos suprimidos).
- No toca muestras `sent`/`received`: solo informa.
- No incluye Telegram/n8n ni la pantalla nueva del manager: llegan en los planes 2 y 3.
- **Cambio de comportamiento para la web actual:** desde la migración 5, la base **rechaza** editar las fechas
  de una baja activa ("Dates of an active unavailability cannot be edited; cancel and declare a new one") y
  reactivar una baja cancelada. Si alguien usa "editar fechas" en la web actual verá un error; lo correcto es
  cancelar la baja y declarar otra (spec 5.7/5.8). Borrar una baja activa ahora revierte primero su impacto.
- **Edge function `propose-reassignments`:** sigue desplegada en Supabase. El frontend ya no la llama,
  así que se puede **eliminar justo después de aplicar las migraciones** (dashboard → Edge Functions, o
  MCP). Pedir confirmación antes.

## 9. Qué verá el usuario

- Al crear una baja, la incidencia aparece ya con las muestras resueltas automáticamente ("resuelta
  automáticamente") o "pendiente del manager" si alguna no cupo.
- Las bajas antiguas ya revisadas siguen como "resueltas". Las de KENYA no se recalculan por decisión del responsable (ver sección 7).
- La pantalla nueva del manager llega con el frontend (plan 2); mientras tanto los datos ya estarán listos.

## 10. Registro de la ejecución real

_(pendiente: se rellena al aplicar — fecha/hora, resultado de cada verificación, líneas creadas por baja)_
