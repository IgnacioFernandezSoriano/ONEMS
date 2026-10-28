# Incidencias reportadas por el panelista — Diseño

**Fecha:** 2026-08-06
**Autor:** Ignacio Fernández (con Claude)
**Estado:** aprobado el esquema global; pendiente de revisión final antes del plan.

---

## 0. Resumen en una frase

Una tabla nueva de **incidencias que el panelista reporta** (desde Telegram, vía n8n, en
otro entorno) y una **pantalla nueva en el grupo "Incidencias"** donde el manager de la
cuenta las ve y las gestiona. Según la **categoría**, la pantalla ofrece un **tratamiento
distinto**, reutilizando los motores que ya existen (bajas, edición del plan, ficha del
panelista).

Encaja en el marco extensible "Incidencias" (subsistema C) ya en producción. Es un
**segundo tipo de incidencia**, de origen distinto: no la detecta un trigger ni un cron —
la **origina el panelista**.

---

## 1. Contexto y límites

- **Base de datos:** `onems-dev`, project-ref `sehbnpgzqljrsqimwyuz` (única base). RLS por
  `account_id`.
- **Fuera de alcance de este spec:** los workflows de n8n y el bot de Telegram. Se
  construyen en **otro entorno**. Aquí dejamos la **tabla + RLS + RPCs + pantalla** y un
  **documento de contrato** para que n8n escriba/lea contra la BD.
- **Decisiones ya tomadas** (sesión 2026-08-06):
  1. La pantalla no solo gestiona: **dispara acciones reales** según categoría.
  2. Hay **canal de vuelta**: el manager puede responder al panelista (n8n lo envía por Telegram).
  3. El enlace al envío afectado **NO es por tag** (puede ser justo lo ilegible): el
     panelista **señala el envío** y viaja su `allocation_plan_detail_id`.
  4. La entrada del menú va **encima** de "Disponibilidad de panelistas".

---

## 1.b. Decisión de arquitectura: n8n/Telegram sigue separado (2026-08-06)

Se evaluó integrar el entorno Telegram/n8n dentro de este proyecto. **Decisión: no colapsar
los runtimes; integrar solo el contrato y los artefactos.**

- **Se descarta** reescribir Telegram como Edge Functions de Supabase (Opción B): los flujos
  de Telegram ya funcionan en prod (parcels, foto de tag), reescribirlos es riesgo sin
  beneficio inmediato; y el dueño del repo no programa — n8n le da autonomía visual sin
  ciclo de código+deploy. El acoplamiento actual (BD compartida + documento de contrato) ya
  es limpio y de bajo acoplamiento: fusionar runtimes lo empeoraría.
- **Se adopta** (Opción A): la tabla + RLS + RPCs viven en este repo; n8n/Telegram consume
  el **contrato** (§7). Además: versionar en el repo los workflows de n8n (export JSON) + el
  doc de contrato como única fuente de verdad, y **sacar la API key de n8n de los docs** a un
  secreto (mal olor de seguridad actual).
- **La incidencia nueva** se mantiene en n8n (solo un `INSERT` + un `SELECT` de respuestas),
  por consistencia con los flujos de Telegram existentes.
- **Reconsiderar la Opción B** solo si n8n estorba (coste, bug intratable, necesidad de
  tests), y entonces como proyecto propio, no mezclado con esto.

---

## 2. Modelo de datos — tabla `panelist_incident`

Una fila por incidencia reportada.

| Columna | Tipo | Nota |
|---|---|---|
| `id` | uuid PK (`gen_random_uuid()`) | |
| `account_id` | uuid NOT NULL | **RLS**; lo aporta n8n desde el panelista |
| `panelist_id` | uuid NOT NULL FK `panelists(id)` | quién reporta |
| `category` | text NOT NULL | CHECK en los 9 códigos (ver §3) |
| `status` | text NOT NULL DEFAULT `'open'` | CHECK `open`/`in_progress`/`resolved`/`dismissed` |
| `description` | text NULL | texto libre del panelista |
| `photo_url` | text NULL | foto opcional (paquete roto, etiqueta…) |
| `allocation_plan_detail_id` | uuid NULL FK `allocation_plan_details(id)` | el **envío señalado** (solo categorías ligadas a envío) |
| `payload` | jsonb NULL | datos específicos de la categoría (material pedido, datos de contacto nuevos…) |
| `resolution_note` | text NULL | nota interna del manager al resolver |
| `reply_to_panelist` | text NULL | mensaje de vuelta al panelista |
| `reply_status` | text NOT NULL DEFAULT `'none'` | CHECK `none`/`pending_send`/`sent` |
| `reply_sent_at` | timestamptz NULL | lo marca n8n al enviar |
| `created_via` | text NOT NULL DEFAULT `'telegram'` | `telegram`/`web` |
| `reported_at` | timestamptz NOT NULL DEFAULT `now()` | |
| `resolved_at` | timestamptz NULL | |
| `resolved_by` | uuid NULL FK `profiles(id)` | manager que resolvió |
| `created_at`, `updated_at` | timestamptz DEFAULT `now()` | |

**Índices:** `(account_id, status)`, `(panelist_id)`, `(allocation_plan_detail_id)`.

**RLS:** SELECT/UPDATE solo filas de la cuenta del usuario (patrón `account_id` del proyecto).
n8n entra como service-role (salta RLS) → el contrato le obliga a filtrar por `account_id`.

**Badge del menú:** nº de filas con `status IN ('open','in_progress')` de la cuenta activa.

---

## 3. Categorías → tratamiento

### 3.0. Principio de diseño

Reutilizamos el patrón de la baja: **"el sistema propone, el manager decide y confirma"**.
A diferencia de la baja (un motor genera N propuestas), aquí, al abrir el detalle, la pantalla
**precalcula el contexto y propone la acción según la categoría**. Cada ficha reutiliza
maquinaria existente (motor de bajas, estado/edición del plan, ficha del panelista); no se
inventa lógica nueva. Cada ficha define cuatro cosas: **qué precalcula la pantalla**, **qué
acción propone**, **qué pasa al confirmar** y **qué respuesta sale al panelista**.

### 3.1. Índice de categorías

Nueve códigos cerrados (i18n por código, patrón `reason.*` ya usado):

| Código | Categoría | Enlaza envío | Tipo de tratamiento |
|---|---|:---:|---|
| `missing_materials` | Falta de materiales para el envío | ✔ | acción sobre envío + reposición |
| `unreadable_label_receipt` | Etiqueta ilegible (recepción) | ✔ | acción sobre envío |
| `parcel_damaged` | Envío llegó golpeado/roto | ✔ | acción sobre envío |
| `parcel_returned` | Envío devuelto al remitente | ✔ | acción sobre envío |
| `how_to_send` | No sé cómo hacer el envío | ✔ | soporte / responder |
| `unavailability_request` | Petición de baja como panelista | — | dispara motor de bajas |
| `tag_photo_problem` | Problema al hacer la foto del tag | ✔ | acción sobre envío |
| `contact_data_change` | Cambio de datos de contacto | — | actualiza datos |
| `other` | Otros | opcional | triaje libre |

### 3.2. Fichas de tratamiento

**`missing_materials` — Falta de materiales**
- *Precalcula:* el envío señalado + **los materiales que el producto requiere**
  (`product_materials` + `material_catalog`).
- *Propone:* "Reponer y **reprogramar** a fecha con margen" · "Marcar repuesto, misma fecha" ·
  "Cancelar envío".
- *Confirma:* mueve/cancela el envío + marca repuesto.
- *Respuesta:* "Material en camino; tu envío pasa al {fecha}".

**`unreadable_label_receipt` — Etiqueta ilegible en recepción**
- *Precalcula:* el envío entrante señalado (estado `sent`, destino = nodo del panelista).
- *Propone:* **"Registrar recepción manual"** (sin foto del tag).
- *Confirma:* `status='received'`, `received_at=now()`.
- *Respuesta:* "Recepción registrada, gracias".

**`parcel_damaged` — Envío roto/golpeado**
- *Precalcula:* el envío + producto + foto adjunta del panelista.
- *Propone:* **"Invalidar muestra"** · opcional "Programar reenvío de reemplazo".
- *Confirma:* `status='invalid'` (+ reenvío si aplica).
- *Respuesta:* "Registrado, gracias por avisar".

**`parcel_returned` — Devuelto al remitente**
- *Precalcula:* el envío.
- *Propone:* **"Reprogramar"** (nueva fecha) · **"Cancelar"**.
- *Confirma:* mueve o cancela el envío.
- *Respuesta:* según decisión.

**`how_to_send` — No sé cómo enviar**
- *Precalcula:* envío + producto + **materiales + transportista** (las instrucciones montadas).
- *Propone:* **plantilla de instrucciones** editable.
- *Confirma:* solo respuesta (no toca el plan).
- *Respuesta:* las instrucciones (el entregable aquí *es* la respuesta).

**`unavailability_request` — Petición de baja**
- *Precalcula:* nada extra; abre el mini-flujo de baja.
- *Propone:* **"Crear baja"** con fechas/motivo → inserta `panelist_unavailability` → el
  **motor existente genera las propuestas de reasignación**. La incidencia queda enlazada y
  aparece también en "Disponibilidad de panelistas".
- *Confirma:* baja creada.
- *Respuesta:* "Baja registrada del {inicio} al {fin}".

**`tag_photo_problem` — Problema con la foto del tag**
- *Precalcula:* el envío señalado (de envío o recepción).
- *Propone:* **"Registrar a mano"** el estado que no pudo declarar.
- *Confirma:* marca `sent`/`received` según el caso.
- *Respuesta:* "Hecho por ti; revisa la app".

**`contact_data_change` — Cambio de datos de contacto**
- *Precalcula:* **datos actuales del panelista vs. los nuevos** (`payload`), lado a lado.
- *Propone:* **"Aplicar cambios"** (telegram_id / teléfono / idioma).
- *Confirma:* update de `panelists`.
- *Respuesta:* "Datos actualizados".

**`other` — Otros**
- *Precalcula:* envío si lo hay.
- *Propone:* triaje libre + respuesta.
- *Confirma:* solo estado/respuesta.

Resolver una incidencia = ejecutar (si aplica) la acción propuesta **y** poner `status`.

---

## 4. RPCs de acción (backend)

Todas `SECURITY DEFINER`, `search_path=public`, con guarda cross-tenant (la cuenta del actor
debe coincidir con `account_id` de la incidencia / del recurso). Firmas a fijar en el plan;
por resultado:

- `resolve_panelist_incident(p_incident_id, p_status, p_resolution_note, p_reply_text)` —
  genérica: fija `status`, `resolution_note`, `resolved_by/at`; si `p_reply_text` no es NULL,
  pone `reply_to_panelist` y `reply_status='pending_send'`.
- `mark_detail_received_manual(p_detail_id)` — `allocation_plan_details.status='received'`,
  `received_at=now()`. Para `unreadable_label_receipt` / `tag_photo_problem`.
- `invalidate_detail(p_detail_id, p_note)` — `status='invalid'`. Para `parcel_damaged`.
- Reprogramar/cancelar (`parcel_returned`): reutilizar la vía de edición de plan ya existente
  (a confirmar en el plan si es RPC nueva o la pantalla de plan).
- Crear baja desde incidencia (`unavailability_request`): insertar `panelist_unavailability`
  (`status='active'`) con fechas/motivo del manager; el trigger existente genera propuestas.
- Actualizar contacto (`contact_data_change`): update de `panelists` (telegram_id/phone/language)
  con guarda de cuenta.

Cada acción, al completarse, puede llamar internamente a `resolve_panelist_incident` o dejar
la incidencia en `in_progress` hasta que el manager la cierre (decisión de detalle en el plan).

---

## 5. Pantalla del manager

- **Ruta:** `/incidents/panelist-reported`. **Menú:** grupo `incidents.menu_group`,
  entrada nueva **encima** de "Disponibilidad de panelistas"
  (`/incidents/panelist-availability`). Badge propio = incidencias abiertas.
  Roles `['admin','superadmin']`, igual que la existente.
- **Archivos** (patrón página→hook→supabase):
  - `src/pages/incidents/PanelistReportedIncidents.tsx` — bandeja.
  - `src/components/incidents/ReportedIncidentPanel.tsx` — detalle + acciones por categoría.
  - `src/lib/hooks/useReportedIncidents.ts` — fetch bandeja, fetch detalle, acciones, resolver.
  - Tipos en `src/lib/types` (o `types_*.ts`).
- **Bandeja (nivel 1):** lista de incidencias de la cuenta con filtro por **categoría** y
  **estado**; columnas: panelista, categoría (traducida), envío (si hay), fecha, estado.
- **Detalle (nivel 2):** cabecera del panelista + envío señalado (si `allocation_plan_detail_id`);
  texto y foto; **bloque de acciones dependiente de la categoría** (§3); zona **"Resolver"**
  con nota interna y **respuesta opcional al panelista**.
- **i18n:** claves nuevas `reported_incidents.*` (menú, columnas, estados, botones) y
  `reported_incidents.category.*` (las 9) en `public/locales/{en,es,fr,ar}.csv`. FR/AR
  autogeneradas con repaso nativo pendiente antes de prod (nota conocida del proyecto).
- **Realidad conocida:** la bandeja **no es tiempo real** (carga al montar/cambiar cuenta);
  tras un alta por n8n hay que **refrescar (F5)**, igual que la de disponibilidad.

---

## 6. Canal de vuelta al panelista

- Columnas `reply_to_panelist` / `reply_status` / `reply_sent_at` en `panelist_incident`.
- Al resolver con respuesta: `reply_status='pending_send'`.
- **n8n (otro entorno)** consulta las `pending_send` de la cuenta, envía por Telegram en el
  `language` del panelista, y marca `reply_status='sent'`, `reply_sent_at=now()`.
- Nosotros dejamos columnas + contrato; el envío es de n8n.

---

## 7. Contrato para n8n (documento aparte, como el de subsistema C)

Al terminar la implementación, escribir `docs/integrations/AAAA-MM-DD-n8n-incidencias-reportadas.md`:

- **INSERT de alta** desde Telegram: `account_id` (del panelista), `panelist_id`, `category`
  (uno de los 9 códigos), `description`, `photo_url`, `allocation_plan_detail_id` (el envío
  que el panelista señala), `payload` (opcional). Recordatorio: filtrar/derivar `account_id`
  correctamente (service-role salta RLS).
- **SELECT de respuestas** `reply_status='pending_send'` para enviar y luego marcar `sent`.
- Los 9 códigos de categoría y su significado.
- Regla de oro multi-tenant y "no escribir el plan a mano; usar RPCs".

---

## 8. Qué construimos (secuencia de implementación)

1. **Migración** forward-only: tabla `panelist_incident` + CHECKs + índices + RLS.
2. **RPCs de acción** (§4) + tests locales (replay baseline en Postgres portable).
3. **Pantalla** (§5): tipos, hook, bandeja, detalle con acciones por categoría, menú/ruta, i18n 4 CSV.
4. **Documento de contrato** para n8n (§7).

Puertas de calidad del proyecto: `npm run lint` y `npm run build` deben pasar. Sin tests
de frontend automatizados.

---

## 9. Decisiones cerradas (2026-08-06)

- **`parcel_returned` (y reprogramar en general):** **RPC in-line**. El manager reprograma/
  cancela sin salir del detalle de la incidencia (pequeñas RPCs `reschedule_detail` /
  `cancel_detail`). Mantiene el flujo guiado en una sola pantalla.
- **Cierre:** **Resolver explícito**. La acción (recepción manual, baja, etc.) deja la
  incidencia `in_progress`; el manager pulsa "Resolver" añadiendo la respuesta al panelista.
  Así el canal de vuelta siempre entra en la resolución.
- **`payload`:** **esquema mínimo documentado por categoría** (en el contrato §7). La UI pinta
  claves conocidas; ejemplos: `contact_data_change` → `{telegram_id?, phone?, language?}`;
  `missing_materials` → `{materials?: [{name, quantity}]}`.
- **Fotos:** **Supabase Storage**. n8n sube la foto a un bucket dedicado y `photo_url` guarda
  la ruta/URL de storage (duradera, bajo control multi-tenant). El bucket y su política de
  acceso se crean en la migración/entorno.
