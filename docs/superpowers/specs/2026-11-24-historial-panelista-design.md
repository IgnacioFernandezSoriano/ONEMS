# Historial del panelista (diseño)

Fecha: 2026-11-24. Base: onems-dev `sehbnpgzqljrsqimwyuz`. Continúa §5.8 bis de
`2026-11-20-gps-casa-apartado-design.md`, rehecho con lo que Ignacio decidió el 24/11.

## 1. Por qué
Cuando un gestor trata algo con un panelista (una incidencia, una baja, un error de recepción) hoy no ve lo que ha
pasado antes con él: está repartido en varias pantallas y no hay ningún sitio donde apuntar lo que se habla con él.
Ignacio (24/11): una pantalla con el historial del panelista, **accesible desde los puntos donde se está
interactuando con él**.

Éxito: desde cualquier incidencia o lista donde aparece un panelista, un clic abre su historial sin perder el sitio;
el gestor ve en orden lo que ha pasado y deja una nota de lo que ha hablado.

## 2. Objetivos, no objetivos, anti-objetivos
- Objetivos: historial único y ordenado por fecha; notas del gestor; botón en los puntos de contacto.
- No objetivos: el panelista **nunca** ve el historial ni las notas; el bot no cambia; desde esta pantalla no se
  envía nada al panelista ni se resuelve nada (para eso están las pantallas actuales, a las que se enlaza).
- Anti-objetivos: que muestre datos de otra cuenta; que sea lento al abrir (se abre a menudo); que una sección
  falte en silencio porque un rol no puede leer una tabla.

## 3. Decisiones de Ignacio (24/11)
1. Historial completo (todo lo que ha pasado con el panelista + notas), no solo notas de GPS.
2. Se abre como **panel lateral** encima de la pantalla donde estás (opción A del boceto), sin salir de ella.
3. Construcción: **una función en la base** que lo junta todo (enfoque A); la web hace una llamada.
4. Notas: texto libre con autor y fecha, las ve cualquier gestor de la cuenta, solo el autor borra la suya, sin
   «resultado» obligatorio (lo propuse y lo dio por bueno).
5. **Quién lo ve (24/11, tras la revisión):** solo quien gestiona panelistas, es decir quien puede **ver** la opción
   `panelists` (por plantilla: Account Manager, Panelist Manager, UPU account manager, Allocation Plan Manager). Ven
   el historial **entero**. Escriben notas quienes pueden **editar** `panelists` (AM, PM, UPU). El proveedor de
   materiales y el DO coordinator no ven el botón.

## 4. Enfoques
| Enfoque | Ventajas | Inconvenientes | |
|---|---|---|---|
| **A. Función en la base** que devuelve el historial ya ordenado + cifras | Una llamada; «cargar más» fácil; permisos en un sitio; reutilizable por el agente/bot | Cada fuente nueva = migración | **Elegido** |
| B. La web consulta cada tabla y mezcla | Casi no toca la base | 6-7 consultas; paginación difícil; huecos silenciosos por RLS; no reutilizable | Descartado |

## 5. Diseño

### 5.1 Datos nuevos: `panelist_note`
`id uuid pk`, `account_id uuid not null`, `panelist_id uuid not null references panelists on delete cascade`,
`body text not null` (1–2000 caracteres), `created_by uuid not null` (auth.uid()), `created_at timestamptz default now()`.
RLS activado sin políticas de escritura directa; lectura y escritura solo por las funciones de 5.2. Borrado real (no
lógico) solo por su autor.

### 5.2 Funciones (SECURITY DEFINER, `search_path` fijo, EXECUTE solo `authenticated`)
*(Decisión mía tras la revisión: nada para `service_role` en esta entrega — `has_access` necesita `auth.uid()` y
`created_by` también. Si el agente o el bot lo necesitan, será una función aparte.)*
- `panelist_history(p_panelist_id uuid, p_before timestamptz DEFAULT NULL, p_limit int DEFAULT 50) RETURNS jsonb`
  - Permiso: `has_access(cuenta del panelista, 'panelists', 'view')` (decisión de Ignacio, §3.5). Si no → 42501.
  - Devuelve `{"panelist": {...}, "stats": {...}, "events": [...], "next_before": ts|null, "can_write": bool}`.
  - `panelist`: código, nombre, móvil, ciudad del nodo, nodo, POBOX sí/no, fecha de alta, estado, idioma.
  - `stats` (últimos 30 días salvo indicación): envíos registrados / programados; recepciones con problema
    (`receipt_case` con motivo distinto de `ok*`); «No» de GPS; días de baja del año; apartado/casa guardados
    (sí/no, «a revisar»).
  - `events`: lista ordenada por fecha descendente, cortada en `p_limit`, más antiguos que `p_before`. Cada evento:
    `{"at": ts, "type": ..., "subtype": ..., "status": ..., "title_key": ..., "data": {...}, "link": {...}}`.
    Fuentes y tipo:
    - `note` — `panelist_note` (cuerpo, autor por nombre o correo, `can_delete` si es suyo).
    - `incident` — `panelist_incident` del panelista (categoría, estado, descripción corta, fecha `reported_at`).
      Las de `gps_location` con `payload.reason = 'wrong_place'` salen como tipo `gps` («dijo No»).
    - `receipt` — `receipt_case` donde es el receptor (`panelist_id`) o el culpable como remitente
      (`culprit_panelist_id`, `culprit_role = 'sender'`); motivo, estado, etiqueta, fecha `first_attempt_at`.
      Se omiten `ok`, `ok_same_city`.
    - `leave` — `panelist_unavailability` (del–al, motivo, `review_status`, `status`), fecha `created_at`.
    - `notice` — `panelist_notification` con `kind = 'manager_notice'` (texto del aviso), fecha de creación.
    - `gps_ref` — `panelist_location_reference` activas o `declined` (apartado/casa guardado, «a revisar»,
      «no quiere guardar su casa»), fecha `created_at`. **Sin coordenadas** en la respuesta.
  - `link`: pantalla y id para «ver» (incidencia reportada, baja, error de recepción).
  - `can_write`: `has_access(cuenta, 'panelists', 'edit')`.
- `panelist_note_add(p_panelist_id uuid, p_body text) RETURNS uuid` — requiere `can_write`; valida longitud.
- `panelist_note_delete(p_note_id uuid) RETURNS void` — solo si `created_by = auth.uid()` (o superadmin).

### 5.3 Pantalla: panel lateral «📋 Historial»
- Componente único `PanelistHistoryDrawer` (derecha, ~60 % del ancho en escritorio, pantalla completa en móvil) con
  hook `usePanelistHistory(panelistId)` (página → hook → supabase, como el resto).
- Cabecera: código y nombre, ciudad/nodo/POBOX, alta, móvil; fichas con las cifras de `stats`.
- Caja «Añadir nota…» + Guardar (solo si `can_write`).
- Filtros: Todo · Notas · Incidencias · Recepciones · GPS · Bajas · Avisos (filtran lo ya cargado; «cargar más»
  pide la página siguiente con `next_before`).
- Cada evento: fecha, icono, una línea de texto, estado; notas propias con «borrar» (con confirmación).
- «ver ›» abre la pantalla de origen **en una pestaña nueva** (el panel y la pantalla donde estabas no se pierden)
  y solo se muestra si el usuario puede ver esa pantalla (`reported_incidents`, `panelist_availability`,
  `receipts`). *(Decisión mía tras la revisión.)* Enlace directo por URL: las bajas ya lo tienen
  (`?unavailability=<id>`); se añade `?incident=<id>` a Incidencias reportadas y `?case=<id>` a Errores de
  recepción, que abre el caso directamente aunque sea de otro día (sin parámetro, ambas pantallas se comportan
  exactamente como hoy).
- Se cierra con ✕ o Esc y vuelves donde estabas.
- **Textos en los 4 idiomas** (EN/ES/FR/AR, RTL incluido); nada fijo en el componente.

### 5.4 Dónde está el botón «📋 Historial»
Junto al nombre del panelista en: detalle de incidencia reportada (`ReportedIncidentHeader`), incidencias de baja
(`PanelistAvailabilityIncidents`), errores de recepción (detalle del caso y tabla de quién repite fallos), y cada
fila de la lista de panelistas (`Panelists`). Se muestra solo si el usuario puede ver `panelists`.

### 5.5 Pruebas
- BD (Postgres local, `supabase/tests/`): aislamiento entre cuentas (usuario de otra cuenta → 42501), rol sin
  ver `panelists` (p. ej. proveedor de materiales) → 42501, rol con ver pero sin editar → `can_write` false y
  `panelist_note_add` rechazado, orden y paginación, cada fuente aparece con su tipo, `wrong_place` sale
  como `gps`, sin coordenadas en la salida, nota: añadir/borrar propio/no borrar ajeno, longitud.
- Web: `npm run lint` y `npm run build`; prueba en navegador con DEMO2.

## 6. Puesta en marcha
Migración en onems-dev con confirmación → web en `develop` (Netlify dev) → prueba de Ignacio en DEMO2 → PR a `main`
avisando antes qué verán Kenya/Senegal (el botón nuevo en esas pantallas).

## 7. Decisiones mías (revisar)
- «ver ›» en pestaña nueva, oculto sin permiso de la pantalla de destino; enlaces `?incident=` y `?case=` nuevos.
- Sin acceso para `service_role` en esta entrega.
- 50 eventos por página; recepciones `ok*` fuera; mensajes individuales de las conversaciones **no** salen (se ven
  entrando en la incidencia), solo la incidencia.
- Las coordenadas de casa/apartado nunca salen en el historial (privacidad, consentimiento v4).

## 8. Lo que queda al constructor
Nombres exactos de claves de i18n, iconos, estilos del panel, forma exacta del texto de cada evento, índices.
