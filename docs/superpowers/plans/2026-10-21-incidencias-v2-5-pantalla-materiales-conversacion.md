# Incidencias v2 — Plan 5: Pantalla (conversación + falta de material v2 + hoja de envíos)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bloque "Conversación" en el detalle de las dos clases de incidencia (reportadas y bajas) con envío de mensajes del manager; nuevo cálculo de suministro de la falta de material (periodo, vecinos primero, columnas); hoja de envíos (pantalla, imprimir/PDF, CSV para Excel); botón para marcar enviado el envío del central.

**Architecture:** página → hook → supabase. Componente compartido `IncidentConversation` + hook `useIncidentConversation`. Se rehace la lógica de `resolveSupply` en `useMaterialsTreatment` y la sección 2 de `MissingMaterialsSections`; la hoja de envíos es un componente nuevo que reutiliza `printPDF` y `downloadCSV` de `src/lib/exportUtils.ts` (sin dependencias nuevas).

**Tech Stack:** React 18 + TS + Vite + Tailwind, `@supabase/supabase-js`, `date-fns`, i18n CSV.

**Specs:** `docs/superpowers/specs/2026-10-21-incidencias-conversacion-design.md` (§3, §5), `docs/superpowers/specs/2026-10-21-falta-material-v2-anexo-design.md` (§3, §4, §6, §8b). Requiere el **Plan 4 aplicado**.

## Global Constraints

- Todo texto visible por `t()`; claves en los 4 CSV `public/locales/{en,es,fr,ar}.csv` (CRLF, comillas si hay coma). Utilidades lógicas RTL (`text-start`, `ms-*`, `pe-*`).
- `npm run lint` sin avisos NUEVOS (48 preexistentes) y `npm run build` limpio.
- Las lecturas/escrituras de una incidencia usan **su** `account_id` (no la cuenta efectiva del visor).
- RPCs del Plan 4: `send_manager_message(p_incident_kind, p_incident_id, p_body)`; tabla `incident_message` (SELECT por RLS); `material_shipments.panelist_incident_id`.
- Disparar el envío inmediato tras `send_manager_message` con el mismo webhook "push" que hoy usa la respuesta del panel (buscar en `src/` la llamada actual al webhook de "Deliver incident replies"; si no existe, no añadir ninguna — el workflow corre cada 5 min).

## Review Focus

1. Conversación vacía (incidencias antiguas): texto "Sin mensajes todavía", sin errores. *(Tarea 1)*
2. Mensaje del manager fallido (`status='failed'`): se ve marcado y con el error en tooltip. *(Tarea 1)*
3. Donante con excedente 0 tras su propia necesidad: no aparece como origen. *(Tarea 2)*
4. Material sin vecinos ni central: todo a compra, y solo entonces aparecen fecha prevista y días sin stock. *(Tarea 2)*
5. Hoja de envíos con un envío de donante sin dirección: la línea sale con "—", no rompe la impresión. *(Tarea 3)*

---

### Task 1: Conversación en ambas incidencias

**Files:** Create `src/lib/hooks/useIncidentConversation.ts`, `src/components/incidents/IncidentConversation.tsx`; Modify `ReportedIncidentPanel.tsx` (sustituye el cuadro "Respuesta al panelista" por el envío vía conversación; "Resolver" ya no lleva texto de respuesta), `IncidentReviewPanel.tsx` (añade el bloque al final); CSVs.

**Interfaces:**
- `useIncidentConversation(kind: 'reported' | 'unavailability', incidentId: string)` → `{ messages, loading, error, reload, send(body: string): Promise<void> }`; `messages` ordenados por `created_at`; `send` llama a `send_manager_message` y recarga. Sondeo cada 30 s mientras el componente está montado (para ver respuestas sin F5).
- `IncidentConversation({ kind, incidentId })`: burbujas (bot/manager a la derecha con etiqueta, panelista a la izquierda, `internal` centrado en gris), hora `dd/MM HH:mm`, estado (`pending_send` reloj, `sent` ✓, `failed` ⚠ con `error` en `title`), botones pulsados (`meta.callback`) como chip; caja de texto + botón Enviar (deshabilitado vacío o enviando).
- Claves `incident_conversation.*`: `title`, `empty`, `placeholder`, `send`, `author.bot`, `author.manager`, `author.panelist`, `author.system`, `status.pending_send`, `status.sent`, `status.failed`, `button_pressed`.

- [ ] Step 1: Hook + componente. Step 2: Enchufar en ambos paneles (en reportadas, el bloque "Resolver" queda con nota interna + Resolver/Descartar; el texto al panelista se manda desde la conversación). Step 3: claves en 4 CSV. Step 4: lint/build. Step 5: Commit `feat(incidents): conversacion con el panelista en el detalle de cada incidencia`.

### Task 2: Nuevo cálculo de suministro

**Files:** Modify `src/lib/hooks/useMaterialsTreatment.ts`, `src/components/incidents/MissingMaterialsSections.tsx`; CSVs.

**Interfaces:**
- `useMaterialsTreatment(accountIdOverride?)` gana `resolveSupplyV2(panelistId: string, horizonEnd: string): Promise<SupplyLine[]>` con
  ```ts
  interface SupplyLine { material_id: string; code: string; name: string; is_blocking: boolean; need: number;
    fromNeighbours: { donor_panelist_id: string; donor_name: string; quantity: number }[];
    fromCentral: number; toPurchase: number }
  ```
  Algoritmo: `calculatePanelistRequirements(account, hoy, horizonEnd)` una vez (todas las necesidades); necesidad del panelista = su línea (ya resta su stock y lo en camino; excluir de "en camino" los envíos con `panelist_incident_id` = esta incidencia); donantes = panelistas activos de la **misma ciudad** (por `nodes.city_id`) con `excedente = stock − necesidad propia (misma llamada)` > 0, de mayor a menor; luego central (`material_stocks`); el resto compra.
- Horizonte por defecto: último día del mes de hoy; campo "Días de necesidad a cubrir" (vacío = por defecto; si tiene N, `hoy + N`). Recalcula al cambiar.
- Tabla por material: Necesidad · Vecinos (nombre: cantidad, …) · Central · Compra · selector "Cambiar origen" (`propuesta` | `solo vecinos` | `solo central` | `compra`) con tope por disponibilidad y resto a compra.
- Fecha prevista + días sin stock + baja: **solo** si algún material tiene `toPurchase > 0` tras los cambios.
- "Confirmar suministro": crea envíos con `executeSupply` y fija `panelist_incident_id` en **todos** (central y donantes) — `update material_shipments set panelist_incident_id = … where id in (…)`; guarda ids en payload como hoy (guardas de reintento intactas). **Ya no** marca envíos como enviados en la sección 3 (se elimina `sendPending`): el donante lo confirma por Telegram (Plan 6) y el central desde la hoja (Tarea 3).
- Elimina la columna/selector antiguos ("Planned split") y sus claves si quedan sin uso.

- [ ] Steps: implementar; claves `reported_incidents.materials.days_to_cover`, `.days_to_cover_hint`, `.col_need`, `.col_neighbours`, `.col_central`, `.col_purchase`, `.source_proposal`, `.source_only_neighbours`, `.source_only_central`, `.source_purchase_all`; lint/build; commit `feat(incidents): suministro de material para el periodo, vecinos primero`.

### Task 3: Hoja de envíos

**Files:** Create `src/components/incidents/MaterialShipmentSheet.tsx`; Modify `MissingMaterialsSections.tsx` (muestra la hoja cuando hay envíos de la incidencia); CSVs.

**Interfaces:**
- Carga `material_shipments` con `panelist_incident_id = incidentId` + items + material (`code`, `name`) + receptor (`panelists`: name, panelist_code, address_line1/2, address_city, address_country, mobile, node) + donante (`source_panelist_id` → mismos campos).
- Tabla: Origen (Almacén central | donante: nombre, nodo, dirección, teléfono) · Destino (nombre, nodo, dirección, teléfono) · Material (código, nombre) · Cantidad · Debe llegar (`expected_date` dd/MM/yyyy) · Estado (pendiente / enviado / parcial / recibido, con cantidades recibidas).
- Botones: **Imprimir / PDF** (HTML → `printPDF`), **Descargar Excel (CSV)** (`downloadCSV`), y por cada envío **central** en `pending`: **Marcar enviado** (`markShipmentSent` del hook con la cuenta del incidente) con `confirm()`.
- Claves `material_sheet.*` (título, columnas, estados, botones, `central_warehouse`, `confirm_mark_sent`).

- [ ] Steps: componente; enchufar; claves; lint/build; commit `feat(incidents): hoja de envios de material (pantalla, PDF, Excel)`.

### Task 3b: Estado `partially_received` en Stock

- [ ] `src/lib/materialCalculator.ts`: el material "en camino" cuenta envíos `pending`, `sent` y `partially_received`, y suma lo **pendiente** por línea (`quantity_sent - coalesce(quantity_received,0)`), no `quantity_sent`.
- [ ] Pestaña de envíos de Stock (`ShipmentsTab`): filtro y etiqueta para `partially_received` (clave `stock.status_partially_received` en 4 CSV) y cantidades recibidas visibles.
- [ ] lint/build; commit `fix(stock): envios parcialmente recibidos en el calculo y en la lista`.
- **Debe ir en producción antes que el flujo de recepción parcial del Plan 6.**

### Task 4: Verificación de claves y cierre

- [ ] Script de claves (todas las `t('…')` de `incident_conversation.*`, `material_sheet.*`, `reported_incidents.*` existen en los 4 CSV); lint/build; `graphify update .`; commit si hubo cambios.
