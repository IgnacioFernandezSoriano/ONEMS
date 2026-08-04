# Motor de propuestas de reasignación por baja de panelista (subsistema B)

**Fecha:** 2026-08-04
**Estado:** diseño aprobado (pendiente de plan de implementación)
**Autor:** Ignacio Fernández + Claude

---

## 1. Contexto y objetivo

Cuando un panelista se declara en **baja temporal** (unavailability period), las muestras
del allocation plan en las que participa (como origen = "envío" o como destino =
"recepción") quedan comprometidas. El sistema debe **proponer** qué hacer con cada muestra
afectada y dejar que el **manager de la cuenta confirme** (registro a registro o en masa),
pudiendo además editar la acción a mano.

Este spec cubre **solo el subsistema B: el motor de propuestas de reasignación**. Es el
corazón del proceso descrito en `Proceso de baja temporal de panelista.md`. Los otros dos
subsistemas se abordan en specs posteriores:

- **A — Ingesta Telegram/n8n** (el panelista declara la baja por Telegram; n8n la crea en
  ONEMS y le confirma). Se hará **al final**, desde el entorno n8n↔ONEMS del usuario. B deja
  su Edge Function invocable por HTTP para que n8n la llame igual que la UI.
- **C — Pantalla del manager** (alarma en gestión de incidencias, lista de casos,
  revisar/confirmar propuestas visualmente, load balancing manual, marcar "estudiado"). B
  deja el dato (`review_status`) y las RPC listas para que C las consuma.

### Decisión de fondo: propuesta en vez de auto-ejecución

Hoy existe el trigger `reassign_on_unavailability` que, al crear la baja, **reasigna
automáticamente y en el acto** (round-robin a otros nodos de la misma ciudad, origen y
destino, con `reassigned_by = NULL`). Esto contradice el flujo "el sistema propone → el
manager confirma" del documento. Además solo implementa el nivel *a* de forma tosca, nunca
el desplazamiento de fecha ni la cancelación, y no distingue recepción "ya salida vs no
salida".

**Veredicto (tras analizar el sistema actual): reutilizar los primitivos, rehacer la
orquestación.**

- 🟢 **Se reutilizan** (buenos cimientos, no se tocan):
  - `is_panelist_available(panelist_id, date)` y `is_node_available(node_id, date)` —
    resuelven "¿hay nodo alternativo con panelista disponible ese día?" y "¿la fecha
    desplazada cae en un hueco disponible?".
  - `rpc_balance_node_load_by_period(city, start, end, p_apply_changes)` — balanceo entre
    nodos de una ciudad con **modo preview**; disponible para el load balancing manual del
    paso 8 (subsistema C).
  - La **query de detección** de muestras afectadas (los `allocation_plan_details` del nodo
    en el rango de fechas, excluyendo estados terminales) del trigger actual.
- 🔴 **Se rehace:** la **acción** del trigger `reassign_on_unavailability` (mutar el plan en
  el acto). Se sustituye por un motor que **genera propuestas** y espera confirmación.

---

## 2. Modelo de datos

### 2.1 Nueva tabla `panelist_reassignment_proposal`

RLS por `account_id` (como toda tabla de datos de cuenta). Una fila por muestra afectada.

| Campo | Tipo | Para qué |
|---|---|---|
| `id` | uuid PK | — |
| `account_id` | uuid NOT NULL | aislamiento tenant (RLS) |
| `unavailability_id` | uuid → `panelist_unavailability` | a qué baja pertenece (agrupa el "caso") |
| `allocation_plan_detail_id` | uuid → `allocation_plan_details` | la muestra afectada |
| `affected_role` | text CHECK ∈ (`origin`,`destination`) | ¿la baja le pega como envío o recepción? |
| `sample_status_at_detection` | text | estado de la muestra cuando se detectó |
| `suggested_action` | text CHECK ∈ (`reroute`,`shift_date`,`cancel`,`none`) | lo que propone el motor |
| `suggested_target_node_id` | uuid NULL → `nodes` | destino de la propuesta (si `reroute`) |
| `suggested_date` | date NULL | nueva fecha (si `shift_date`) |
| `suggested_reason` | text | por qué el motor eligió ese nivel |
| `final_action` | text NULL CHECK ∈ (`reroute`,`shift_date`,`cancel`,`manual`) | lo que confirma el manager |
| `final_target_node_id` | uuid NULL → `nodes` | nodo final (reroute/manual) |
| `final_date` | date NULL | fecha final (shift_date/manual) |
| `status` | text NOT NULL DEFAULT `pending` CHECK ∈ (`pending`,`confirmed`,`dismissed`) | ciclo de vida |
| `confirmed_by` | uuid NULL → `profiles` | auditoría |
| `confirmed_at` | timestamptz NULL | auditoría |
| `created_at`, `updated_at` | timestamptz | — |

**Índices:** `(account_id)`, `(unavailability_id)`, `(allocation_plan_detail_id)`,
`(account_id, status)`.

**RLS:** SELECT/INSERT/UPDATE restringidos a `account_id = current_user_account_id()`, más
la política equivalente para superadmin ya usada en el resto de tablas del proyecto.

### 2.2 Columna nueva en `panelist_unavailability`

- `review_status` text NOT NULL DEFAULT `pending_review` CHECK ∈ (`pending_review`,`reviewed`).

Es el flag que en C encenderá/apagará la alarma de incidencias y soporta el paso 9 ("dar por
estudiado"). Mínimo y suficiente para B.

### 2.3 Trigger auto actual

Se hace **DROP del trigger** `reassign_on_unavailability_trigger`. La **función**
`reassign_on_unavailability()` se **conserva** (no se borra) para referencia/rollback. En su
lugar, la creación de la baja invoca la Edge Function del motor.

> Nota: el trigger `check_unavailability_overlap_trigger` (que impide solapes de bajas
> activas) **se mantiene** — no tiene que ver con la reasignación.

---

## 3. El motor — Edge Function `propose-reassignments`

**Ubicación:** `supabase/functions/propose-reassignments/` (Deno).

**Disparo:** tras el INSERT de una baja (desde la UI actual vía hook
`usePanelistUnavailability`, o en el futuro desde n8n por HTTP), se llama a la función con
`{ unavailability_id }`. Corre con service-role y filtra explícitamente por el `account_id`
de esa baja.

### 3.1 Paso 0 — detección de muestras afectadas

Todas las `allocation_plan_details` donde el nodo del panelista de baja participa, con
`fecha_programada ∈ [start_date, end_date]` y `status NOT IN ('received','cancelled','invalid')`.
Clasificación por muestra:

- **Envío** si el nodo del panelista es `origin_node_id`.
- **Recepción** si es `destination_node_id`.
- Si es ambos (panelista origen y destino de la misma muestra — raro), se generan **dos**
  propuestas, una por rol.

### 3.2 Cascada para ENVÍOS (panelista = origen)

Por muestra, en orden; se para en el primer nivel que aplica:

1. **`reroute`** — ¿hay otro nodo de la misma ciudad con panelista disponible ese día
   (`is_node_available`) y que no esté también de baja? Si hay varios, se reparte la carga
   entre ellos. → propuesta `reroute` a ese nodo.
2. **`shift_date`** — primera fecha **fuera** del periodo de baja y **dentro del mismo mes**
   en la que el propio nodo/panelista vuelva a estar disponible. → propuesta `shift_date`.
3. **`cancel`** — terminal.

### 3.3 Cascada para RECEPCIONES (panelista = destino)

"No ha salido" = `status ∈ (pending, notified)`. "Ya salió" = `status = sent` o posterior.

- **No ha salido:**
  1. **`reroute`** — cambiar el destino a otro nodo de la misma ciudad con panelista
     disponible ese día.
  2. **`cancel`** — terminal.
- **Ya salió:** no se puede reencaminar → `suggested_action = 'none'` con
  `suggested_reason` = "ya en tránsito; llegará con retraso / no se registrará a tiempo". Se
  muestra al manager como **informativa**, sin acción sobre el plan.

### 3.4 Salida

Inserta N filas en `panelist_reassignment_proposal` (todas `pending`), cada una con su
`suggested_action` + target + `suggested_reason`. **No muta ningún `allocation_plan_detail`.**

### 3.5 Idempotencia

Si se re-ejecuta para la misma baja (p.ej. se edita el periodo): borra y regenera las
propuestas aún `pending` de esa baja, y **respeta** las ya `confirmed`.

---

## 4. Aplicar al confirmar (mutación del plan)

La mutación del plan solo ocurre cuando el manager confirma, vía RPC Postgres (SECURITY
DEFINER, validando que el manager comparte `account_id` con la propuesta/muestra). La
pantalla C consumirá estas RPC; en B se construyen y se dejan testeables.

### 4.1 `apply_reassignment_proposal(proposal_id, final_action, final_target_node_id, final_date)`

Todo en **una transacción**: muta la muestra y cierra la propuesta atómicamente.

| `final_action` | Efecto sobre `allocation_plan_detail` |
|---|---|
| `reroute` | Guarda `original_origin_node_id`/`original_destination_node_id` según rol; fija el nuevo `origin_node_id`/`destination_node_id`; `reassignment_reason='panelist_unavailable'`, `reassigned_at=now()`, `reassigned_by=<manager>` |
| `shift_date` | Cambia `fecha_programada` a `final_date` + auditoría igual |
| `cancel` | `status='cancelled'` + auditoría |
| `manual` | El manager fija a mano `origin_node_id`/`destination_node_id`/`fecha_programada`; guarda los `original_*`; `reassignment_reason='manual'`, `reassigned_by=<manager>` |
| (`none`) | No confirma acción; la propuesta se marca `dismissed` (vista/aceptada sin cambio) |

Marca la propuesta `confirmed` (o `dismissed`) con `confirmed_by/at`.

### 4.2 `apply_reassignment_proposals_bulk(unavailability_id)`

Aplica todas las propuestas `pending` de un caso usando su `suggested_action` (el "confirmar
todo lo propuesto" del paso 7). Internamente llama a `apply_reassignment_proposal` una a una.

### 4.3 Acción manual = "editar el mismo registro"

`final_action='manual'` cubre el requisito de **editar la propia muestra afectada** (cambiar
nodo origen/destino o fecha sobre el mismo registro). Es también el sustituto manual de
"regenerar" mientras esa función quede aplazada.

### 4.4 Seguridad multi-tenant

Ambas RPC verifican que la propuesta, la muestra y el manager comparten `account_id`. Nunca
se cruza cuenta.

---

## 5. Fronteras del subsistema B

### B entrega
1. Migración forward-only (timestamp > baseline): tabla `panelist_reassignment_proposal` +
   columna `review_status` + DROP del trigger auto (función conservada).
2. Edge Function `propose-reassignments` (las dos cascadas, sin mutar).
3. RPCs `apply_reassignment_proposal` + `apply_reassignment_proposals_bulk`.
4. Enganche mínimo: la creación de baja (`usePanelistUnavailability`) invoca la Edge Function
   tras el INSERT.

### B NO hace (fronteras con A y C)
- ❌ **Pantalla del manager (C):** alarma, lista de casos, revisión/confirmación visual, load
  balancing manual (paso 8), marcar "estudiado". Solo se deja el dato (`review_status`) y las
  RPC listas.
- ❌ **Telegram/n8n (A):** se hará al final desde el entorno n8n del usuario; la Edge Function
  queda invocable por HTTP.
- ❌ **Regenerar** muestras de reemplazo: aplazado; se cubre a mano con `final_action='manual'`.

---

## 6. Puerta de calidad y seguridad

No hay suite de tests de frontend. Verificación:

- Migración validada en el **Postgres portable local (5433)** con `replay_baseline.ps1`
  **antes** de tocar prod.
- Edge Function y RPC probadas contra esa BD local con una baja que dispare **cada rama** de
  la cascada (reroute / shift_date / cancel para envíos; reroute / cancel / none para
  recepciones).
- `npm run build` + `npm run lint` limpios.
- **Nada se aplica a la BD de prod (`sehbnpgzqljrsqimwyuz`) sin confirmación explícita del
  usuario**, según las reglas del proyecto. Migraciones forward-only; no se toca el baseline
  ni las migraciones archivadas.

---

## 7. Preguntas abiertas / iteraciones futuras

- **Regenerar** muestras de reemplazo (invocando una porción de `allocationPlanCalculator`):
  iteración 2.
- **Subsistema C** (pantalla del manager) y **A** (Telegram/n8n): specs propios.
- Reparto de carga en `reroute` de envíos cuando hay varios nodos alternativos: se detalla en
  el plan de implementación (round-robin simple reutilizando la lógica de detección actual).
