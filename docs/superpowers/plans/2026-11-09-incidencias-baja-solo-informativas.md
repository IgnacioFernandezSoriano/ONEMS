# Incidencias de baja solo informativas: plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Al declarar una baja, el motor resuelve solo todas las muestras afectadas: las retrasa, las pasa a otro nodo, las lleva a una semana posterior o las anula. La incidencia queda solo informativa: nunca hay líneas `pending` ni estado `pending_manager`.

**Architecture:** Todo el cambio de comportamiento está en PL/pgSQL y va en una migración nueva que re-emite funciones vivas.
- `resolve_unavailability_incident` añade un paso final, "resolver pendientes", que aplica `incident_suggest` o anula.
- `incident_apply_change` y `incident_apply_cancel` toleran las muestras ya anuladas y propagan a las otras bajas.
- Una segunda migración hace la puesta al día de los datos.
- El frontend quita el bloque «Pending your decision» y deja una sola tabla informativa.

**Tech Stack:** Postgres 17 (PL/pgSQL), tests SQL sobre el Postgres local 5433 (`supabase/tests/run_tests.sh`), React 18 + TypeScript + Vite, i18n con 4 CSV.

**Spec:** `docs/superpowers/specs/2026-11-09-incidencias-baja-solo-informativas-design.md`. Enmienda a `docs/superpowers/specs/2026-10-20-incidencias-indisponibilidad-resolucion-automatica-design.md`, que sigue vigente en todo lo que no se contradice.

## Global Constraints

- **BD única:** onems-dev `sehbnpgzqljrsqimwyuz`, compartida con producción.
  - Ninguna tarea escribe en la BD remota salvo la Tarea 6, y siempre tras confirmar con el usuario nombrando el proyecto y su ref.
  - Prohibido `supabase db push` y `supabase db reset`.
- **La BD viva va por delante del repo.** Toda función re-emitida parte de su definición VIVA: `select pg_get_functiondef('public.<fn>(<args>)'::regprocedure)` por el MCP de solo lectura, guardada en el scratchpad. No se parte de la migración antigua. Si lo vivo y la última migración del repo difieren en algo ajeno a esta tarea, se conserva lo vivo.
- **Migraciones:** forward-only, `supabase/migrations/20261109180000_incident_auto_only.sql` (funciones) y `supabase/migrations/20261109180100_incident_auto_only_catchup.sql` (puesta al día). No tocar el baseline ni las migraciones anteriores.
- **Permisos:** `CREATE OR REPLACE` conserva los permisos. Toda función NUEVA lleva `REVOKE ALL ... FROM PUBLIC, anon, authenticated` y `GRANT EXECUTE ... TO service_role`, salvo `incident_attention_counts`, que mantiene los suyos.
- **Umbrales:** 6 / 20 % (carga de referencia / desviación); horizonte de 8 semanas (56 días), el de `incident_suggest`.
- **Motivos (`suggested_reason`) nuevos:** `handled_by_other_incident` y `engine_error`. Los que ya existían y ahora aparecen en líneas `auto_resolved`: `shift_later_week`, `alt_node_later_week` y `no_slot_8_weeks`.
- **Nunca** se toca una muestra `sent`/`received`, nunca se mueve a otra ciudad, nunca se satura un nodo.
- **Ninguna muestra anulada se reactiva.** No se crea ninguna vía para ello (decisión del usuario).
- **Frontend:** texto visible solo vía `useTranslation()`, con claves en los 4 CSV de `public/locales/`. `npm run lint` y `npm run build` en verde.
- **Git:** rama `feat/incidencias-baja-informativas` desde `develop`. Commits con `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Push y PR solo en la Tarea 6, con permiso del usuario.

## Review Focus

1. **Muestra con origen y destino de baja a la vez.** Una baja la mueve a una fecha que cae en la otra baja. Lo esperado: la otra baja la resuelve también, sin quedar `pending` y sin bucle infinito. Test en la Tarea 2: `twin_move_reevaluates`.
2. **Línea antigua `pending` cuya muestra ya está anulada por otra baja** (los 13 casos reales). Lo esperado: pasa a `info` / `handled_by_other_incident` sin error y sin tocar la muestra. Tests en la Tarea 1 (`legacy_cancelled_line_info`) y la Tarea 2 (`apply_cancel_already_cancelled`).
3. **Fallo inesperado al aplicar una muestra.** Lo esperado: esa línea queda `info` / `engine_error` y las demás de la misma baja se resuelven igual. Test en la Tarea 1: `engine_error_isolated`.
4. **Muestra `notified` del mismo día de la baja.** Lo esperado: se mueve o se anula. Una `sent` del mismo día no se toca y queda `info`. Test en la Tarea 1: `notified_today_resolved_sent_untouched`.
5. **Pantalla con incidencias antiguas en `pending_manager` o con líneas `pending`** antes de la puesta al día. Lo esperado: la pantalla no se rompe y muestra esas líneas en la tabla única como «pendiente» sin botones. Comprobación manual en la Tarea 4.

---

### Task 1: Motor: resolver todo, nunca dejar pendientes

**Files:**
- Create: `supabase/migrations/20261109180000_incident_auto_only.sql`
- Create: `supabase/tests/incident_auto_only.test.sql`
- Modify (expectativas que cambian): `supabase/tests/resolve_unavailability_incident.test.sql`, `supabase/tests/incident_manager_rpcs.test.sql`, `supabase/tests/incident_move_to_cell.test.sql`, `supabase/tests/incident_triggers.test.sql`

**Interfaces:**
- Consumes (vivas, sin cambios de firma):
  - `incident_suggest(p_proposal_id uuid, p_week_start date, p_reference_load numeric, p_deviation_percent numeric) → jsonb {found, date, node_id, ...}`
  - `incident_apply_change(p_proposal_id uuid, p_new_date date, p_new_node_id uuid, p_mode text)`: si el nodo es NULL, solo cambia la fecha.
  - `incident_apply_cancel(p_proposal_id uuid, p_mode text)`
- Produces:
  - `incident_resolve_pending_lines(p_unavailability_id uuid, p_reference_load numeric DEFAULT 6, p_deviation_percent numeric DEFAULT 20) RETURNS integer`: número de líneas que cierra.
  - `resolve_unavailability_incident` (misma firma) la llama justo antes de `incident_recompute_status`.
  - `incident_recompute_status` (misma firma) ya no devuelve nunca `pending_manager`.

**Comportamiento de `incident_resolve_pending_lines`.** Por cada línea `pending` de la baja, en orden `fecha_programada, id`, y cada una en su propio subbloque `BEGIN…EXCEPTION`:
1. Si la muestra ya no está `pending`/`notified`:
   - si está `cancelled`, la línea pasa a `status='info'`, `final_action='none'`, `suggested_reason='handled_by_other_incident'`;
   - si está `sent`/`received`, la línea pasa a `info` con el motivo `already_sent` o `in_transit`, con la regla del paso (b) del motor.
2. Si no, `s := incident_suggest(line, NULL, ref, dev)`.
   - Con `found`:
     - si `node_id` es el nodo de la baja → `incident_apply_change(line, s.date, NULL, 'auto')` y `suggested_reason='shift_later_week'`;
     - si no → `incident_apply_change(line, s.date, s.node_id, 'auto')` y `suggested_reason='alt_node_later_week'`.
   - Sin `found` → `incident_apply_cancel(line, 'auto')` y `suggested_reason='no_slot_8_weeks'`.
3. Si salta EXCEPTION, la línea pasa a `status='info'`, `final_action='none'`, `suggested_reason='engine_error'`, `resolution_note=SQLERRM`. Se emite un `RAISE WARNING`.

**Paso (a) de `resolve_unavailability_incident`.** Se mantiene el DELETE de líneas pending que ya no aplican, con una excepción: las de muestras `cancelled` no se borran, se dejan para que las cierre `incident_resolve_pending_lines` (punto 1).

**Paso (b), muestra `cancelled`.** Sigue sin generar línea (spec del 20/10). `handled_by_other_incident` solo aparece en líneas que ya existían.

- [ ] **Step 1: Volcar las definiciones vivas al scratchpad.** Por el MCP de solo lectura: `resolve_unavailability_incident(uuid,numeric,numeric)`, `incident_recompute_status(uuid)`, `incident_apply_change(uuid,date,uuid,text)` e `incident_apply_cancel(uuid,text)`. Compararlas con la última migración del repo que las define y anotar en el ledger las diferencias que haya.

- [ ] **Step 2: Escribir `supabase/tests/incident_auto_only.test.sql` con las utilidades `pg_temp.mk/fill/baja/run/line` copiadas de `resolve_unavailability_incident.test.sql`.**
  - Formato: un escenario por `BEGIN … ROLLBACK`, con `\ir fixtures/incident_city.sql` y `\ir fixtures/no_incident_triggers.sql`.
  - Cada escenario hace `RAISE EXCEPTION 'FAIL <escenario> ...'` si falla y `RAISE NOTICE 'PASS <escenario>'` si pasa.

  | Escenario | Preparación | Lo que se comprueba |
  |---|---|---|
  | `later_week_same_node` | Baja de P1 del 2027-03-22 al 03-31, de modo que no quede ningún día del mes tras la baja. Muestra N1→N4 el 03-24. `fill('N2','2027-03-01','2027-03-29',8)` y lo mismo para N3: marzo lleno para los pasos 2/2b, incluida la semana del 03-29 al 04-04. N1 sin relleno. | Línea `auto_resolved`, `final_action='shift_date'`, `final_date='2027-04-01'`, `suggested_reason='shift_later_week'`. Muestra con `status='pending'` y `original_fecha_programada='2027-03-24'`. Baja con `incident_status='auto_resolved'`. |
  | `later_week_other_node` | Lo mismo, más `fill('N1','2027-04-01','2027-05-27',8)` (jueves, fuera de la baja). | `final_action='reroute'`, `final_target_node_id`=N2, `final_date='2027-04-05'`, `suggested_reason='alt_node_later_week'`. |
  | `cancel_no_slot` | Lo mismo, más `fill('N2','2027-04-05','2027-05-24',8)` y lo mismo para N3. El horizonte termina el 05-19. | Muestra `cancelled`, línea `auto_resolved`, `final_action='cancel'`, `suggested_reason='no_slot_8_weeks'`. |
  | `never_pending` | Tras cada escenario anterior. | `count(*) FILTER (WHERE status='pending') = 0` en la baja e `incident_status <> 'pending_manager'`. |
  | `legacy_pending_line_resolved` | Muestra con línea `pending` insertada a mano (`suggested_action='cancel'`), como las del motor viejo. Hay hueco el 04-05. | Tras `run()`, la línea queda `auto_resolved` y la muestra se mueve. |
  | `legacy_cancelled_line_info` | Línea `pending` insertada a mano sobre una muestra ya `cancelled`. | Tras `run()`: línea `info`, `suggested_reason='handled_by_other_incident'`; muestra sin cambios en `updated_at` y `status`. |
  | `engine_error_isolated` | Dos muestras afectadas, sin hueco las dos. Trigger temporal `BEFORE UPDATE` sobre `allocation_plan_details` que hace `RAISE` solo para la muestra X. | Línea de X: `info` / `engine_error` / `resolution_note` no vacío. Línea de Y: `auto_resolved` / `cancel`. Baja: `auto_resolved`. |
  | `notified_today_resolved_sent_untouched` | Baja que empieza `current_date`, ajustada a día laborable. Muestra A `notified` y muestra B `sent`, ambas en `current_date`. | A resuelta (movida o anulada, línea `auto_resolved`). B `sent`, sin cambios, línea `info`. |

- [ ] **Step 3: Ejecutar el test y ver que falla.**
  Run: `bash supabase/tests/run_tests.sh incident_auto_only`
  Expected: FAIL en `later_week_same_node`; la línea queda `pending`.

- [ ] **Step 4: Escribir la migración `20261109180000_incident_auto_only.sql`.**
  - Cabecera en castellano llano: qué cambia y por qué, con referencia a la spec.
  - Contenido:
    - `incident_resolve_pending_lines` (nueva, con permisos solo `service_role`);
    - `resolve_unavailability_incident` re-emitida desde la definición viva, con los cambios del paso (a) y la llamada final;
    - `incident_recompute_status` re-emitida con `v_status := CASE WHEN c.n_manager > 0 THEN 'resolved' ELSE 'auto_resolved' END`. Una línea `pending` residual no cambia el estado, pero sigue contando en `auto_summary` como `pending=`.

- [ ] **Step 5: Ejecutar el test y ver que pasa.**
  Run: `bash supabase/tests/run_tests.sh incident_auto_only`
  Expected: PASS en los 8 escenarios.

- [ ] **Step 6: Actualizar los tests antiguos que esperaban `pending` / `pending_manager` del motor.**
  - Los escenarios que comprobaban «queda pendiente con propuesta X» pasan a comprobar que la propuesta X se ha APLICADO (`auto_resolved`, mismo destino o fecha) o que la muestra se ha anulado.
  - Los tests de `apply_manager_decision`, `apply_manager_move` y `suggest_for_*` necesitan una línea `pending`: se crean insertándola a mano, no a través del motor. Esas funciones siguen existiendo.
  - Cada expectativa cambiada lleva un comentario `-- 2026-11-09: el motor ya no deja pendientes`.
  - Run: `bash supabase/tests/run_tests.sh`
  - Expected: todos PASS, salvo los fallos ajenos que ya existieran antes, que se apuntan en el ledger con su nombre.

- [ ] **Step 7: Commit.** `feat(incidents): el motor de bajas resuelve todas las muestras, sin decision del manager`

### Task 2: Muestras compartidas entre dos bajas

**Files:**
- Modify: `supabase/migrations/20261109180000_incident_auto_only.sql` (añadir al final)
- Modify: `supabase/tests/incident_auto_only.test.sql` (escenarios nuevos)

**Interfaces:**
- Consumes: `incident_resolve_pending_lines` y `resolve_unavailability_incident`, de la Tarea 1.
- Produces:
  - `incident_close_twin_lines(p_detail_id uuid, p_except_proposal_id uuid) RETURNS integer`:
    - si la muestra está `cancelled`, pasa a `info` / `handled_by_other_incident` toda línea `pending` de esa muestra en OTRA baja;
    - después recalcula el estado de cada baja tocada.
  - `incident_refresh_other_incidents(p_detail_id uuid, p_except_unavailability_id uuid) RETURNS integer`:
    - ejecuta `resolve_unavailability_incident` para cada baja `active` con `end_date >= current_date`, distinta de la excepción, cuyo panelista tenga como nodo el origen o el destino ACTUAL de la muestra y cuyo rango cubra su `fecha_programada` actual;
    - limita la profundidad con `current_setting('onems.incident_refresh_depth', true)`: máximo 3 niveles, incrementando antes de llamar y restaurando después.
  - `incident_apply_cancel` (misma firma):
    - si la muestra ya está `cancelled`, NO lanza excepción: la línea pasa a `info` / `handled_by_other_incident` y la función termina;
    - si la anula, llama a `incident_close_twin_lines`;
    - otros estados no `pending`/`notified` siguen lanzando la excepción de hoy.
  - `incident_apply_change` (misma firma): tras aplicar, llama a `incident_close_twin_lines` y a `incident_refresh_other_incidents`, en ese orden.

- [ ] **Step 1: Añadir los escenarios al test.** Usan una segunda baja de P2 (nodo N2), con id fijo `f0000000-0000-0000-0000-000000000002` y la utilidad `pg_temp.baja2`.

  | Escenario | Preparación | Lo que se comprueba |
  |---|---|---|
  | `apply_cancel_already_cancelled` | Línea `pending` a mano sobre una muestra `cancelled`. Se llama a `incident_apply_cancel(line,'manager')`. | Sin excepción; línea `info` / `handled_by_other_incident`. |
  | `twin_cancel_closes_other` | Muestra N1→N2 el 03-10. Baja A (P1) y baja B (P2), las dos del 03-08 al 03-12. Línea `pending` legacy de B insertada a mano. Sin hueco: `run()` de A la anula. | La línea de B queda `info` / `handled_by_other_incident`. B con `incident_status='auto_resolved'`. |
  | `twin_move_reevaluates` | Muestra N1→N2 el 2027-03-03. A es P1 del 03-02 al 03-04: su paso 1 la retrasa al 03-05, el primer laborable libre. B es P2 del 03-05 al 03-12, así que la fecha nueva cae en la baja de B. | Tras `run()` de A: B tiene una línea de esa muestra que no es `pending` y no queda ninguna línea `pending` en ninguna de las dos bajas. Si el paso 1 de A elige otra fecha, se ajusta el rango de B para que la cubra y se apunta como Ruling. |
  | `refresh_depth_guard` | Con `set_config('onems.incident_refresh_depth','3',true)`. | `incident_refresh_other_incidents` devuelve 0 y no ejecuta el motor. |

- [ ] **Step 2: Ejecutar y ver que falla.**
  Run: `bash supabase/tests/run_tests.sh incident_auto_only`
  Expected: FAIL en `apply_cancel_already_cancelled` con "is cancelled and cannot be cancelled".

- [ ] **Step 3: Añadir las funciones a la migración.** Partir de las definiciones vivas de `incident_apply_cancel` e `incident_apply_change`.

- [ ] **Step 4: Ejecutar todos los tests.**
  Run: `bash supabase/tests/run_tests.sh`
  Expected: todos PASS (los ajenos ya apuntados se mantienen).

- [ ] **Step 5: Commit.** `fix(incidents): una muestra compartida por dos bajas ya no deja lineas atascadas`

### Task 3: Badge del menú

**Files:**
- Modify: `supabase/migrations/20261109180000_incident_auto_only.sql` (añadir)
- Modify: `supabase/tests/incident_attention_counts.test.sql`

**Interfaces:**
- Produces: `incident_attention_counts(p_account_id uuid)`, misma firma y mismos permisos. La columna `unavailability` cuenta las bajas de la cuenta con `created_at >= now() - interval '7 days'`, O con mensajes entrantes sin leer (la parte `unread` de hoy se mantiene). Ya no mira `pending_manager`.

- [ ] **Step 1: Test.** En la cuenta del actor:
  - una baja creada hace 2 días cuenta;
  - una de hace 10 días sin mensajes no cuenta;
  - una de hace 10 días con un mensaje entrante sin leer cuenta;
  - una `pending_manager` de hace 10 días NO cuenta.

  Esperado: `unavailability = 2`. Además, una baja de otra cuenta nunca cuenta.
- [ ] **Step 2: Ejecutar y ver que falla.** `bash supabase/tests/run_tests.sh incident_attention_counts` → FAIL.
- [ ] **Step 3: Re-emitir la función desde la definición viva, con el cambio.**
- [ ] **Step 4: Ejecutar.** `bash supabase/tests/run_tests.sh incident_attention_counts incident_auto_only` → PASS.
- [ ] **Step 5: Commit.** `feat(incidents): el badge de bajas cuenta las declaradas en los ultimos 7 dias`

### Task 4: Pantalla informativa

**Files:**
- Modify: `src/components/incidents/IncidentReviewPanel.tsx`: quitar el bloque de pendientes, la selección múltiple, Confirm/Void, la barra `confirmState` y `apply_manager_decision`/`apply_manager_move`. Se mantiene el arrastre de cualquier muestra (`apply_sample_move` vía `suggest_for_sample_move`) y su barra de confirmación del movimiento.
- Modify: `src/components/incidents/IncidentLinesTable.tsx`: una sola tabla con columnas muestra · rol · fecha original · resultado · cuándo.
- Modify: `src/components/incidents/IncidentHeader.tsx`: resumen legible del `auto_summary`.
- Modify: `src/pages/incidents/PanelistAvailabilityIncidents.tsx`: filtros sin `pending_manager`, filtro por defecto `all` y sin la columna «Pending».
- Modify: `src/lib/hooks/useUnavailabilityIncidents.ts`:
  - quitar `applyDecision` y el contador `pending_manager` si nadie más los usa;
  - orden por `created_at` descendente;
  - el filtro `open` desaparece de `FILTER_OPTIONS` (el tipo puede conservarlo).
- Modify: `public/locales/{en,es,fr,ar}.csv` (o la ruta real de los 4 CSV): claves nuevas `incidents.result.*` e `incidents.summary.*`.

**Interfaces:**
- Consumes: `auto_summary` con formato `shift=N;reroute=N;cancel=N;info=N;pending=N` y, en cada línea, `status`, `final_action`, `final_date`, `final_target_node_id` y `suggested_reason`.
- Resumen de la cabecera, clave `incidents.summary.text`: «{{total}} muestras afectadas: {{shift}} retrasadas, {{reroute}} a otro nodo, {{cancel}} anuladas, {{info}} sin cambios». Si `pending > 0` (datos antiguos), se añade «, {{pending}} pendientes».
- Columna «resultado» por línea:

  | Línea | Texto |
  |---|---|
  | `shift_date` | «Retrasada al {fecha}» |
  | `reroute` | «Pasada a {nodo}» (+ «el {fecha}» si hay `final_date`) |
  | `cancel` | «Anulada (sin hueco en 8 semanas)» |
  | `info` | texto según `suggested_reason`: `already_sent`, `in_transit`, `back_before_arrival`, `handled_by_other_incident` («Ya resuelta en otra incidencia»), `engine_error` («No se pudo resolver: revisar») |
  | `pending` (datos antiguos) | «Pendiente», sin botones |
  | `manager_resolved` | lo mismo que `auto_resolved` + «(manual)» |

- [ ] **Step 1: Hacer los cambios de los cinco ficheros y los 4 CSV.** FR y AR se traducen igual que el resto del módulo.
- [ ] **Step 2: Lint y build.**
  Run: `npm run lint && npm run build`
  Expected: 0 errores; el tope de warnings no sube respecto a `develop`.
- [ ] **Step 3: Comprobación manual en `npm run dev`** (cuenta KENYA, solo lectura):
  - la bandeja lista las 6 bajas sin columna «Pending»;
  - el detalle de Jackline obiero muestra la línea antigua `pending` como «Pendiente» sin botones y sin errores en consola (Review Focus 5);
  - arrastrar una muestra sigue abriendo la barra de confirmación. No confirmar.
- [ ] **Step 4: Commit.** `feat(incidents): la pantalla de bajas pasa a ser informativa (sin Confirm/Void)`

### Task 5: Puesta al día

**Files:**
- Modify: `supabase/migrations/20261109180000_incident_auto_only.sql`: añadir `incident_resolve_all_open() RETURNS integer`, que ejecuta `resolve_unavailability_incident` sobre cada baja `active` con líneas `pending` o `incident_status='pending_manager'` y devuelve cuántas trata. Permisos solo `service_role`.
- Create: `supabase/migrations/20261109180100_incident_auto_only_catchup.sql`, con una sola sentencia: `SELECT public.incident_resolve_all_open();`, más su comentario.
- Modify: `supabase/tests/incident_auto_only.test.sql`

- [ ] **Step 1: Test `resolve_all_open`.**
  - Preparación: una baja activa con una línea `pending` legacy y otra baja activa ya `auto_resolved`.
  - Comprobación: devuelve 1; después no queda ninguna línea `pending` ni ninguna baja `pending_manager`.
- [ ] **Step 2: Ejecutar y ver que falla** (la función no existe). `bash supabase/tests/run_tests.sh incident_auto_only` → FAIL.
- [ ] **Step 3: Implementar y crear la migración de puesta al día.**
- [ ] **Step 4: Ejecutar todos los tests.** `bash supabase/tests/run_tests.sh` → PASS. La migración 180100 corre en la reconstrucción local sin error.
- [ ] **Step 5: Commit.** `chore(incidents): puesta al dia de las bajas abiertas con la regla nueva`

### Task 6: Despliegue (cada paso con confirmación del usuario)

- [ ] **Step 1: Ensayo en solo lectura.** Por el MCP de solo lectura, listar lo que hará la puesta al día:
  - líneas `pending` por baja;
  - para las que tienen la muestra `pending`/`notified`, el resultado de `incident_suggest`: dónde iría cada muestra o si se anula;
  - las que se cerrarán como `handled_by_other_incident`;
  - cuántas caen en la semana actual (generan aviso de Telegram).

  Enseñárselo al usuario.
- [ ] **Step 2: Pedir confirmación explícita** nombrando onems-dev `sehbnpgzqljrsqimwyuz`. Con ella, aplicar `20261109180000` y luego `20261109180100` con `apply_migration` del MCP, en ese orden.
- [ ] **Step 3: Verificar en vivo.**
  - `select count(*) from panelist_reassignment_proposal where status='pending'` → 0;
  - ninguna baja `pending_manager`;
  - `select status, count(*) from panelist_notification where created_at > now() - interval '10 minutes' group by 1` → los avisos encolados coinciden con el ensayo.
- [ ] **Step 4: Push y PR, con permiso del usuario.**
  - Push de la rama.
  - PR a `develop` con título y descripción para pegar (gh no está instalado).
  - Después, el usuario decide el PR `develop → main` para que la pantalla llegue a onems.edgeavs.net.
  - Hasta entonces, producción sigue mostrando los botones Confirm/Void, pero sin líneas pendientes no aparecen.
- [ ] **Step 5: Actualizar la memoria** `incidencias-indisponibilidad-resolucion-automatica.md` con el cambio y la fecha.
