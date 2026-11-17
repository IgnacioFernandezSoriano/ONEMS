# Posición GPS al declarar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** registrar la posición del móvil al declarar envíos/recepciones por el bot, con permiso único auditable, sin bloquear nunca una declaración, abriendo incidencia de GPS al gestor y mostrando en el informe quién no registra con GPS.

**Architecture:** toda la lógica (permiso, visita de 30 min, distancia, estado por declaración, incidencias, enlace retroactivo) vive en funciones de BD de onems-dev; n8n solo captura mensajes, llama a esas funciones y envía textos. El informe lee nuevos campos de `ops_report._data`.

**Tech Stack:** Postgres (Supabase onems-dev `sehbnpgzqljrsqimwyuz`), tests SQL locales (`supabase/tests/run_tests.sh`, Postgres portable 5433); n8n Cloud (scripts Python que transforman el JSON del flujo + `push.py`); ops-agent Python (pytest); frontend React (CSV de traducciones).

**Spec:** `docs/superpowers/specs/2026-11-17-gps-declaracion-design.md` (leer entero: §4 flujo, §5 datos, §5.4 incidencias, §7 informe, §11 decisiones).

## Global Constraints

- Nunca bloquear, retener ni perder una declaración por el GPS: cualquier fallo de las funciones GPS se ignora en n8n (`continueOnFail`/`onError: continueRegularOutput`) y la declaración sigue igual.
- Antes de CUALQUIER escritura en Supabase: nombrar `onems-dev` + `sehbnpgzqljrsqimwyuz` y pedir confirmación explícita a Ignacio.
- n8n: DEV primero (main `eeM4E4RS1UDThvUF`); PROD (`IkVtek2csP5AbWxB`) solo tras pruebas OK de Ignacio. Backup JSON del flujo vivo antes de cada push en `panelist_n8n/backups/<id>_pre_gps_20261117.json`.
- Textos del bot en 5 idiomas (es/en/fr/ar/pt), escuetos; nunca decir al panelista que está lejos ni que se abrió incidencia.
- Web: 4 idiomas (en/es/fr/ar) en `public/locales/*.csv`. Informe: idiomas que ya tiene `report_i18n.py`.
- Umbrales: precisión 200 m; lejos = `distance_m − coalesce(accuracy_m,0) > 500`; visita 30 min; ubicación vieja > 5 min; borrado de coordenadas a 12 meses.
- Al copiar JSON de n8n al repo: tapar service_role (`<SUPABASE_SERVICE_ROLE_KEY>`) y claves Resend. No commit/push sin que Ignacio lo pida. Migración forward-only nueva, timestamp > `20261117120000`.

## Review Focus

1. Fallo de BD en una función GPS durante una declaración → la declaración se registra y el panelista ve su resultado normal (test: n8n con la función renombrada en DEV / test SQL de que `gps_mark_declaration` nunca lanza con detail inexistente).
2. Panelista sin `telegram_id`, sin nodo o en ciudad sin centros con coordenadas → estado `no_reference`, sin excepción (test SQL).
3. Dos visitas seguidas (> 30 min) → segunda incidencia distinta; dentro de 30 min → misma incidencia (test SQL).
4. Ubicación reenviada o antigua (`message.date` > 5 min) → ignorada como si no hubiera llegado (test SQL).
5. Panelista que retira el permiso y vuelve a darlo → histórico completo de filas y estado vigente = última (test SQL).

---

### Task 1: Esquema y funciones GPS en BD (local)

**Files:**
- Create: `supabase/migrations/20261117150000_gps_declaracion.sql`
- Test: `supabase/tests/gps_declaracion.test.sql` (seguir el estilo de `incident_auto_only.test.sql`: `DO $$ … ASSERT … $$`, fixtures propias)

**Interfaces (Produces):**
- Tablas `public.panelist_location_consent`, `public.declaration_location` (columnas exactas del spec §5.1/§5.2; `latitude`/`longitude` nullable; RLS por `account_id` con el mismo patrón que `panelist_incident`).
- Columnas en `allocation_plan_details`: `sent_location_id uuid`, `sent_gps_status text`, `received_location_id uuid`, `received_gps_status text` (CHECK con los 8 valores del spec §5.3).
- `pi_category_check` ampliado con `'gps_location'`.
- `gps_visit_start(p_panelist_id uuid, p_telegram_id text) returns jsonb` → `{need_consent bool, need_location bool, consent text|null}`; crea/reutiliza `panelist_context` `gps_visit` (spec §11).
- `gps_record_consent(p_panelist_id uuid, p_decision text, p_language text, p_text_version text, p_text text, p_message_id text) returns jsonb` → inserta fila; si `denied` abre incidencia `gps_location` (una vez por decisión denegada).
- `gps_save_location(p_panelist_id uuid, p_telegram_id text, p_lat numeric, p_lon numeric, p_accuracy numeric, p_msg_date timestamptz, p_msg_id text) returns jsonb` → `{action: 'stale'|'low_accuracy_retry'|'saved', status, location_id, distance_m}`; primera `low_accuracy` de la visita devuelve `low_accuracy_retry` sin guardar estado definitivo; segunda la guarda. Con `saved`: actualiza la visita, hace el enlace retroactivo (§11) y pasa a `auto_resolved` la incidencia de la visita si todas sus declaraciones quedan `ok`.
- `gps_set_unavailable(p_panelist_id uuid, p_telegram_id text) returns jsonb` → marca la visita y pasa a `gps_unavailable` las declaraciones `no_location` de la visita; añade a la incidencia.
- `gps_mark_declaration(p_detail_id uuid, p_kind text /*'sent'|'received'*/, p_panelist_id uuid) returns jsonb` → `{status, warn bool}`; `warn` = true solo la primera vez por visita que queda `no_location` (con permiso concedido y sin aviso previo); `no_answer` (permiso sin responder) no avisa ni abre incidencia. Abre/añade a la incidencia de la visita (spec §5.4) vía `insert_panelist_incident_auto` o actualizando su `payload`. Nunca lanza (`EXCEPTION WHEN OTHERS` → `{status:null, warn:false}`).
- `gps_purge_coordinates() returns int` + job pg_cron mensual (`'0 3 1 * *'`) que pone a NULL lat/lon con `captured_at < now() - interval '12 months'`.
- Todas `SECURITY DEFINER`, `search_path = public`, `EXECUTE` solo a `service_role` (las llama n8n con service_role).

- [ ] **Step 1:** escribir `gps_declaracion.test.sql` con estos casos (fixtures: cuenta, ciudad con 2 centros con coordenadas conocidas, nodo, panelista con telegram_id, un detail enviado y otro recibido):
  - consentimiento: sin filas → `need_consent=true`; `granted` → `need_consent=false, need_location=true`; `denied` → `need_location=false` y 1 incidencia `gps_location`; denied→granted→denied → 3 filas, vigente `denied`.
  - posición a 100 m de un centro, accuracy 20 → `saved`, `ok`; a 900 m, accuracy 50 → `far`; accuracy 350 → primero `low_accuracy_retry`, luego `saved/low_accuracy`; `p_msg_date = now()-10min` → `stale`; ciudad sin centros con coordenadas → `no_reference`.
  - `gps_mark_declaration` sin posición → `no_location`, `warn=true`, incidencia abierta; segunda declaración misma visita → `warn=false`, misma incidencia con 2 detalles en payload; posición válida después → ambas `ok`, incidencia `auto_resolved`.
  - visita caducada (forzar `created_at` −31 min) → nueva incidencia distinta.
  - sin permiso → `no_consent`, sin incidencia nueva; permiso sin responder → `no_answer`, `warn=false`, sin incidencia; detail inexistente → no lanza.
  - `gps_purge_coordinates` borra lat/lon de una fila de hace 13 meses y conserva `distance_m`.
- [ ] **Step 2:** `bash supabase/tests/run_tests.sh gps_declaracion` → FAIL (funciones no existen).
- [ ] **Step 3:** escribir la migración. Distancia haversine en SQL puro (radio 6371000 m); referencia = centros de `postal_centers` con `city_id` = ciudad del nodo del panelista (`nodes.city_id`) y coordenadas no nulas.
- [ ] **Step 4:** `bash supabase/tests/run_tests.sh gps_declaracion incident_auto_only incident_schema incident_triggers` → todos PASS.
- [ ] **Step 5:** sin commit (pedir a Ignacio al final).

### Task 2: Aplicar la migración en onems-dev

- [ ] **Step 1:** auditar en vivo (solo lectura) que `pi_category_check`, `panelist_context` y `insert_panelist_incident_auto` coinciden con lo que asume la migración.
- [ ] **Step 2:** pedir confirmación a Ignacio nombrando `onems-dev` + `sehbnpgzqljrsqimwyuz`; aplicar con `apply_migration` (nombre `gps_declaracion`).
- [ ] **Step 3:** verificar: `select gps_visit_start(<panelista DEV 9ba5739f-…>, <su telegram_id>)` devuelve `need_consent=true`; `get_advisors` security sin avisos nuevos sobre las tablas creadas.

### Task 3: Web — categoría de incidencia "Ubicación GPS"

**Files:** `src/lib/types.ts:552`, `src/pages/incidents/PanelistReportedIncidents.tsx:10`, `src/components/incidents/ReportedIncidentPanel.tsx:18` (ancla de guía `c-gps`), `public/locales/{en,es,fr,ar}.csv` (clave `reported_incidents.category.gps_location`: "GPS location" / "Ubicación GPS" / "Localisation GPS" / "الموقع الجغرافي (GPS)").

- [ ] **Step 1:** añadir la categoría en los 3 ficheros y las 4 claves.
- [ ] **Step 2:** mostrar en el panel de la incidencia la lista de envíos del `payload` (`details[]` con etiqueta y estado) y, si existe, la distancia; usar `useTranslation` para los textos nuevos (claves en los 4 CSV).
- [ ] **Step 3:** `npm run lint` y `npm run build` → 0 errores.

### Task 4: Bot DEV — permiso, ubicación y aviso

**Files:** Create `<scratchpad>/n8n/gps1.py` (mismo patrón que `botones3.py`/`botones5.py`: carga JSON, `rep()` con aserción de unicidad, nodos nuevos clonando credenciales de `Clear selected parcel ctx`, guarda JSON). Aplicar sobre el JSON vivo DEV y publicar con `push.py`.

**Interfaces:** consume las funciones de Task 1 vía nodos Postgres con `queryReplacement` (nunca SQL interpolado con `{{ }}`).

- [ ] **Step 1 (Route & Identify):** reconocer, antes del texto libre: `message.location` → acción `gps_location` (pasa lat, lon, `horizontal_accuracy`, `message.date`, `message_id`); texto igual al botón "🚫 Mi GPS no funciona" en cualquiera de los 5 idiomas → `gps_unavailable`; callbacks `gps_consent:yes|no` → `gps_consent`; `gps_retry` → `gps_retry`; `gps_consent_menu` → `gps_consent_menu`. Nuevas reglas al final de Main Router.
- [ ] **Step 2 (inicio de visita):** en las ramas de `show_pending_parcels`, `start_receipt`, `send_next`, `upload_photo_label` (y "Volver a declarar"), añadir en paralelo (segunda conexión de salida, sin esperar) un nodo `GPS visit start` → IF `need_consent` → mensaje de permiso (texto del spec §4.1, versión `v1`, 5 idiomas, botones inline Acepto/No acepto); IF `need_location` → mensaje con reply keyboard `[{text:"📍 …", request_location:true}],[{text:"🚫 …"}]`, `resize_keyboard`, `one_time_keyboard`.
- [ ] **Step 3 (respuestas):** `gps_consent` → `gps_record_consent` con el texto exacto mostrado → si yes, enviar el teclado de ubicación; si no, "Entendido" + Inicio. `gps_location` → `gps_save_location` → `stale`: ignorar en silencio; `low_accuracy_retry`: mensaje de precisión + pasos + teclado; `saved`: "✅ Ubicación registrada" con `remove_keyboard`. `gps_unavailable` → `gps_set_unavailable` → "Gracias, lo tenemos en cuenta" con `remove_keyboard`. `gps_retry` → reenviar teclado.
- [ ] **Step 4 (tras declarar):** en las ramas de éxito ("Receipt ok?" verdadero; resultado de `Call Process send photo` / `(text)` sin `error`), llamar `gps_mark_declaration(detail_id, 'received'|'sent', panelist_id)` con `onError: continueRegularOutput`, después de enviar el resultado normal; si `warn` → mensaje "⚠️ No hemos podido obtener tu posición" + pasos Android/iPhone + botones inline `gps_retry` / y teclado con "🚫 Mi GPS no funciona".
- [ ] **Step 5 (Ayuda):** botón `📍 Permiso de ubicación` (`gps_consent_menu`) en `Send help link`; muestra la decisión vigente y botones para cambiarla.
- [ ] **Step 6:** añadir los nuevos nodos de mensaje a `Build incident conversation logs` para que se registren en `incident_message`.
- [ ] **Step 7:** backup, push DEV, verificar `versionId == activeVersionId`.
- [ ] **Step 8:** dar a Ignacio las pruebas acción por acción (panelista DEV "Ignacio UPU"): permiso sí/no; compartir ubicación; GPS apagado; permiso de Telegram denegado; "Mi GPS no funciona"; declarar sin compartir y reintentar < 30 min (incidencia auto_resolved); punto elegido en el mapa (anotar si trae precisión — spec §9); Telegram de escritorio. Verificar cada una en ejecuciones n8n y BD.

### Task 5: Informe de operación — columna GPS y "Quién no registra con GPS"

**Files:** Create `supabase/migrations/20261117160000_ops_report_gps.sql` (redefine `ops_report._data` partiendo de su última definición viva — `pg_get_functiondef` en onems-dev — añadiendo por panelista `gps: {total, ok, far, low_accuracy, no_location, gps_unavailable, no_consent, no_answer, consent}` del periodo y en `config` la lista `gps_reference` de ciudades sin centro con coordenadas o con mediana `distance_m` > 500); test `supabase/tests/ops_report_gps.test.sql`. Modify `panelist_n8n/ops-agent/src/<pkg>/report_build.py` (tabla de panelistas `:284`, revisión de configuración `:335`), `report_i18n.py` (columna "GPS", glosario, sección, motivos), `report_html.py` si la sección necesita bloque propio; tests en `ops-agent/tests/test_report.py`.

- [ ] **Step 1:** test SQL: panelista con 3 declaraciones (`ok`, `far`, `no_location`) → `gps.total=3, ok=1, far=1, no_location=1`; declaraciones con estado NULL no cuentan; ciudad con mediana 900 m aparece en `gps_reference`. Run → FAIL; implementar; Run → PASS.
- [ ] **Step 2:** tests pytest: columna "GPS" con formato `ok/total` + `lejos`; color naranja si `ok/total < 0.8` o `far > 0`, rojo si `consent == 'denied'` o (`total >= 3` y `ok == 0`); sección "Quién no registra con GPS" lista solo panelistas con algún estado distinto de `ok` y su motivo dominante; glosario cubre la columna nueva (el test existente de "ninguna columna sin explicación" debe seguir pasando); "Registro anómalo" ya no dice "(aún no hay GPS)". Run `uv run pytest ops-agent/tests/test_report.py` → FAIL; implementar; → PASS.
- [ ] **Step 3:** aplicar la migración en onems-dev con confirmación explícita; generar un informe en modo revisión para DEMO2 y enviarlo solo a Ignacio; desplegar el agente con `deploy.ps1` tras su visto bueno.

### Task 6: Guía del panelista y aviso

**Files:** `public/help/panelist-guide.*.html` (sección con ancla `c-gps`: qué se recoge, para qué, cómo activar el GPS en Android/iPhone, cómo cambiar el permiso).
- [ ] **Step 1:** redactar en todos los idiomas que ya tenga la guía; comprobar que el ancla coincide con Task 3.
- [ ] **Step 2:** texto breve para que los gestores avisen a sus panelistas antes de PROD (entregar a Ignacio, no enviar).

### Task 7: PROD y repositorio

- [ ] **Step 1:** con el OK de Ignacio a las pruebas DEV, aplicar `gps1.py` sobre el JSON vivo PROD (backup previo), push, verificar credenciales PROD y `versionId == activeVersionId`.
- [ ] **Step 2:** sincronizar `workflows/telegram-user-initiated-message.json` y `dev-…` en panelist_n8n (rama `feat/bot-gps`), con claves tapadas; ONEMS: migraciones, tests, web, guía y spec/plan en rama `feat/gps-declaracion` desde `develop`.
- [ ] **Step 3:** commit y PR solo cuando Ignacio lo pida; actualizar memoria.
