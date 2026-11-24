# GPS: referencias de casa y apartado por panelista — diseño

Fecha: 2026-11-20 · Estado: pendiente de aprobación de Ignacio · Sistemas: bot de Telegram (n8n), BD onems-dev
(`sehbnpgzqljrsqimwyuz`), informe de operación (ops-agent, panelist_n8n), pruebas diarias del agente.
Continúa y modifica `2026-11-17-gps-declaracion-design.md` (en adelante, «diseño del 17/11»).

## 1. Por qué

En las ciudades con apartado de correos (POBOX) el panelista debe declarar **en su apartado**. El GPS del 17/11
compara cada posición con la oficina de correos de la ciudad del nodo, pero:

1. **La regla actual nunca da una posición por buena.** Exige `horizontal_accuracy` ≤ 200 m, y Telegram **no
   envía la precisión** en una ubicación compartida una vez (solo en la ubicación en directo). Resultado real (17–20/11):
   las 36 posiciones de Kenya (17 panelistas) y las de DEMO2 son `low_accuracy`; `accuracy_m` es NULL en todas. Cada
   una abre incidencia y el bot pide reintentar sin motivo.
2. **No sabemos dónde está el apartado de cada panelista** (solo la oficina de su ciudad, con coordenadas no
   verificadas) **ni dónde está su casa**, que es el error que queremos detectar. Las distancias medidas son muy
   estables por panelista (p. ej. Nakuru 2.272–2.274 m, Meru 838–879 m): o declaran siempre desde el mismo sitio
   (¿casa?) o la coordenada de la oficina está mal. Hoy no se puede distinguir.
3. La dirección de la ficha no sirve para situar la casa en Kenya: la mayoría son un nombre de barrio o el propio
   número de apartado («Box 123-20100»). Descartado geolocalizar direcciones (además, sacaría datos personales a un
   servicio externo).
4. Efecto colateral: las pruebas diarias del agente (panelista de prueba en DEMO2, que no puede mandar GPS) abren
   cada mañana una incidencia `gps_location` que las pruebas no esperan → aviso «las pruebas dejaron efectos
   inesperados» en el informe de salud, y las incidencias se acumulan sin borrar (4 abiertas, 17–20/11).

Éxito: el gestor ve, por panelista, si declara en su apartado, desde casa o en un sitio dudoso, sin ruido de
incidencias falsas; y el panelista de una ciudad POBOX aprende la regla.

## 2. Decisiones de Ignacio (20/11)

1. **Juzgar por distancia**, no por la precisión que Telegram no envía.
2. **Referencias por panelista**: ubicación de su **apartado** y de su **casa**, obtenidas por el bot con la ubicación
   de Telegram (no geolocalizando la dirección).
3. **En el alta**: tras la dirección, se pide el permiso de ubicación y se pregunta «¿Estás en tu apartado de
   correos?». **No** → se deduce que está en casa y esa posición es la casa. **Sí** → esa posición es su apartado.
   Normalmente están en casa al darse de alta.
4. **En la declaración**: la pregunta «¿desde dónde declaras?» se hace **solo cuando la posición no está en el sitio
   correcto** (no en cada visita; opción A, 20/11). Sirve para **educar** (recordar la regla en ese momento) y, en
   los panelistas ya dados de alta, para obtener sus referencias («proceso puntual»: no hay campaña aparte).
5. **Incidencias** (§5.8): cada diferencia → pregunta + recordatorio automáticos, incidencia `auto_resolved`;
   **3 visitas seguidas** con diferencia → incidencia abierta para el gestor, que lo trata con el panelista y deja
   constancia en el **historial del panelista**, que se abre también desde la incidencia.
6. Clasificación propuesta y aceptada: cerca del apartado = bien; cerca de casa = «declaró desde casa»; resto =
   dudoso (solo informe).
7. Sigue vigente del 17/11: **nunca se bloquea ni se pierde una declaración** por nada de esto; mensajes escuetos,
   nunca acusar al panelista.
8. **El «sitio correcto» depende de la ciudad** (20/11): en ciudad POBOX es **el apartado**; en ciudad **sin POBOX**
   es **su casa** (la dirección de envío). Se controla igual en los dos casos: que declare desde su sitio correcto.
   Por tanto la casa se captura en todas las cuentas: en POBOX es el sitio a evitar, en no-POBOX el sitio correcto.

> Consecuencia: hoy Senegal y DEMO2 se comparan con la oficina de correos de la ciudad, que en ciudad sin POBOX es
> la referencia equivocada. Con este diseño pasan a compararse con la casa.

## 2 bis. Decisiones de Ignacio del 23/11 (PREVALECEN sobre §5.4 y §5.8 donde choquen)

Objetivo: **no ser pesado con el panelista**.
1. Solo cuando la posición sale **fuera del rango** de su sitio correcto, el bot pregunta: ciudad POBOX → «¿Estás en
   tu apartado de correos?»; ciudad sin POBOX → «¿Estás en tu domicilio?». Si la posición está bien, no se pregunta
   nada. Una sola pregunta por visita (lote de 30 min), como en §5.4.
2. **Responde «Sí»** → con esa información **se ajusta el modelo**: esa posición pasa a ser su referencia
   (`pobox` o `home`, `source = declaration`) para juzgar las visitas siguientes. **No hay incidencia** ni
   recordatorio. Si queda lejos de la oficina o de la ciudad (comprobaciones §5.6) se marca `needs_review` y el
   gestor la ve en el informe. Se registra lo que ha contestado (`self_reported_place` en las declaraciones de la
   visita).
3. **Responde «No»** (confirma que declara desde un sitio que no le toca) → el bot le envía un **recordatorio**
   escueto de que debe declarar donde le toca, y se registra una incidencia `gps_location` **ya resuelta**
   (`auto_resolved`) con la pregunta, la respuesta y el recordatorio en `incident_message`, **solo para el control
   estadístico** posterior (informe L-X-V, como hoy).
4. **Reincidencia:** solo estadística. **No** se abre incidencia al gestor tras N visitas seguidas (se elimina la
   regla «3 visitas seguidas → incidencia abierta» de §5.8.2-3). El informe L-X-V muestra quién reincide y el
   gestor actúa si quiere (el historial del panelista de §5.8 bis sigue disponible para sus notas).
5. **Sin respuesta:** nada (ni incidencia ni mensaje); la declaración queda «lejos, sin respuesta» y sale en el
   informe.
6. **Momento de la pregunta (24/11, tras dos pruebas reales de Ignacio):** la pregunta se hace **al principio, sola**,
   en cuanto llega la ubicación, y la lista de envíos se enseña **después de contestar**. Si no contesta, al volver a
   pulsar «Confirmar un envío» la ubicación ya vale y va directo a la lista, sin repetir la pregunta (una vez por
   visita y por posición). Se probó y se descartó «preguntar a la vez que la lista» (confunde) y «al terminar la
   declaración». Migración `20261123190400_gps_place_ask_at_location`.
7. Fase 1 (aplicada el 23/11, migraciones `20261123180000..180200`): «lejos» ya no abre incidencia; solo
   `no_location` / `gps_unavailable` / `no_consent` la abren, como el 17/11.

## 3. Restricciones

- Telegram: el bot solo recibe la posición si el panelista pulsa un botón `request_location` (teclado de respuesta,
  solo app móvil); un punto elegido a mano en el mapa también llega como ubicación (no detectable). Sin precisión en
  ubicaciones puntuales.
- «Ciudad POBOX» = `effective_city_policy(city_id).pobox_enabled` (como `ops_fix._pobox_no_send`). Hoy ninguna
  ciudad lo tiene a nivel de ciudad; Kenya lo hereda de `account_config.pobox_enabled = true`. Senegal y DEMO2: no.
- **Permiso:** el texto vigente (v3) dice que la ubicación se usa «solo para comprobar que declaras en la oficina o en
  tu apartado». Guardar la casa es un **uso nuevo** → texto **v4** que el panelista acepte antes de guardar su casa
  (ver §6). Sin v4 aceptado no se guarda ninguna referencia de casa.
- Privacidad ya en marcha (18/11): «🗑 borrar mis datos» en Ayuda, purga de ejecuciones n8n con coordenadas
  (`location_purge.py`), coordenadas de declaraciones borradas a 12 meses.
- Lógica en funciones de BD; n8n solo captura y llama. DEV antes que PROD. Escrituras en onems-dev con confirmación
  explícita.

## 4. Enfoques considerados

| Enfoque | Pros | Contras | Decisión |
|---|---|---|---|
| A. Geolocalizar la dirección de la ficha (Google u otro) | Automático, sin molestar | En Kenya da el centro del barrio o la oficina (error de km); datos personales a un tercero | Descartado |
| B. Pedir la casa con un mensaje aparte («cuando estés en casa, pulsa aquí») | Simple | Depende de que el panelista lo haga; no educa | Solo como respaldo (§5.3) |
| C. **Ubicación en el alta + pregunta «¿desde dónde declaras?» cuando la posición no cuadra** | Exacto, sin terceros, educa en el momento, obtiene referencias de los ya dados de alta sin campaña; quien declara bien no ve nada | Depende de la honestidad de la respuesta (mitigado en §5.6 y §5.8) | **Elegido por Ignacio** (la variante «pregunta en cada visita» se descartó: un paso más para quien declara bien) |
| D. «Lugar habitual» deducido de las posiciones repetidas | Sin preguntar | Indirecto; no sabe si el lugar es casa | Solo como indicio en el informe mientras falten referencias |

## 5. Diseño

### 5.1 Arreglo inmediato (se puede entregar antes que el resto)
1. `gps_save_location`: el estado deja de depender de `accuracy_m`. Mientras no haya referencias (§5.2), con la
   oficina de la ciudad: `ok` si `distance_m ≤ 300`, `far` si > 300 (umbrales en §5.4). Si llega precisión (> 200 m)
   se guarda como dato, sin cambiar el estado. Se quita el paso «📍 Tu posición es poco precisa → Reintentar».
2. Recalcular los `declaration_location` existentes y las marcas `*_gps_status` de sus declaraciones con la regla
   nueva; las incidencias `gps_location` abiertas cuyo único motivo era `low_accuracy` pasan a `auto_resolved` con una
   nota («regla corregida 20/11: Telegram no envía la precisión»).
3. Incidencias: `low_accuracy` y `far` dejan de abrir incidencia por visita (pasan al informe). `no_location`,
   `gps_unavailable` y `no_consent` siguen como en el diseño del 17/11 (ver §9, decisión mía).
4. Pruebas diarias: `ops_test._expected_incidents()` acepta también `gps_location` del panelista de prueba (así
   `ops_test._reset()` la borra con sus mensajes). Borrar las 4 incidencias de prueba acumuladas (17–20/11) y sus
   `incident_message`.

### 5.2 Datos nuevos: `panelist_location_reference`
Una fila por referencia: `id`, `account_id`, `panelist_id`, `kind` (`home`|`pobox`), `latitude`, `longitude`,
`captured_at`, `source` (`registration`|`declaration`|`reminder`), `location_id` (fila de `declaration_location` de
la que sale, si aplica), `distance_to_postal_center_m`, `needs_review` (bool) + `review_reason`, `active` (bool),
`created_at`. Referencia vigente = la última `active` por `(panelist_id, kind)`. RLS por `account_id`, como
`declaration_location`. Se incluye en «🗑 borrar mis datos» y se borra al dar de baja al panelista; **no** caduca a
los 12 meses (se necesita mientras sea panelista).

### 5.3 Alta (flujo `register-new-panelist`)
Pasos hoy: nombre → teléfono → calle → extra → código postal → ciudad → país. Paso nuevo **`location`** tras
`country` (cuando ya se conoce la cuenta):
1. Texto de permiso **v4** con ✅ Acepto / ❌ No acepto (se registra en `panelist_location_consent` como siempre).
   No acepta → el alta termina igual, sin referencias.
2. Pregunta según el tipo de ciudad (la ciudad que escribe el panelista en el alta, resuelta contra `cities` de la
   cuenta; si no se resuelve, la política de la cuenta):
   - **POBOX:** «¿Dónde estás ahora mismo?» → **📮 En mi apartado de correos** / **🏠 No, en otro sitio** (= casa).
   - **Sin POBOX:** «¿Estás ahora en tu casa (la dirección que nos has dado)?» → **🏠 Sí** / **⏰ No, más tarde**.
3. Teclado con «📍 Compartir mi ubicación» (+ «⏰ Más tarde»). Llega la posición → referencia `pobox` o `home` con
   `source = registration`. El paso va **después** de insertar el panelista (hace falta su `panelist_id`); las
   comprobaciones de §5.6 que dependen del nodo se calculan cuando el gestor le asigna nodo.
4. «Más tarde» o no llega nada → el alta termina igual. Respaldo (enfoque B): si al día siguiente sigue sin
   referencia `home`, un recordatorio «Cuando estés en casa, pulsa aquí» (una sola vez; después solo por §5.4).
   Si la primera referencia fue `pobox`, el mismo recordatorio pide la casa.

### 5.4 Declaración: la pregunta solo cuando no cuadra (opción A, Ignacio 20/11)
**Una sola pregunta por lote** (Ignacio, 20/11): cualquier pregunta de este apartado se hace **una vez por visita**
(ventana de **30 minutos** desde la primera declaración, la misma «visita» del diseño del 17/11) y la respuesta vale
para **todas las declaraciones del lote**; dentro de esa media hora no se vuelve a preguntar ni a recordar la regla,
aunque declare más paquetes.

La petición de ubicación de la visita no cambia (diseño del 17/11 §4.2). Al llegar la posición se clasifica (§5.5):
- **`ok`** → nada más; el panelista no ve ninguna pregunta.
- **Diferencia** (`from_home` o `far`) → pregunta «¿desde dónde declaras?» y, si procede, recordatorio (§5.8.1).
  Con la respuesta, si aún no hay referencia de ese sitio, se guarda (`source = declaration`, comprobaciones §5.6):
  - POBOX, «📮 Desde mi apartado» sin referencia `pobox` → `pobox` (candidata; `needs_review` si está a > 1.000 m de
    la oficina).
  - «🏠 Desde mi casa» sin referencia `home` (y con permiso v4) → `home`.
  - Si ya hay referencia, la respuesta no la cambia (corregirla es cosa del gestor, §5.8 bis).
- La respuesta se guarda (`self_reported_place`: `pobox`|`home`|`other`) en cada declaración de la visita (§5.7).
- Si no tiene v4 y responde «desde mi casa», se le muestra v4 una vez (acepta → se guarda la casa; no → no se guarda
  y no se vuelve a pedir).

**Ciudad sin POBOX sin referencia `home`:** no hay con qué comparar (`no_reference`), así que no se detectaría
nunca una diferencia. Mientras falte la casa, en cada visita se pregunta «¿Estás en tu casa?» → **🏠 Sí** (se
guarda como `home`) / **📍 No** («Recuerda: las declaraciones se hacen desde tu casa.»). Con la casa guardada, la
pregunta deja de hacerse. *(Decisión mía: es la única forma de obtener la casa de los ya dados de alta en estas
ciudades.)*

**Ciudad POBOX sin referencia `pobox`:** se compara con la oficina de la ciudad (como hoy); la referencia propia
llega por la pregunta de las diferencias.

### 5.5 Clasificación de cada posición
Sitio correcto = `pobox` vigente (ciudad POBOX; si no hay, la oficina más cercana de la ciudad del nodo, como hoy) o
`home` vigente (ciudad sin POBOX; si no hay → `no_reference`, **no** se compara con la oficina). Orden:
1. a ≤ 300 m del sitio correcto → **`ok`**
2. solo POBOX: a ≤ 150 m de la casa → **`from_home`**
3. si no → **`far`** (dudoso)
4. sin referencia → `no_reference`

POBOX: si casa y apartado están a < 300 m entre sí no se pueden distinguir: la referencia queda `needs_review` y la
posición cuenta como `ok`. Umbrales en configuración (no fijos en código) para ajustarlos con datos reales.

### 5.6 Comprobaciones de las referencias (contra respuestas falsas)
Una referencia queda `needs_review` (la ve el gestor en el informe; no bloquea ni cambia mensajes) si:
- `pobox` a > 1.000 m de la oficina de correos más cercana de su ciudad (¿dijo «sí» desde casa? ¿coordenada mal?);
- POBOX: `home` a < 200 m de su oficina de correos (¿se dio de alta en la oficina?);
- POBOX: `home` y `pobox` a < 300 m entre sí;
- `home` a > 5 km del centro de la ciudad de su nodo (¿se dio de alta fuera de casa, o vive fuera de la ciudad?).

**Reclasificación al aparecer una referencia** (decisión mía): se recalculan las marcas de las declaraciones de los
últimos 14 días para el informe, pero **no** se abren incidencias retroactivas.

### 5.7 Marcas en la declaración
`allocation_plan_details`: valores nuevos de `sent_gps_status` / `received_gps_status`: `from_home`;
`low_accuracy` deja de generarse (queda en filas antiguas hasta el recálculo de §5.1.2). Columnas nuevas
`sent_self_reported_place` / `received_self_reported_place`.

### 5.8 Diferencias de lugar: automático primero, gestor si se repite (Ignacio, 20/11)
**Diferencia** = visita cuya posición no está en el sitio correcto (`from_home` o `far`).

1. **En cada diferencia, automático:** el bot pregunta al panelista desde dónde declara — POBOX: «📮 Desde mi
   apartado / 🏠 Desde mi casa / 📍 Desde otro sitio»; sin POBOX: «🏠 Desde mi casa / 📍 Desde otro sitio».
   - Si contesta un sitio que **no** es el correcto → **recordatorio de la regla** (escueto, sin acusar).
   - Si contesta el sitio correcto pero la posición dice otra cosa → se anota la contradicción (la ve el gestor en
     el historial); sin mensaje extra al panelista. Si aún no hay referencia de ese sitio, se guarda como referencia
     candidata con `needs_review` (§5.6) — así se resuelven las oficinas con coordenadas mal (p. ej. Nakuru 2,27 km).
   - Se registra una incidencia `gps_location` **`auto_resolved`** con la pregunta, la respuesta y el recordatorio
     en `incident_message` (registro de comunicaciones, como todas las incidencias).
   - Sin respuesta en la visita → la incidencia queda igualmente `auto_resolved` con «sin respuesta».
2. **Se repite en el tiempo = 3 visitas seguidas con diferencia** (Ignacio, 20/11; antes 5) (sin ninguna visita `ok` entre medias) → se abre
   una incidencia `gps_location` **abierta, para el gestor**: tratar con el panelista si declara bien o no. La
   cuenta se reinicia con una visita `ok` o cuando el gestor resuelve la incidencia.
3. Mientras esa incidencia esté abierta no se abren más (las nuevas diferencias se añaden a ella).
4. Las incidencias no se mencionan al panelista.

### 5.8 bis Historial de lo tratado con el panelista
Al resolver la incidencia del punto 2, el gestor elige un **resultado** — `declara_bien` (la referencia estaba mal),
`corregido` (habló con él y se compromete), `reincide`, `otro` — y escribe una nota. Ficha nueva
`panelist_follow_up` (`account_id`, `panelist_id`, `topic` = `gps_place`, `incident_id`, `outcome`, `note`,
`created_by`, `created_at`; RLS por cuenta) que guarda **cada cosa tratada**, también las notas que el gestor añada
sin incidencia. En ONEMS, la ficha del panelista muestra su historial (tratamientos + incidencias GPS automáticas
resumidas). **Desde la incidencia** (pantalla Incidencias, panel de detalle) hay un botón «Historial del panelista»
que abre ese mismo historial sin salir de la incidencia (Ignacio, 20/11): lo tratado antes, las incidencias GPS
automáticas con la pregunta, la respuesta y el recordatorio, y las referencias de casa/apartado con su estado de
revisión. Textos en los 4 idiomas de la web. El informe L-X-V cita el último resultado junto a los panelistas que reinciden. *(El tema `gps_place` es
el primero; la tabla sirve para otros temas más adelante.)*
Si el resultado es `declara_bien`, la referencia que causaba la diferencia se marca para recaptura (`active = false`).

### 5.9 Informe de operación (L-X-V)
- Columna GPS: `en apartado / desde casa / dudoso / sin posición`.
- «Quién no registra con GPS» se mantiene; nueva línea «Declaran desde casa» (nombre, ciudad, nº de visitas).
- Revisión de configuración: referencias `needs_review` con su motivo; panelistas POBOX sin referencias; oficinas
  cuya mediana de distancia sigue alta.
- Mientras un panelista no tenga referencia `home`: indicio de «lugar habitual» (≥ 3 posiciones a < 100 m entre sí,
  fuera del apartado) marcado «probablemente casa».

### 5.10 Pruebas diarias del agente
El panelista de prueba (DEMO2, sin POBOX) no ve la pregunta. Si DEMO2 pasara a POBOX, la prueba debe contestarla
(fuera de alcance ahora). Con §5.1.4 la incidencia de «sin posición» deja de contar como efecto inesperado.

## 6. Texto de permiso v4 (borrador, 5 idiomas; lo revisa Ignacio)
Cambia «Lo usamos solo para comprobar que declaras en la oficina o en tu apartado» por «Lo usamos para comprobar que
declaras desde el sitio que te corresponde (tu apartado de correos o, si en tu ciudad no hay, tu casa)» y añade
«🏠 Guardamos una vez la ubicación de tu casa y, si tienes, de tu apartado». Mantiene: no te seguimos, solo cuando
pulsas el botón, puedes borrarlo desde Ayuda.

Reglas (decisiones mías):
- **Un solo permiso v4** cubre la posición al declarar y las referencias (casa y apartado). En el alta se pide v4.
- **No acepta v4 en el alta** = igual que «No acepto» del 17/11 (`no_consent`, una incidencia, no se vuelve a
  pedir; puede activarlo desde Ayuda).
- **Panelistas con v3**: siguen declarando con v3; la primera vez que haya que **guardar una referencia** (casa o
  apartado) se muestra v4 una vez. Acepta → se guarda. No acepta → no se guarda ninguna referencia y no se vuelve a
  pedir v4 (sigue con v3; sus posiciones se comparan con la oficina como hoy, o `no_reference` en ciudad sin POBOX).

## 7. Puesta en marcha
1. **§5.1 arreglo inmediato** (BD + bot, DEV → PROD) — independiente, va primero.
2. BD: tabla de referencias, clasificación nueva, incidencias, v4.
3. Bot DEV: paso del alta, pregunta por visita, recordatorio. Pruebas con el panelista DEV en Android/iPhone.
4. Informe. 5. Aviso a gestores y guía del panelista (sección «Ubicación»). 6. Bot PROD.
7. Tras 2 semanas: revisar `needs_review` y oficinas con mediana alta; ajustar umbrales.

## 8. No objetivos
- Geolocalizar direcciones; ubicación en directo; detectar puntos elegidos en el mapa.
- Bloquear o retrasar declaraciones o altas.
- Pantalla/mapa en ONEMS para editar referencias (posible después; ahora el gestor las ve en el informe).
- Usar el GPS como prueba en la regla POBOX de recepción.

## 9. Decisiones tomadas por mí (revisar)
- Umbrales: apartado 300 m, casa 150 m, revisión pobox > 1.000 m de la oficina, casa < 200 m de la oficina.
- `no_location`, `gps_unavailable`, `no_consent` mantienen sus incidencias del 17/11; solo `low_accuracy`/`far`
  dejan de abrirlas por visita.
- «Seguidas» = visitas con posición consecutivas del panelista; las visitas sin posición no cuentan ni reinician.
- Una referencia guardada no la cambia el panelista con sus respuestas; corregirla (borrarla para que se vuelva a
  capturar) queda para el gestor vía soporte/Claude hasta que exista pantalla.
- Referencias sin caducidad a 12 meses; se borran con «🗑 borrar mis datos» y con la baja.
- Ciudad sin POBOX: la pregunta por visita solo hasta tener la casa; umbral de «casa = sitio correcto» 300 m.
- En el alta se usa la ciudad escrita por el panelista (o la política de la cuenta); el paso va tras insertar.
- Recordatorio de casa: uno solo, al día siguiente del alta.
- Referencias del 20/11 con permiso: ver §6.
