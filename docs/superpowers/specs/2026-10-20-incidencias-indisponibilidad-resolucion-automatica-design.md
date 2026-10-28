# Incidencias de indisponibilidad de panelista: resolución automática + decisión del manager

**Fecha:** 2026-10-20
**Estado:** revisado por builder-check (2026-10-20); pendiente de aprobación del usuario
**Sustituye en parte a:** `2026-08-04-motor-reasignacion-baja-panelista-design.md` (motor B) y
`2026-08-05-subsistema-c-incidencias-panelistas-design.md` (pantalla C). Lo que aquí no se
contradice sigue vigente.

---

## 1. Intención

Hoy, cuando un panelista declara una baja temporal, ONEMS genera *propuestas* de reasignación
y el manager las confirma una a una. En la práctica no funciona:

- Si la baja llega antes de aplicar el plan (KENYA, 14/10 vs plan del 15/10) o el plan se mueve
  después, la baja queda con 0 propuestas y **no aparece** en la pantalla.
- Las bajas que el panelista escribe en texto libre por Telegram ("la próxima semana hago
  vacaciones") solo mandan un email: **no se guardan**.
- El manager tiene que decidir cada muestra aunque la solución sea obvia.

Lo que se quiere: **toda baja se convierte en una incidencia visible**, el sistema **resuelve
solo lo que pueda** (retrasar la fecha o pasar la muestra a otro nodo de la misma ciudad sin
sobrecargarlo), y el manager **solo decide lo que el sistema no ha podido**, con la vista de
carga delante y una propuesta ya hecha. Los panelistas afectados por cambios de la semana en
curso se enteran por Telegram.

## 2. Objetivos, no-objetivos, anti-objetivos

**Objetivos**
1. Cualquier baja (botones Telegram, texto libre Telegram, web) crea una incidencia con estado.
2. Estados: `New` → `Resuelta Automáticamente` | `Pendiente Decisión Manager` → `Resuelta`.
3. Resolución automática por muestra: (1) retrasar dentro del mes; (2) otro nodo de la misma
   ciudad (misma semana, si no dentro del mes), repartiendo carga; (3) si no, manager.
4. Pantalla del manager: una fila por incidencia; dentro, todas las muestras (resueltas y
   pendientes), la carga por semanas de la ciudad con filtros, propuesta del sistema por cada
   pendiente, y acciones **aceptar / otra semana / anular**. Campo de resolución final.
5. Avisos Telegram: "Recibido. Gracias por informar" al que declara; detalle del envío nuevo a
   cada panelista afectado por un cambio en la semana actual.
6. Las bajas se recalculan cuando se aplica o se mueve el plan (no solo al crearlas).

**No-objetivos**
- Resolver incidencias desde Telegram (el manager decide en la web).
- Otros tipos de incidencia (materiales, reportadas por panelista): no cambian.
- Rebalancear el plan entero; solo se mueven las muestras afectadas por la baja.
- Cambiar el aviso diario de las 9:00 de n8n (sigue igual y cubre semanas futuras).

**Anti-objetivos (sería un fracaso aunque "funcione")**
- Tocar una muestra ya enviada (`status in ('sent','received')`): nunca.
- Mover una muestra a un nodo de **otra ciudad**: nunca (cambiaría la ruta medida).
- Saturar un nodo por resolver rápido.
- Que un fallo de este motor impida aplicar o editar un plan.
- Cruzar datos entre cuentas (RLS por `account_id` como siempre).
- Cadenas de UI fuera de `useTranslation()` / los 4 CSV de `public/locales/`.

## 3. Restricciones

- Una sola BD Supabase: **onems-dev `sehbnpgzqljrsqimwyuz`**. Toda escritura se confirma
  antes. La BD va por delante de `main`: auditar el estado real antes de cada migración.
- Migraciones forward-only con timestamp > baseline; validadas en el Postgres local 5433
  (`supabase/tests/`) antes de ir a prod. Hay un borrador ya probado en local,
  `20261020120000_unavailability_refresh_and_declare.sql` + su test: **se rehace** dentro de
  este proyecto (no aplicar tal cual).
- Envíos solo **lunes a viernes** (regla vigente del plan; trigger `set_allocation_detail_week_fields`).
- n8n vive en el repo `panelist_n8n` (abierto en el mismo workspace). Cambiar primero el
  workflow **[DEV] Telegram - User initiated message** y los JSON del repo; PROD después.
  Comparar siempre n8n vivo con el JSON antes de tocar.
- El responsable no es programador: runbooks en lenguaje claro, nada irreversible sin confirmar.

## 4. Vocabulario

| Término | Qué es en la BD |
|---|---|
| **Incidencia** | una fila de `panelist_unavailability` (la baja). Una baja = una incidencia. |
| **Línea** | una fila de `panelist_reassignment_proposal`: una muestra afectada y qué se hizo con ella. |
| **Muestra** | una fila de `allocation_plan_details`. |
| **Semana actual** | lunes a domingo que contiene `current_date`. |
| **Mes de la muestra** | el mes de `fecha_programada` original (el plan es mensual). |
| **Carga** | lo que mide `rpc_get_node_load_by_period`: envíos por nodo y semana, con `saturation_level` según carga de referencia (por defecto 6) y desviación (20 %). |

## 5. Comportamiento

### 5.1 Entrada de una baja

Vías, todas acaban en la misma tabla y disparan el mismo motor:
- **Web** (pantalla de panelistas): insert como hoy.
- **Telegram, botones** (workflow `Panelist unavailability`): hoy hace un INSERT directo; pasa a
  llamar a `declare_panelist_unavailability` (misma validación, un solo punto de entrada).
- **Telegram, texto libre** (`time_off_subagent` del workflow principal): cuando el panelista
  confirma las fechas, llama a `declare_panelist_unavailability` con panelista, fechas y motivo
  `vacation`/`other`. Sigue mandando el email al manager (decisión mía: no quitar lo que ya hay).
  Vale para **cualquier periodo** que el ayudante sepa interpretar (mañana, del 3 al 7, hasta
  fin de mes…): el ayudante ya resuelve las fechas, solo cambia lo que hace al confirmar.

`declare_panelist_unavailability(p_panelist_id, p_start, p_end, p_reason, p_notes) → jsonb`
valida como el menú de botones (fin ≥ inicio, no en el pasado según zona horaria del país del
panelista, ≤ 90 días, sin solape con otra baja activa) y devuelve `{ok, unavailability_id,
affected_samples, incident_status}` o `{ok:false, error_code, ov_start, ov_end}`. Solo
`service_role` puede ejecutarla (n8n). Devuelve el estado para que n8n pueda decir "Recibido".

Al que declara se le responde por Telegram **"Recibido. Gracias por informar"** (en su idioma):
- en las dos vías Telegram lo contesta n8n directamente en la conversación;
- en la vía web se encola un aviso (ver 5.5) y n8n lo entrega.

### 5.2 Motor de resolución (BD, `resolve_unavailability_incident(p_unavailability_id)`)

Corre dentro de la transacción que crea/activa la baja (trigger ya existente, reescrito) y
también cuando cambia el plan (5.6). Es **determinista, sin IA**. Best-effort: si falla, deja
WARNING y no revierte la baja ni el plan.

1. **Detectar** muestras afectadas: `fecha_programada` dentro de la baja, nodo del panelista
   como `origin_node_id` (rol *origin*) o `destination_node_id` (rol *destination*). Se crea
   una línea por muestra y rol. Las que ya tienen línea no se duplican.
2. **Clasificar** cada línea nueva:
   - Muestra `sent`/`received`, o rol *destination* con envío ya salido → línea **informativa**
     (`info`, `final_action='none'`): no se toca y no bloquea.
   - Muestra `cancelled`/`incident` → no genera línea.
   - Resto (`pending`, `notified`) → candidata a resolución automática.
3. **Paso 1, retrasar** (ambos roles): buscar la fecha **más cercana posterior al fin de la
   baja**, dentro del **mes de la muestra**, lunes a viernes, con el nodo del panelista
   disponible ese día (`is_node_available`). Si en la misma incidencia hay varias muestras del
   mismo nodo, repartirlas por días (decisión mía: cada día del mes recibe como mucho una más que
   el que menos tenga; es la forma simple de "no amontonar"). Si existe → aplicar
   (`fecha_programada` nueva, guardar la original en `original_fecha_programada`,
   `reassignment_reason='panelist_unavailable'`), línea `auto_resolved`, `final_action='shift_date'`.
4. **Paso 2, otro nodo de la misma ciudad** (si el paso 1 no da fecha):
   - Candidatos: nodos de la misma ciudad y cuenta, distintos del original, con panelista
     disponible en la fecha (`is_node_available`).
   - Puntuación: carga del nodo en esa semana (misma cuenta que `rpc_get_node_load_by_period`:
     envíos por `origin_node_id` + recepciones por `destination_node_id`) **más** lo que ya se le
     ha asignado en este mismo recorrido. Se elige el de menor carga; a igual carga, el de menor
     `auto_id`. Se descarta cualquier nodo que quedaría en `saturated` según la carga de
     referencia y desviación de la cuenta (valores por defecto 6 / 20 %).
   - Primero en la **misma fecha** (misma semana). Si no hay nodo, probar otras fechas
     laborables del **mes de la muestra** (más cercanas primero) con el mismo criterio.
   - Rol *origin*: cambia `origin_node_id` (y `original_origin_node_id`); rol *destination*:
     cambia `destination_node_id` (y `original_destination_node_id`). Línea `auto_resolved`,
     `final_action='reroute'` (+ `shift_date` si además cambió la fecha: se guarda ambas cosas
     en la línea).
5. **Si nada de lo anterior**: línea `pending` con la **mejor alternativa para el manager**
   (5.3) ya calculada.
6. **Estado de la incidencia** (recalculado siempre al final, también desde 5.4):
   - sin líneas o todas `auto_resolved`/`info` → `auto_resolved` ("Resuelta Automáticamente";
     si no había muestras, resolución "Sin muestras afectadas");
   - alguna `pending` → `pending_manager`;
   - ninguna `pending` y alguna decidida por el manager → `resolved`.
   - Se rellena `auto_summary` ("9 retrasadas, 4 pasadas a otro nodo, 2 pendientes").
7. **Avisos** (5.5) por cada cambio aplicado.

Nota sobre el orden: el motor actual hace reroute antes que shift; **se invierte** (el usuario
prefiere no cambiar de panelista si basta con retrasar).

**Decisiones tomadas tras la revisión del builder (mías):**
- **Estado de la muestra tras moverla.** Toda muestra que el motor (o el manager) retrasa o
  reencamina vuelve a `status='pending'` si estaba `notified`, y se refrescan
  `origin_panelist_name`/`destination_panelist_name`. Motivo: el aviso diario de n8n solo avisa
  muestras `pending` el día de su fecha; si se quedara `notified` nadie avisaría al nuevo
  emisor ni en la nueva fecha. Así el aviso diario cubre las semanas futuras sin tocar n8n.
- **Qué es "saturado" para el motor.** Carga semanal de un nodo = muestras no canceladas de
  esa semana en que el nodo es origen **más** las que es destino (las dos subcolumnas Env/Rec
  del panel). Un nodo se descarta si, tras asignarle la muestra, su carga semanal superaría
  `referencia × (1 + 1,5 × desviación/100)` (con 6 / 20 % → más de 7,8, es decir 8 o más). Es
  el mismo umbral "saturated" de `rpc_get_node_load_by_period`, aplicado por semana en vez de
  por media del periodo, para que coincida con lo que el manager ve en las columnas semanales.
- **Carga de referencia y desviación.** No existen por cuenta; son filtros de la pantalla.
  El motor automático usa 6 / 20 %. `suggest_for_week` y `apply_manager_decision` aceptan
  ambos como parámetros opcionales y la pantalla pasa los valores de sus filtros, así la
  propuesta que ve el manager usa los mismos filtros que el panel de carga. Configurarlos por
  cuenta queda para más adelante.
- **Zona horaria para "no en el pasado".** Función `panelist_local_today(p_panelist_id)` con
  el mismo mapa país → zona que usa hoy el menú de Telegram (KENYA, USA, SPAIN; resto UTC).
  Una columna de zona horaria por panelista es trabajo futuro; no se añade aquí.

### 5.3 Propuesta para el manager (líneas pendientes)

Para cada línea `pending` el sistema calcula y guarda `suggested_*`:
1. la **primera semana posterior** en la que quepa la muestra sin saturar: mismo nodo si está
   disponible, si no el nodo menos cargado de la ciudad ese día; día laborable más cercano.
   El automático nunca sale del mes de la muestra, pero **al manager se le puede ofrecer** una
   semana del mes siguiente (horizonte: 8 semanas desde la fecha original); es él quien
   decide. Al moverla fuera de su mes la muestra **no cambia de plan** (`plan_id` igual; solo
   fecha, y `month`/`year` los pone el trigger de semana), decisión mía para no tocar Reporting;
2. si no hay nada en ese horizonte → `suggested_action='cancel'`.

`suggest_for_week(p_proposal_id, p_week_start) → {date, node_id, node_code, load_after,
saturation_level}` devuelve la misma elección pero **para la semana que el manager señale**
(la usa el botón "otra semana"). Solo lectura.

### 5.4 Acciones del manager

`apply_manager_decision(p_proposal_id, p_decision, p_week_start)` con `p_decision` en
`accept` (aplica `suggested_*`), `week` (aplica el resultado de `suggest_for_week` para esa
semana), `cancel` (muestra a `cancelled`). Guarda multi-tenant como `apply_reassignment_proposal`
(superadmin o misma cuenta). Marca la línea `manager_resolved`, `confirmed_by/at`, y recalcula
el estado de la incidencia. Acción en bloque: "Aceptar todas las propuestas" = bucle.

`set_incident_resolution(p_unavailability_id, p_text)` guarda la resolución final escrita
por el manager (se puede editar también en incidencias ya resueltas).

El manager **no puede** actuar sobre líneas `auto_resolved` ni `info` desde esta pantalla
(decisión mía: si quiere deshacer algo, edita el plan; la pantalla lo muestra con un enlace).

### 5.5 Avisos por Telegram

Tabla nueva `panelist_notification` (cola): `id, account_id, panelist_id, kind, payload jsonb,
status (pending_send|sent|failed), created_at, sent_at, error`. RLS por cuenta; n8n lee con
service role. La BD **encola**, n8n **entrega** (patrón ya usado en `deliver-incident-replies`:
sondeo periódico + webhook de empuje opcional). Los textos en 4 idiomas los compone n8n a
partir del `payload`, como hace con el resto de mensajes.

Tipos:
- `unavailability_received`: "Recibido. Gracias por informar." Solo se encola para bajas
  creadas desde la web (las de Telegram las contesta n8n en línea).
- `plan_change_this_week`: cuando la fecha **nueva o antigua** de una muestra cae en la semana
  actual y la muestra cambió de fecha, nodo o se anuló. Payload: muestra, producto/carrier,
  fecha, origen y destino (nodo + dirección como en "Parcels to send"), qué cambió.
  Destinatarios = los panelistas que tienen que actuar sobre esa muestra y **no** son el de
  baja: retraso → el que envía; cambio de origen → el nuevo emisor; cambio de destino → el
  nuevo receptor **y** el emisor (lleva la dirección nueva); anulación → el emisor.
  Cambios en semanas futuras no se avisan aquí: los cubre el aviso diario de las 9:00.

### 5.6 Recalcular cuando cambia el plan

Triggers de sentencia en `allocation_plan_details` (INSERT y UPDATE de fecha/origen/destino):
para cada baja activa y vigente cuyo rango toque las filas cambiadas, se vuelve a correr el
motor en modo **aditivo** (añade líneas nuevas, retira `pending` de muestras que ya no están
afectadas, no toca `auto_resolved`/`manager_resolved`, reabre la incidencia si añadió
pendientes). Se ignoran los cambios que vienen de las propias resoluciones (`reassigned_at`
cambia) para no pisarse. Nunca bloquea el plan (EXCEPTION → WARNING).

### 5.7 Las fechas de una baja no se editan

Las fechas vienen del panelista y **no son editables** por el manager. La web deja de ofrecer
"editar fechas" para una baja activa (`updateUnavailabilityPeriod` queda solo para `notes`);
si el panelista se equivocó, cancela la baja (Telegram o web) y declara otra. Lo que el
manager edita es el plan de muestras, y eso ya lo cubre 5.6.

### 5.8 Cancelar una baja

El trigger actual revierte reroutes confirmados y descarta pendientes. Se amplía: también
revierte los **retrasos** (nuevo `original_fecha_programada`) y las anulaciones hechas por este
motor que no hayan salido, y marca la incidencia `resolved` con resolución "Baja cancelada".
Cambios ya avisados en la semana actual generan un nuevo aviso con la vuelta atrás.

## 6. Pantalla (web)

Ruta existente `/incidents/panelist-availability`, página `PanelistAvailabilityIncidents.tsx`
+ `ProposalReviewPanel.tsx`, hook `useReassignmentProposals.ts` (se rehacen; se puede partir
el panel en componentes).

**Bandeja**: una fila por incidencia (todas las bajas, también sin muestras). Columnas:
panelista, nodo/ciudad, fechas, nº muestras afectadas (envíos/recepciones), pendientes,
**estado** (badge: New / Resuelta Automáticamente / Pendiente Decisión Manager / Resuelta),
fecha. Filtro por estado, por defecto "abiertas" (New + Pendiente). Badge del menú = nº de
incidencias `pending_manager`. Superadmin: cuenta seleccionada (`useEffectiveAccountId`).

**Detalle**: cabecera (panelista, nodo, fechas, motivo, estado, resumen automático, campo
**Resolución final** editable con guardar); panel de carga de la ciudad **por semanas** con los
mismos filtros que Load Balancing (rango de fechas, carga de referencia, desviación; reutiliza
`rpc_get_node_load_by_period` y `useCityNodeLoad`); tabla de líneas en dos bloques:
- **Pendientes**: muestra, rol, fecha original, propuesta del sistema (semana, día, nodo, carga
  resultante), botones **Aceptar · Otra semana… · Anular**. "Otra semana…" se elige pulsando la
  cabecera de una semana del panel de carga (o un selector): muestra lo que propone
  `suggest_for_week` y pide confirmar. Selección múltiple + "Aceptar las seleccionadas".
- **Resueltas** (automáticas, del manager e informativas): qué se hizo, cuándo, por quién.
Mientras haya pendientes, el estado es Pendiente; al resolver la última pasa a Resuelta sin
botón aparte. La pantalla recarga tras cada acción (no es tiempo real; F5 para ver bajas
nuevas, como hoy).

Textos nuevos en los 4 CSV (`incidents.*`); FR/AR autogenerados, pendientes de repaso nativo
como el resto del módulo.

## 7. Datos (resumen para el builder)

- `panelist_unavailability`: + `incident_status text` (`new|auto_resolved|pending_manager|resolved`,
  default `new`), + `auto_summary text`, + `final_resolution text`, + `resolved_at`.
  `review_status` se mantiene sincronizado (pending_manager ↔ pending_review, resto ↔ reviewed)
  hasta que el frontend deje de usarlo; luego se retira en otra migración.
- `panelist_reassignment_proposal`: `status` amplía a `pending|auto_resolved|manager_resolved|
  info|dismissed` (los `confirmed` existentes pasan a `manager_resolved`); `final_action` admite
  `none`; + `final_date` ya existe; + `resolution_note text`; + `applied_at`.
- `allocation_plan_details`: + `original_fecha_programada date`.
- `panelist_notification`: nueva (5.5).
- Funciones: `declare_panelist_unavailability`, `resolve_unavailability_incident(uuid, p_additive)`,
  `suggest_for_week`, `apply_manager_decision`, `set_incident_resolution`,
  `tg_refresh_proposals_on_plan_change`; `generate_reassignment_proposals` y
  `apply_reassignment_proposal` quedan como envoltorios de compatibilidad o se retiran si nada
  los llama (la edge function `propose-reassignments` se retira: el trigger la sustituye).
- Permisos: motor y cola solo `service_role`/triggers; RPCs del manager `authenticated` con
  guarda multi-tenant; `anon` sin nada.
- Datos existentes: las 2 bajas de KENYA (Nancy Weru 29/11–5/12, Petet 16–20/11, hoy con 0
  líneas) se tratan **igual que una baja nueva** al aplicar la migración (decidido por el
  usuario): lo que quepa se retrasa o cambia de nodo al momento y el resto queda
  `pending_manager`. Petet vuelve a abrirse si quedan pendientes.
  Los avisos de la puesta al día **no** se encolan (decisión mía: evitar mensajes de golpe a
  panelistas por cambios de hace días); se avisará solo de lo que cambie a partir de entonces.

## 8. n8n (repo `panelist_n8n`)

1. `time_off_subagent` ([DEV] primero): nueva herramienta Postgres
   `select declare_panelist_unavailability($1,$2,$3,$4)`; al confirmar el panelista, la llama
   y responde "Recibido. Gracias por informar" (o el `error_code` traducido: solape, pasado…).
   El email al manager se mantiene.
2. `Panelist unavailability` (botones): el nodo `Insert unavailability` pasa a llamar a la misma
   función y a usar su `error_code` (puede hacerse después; el trigger ya cubre el INSERT).
3. Workflow nuevo **Deliver panelist notifications**: clon de `deliver-incident-replies` sobre
   `panelist_notification` (sondeo cada 15 min + webhook `onems-panelist-notification`), con
   plantillas en 4 idiomas por `kind`.
4. Doc de traspaso en `docs/integrations/2026-10-20-n8n-incidencias-indisponibilidad.md`
   (contrato de la función, de la cola y ejemplos), como los anteriores.

## 9. Pruebas y despliegue

- Tests SQL en `supabase/tests/*.test.sql` sobre el Postgres local: detección, orden shift→reroute,
  reparto de carga y descarte por saturación, informativas, propuesta para el manager,
  `suggest_for_week`, `apply_manager_decision`, estados, cola de avisos (semana actual sí /
  futura no, destinatarios), refresco por cambio de plan, cancelación de baja, permisos,
  cross-tenant.
- Frontend: `npm run lint` (tope actual 48 warnings) y `npm run build`.
- Despliegue, en este orden y con confirmación en cada paso: migración a onems-dev →
  frontend a `develop` → PR a `main` → n8n [DEV] → prueba e2e por Telegram (texto libre y
  botones, baja con y sin muestras, cambio en semana actual) → n8n PROD.

## 10. Se deja al builder

- Reparto exacto de fechas en el paso 1 y empates; estructura de componentes; nombres de claves
  i18n; forma del `payload` de los avisos (con tal de que n8n tenga nodo, dirección, fecha,
  producto, qué cambió); índices; si `generate_reassignment_proposals` se retira o se envuelve.
