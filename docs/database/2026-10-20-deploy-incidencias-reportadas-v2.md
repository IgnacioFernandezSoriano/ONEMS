# Despliegue — Incidencias reportadas v2 (base de datos)

**Migración:** `supabase/migrations/20261020170000_reported_incidents_v2.sql` (una sola, forward-only).
**Proyecto:** onems-dev `sehbnpgzqljrsqimwyuz` (la única BD; "prod" y "dev" apuntan aquí).
**Test local:** `bash supabase/tests/run_tests.sh reported_incidents_v2` → PASS (2026-10-21).
**Plan / spec:** `docs/superpowers/plans/2026-10-20-incidencias-reportadas-v2-1-base-datos.md`, `docs/superpowers/specs/2026-10-20-incidencias-reportadas-tratamiento-v2-design.md`.

## Qué cambia

1. `panelist_incident.status` admite `auto_resolved` (CHECK ampliado; superconjunto del anterior, ninguna fila existente lo viola).
2. `create_unavailability_from_incident` acepta la razón `materials` (antes la convertía en `other`).
3. `update_panelist_contact_v2(…9 parámetros…)` con validación (email, teléfono, idioma, dirección ≤ 200) y Telegram protegido cuando llama n8n; la firma antigua `update_panelist_contact(uuid,text,text,text)` queda como wrapper. **Ojo:** la firma antigua ahora valida teléfono e idioma (p. ej. `(555) 123-4567` o `Spanish` se rechazan).
4. `insert_panelist_incident_auto(…)` — alta desde n8n con `account_id` derivado del panelista.
5. `suggest_reroute_returned_sample(…)` / `reroute_returned_sample(…)` — vista previa y reenvío de una muestra devuelta a otro nodo de la misma ciudad.
6. `list_nodes_for_sample_move(…)` — nodos candidatos (misma ciudad, sin origen ni destino actual).
7. **Cierre de agujero pre-existente:** `REVOKE … FROM PUBLIC, anon` en 9 RPCs antiguas (`resolve_panelist_incident`, `mark_detail_received_manual`, `invalidate_detail`, `reschedule_detail`, `cancel_detail`, `create_unavailability_from_incident`, `send_material_shipment`, `receive_material_shipment`, `find_surplus_donors`) que tenían EXECUTE para `anon` por privilegio por defecto. `authenticated` (y `service_role` donde ya lo tenía o lo necesita n8n) conservan el acceso.

## Comprobaciones previas (hechas el 2026-10-21 por la Management API, solo lectura)

- Las 14 firmas que la migración toca o usa existen en la BD viva (`to_regprocedure`): ✅.
- Los cuerpos vivos de `create_unavailability_from_incident` y `update_panelist_contact` son los del repo (`20260806160000`): no hay hot-fixes que se pierdan ✅.
- `pi_status_check` vivo = el antiguo; 0 filas con estados fuera de la lista ✅.
- Roles conectados: `authenticator` (PostgREST), `postgres`, `supabase_admin`. n8n entra por el pooler como `postgres` (dueño de las funciones): el REVOKE no le afecta ✅. Roles personalizados existentes (`baptiste_admin`, `supabase_etl_admin`, `monitoring_reader`, `supabase_privileged_role`) **pierden el EXECUTE que tenían por PUBLIC** sobre esas 9 RPCs; si alguno las necesita, `GRANT EXECUTE … TO <rol>` explícito.

## Aplicación

1. Confirmación explícita del usuario (proyecto + ref).
2. `apply_migration` (MCP supabase-onems) con el contenido íntegro del fichero. Postgres la ejecuta en una transacción: si algo falla, no queda nada a medias.
3. PostgREST recarga el esquema solo (event trigger de Supabase); si una RPC nueva diera 404 desde la web, `NOTIFY pgrst, 'reload schema';`.

## Comprobaciones posteriores

```sql
select pg_get_constraintdef(oid) from pg_constraint where conname = 'pi_status_check';  -- contiene auto_resolved
select proname, pg_get_function_identity_arguments(oid) from pg_proc
 where proname in ('insert_panelist_incident_auto','reroute_returned_sample','suggest_reroute_returned_sample',
                   'list_nodes_for_sample_move','update_panelist_contact','update_panelist_contact_v2')
 order by 1,2;  -- 6 filas
select f, has_function_privilege('anon', f, 'EXECUTE') as anon, has_function_privilege('authenticated', f, 'EXECUTE') as auth
  from unnest(array['public.resolve_panelist_incident(uuid,text,text,text)','public.mark_detail_received_manual(uuid)',
   'public.invalidate_detail(uuid,text)','public.reschedule_detail(uuid,date)','public.cancel_detail(uuid)',
   'public.create_unavailability_from_incident(uuid,date,date,text)','public.update_panelist_contact(uuid,text,text,text)',
   'public.update_panelist_contact_v2(uuid,text,text,text,text,text,text,text,text)','public.send_material_shipment(uuid)',
   'public.receive_material_shipment(uuid)','public.find_surplus_donors(uuid,uuid,uuid,numeric)',
   'public.insert_panelist_incident_auto(uuid,text,text,jsonb,uuid,text)','public.reroute_returned_sample(uuid,uuid,date)',
   'public.suggest_reroute_returned_sample(uuid,uuid,date)','public.list_nodes_for_sample_move(uuid)']) f;  -- anon=false, auth=true en las 15
```

## Vuelta atrás (solo si hace falta)

- Estado: `ALTER TABLE panelist_incident DROP CONSTRAINT pi_status_check; ALTER TABLE … ADD CONSTRAINT pi_status_check CHECK (status IN ('open','in_progress','resolved','dismissed'));` **solo si no hay filas `auto_resolved`**.
- `DROP FUNCTION` de `insert_panelist_incident_auto`, `reroute_returned_sample`, `suggest_reroute_returned_sample`, `list_nodes_for_sample_move`, `update_panelist_contact_v2`.
- Recrear `create_unavailability_from_incident` y `update_panelist_contact` con el cuerpo de `20260806160000_panelist_incident.sql`.
- **No** devolver EXECUTE a `anon`: el cierre del punto 7 es un arreglo de seguridad y debe mantenerse.
