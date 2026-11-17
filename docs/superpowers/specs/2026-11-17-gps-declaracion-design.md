# Posición GPS al declarar envíos y recepciones — diseño

Fecha: 2026-11-17 · Estado: pendiente de aprobación de Ignacio · Sistemas: bot de Telegram (n8n), BD onems-dev
(`sehbnpgzqljrsqimwyuz`), informe de operación por cuenta (ops-agent, panelist_n8n).

## 1. Por qué

Hoy "declaró un envío/recepción" no prueba que el panelista estuviera en la oficina o en su apartado. El informe de
operación solo puede dar indicios indirectos (horas raras, fin de semana, varios registros en el mismo minuto). Con la
posición del móvil en el momento de declarar, el gestor ve si el panelista estaba donde debía y quién no la está
dando. Es evidencia razonable, no prueba absoluta (se puede falsear).

## 2. Decisiones de Ignacio (17/11)

1. **Nunca se bloquea ni se pierde una declaración**, en ningún caso. Sin posición, la declaración se registra igual,
   queda marcada con el motivo y **se levanta una incidencia** para el gestor (§5.4).
2. **En todas las ciudades** (no solo POBOX).
3. **Permiso una sola vez**: la primera vez que el bot vaya a pedir la ubicación pide antes el permiso del panelista
   y deja constancia (qué texto vio, en qué idioma, cuándo, qué respondió) por si lo piden las autoridades. No se le
   recuerda periódicamente.
4. Si el panelista no puede dar la posición, el bot le **avisa de que no se ha podido obtener**, le explica cómo
   activar el GPS y le deja **reintentar** o **decir que su GPS no funciona**; en ese caso la lectura se gestiona
   normalmente.
5. Los **informes de panelistas** indican **quién no está registrando con GPS**.

## 3. Restricciones técnicas de Telegram (condicionan el diseño)

- El bot no puede leer ni activar el GPS: solo recibe la posición si el panelista pulsa un botón
  `request_location`, que existe **solo en teclado de respuesta** (reply keyboard), no en botones inline, y **solo en
  la app móvil** (no en escritorio ni web).
- Si el GPS del móvil está apagado o Telegram no tiene permiso, es el propio móvil quien lo pide; si el panelista lo
  rechaza, **no llega nada** al bot. El bot solo puede detectar la ausencia (el panelista sigue sin haber mandado
  ubicación) — no la causa.
- El mensaje de ubicación trae `latitude`, `longitude` y normalmente `horizontal_accuracy` (metros). Un punto
  elegido a mano en el mapa también llega como ubicación: hay que verificar en pruebas si trae precisión (ver §9).
- El EXIF de la foto de la etiqueta no sirve: Telegram lo elimina en las fotos comprimidas.

## 4. Flujo en el bot

### 4.1 Permiso (una vez por panelista)
Al primer momento en que tocaría pedir la ubicación (§4.2) y el panelista no tiene decisión registrada, el bot
muestra un texto breve (5 idiomas) — qué se recoge (posición solo al declarar), para qué (comprobar que la
declaración se hace en la oficina/apartado), quién lo ve (los responsables de su cuenta y el equipo técnico de UPU; texto v2), cuánto se guarda (§6) y que puede cambiar la
decisión desde Ayuda — con botones inline **"✅ Acepto"** / **"❌ No acepto"**.
- Se registra la decisión (§5.1). Acepta → sigue a §4.2. No acepta → no se le vuelve a pedir ubicación; todas sus
  declaraciones quedan `no_consent`.
- Si en lugar de responder manda una foto/etiqueta, la declaración se procesa con `no_answer` y el permiso se vuelve
  a plantear al empezar la siguiente visita (hasta que responda).
- **Ayuda → "📍 Permiso de ubicación"** muestra la decisión actual y permite cambiarla (retirar el permiso debe ser
  tan fácil como darlo). Cada cambio es una fila nueva; nunca se borra el histórico.

### 4.2 Pedir la ubicación: una vez por visita
- Momento: al pulsar **"📤 Confirmar un envío"** o **"📥 Confirmar una recepción"** (y sus equivalentes "Declarar
  otra…", "Siguiente envío", "Volver a declarar"), **si no hay una posición válida de los últimos 30 minutos**.
- El bot envía "📍 Comparte tu ubicación para registrar dónde declaras" con un teclado de respuesta de dos botones:
  **"📍 Compartir mi ubicación"** (`request_location`) y **"🚫 Mi GPS no funciona"** (texto). El mensaje siguiente
  del bot retira el teclado (`remove_keyboard`).
- **El flujo de declaración sigue en paralelo**: el panelista puede mandar la foto/etiqueta sin compartir la
  ubicación; nunca se le hace esperar.
- Una posición válida cubre **todas las declaraciones de esa visita durante 30 minutos**.

### 4.3 Casos
| Caso | Qué hace el bot | Marca en la declaración |
|---|---|---|
| Llega ubicación con precisión ≤ 200 m | "✅ Ubicación registrada", retira teclado | `ok` o `far` (§5.3) |
| Llega con precisión > 200 m (o sin precisión) | Primera vez: "📍 Tu posición es poco precisa", pasos para activar la ubicación precisa, botones **🔁 Reintentar** / **🚫 Mi GPS no funciona**. Segunda vez: la acepta | `low_accuracy` (o `ok`/`far` si el reintento sale bien) |
| Declara (foto/etiqueta) sin haber mandado ubicación | La declaración se procesa normal. **Después** del resultado, el bot añade: "⚠️ No hemos podido obtener tu posición", pasos para activarla (Android / iPhone: ubicación activada, permiso de Telegram "mientras se usa", ubicación precisa) y botones **🔁 Reintentar** / **🚫 Mi GPS no funciona**. Solo una vez por visita | `no_location` |
| Pulsa "🚫 Mi GPS no funciona" | "Gracias, lo tenemos en cuenta" + sigue | `gps_unavailable` (para la visita) |
| Sin permiso | No pide nada | `no_consent` |
| Ubicación vieja (mensaje de hace > 2 min, p. ej. reenviada) | Se ignora y se trata como "sin ubicación" | — |

**Enlace retroactivo:** una posición válida que llega dentro de los 30 min se liga también a las declaraciones del
mismo panelista de los 30 min anteriores que estén en `no_location` (cubre "declaré y luego reintenté").

### 4.4 Mensajes
Escuetos, 5 idiomas (es/en/fr/ar/pt), como el resto del bot. **Nunca** se le dice al panelista que está lejos de la
oficina ni se le acusa de nada (regla de mensajes escuetos).

## 5. Datos (BD onems-dev, migración nueva forward-only)

### 5.1 `panelist_location_consent` (histórico, nunca se borra)
`id`, `account_id`, `panelist_id`, `telegram_id`, `decision` (`granted`|`denied`), `decided_at`, `language`,
`consent_text_version`, `consent_text` (texto exacto mostrado), `telegram_message_id`, `source` (`bot`).
Decisión vigente = última fila del panelista. RLS por `account_id`.

### 5.2 `declaration_location` (una fila por posición recibida)
`id`, `account_id`, `panelist_id`, `telegram_id`, `captured_at` (fecha del mensaje de Telegram), `received_at`,
`latitude`, `longitude`, `accuracy_m` (nullable), `nearest_postal_center_id`, `distance_m`, `status`
(`ok`|`far`|`low_accuracy`|`no_reference`), `telegram_message_id`. RLS por `account_id`.

### 5.3 Marca en cada declaración
En `allocation_plan_details`: `sent_location_id`, `sent_gps_status`, `received_location_id`, `received_gps_status`.
Valores de `*_gps_status`: `ok`, `far`, `low_accuracy`, `no_reference`, `no_location`, `gps_unavailable`,
`no_consent`, `no_answer`. Las declaraciones anteriores a la puesta en marcha quedan en NULL (= "antes del GPS") y
no cuentan en los informes.

**Distancia y referencia:** referencia = centro postal (`postal_centers` con coordenadas) **de la ciudad del nodo del
panelista** más cercano a la posición. `far` = `distance_m − coalesce(accuracy_m,0) > 500`. Sin centro con
coordenadas en esa ciudad → `no_reference`. El cálculo se hace en una función de BD (haversine; no hace falta PostGIS)
para que n8n solo llame y reciba el estado.

Nota: los nodos no tienen coordenadas; Kenya tiene 29/29 centros con coordenadas y DEMO2 7/7, pero **no está
verificado que sean las oficinas del apartado** de cada panelista. Ver §8.

## 5.4 Incidencia de GPS (decisión de Ignacio, 17/11)
Ningún envío/recepción queda bloqueado ni retenido por el GPS, pero **cada problema de GPS levanta una incidencia**
para el gestor (pantalla de Incidencias de ONEMS, categoría nueva `gps_location`, en los 4 idiomas de la web):
- **Una incidencia por visita**, no por paquete: agrupa todas las declaraciones de esa visita sin GPS válido (lista
  de envíos y estados en el `payload`; `allocation_plan_detail_id` = la primera). Se abre con la primera declaración
  de la visita que quede en `no_location`, `gps_unavailable`, `low_accuracy` o `far`, y las siguientes de la misma
  visita se añaden a ella.
- **Se resuelve sola** (`auto_resolved`) si dentro de la ventana de 30 min llega una posición válida y todas sus
  declaraciones pasan a `ok` (enlace retroactivo). Si no, queda abierta para el gestor.
- **Sin permiso:** una sola incidencia cuando el panelista responde "No acepto" (no una por visita), para que el
  gestor hable con él. `no_answer` no abre incidencia (se vuelve a preguntar).
- Al panelista no se le dice que se ha abierto una incidencia (mensajes escuetos); el aviso "no hemos podido obtener
  tu posición" ya le indica qué hacer. Cada incidencia registra los mensajes del bot y del panelista en
  `incident_message`, como el resto.
- Se crea con la función existente `insert_panelist_incident_auto`.

## 6. Privacidad y conservación
- Solo se guarda la posición enviada al declarar; nunca seguimiento continuo (no se pide ubicación en directo).
- Coordenadas exactas (`latitude`, `longitude`) se borran a los **12 meses** (tarea pg_cron diaria); se conservan
  `distance_m`, `status` y el centro de referencia. Los registros de permiso se conservan siempre.
- Solo visible para la cuenta del panelista (RLS) y el superadmin; nunca en Telegram de managers ni en el repo.

## 7. Informe de operación por cuenta (ops-agent, L-X-V)
- `ops_report._data` añade por panelista, en el periodo: declaraciones con GPS `ok`, `far`, sin GPS (por motivo) y
  su decisión de permiso.
- **Anexo 1 Panelistas**: columna **"GPS"** = `con posición / total` + `lejos` (naranja si < 80 % con posición o
  algún `far`; rojo si `no_consent` o 0 % en ≥ 3 declaraciones). Se añade a su glosario en todos los idiomas.
- **Sección nueva "Quién no registra con GPS"** (dentro de "Lo importante" si hay alguno): nombre, ciudad, motivo
  dominante (no dio permiso / dice que su GPS no funciona / no la envía / posición poco precisa) y nº de
  declaraciones afectadas.
- **Revisión de configuración**: ciudades sin centro con coordenadas, y ciudades donde la **mediana** de distancia
  de declaraciones `ok/far` supera 500 m (indicio de que la coordenada de referencia está mal, no el panelista).
- La columna "Registro anómalo" sustituye "(aún no hay GPS)" por los `far`.

## 8. Puesta en marcha
1. BD en onems-dev (con confirmación explícita antes de aplicar). 2. Bot DEV, pruebas con el panelista DEV "Ignacio
UPU" (móvil Android e iPhone si es posible; GPS apagado; permiso denegado; punto elegido en mapa; escritorio).
3. Informe. 4. Aviso a los gestores; actualización de la guía del panelista (sección "Ubicación"). 5. Bot PROD.
6. Tras 2 semanas, revisar en el informe las ciudades con mediana alta y corregir coordenadas de referencia.

## 9. A verificar en pruebas (no bloquea el diseño)
- Si un punto elegido en el mapa llega sin `horizontal_accuracy` → si es así, tratarlo como `low_accuracy`.
- Que el trigger de n8n entrega mensajes `location` y textos del teclado de respuesta al flujo principal.

## 10. No objetivos
- Hacer la ubicación obligatoria o bloquear (descartado por Ignacio).
- Usar el GPS como prueba en la regla POBOX de recepción (fase posterior posible).
- Pantalla/mapa en ONEMS para el gestor (posible después; el informe es el canal ahora).
- Detección de apps de falsear ubicación más allá de lo de §9 y de coordenadas repetidas exactas (las marca el
  informe como dato, sin estado propio).

## 11. Decisiones tomadas por mí (revisar)
- **Visita** = fila `panelist_context` con `context_type = 'gps_visit'` (tabla ya usada por el bot), creada al
  pedir la ubicación (§4.2) y válida 30 min desde `created_at` (hora del servidor). `context_data`:
  `{location_id|null, gps_unavailable: bool, warned: bool, consent_asked: bool}`. Caducada o inexistente → visita
  nueva. Ahí viven el aviso "una sola vez", el "GPS no funciona" de la visita y la ventana de 30 min.
- **Cuándo se marca una declaración:** solo cuando queda registrada con éxito (mismo punto donde hoy se escribe
  `sent_at` / `received_at`), con una función de BD `gps_status_for_declaration(panelist_id) → (location_id, status)`
  que lee la visita vigente y el permiso. Declaraciones fallidas o duplicadas no cambian ningún envío, así que no se
  marcan.
- **Enlace retroactivo:** al llegar una posición válida, actualiza los envíos del panelista con `sent_at` /
  `received_at` en los 30 min anteriores (hora del servidor) cuyo estado sea `no_location` o `no_answer` y les pone el
  `location_id` y el estado calculado.
- **Referencia de distancia:** el más cercano de los centros con coordenadas de la ciudad del nodo del panelista;
  si declara en otra ciudad saldrá `far`, y eso es justo lo que queremos ver.
- **Retención:** `latitude`/`longitude` son nullable; a los 12 meses se ponen a NULL y la fila se conserva (las
  marcas siguen apuntando a ella).
- **Ubicación vieja:** `message.date` de Telegram frente a la hora del servidor, con tolerancia de **5 min** (absorbe
  colas y desfases).
- **Teclado de respuesta:** el texto "🚫 Mi GPS no funciona" (5 idiomas) y los mensajes `location` se reconocen en
  "Route & Identify" **antes** que el texto libre, con acción propia; el resto del bot no cambia.
- Idiomas: 5 (es/en/fr/ar/pt), como ya tiene el bot.
- Umbrales: precisión 200 m; "lejos" 500 m netos de precisión; ventana de visita 30 min.
- Permiso revocable desde Ayuda; `no_answer` vuelve a preguntar en la siguiente visita.
- Borrado de coordenadas a 12 meses.
- Aviso "no hemos podido obtener tu posición" una sola vez por visita, después del resultado de la declaración.

## 12. Cambios tras la puesta en marcha (17/11)
- Permiso: el histórico sobrevive al borrado del panelista (`panelist_id` NULL + código y nombre guardados), migración
  `20261117170000_gps_consent_keep`; borrado de coordenadas diario.
- Texto del permiso v2 (quién lo ve: responsables de la cuenta y equipo técnico de UPU).
- Registro propio de interacciones del bot en Supabase (`bot_interaction_log`, sin coordenadas, 60 días,
  `20261117180000_bot_interaction_log`); n8n solo guarda ejecuciones con error. Sin ejecuciones n8n adicionales.
- Tras compartir la ubicación (o "Mi GPS no funciona") el bot vuelve a mostrar el envío elegido, el modo recepción o
  la lista.
