# ONEMS Carrier Link — Manual de conexión para carriers

Versión 1.0 (borrador para revisión) · contrato de demanda `schema_version` **1.1**

> Este manual va dirigido al equipo técnico del carrier que va a construir el **conector**: el programa que,
> desde los sistemas del carrier, contesta a las peticiones de ONEMS. No hace falta conocer ONEMS de antes.
> Todos los identificadores de los ejemplos (demandas, estratos, lotes, envíos) son **ilustrativos**: salen de
> un carrier simulado ("SIMPOST") y no existen en ningún sistema real.

---

## Índice

1. [Introducción y objetivo](#1-introducción-y-objetivo)
2. [Conceptos y glosario](#2-conceptos-y-glosario)
3. [Qué tiene que hacer el conector](#3-qué-tiene-que-hacer-el-conector)
4. [Autenticación y claves](#4-autenticación-y-claves)
5. [Calendario y peticiones (`GET /demands`)](#5-calendario-y-peticiones-get-demands)
6. [Selección de envíos](#6-selección-de-envíos)
7. [Envío de lotes (`POST /batches`)](#7-envío-de-lotes-post-batches)
8. [Equivalencias que configura ONEMS](#8-equivalencias-que-configura-onems)
9. [Respuestas y errores](#9-respuestas-y-errores)
10. [Ensayo y certificación](#10-ensayo-y-certificación)
11. [Ejemplo completo](#11-ejemplo-completo)
12. [Preguntas frecuentes](#12-preguntas-frecuentes)
13. [Contacto](#13-contacto)

---

## 1. Introducción y objetivo

ONEMS es la plataforma que usa el regulador postal para medir la calidad del servicio: cuánto tarda un envío
desde que entra en la red postal hasta que se entrega. Hasta ahora lo mide con envíos de prueba que mueven
personas voluntarias (panelistas).

**Carrier Link** añade otra fuente: envíos **reales** del carrier, elegidos **al azar**, con las lecturas
(escaneos) que el propio carrier ya registra en sus sistemas. Así la medida cubre muchos más envíos sin que
nadie tenga que mover paquetes de prueba.

El intercambio es siempre el mismo y lo inicia el conector del carrier:

1. ONEMS publica **peticiones** ("demandas"): qué rutas, qué semanas, cuántos envíos y en qué puntos de lectura.
2. El conector las **lee** (`GET`), busca en los datos del carrier los envíos que cumplen las condiciones,
   **elige al azar** unos cuantos y **devuelve sus lecturas** a ONEMS (`POST`) en uno o varios **lotes**.
3. ONEMS valida los lotes, hace su propio sorteo entre los candidatos válidos y los convierte en muestras.

Principios importantes:

- **El carrier nunca recibe conexiones de ONEMS.** Es el conector el que llama a ONEMS por HTTPS. No hay que
  abrir puertos ni dar acceso a las bases de datos del carrier.
- **El conector envía los datos con los nombres y valores propios del carrier.** La traducción a los
  conceptos de ONEMS (las "equivalencias", §8) la configura el equipo de ONEMS.
- **No se envían datos personales** (nombres, teléfonos, direcciones o correos de remitentes o destinatarios).
- **Se puede ensayar todo sin consecuencias** (modo ensayo, `dry_run`, §10) antes de pasar a producción.

---

## 2. Conceptos y glosario

| Concepto | Qué es |
|---|---|
| **Envío / registro** | Un objeto postal identificado por su número de seguimiento (`item_id` en ONEMS). |
| **Lectura (escaneo)** | Un evento registrado por el carrier sobre un envío: qué envío, cuándo, dónde y qué tipo de evento (admisión, entrega…). El conector envía **una fila por lectura**. |
| **Punto de lectura** | Un lugar del carrier (oficina, centro…) más, opcionalmente, un tipo de evento (`mode_ref`). Cada punto pertenece a una ciudad y hace de **inicio** (origen), de **fin** (destino) o de ambos. Los da de alta ONEMS con los códigos del carrier (`place_ref`, `mode_ref`). |
| **Muestra** | Un envío real que ONEMS ha elegido para la medida. Su tiempo de tránsito va de su primera lectura en un punto de inicio a su última lectura en un punto de fin. |
| **Petición o demanda** | Un encargo de ONEMS al conector, con un identificador (`demand_id`) y una lista de estratos. |
| **Estrato** | Una parte de la demanda: una ruta (ciudad de origen → ciudad de destino) durante un periodo (una semana ISO), con sus puntos de inicio y de fin, el número de muestras que hacen falta (`samples_required`) y el número de candidatos que el conector debe enviar (`candidates_requested`). Se identifica con `stratum_id`. |
| **Población** | Cuántos envíos del estrato cumplen las condiciones (§6). El conector la cuenta y la informa (`population_size`), aunque solo envíe unos pocos. |
| **Candidato** | Cada envío elegido al azar por el conector dentro de la población. |
| **Registro cerrado** | Un envío que ya tiene lectura de inicio **y** lectura de fin. Solo se seleccionan registros cerrados. |
| **Lote** | Un `POST` del conector con las lecturas de los candidatos de uno o varios estratos de una demanda. Lo identifica el conector con su propio `batch_id`. |
| **Ensayo (`dry_run`)** | Envío de un lote solo para validarlo: ONEMS contesta qué haría, pero **no guarda nada**. |
| **Conector** | El programa del carrier que habla con ONEMS. En ONEMS tiene una ficha propia, con un estado: **en pruebas** (`testing`), **activo** (`active`) o **pausado** (`paused`). |
| **Clave** | El secreto con el que el conector se identifica ante ONEMS (§4). |

Glosario rápido de campos:

| Campo | Dónde aparece | Significado |
|---|---|---|
| `demand_id` | demanda, lote | Identificador de la demanda (UUID). |
| `stratum_id` | demanda, lote, respuesta | Identificador del estrato (UUID). |
| `batch_id` | lote | Identificador del lote, lo elige el conector (texto, máx. 200 caracteres). |
| `place_ref` / `mode_ref` | demanda | Código de lugar / código de tipo de evento del punto, **con los valores del carrier**. |
| `period` | demanda | Periodo del estrato: `start`, `end` (fechas, ambas incluidas) e `iso_week`. |
| `samples_required` | demanda | Muestras que ONEMS necesita de ese estrato. |
| `candidates_requested` | demanda | Candidatos que el conector debe sortear y enviar. |
| `population_size` | lote | Tamaño de la población del estrato contada por el conector. |
| `selection_method` | lote | Siempre `uniform_random_within_stratum`. |
| `rows` | lote | Las lecturas de los candidatos, una fila por lectura. |

---

## 3. Qué tiene que hacer el conector

### 3.1. Visión de conjunto

```
   ONEMS                                          CONECTOR DEL CARRIER
   ─────                                          ────────────────────
   1. Emite demandas según el calendario
      del conector (p. ej. cada lunes, 03:00)
                                     ◀── GET  /demands ───  2. Pide las demandas abiertas
      { "demands": [ ... ] }         ─────────────────────▶
                                                            3. Para cada estrato:
                                                               a. cuenta la población (§6)
                                                               b. sortea los candidatos (§6)
                                                               c. reúne sus lecturas (§6)
                                                            4. Agrupa estratos en lotes (§7)
                                     ◀── POST /batches ────  5. Envía cada lote
   6. Valida, sortea, crea muestras  ─────────────────────▶
      y contesta con un resumen                             7. Guarda la respuesta; reintenta
                                                               con el MISMO batch_id si falla
```

### 3.2. Paso a paso

1. **Programar la consulta.** Ejecutar el conector en los días del calendario (§5.1), **a partir de la hora
   siguiente** a la de emisión. Por ejemplo, si el calendario dice 06:00, consultar a partir de las 07:00.
2. **Leer las demandas abiertas** con `GET /demands` (§5). Si la lista está vacía, no hay nada que hacer.
3. **Por cada demanda y cada estrato**:
   1. Calcular la **población**: los envíos cerrados del producto que cumplen la regla de §6.1.
   2. **Sortear** `candidates_requested` envíos de la población con probabilidad uniforme (o todos, si la
      población es menor).
   3. Reunir **todas** las lecturas de esos candidatos en los puntos de inicio o de fin de **cualquier**
      estrato de la demanda (o todas sus lecturas, si la demanda trae `include_all_scans: true`).
4. **Construir los lotes** (§7): un estrato va entero en un único lote (no se puede partir); un lote puede
   llevar varios estratos; como máximo 5.000 lecturas y 5 MB por lote. Si un solo estrato no cabe en esos
   límites, avise al equipo de ONEMS.
5. **Recomendado: ensayar** cada lote con `?dry_run=true` y revisar la respuesta.
6. **Enviar los lotes** de verdad con `POST /batches`. Guardar cada `batch_id` y cada respuesta.
7. **Si un envío falla** por red, `429` o `5xx`, **reintentar el mismo lote con el mismo `batch_id`**: ONEMS no
   lo carga dos veces (§7.4).
8. Cuando todos los estratos de la demanda se han entregado, la demanda desaparece de `GET /demands`.

> El conector no necesita guardar estado de ONEMS entre ejecuciones más allá de los `batch_id` ya enviados,
> pero se recomienda conservar demandas, lotes y respuestas (sin datos personales) para poder auditar.

---

## 4. Autenticación y claves

### 4.1. Dirección base

```
https://<proyecto>.supabase.co/functions/v1/carrier-link-ingest
```

El equipo de ONEMS facilitará la dirección exacta (`<proyecto>`). Todas las llamadas son HTTPS y van
**de servidor a servidor** (la API no admite llamadas desde un navegador).

| Operación | Método y ruta |
|---|---|
| Leer demandas abiertas | `GET  {base}/demands` |
| Enviar un lote | `POST {base}/batches` |
| Ensayar un lote | `POST {base}/batches?dry_run=true` |

### 4.2. Cómo enviar la clave

En **cada** petición, con una de estas dos cabeceras (si vienen las dos, se usa `x-api-key`):

```
x-api-key: <clave>
```
```
Authorization: Bearer <clave>
```

En el `POST` hay que enviar además `Content-Type: application/json`.

### 4.3. Ciclo de vida de la clave

- **La emite ONEMS** (un responsable de la cuenta) para **un conector concreto**. La clave solo sirve para
  ese conector: solo ve sus demandas y solo puede entregar lotes para ellas.
- Tiene la forma `onems_` seguida de 48 caracteres hexadecimales.
- **Se muestra una sola vez**, en el momento de crearla. ONEMS guarda solo una huella (hash), no la clave:
  si se pierde, no se puede recuperar; hay que pedir una nueva.
- Puede tener **fecha de caducidad**. Una clave caducada o desactivada deja de funcionar inmediatamente
  (`401`).
- **Rotación**: se pide una clave nueva, se cambia en el conector y se pide a ONEMS que desactive la anterior.
- Guárdela como cualquier otro secreto (gestor de secretos, variable de entorno protegida). No la escriba en
  registros, código fuente ni correos.

### 4.4. Límites

| Límite | Valor | Qué pasa si se supera |
|---|---|---|
| Peticiones por clave en cualquier ventana de 60 segundos (ventana móvil) | **30** | `429` — esperar y reintentar |
| Tamaño máximo del cuerpo de un lote | **5 MB** (5.242.880 bytes) | `413 CL_BODY_TOO_LARGE` |
| Lecturas (filas) por lote, sumando todos sus estratos | **5.000** | `413 CL_TOO_MANY_ROWS` |
| Demandas devueltas por `GET /demands` | **100** (las más antiguas primero) | las siguientes aparecen al cerrarse las anteriores |
| Longitud de `batch_id` | **200** caracteres | `400 CL_BAD_PAYLOAD` |
| Longitud de identificador de envío, lugar o modo | **200** caracteres | esa lectura se rechaza (`bad_value`) |
| Longitud del valor de un campo adicional | **500** caracteres (solo texto, número o booleano) | ese campo no se guarda |

Para el límite de peticiones cuentan **todas** las peticiones con una clave válida (`GET` y `POST`, también
las que acaban en error `4xx`), salvo las que reciben `429`. Las peticiones con clave inválida (`401`) no
cuentan.

---

## 5. Calendario y peticiones (`GET /demands`)

### 5.1. Cuándo aparecen las demandas

- Cada conector tiene en ONEMS un **calendario de emisión**: unos días de la semana y una hora, en una zona
  horaria (la del conector o, si no tiene, la de la cuenta del regulador). Por defecto: **lunes a las 03:00**.
  El calendario se acuerda con el carrier para no cargar sus sistemas en horas punta.
- Las demandas aparecen **unos minutos después** de la hora del calendario (ONEMS las prepara con un proceso
  periódico). Recomendación: consultar a partir de la **hora siguiente** a la de emisión.
- Una semana entra en una demanda cuando ha terminado y ha pasado además un **plazo de cierre** (por defecto
  7 días), para dar tiempo a que los envíos de esa semana lleguen a destino.
- Una demanda agrupa **todas** las semanas y rutas que ya han pasado su plazo de cierre y aún necesitan
  muestras. Las rutas cuyas ciudades aún no tienen puntos de inicio o de fin dados de alta no aparecen.
- Cada demanda trae su propio calendario (`schedule`) a título informativo.

### 5.2. Petición

```http
GET /functions/v1/carrier-link-ingest/demands HTTP/1.1
Host: <proyecto>.supabase.co
x-api-key: onems_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Respuesta `200`:

```json
{ "demands": [ { ...demanda... }, { ...demanda... } ] }
```

Solo aparecen las demandas **abiertas** (estado `open`) del conector de la clave. Si no hay ninguna:
`{ "demands": [] }`.

### 5.3. La demanda, campo a campo

Ejemplo (ilustrativo, recortado a dos de sus doce estratos; completo en [`ejemplo/01-get-demands.json`](ejemplo/01-get-demands.json)):

```jsonc
{
  "schema_version": "1.1",                       // versión del formato de la demanda
  "demand_id": "761bcb4a-f8b9-40b3-9aef-6a85d80018ee",   // se devuelve tal cual en cada lote
  "carrier": "SIMPOST",                          // código del carrier en ONEMS
  "products": ["STD"],                           // códigos de producto/servicio TAL COMO LOS USA EL CARRIER
  "include_all_scans": false,                    // true = devolver TODAS las lecturas de los candidatos
  "schedule": {                                  // calendario de emisión de este conector (informativo)
    "days": [1, 2, 3, 4, 5, 6, 7],               // días ISO: 1 = lunes … 7 = domingo
    "hour": 6,                                   // hora local de emisión (0-23)
    "timezone": "Africa/Nairobi"                 // zona horaria del calendario
  },
  "strata": [
    {
      "stratum_id": "0004551b-71cb-4c48-b658-ae65533cb1ff",
      "period": {
        "start": "2026-11-02",                   // primer día del periodo (incluido)
        "end": "2026-11-08",                     // último día del periodo (incluido)
        "iso_week": "2026-W45"
      },
      "start_points": [                          // puntos de INICIO (ciudad de origen de la ruta)
        { "place_ref": "EMR-PO", "mode_ref": "ACC" }
      ],
      "end_points": [                            // puntos de FIN (ciudad de destino de la ruta)
        { "place_ref": "SVL-PO", "mode_ref": "DLV" }
      ],
      "samples_required": 2,                     // muestras que hacen falta
      "candidates_requested": 10                 // candidatos que el conector debe enviar
    },
    {
      "stratum_id": "615738ca-1bf6-4ecb-89e5-0de0cbf2e5c0",
      "period": { "start": "2026-11-02", "end": "2026-11-08", "iso_week": "2026-W45" },
      "start_points": [ { "place_ref": "SVL-PO", "mode_ref": "ACC" } ],
      "end_points":   [ { "place_ref": "EMR-PO", "mode_ref": "DLV" } ],
      "samples_required": 2,
      "candidates_requested": 10
    }
  ]
}
```

Detalles:

- **`products`** puede tener varios valores: todos los códigos del carrier que equivalen al producto medido.
  Un envío pertenece al producto si su código de producto es uno de ellos.
- **`start_points` / `end_points`** pueden tener varios puntos; basta con una lectura en cualquiera de ellos.
- **`mode_ref` puede ser `null`**: el punto es "cualquier evento en ese lugar". Una lectura en ese lugar vale
  con cualquier tipo de evento… salvo que el mismo lugar tenga también dado de alta un punto con ese tipo de
  evento concreto: entonces la lectura pertenece a ese punto concreto (el más específico gana). ONEMS aplica
  esta regla con **todos** los puntos de lectura del carrier dados de alta, no solo con los que aparecen en la
  demanda. Para reproducirla exactamente, el conector necesita la **lista completa de puntos**, que ONEMS
  entrega al configurar la conexión (§8.4) y actualiza cuando cambia; sin ella, la población contada por el
  conector puede no coincidir con la de ONEMS.
- **`candidates_requested`** es mayor que `samples_required` a propósito (por defecto 5 veces): ONEMS descarta
  candidatos no válidos o ya usados y luego sortea entre los que quedan.
- Un mismo `stratum_id` puede volver a aparecer en una **demanda posterior** (otro `demand_id`) si faltaron
  muestras de esa semana; en ese caso `samples_required` pide solo lo que falta (§5.4).
- `samples_required` puede ser mayor que lo previsto para esa semana: incluye las muestras que faltaron en
  semanas anteriores de la misma ruta y que ONEMS ha pasado a esta (§5.4).

### 5.4. Estados y caducidad de una demanda

| Estado | Significado | ¿Admite lotes? |
|---|---|---|
| `open` | Abierta, esperando lotes. Es la única que devuelve `GET /demands`. | Sí |
| `fulfilled` | Todos sus estratos se han entregado y todos tienen las muestras pedidas. | No (`409`) |
| `partial` | Todos sus estratos se han entregado, pero alguno con menos muestras de las pedidas. | No (`409`) |
| `failed` | Caducada, cerrada por ONEMS o anulada. | No (`409`) |

- Una demanda queda **cerrada** cuando se han entregado **todos** sus estratos (en uno o varios lotes).
- **Caducidad: 7 días.** Si una demanda sigue abierta 7 días después de emitirse, ONEMS la da por fallida, la
  retira y avisa al equipo de ONEMS. Los lotes de esa demanda que aún no se hubieran procesado del todo
  tampoco se procesan ya.
- Si faltan muestras de un estrato, ONEMS lo **vuelve a pedir** en una demanda nueva solo cuando todavía hay
  envíos que no ha visto: la población declarada era mayor que los candidatos recibidos, o la demanda caducó
  sin respuesta. Cada semana de una ruta se pide como mucho tres veces (sin contar las demandas de prueba,
  §10.2).
- En los demás casos, lo que falta **se pasa a las semanas siguientes de la misma ruta**: por eso una semana
  posterior puede pedir más muestras de las previstas.

---

## 6. Selección de envíos

Esta es la parte más importante: si el conector selecciona de otra forma, la medida deja de ser válida.

### 6.1. Población de un estrato (regla exacta)

Un envío forma parte de la población del estrato si cumple **todo** lo siguiente, considerando solo lecturas
con fecha y hora legibles:

1. **Es del producto**: **todas** sus lecturas de inicio y de fin llevan uno de los códigos de `products`.
   ONEMS valida el producto lectura a lectura: si una sola lectura del envío trae un código sin equivalencia,
   el envío se rechaza (`unknown_product`); si una lectura válida es de otro producto, se rechaza
   (`product_mismatch`).
2. **Tiene lectura de inicio**: al menos una lectura en uno de los `start_points` del estrato. La lectura de
   inicio es la **primera** (la más antigua) de ellas.
3. **Tiene lectura de fin**: al menos una lectura en uno de los `end_points` del estrato **distinta de la
   lectura de inicio**. La lectura de fin es la **última** (la más reciente) de ellas.
4. **Está cerrado dentro del periodo**: la fecha **local** de esa última lectura de fin cae entre
   `period.start` y `period.end`, ambos incluidos. La fecha local es la de la zona horaria del regulador
   (normalmente la del país; ONEMS la confirma al configurar el conector, §8).

Consecuencias:

- **Solo registros cerrados.** Un envío sin lectura de fin (todavía en camino, perdido, o entregado en otra
  ciudad que no es la del estrato) no cuenta.
- **Manda la última lectura de fin.** Si un envío tiene una lectura de fin el día 8 y otra el día 9 (por
  ejemplo, se escaneó como entregado por error y luego se entregó de verdad), su fin es el día 9: si el periodo
  acaba el 8, **no** es de la población. ONEMS aplica exactamente esta regla y lo rechazaría como
  `end_out_of_period`.
- La lectura de inicio puede ser anterior al periodo (un envío admitido el viernes anterior y entregado el
  lunes es del periodo del lunes).
- **No filtre por calidad de datos.** Si un envío cumple la regla pero tiene datos raros (por ejemplo, una
  entrega con hora anterior a la admisión), sigue contando en la población y puede salir sorteado: ONEMS lo
  rechazará con su motivo y lo verá en el resumen. Filtrar antes sesgaría la medida.
- Un mismo envío puede pertenecer a varios estratos (por ejemplo, de semanas distintas en demandas distintas);
  ONEMS descarta los que ya son muestra (`already_sampled`).

`population_size` es el número de envíos que cumplen la regla: **todos**, no solo los enviados.

### 6.2. Sorteo de candidatos

- Elegir `candidates_requested` envíos de la población **al azar con la misma probabilidad para todos**
  (muestreo aleatorio simple sin reemplazo). Si la población es menor, enviar todos.
- No elegir "los primeros", "los últimos", "los más rápidos" ni ningún otro criterio.
- Se recomienda un sorteo **reproducible** (semilla fija + `demand_id` + `stratum_id`) para poder auditarlo.
- En el lote se declara `"selection_method": "uniform_random_within_stratum"`. Cualquier otro valor hace que
  ONEMS **rechace el lote entero** (§9.2).

### 6.3. Qué lecturas enviar de cada candidato

- Con `include_all_scans: false` (lo normal): **todas** las lecturas del candidato que estén en un punto de
  inicio o de fin de **cualquier** estrato de la demanda, **de cualquier ciudad** de la demanda, no solo las
  de su estrato. Así ONEMS detecta envíos mal encaminados (por ejemplo, una lectura de entrega en otra
  ciudad). El conector solo conoce los puntos que trae la demanda, así que esta detección cubre las ciudades
  que aparecen en sus estratos; ONEMS marca un posible mal encaminado con cualquiera de los puntos que tiene
  dados de alta.
- Con `include_all_scans: true`: **todas** las lecturas del candidato, estén donde estén (también las de
  centros de tratamiento y reparto). Está pensado para el diagnóstico de la red, que llegará en una **fase
  posterior**. Hoy, las lecturas en lugares que no son puntos de lectura dados de alta aparecen en la
  respuesta como `unknown_reading_point` (y ONEMS recibe un aviso): es lo esperado en este modo y no invalida
  el envío.
- Incluir también las lecturas duplicadas o con datos dudosos; ONEMS las valida una a una.
- Una fila por lectura; cada fila lleva sus propios campos (identificador, fecha y hora, lugar, tipo de
  evento, producto…), aunque se repitan entre filas del mismo envío.

### 6.4. Datos personales: nunca

**No envíe nunca datos personales**: nombres, teléfonos, direcciones, correos electrónicos u otros datos de
remitentes o destinatarios, ni identificadores de personas. Cada fila solo debe llevar los campos acordados
en las equivalencias (§8).

ONEMS, además, aplica una lista cerrada: guarda solo los campos acordados y **descarta cualquier otro campo
antes de almacenar nada**. Pero esa protección es una red de seguridad, no un permiso: el conector tiene la
obligación de no enviarlos, y un campo con datos personales nunca se acordará como campo adicional.

---

## 7. Envío de lotes (`POST /batches`)

### 7.1. Petición

```http
POST /functions/v1/carrier-link-ingest/batches HTTP/1.1
Host: <proyecto>.supabase.co
x-api-key: onems_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Content-Type: application/json
```

Para ensayar sin guardar nada: `POST .../batches?dry_run=true` (§10).

> **Atención:** solo el valor literal `dry_run=true` (en minúsculas) es un ensayo. Cualquier otro valor
> (`dry_run=1`, `dry_run=TRUE`, `dry_run=yes`…) se trata hoy como un **envío real** y el lote se carga.

### 7.2. El lote, campo a campo

Ejemplo (ilustrativo, recortado: un estrato y 4 de sus 20 filas; completo en [`ejemplo/02-batch-01.json`](ejemplo/02-batch-01.json)):

```jsonc
{
  "demand_id": "761bcb4a-f8b9-40b3-9aef-6a85d80018ee",  // obligatorio: el de la demanda
  "batch_id": "SIM-761bcb4a-25bd8e-01",                  // obligatorio: lo elige el conector, único por demanda
  "strata": [                                            // obligatorio: al menos un estrato
    {
      "stratum_id": "0004551b-71cb-4c48-b658-ae65533cb1ff",   // obligatorio: uno de la demanda
      "population_size": 53,                                  // obligatorio: entero >= 0
      "selection_method": "uniform_random_within_stratum",    // obligatorio: exactamente este valor
      "rows": [                                               // obligatorio: lista (puede estar vacía)
        { "tracking_no": "SP003612846SL", "event_ts": "29/10/2026 12:27:24",
          "site_code": "EMR-PO", "event_code": "ACC", "service": "STD", "weight_g": "906" },
        { "tracking_no": "SP003612846SL", "event_ts": "03/11/2026 16:37:35",
          "site_code": "SVL-PO", "event_code": "DLV", "service": "STD", "weight_g": "906" },
        { "tracking_no": "SP004396827SL", "event_ts": "30/10/2026 16:33:45",
          "site_code": "EMR-PO", "event_code": "ACC", "service": "STD", "weight_g": "1363" },
        { "tracking_no": "SP004396827SL", "event_ts": "04/11/2026 14:56:31",
          "site_code": "SVL-PO", "event_code": "DLV", "service": "STD", "weight_g": "1363" }
      ]
    }
  ]
}
```

- Las **filas usan los nombres de campo y los valores del carrier** (aquí `tracking_no`, `event_ts`,
  `site_code`, `event_code`, `service`, `weight_g`). ONEMS sabe traducirlos gracias a las equivalencias (§8).
- Si un estrato tiene población 0, se envía igualmente con `"population_size": 0` y `"rows": []`: así ONEMS
  sabe que no hay envíos y no se queda esperando.
- No repita el mismo `stratum_id` dentro de un lote (`400 CL_BAD_PAYLOAD`).

### 7.3. Varios lotes por demanda

- Una demanda puede entregarse en **varios lotes** (por ejemplo, para no pasar de 5.000 filas o 5 MB).
- **Cada estrato se entrega una sola vez** por demanda y **entero en un único lote**: no se puede partir en
  dos. Si un solo estrato pasa de 5.000 filas o 5 MB, avise al equipo de ONEMS. Si
  un lote trae un estrato ya entregado en otro lote de la misma demanda, se rechaza el lote entero
  (`400 CL_STRATUM_ALREADY_DELIVERED`).
- Un lote puede llevar tantos estratos como quepan en los límites.
- La demanda se cierra cuando se han entregado todos sus estratos; hasta entonces sigue apareciendo en
  `GET /demands` (con todos sus estratos: el conector debe saber cuáles ya entregó).

### 7.4. Idempotencia: reintentar con el mismo `batch_id`

- El `batch_id` identifica el lote **dentro de la demanda**. Si ONEMS recibe otra vez un lote con un
  `batch_id` que ya tiene guardado para esa demanda, **no lo vuelve a cargar**: devuelve el resumen guardado
  de la primera vez, aunque la demanda ya esté cerrada **y aunque el contenido nuevo sea distinto**: el
  contenido nuevo se ignora sin aviso. Un `batch_id` ya usado no sirve para corregir un lote.
- Excepciones: con el conector **pausado**, también el reenvío recibe `403 CL_FEED_PAUSED`; con el conector
  **en pruebas**, un reenvío real (sin `dry_run`) recibe `403 CL_FEED_TESTING_DRY_RUN_ONLY`.
- Por eso, ante cualquier duda (corte de red, tiempo agotado, `429`, `5xx`), **reenvíe el mismo lote con el
  mismo `batch_id`**. Nunca genere un `batch_id` nuevo para el mismo contenido: sería un lote distinto y,
  si sus estratos ya se entregaron, se rechazaría.
- Si el lote se guardó pero el sorteo se cortó a medias (respuesta con `failed`, §9.3), reenviar el mismo
  `batch_id` **completa el sorteo** de los estratos que faltaban sin repetir los ya hechos.
- Un `batch_id` es libre (texto de hasta 200 caracteres). Recomendación: derivarlo de forma determinista,
  por ejemplo `<prefijo>-<8 primeros de demand_id>-<n.º de lote>`.

---

## 8. Equivalencias que configura ONEMS

ONEMS traduce cada fila del carrier a sus campos estándar. El carrier no tiene que adaptar sus nombres: solo
tiene que **decirnos** cómo son sus datos. Esto se acuerda antes de empezar y lo configura el equipo de ONEMS.

### 8.1. Campos de cada lectura

Los nombres de campo distinguen mayúsculas y minúsculas y tienen que coincidir **exactamente** con los
acordados (`tracking_no` no es `Tracking_No`); un campo con otro nombre se trata como si no viniera.

| Campo estándar de ONEMS | ¿Obligatorio? | Qué nos tiene que decir el carrier | Ejemplo SIMPOST |
|---|---|---|---|
| `item_id` — identificador del envío | **Sí** | Nombre del campo con el número de seguimiento. | `tracking_no` |
| `scan_at` — fecha y hora de la lectura | **Sí** | Nombre del campo, **formato** y **zona horaria** (ver 8.2). | `event_ts`, `DD/MM/YYYY HH24:MI:SS`, `Africa/Nairobi` |
| `place_ref` — lugar de la lectura | **Sí** | Nombre del campo con el código de oficina/centro. | `site_code` |
| `mode_ref` — tipo de evento | Recomendado | Nombre del campo con el código de evento (admisión, entrega…). | `event_code` |
| `product` — producto o servicio | Recomendado | Nombre del campo con el código de servicio. | `service` |

- Sin `product`, ONEMS considera que todas las lecturas son del producto medido.
- Sin `mode_ref`, solo valen puntos de lectura sin tipo de evento (cualquier evento en ese lugar).
- Mientras falte alguno de los tres obligatorios, ONEMS contesta `400 CL_MAPPING_INCOMPLETE`.

### 8.2. Fecha y hora

- **Formato**: patrón con la sintaxis de PostgreSQL `to_timestamp` (por ejemplo `DD/MM/YYYY HH24:MI:SS`,
  `YYYY-MM-DD HH24:MI:SS`). Si no se indica formato, ONEMS acepta fechas ISO 8601
  (`2026-11-03T16:37:35+03:00`, `2026-11-03 16:37:35`).
- **Zona horaria**: nombre IANA (`Africa/Nairobi`, `Europe/Madrid`…) en la que están las horas. Si no se
  indica zona, se usa la del regulador.
- **Desfase dentro del valor** (`+03:00`, `Z`):
  - sin formato acordado (ISO 8601): si el valor trae desfase, se usa ese desfase; si no, la zona configurada;
  - con formato acordado: el desfase solo se lee si el patrón lo incluye (`TZH:TZM`, por ejemplo
    `YYYY-MM-DD HH24:MI:SS TZH:TZM`); si el patrón no lo incluye, se aplica siempre la zona configurada.
- Una hora ilegible (por ejemplo `31/11/2026 25:61:00`) rechaza solo esa lectura (`bad_timestamp`).

### 8.3. Valores: productos

Lista de los códigos de producto o servicio del carrier y a qué producto de ONEMS corresponde cada uno (por
ejemplo `STD` → producto estándar, `EXP` → urgente). Un código sin equivalencia que no coincida tampoco con un
código de ONEMS se rechaza como `unknown_product`. En la demanda, `products` llega ya con los códigos del
carrier.

### 8.4. Lugares y tipos de evento: puntos de lectura

Lista de los lugares del carrier (código `place_ref` y en qué oficina o centro está, es decir, en qué ciudad) y
de los códigos de evento (`mode_ref`) que marcan el **inicio** (admisión, depósito…) y el **fin** (entrega,
llegada a la oficina de destino…). ONEMS da de alta un punto de lectura por cada combinación útil y entrega
al carrier la **lista completa de puntos** dados de alta (lugar, tipo de evento, ciudad y papel de inicio o
fin), que el conector necesita para aplicar la regla del punto más específico (§5.3). Una lectura
en un lugar o evento no dado de alta se rechaza como `unknown_reading_point` y ONEMS recibe un aviso para
revisarlo.

### 8.5. Campos adicionales permitidos

Opcionalmente, una lista corta de campos adicionales útiles para el análisis (por ejemplo `weight_g`, el peso).
Solo se guardan si son texto, número o booleano de hasta 500 caracteres. **Nunca** datos personales (§6.4).
Cualquier campo que no esté en las equivalencias ni en esta lista se descarta al llegar.

### 8.6. Calendario

Días de la semana, hora y zona horaria en que ONEMS emitirá las demandas (§5.1), elegidos por el carrier
según la carga de sus sistemas.

---

## 9. Respuestas y errores

Todas las respuestas son JSON. Los errores tienen la forma:

```json
{ "success": false, "error": "CL_DEMAND_NOT_OPEN" }
```

En los errores de forma del lote, `error` añade una explicación tras el código (por ejemplo
`"CL_BAD_PAYLOAD: population_size must be a non-negative integer"`). Programe contra el **código** (la parte
anterior a los dos puntos), no contra el texto.

### 9.1. Tabla de códigos

| HTTP | Código | Significado | Qué hacer |
|---|---|---|---|
| `200` | — | Petición correcta. En un lote, ver el resumen (§9.2). | Guardar la respuesta. |
| `400` | `CL_BAD_PAYLOAD` | El lote está mal formado: JSON inválido, falta `demand_id`, `batch_id`, `strata`, `stratum_id`, `population_size` (entero ≥ 0), `selection_method` o `rows`; `batch_id` de más de 200 caracteres; `stratum_id` repetido en el lote. | Corregir el conector. No reintentar igual. |
| `400` | `CL_UNKNOWN_STRATUM` | Algún `stratum_id` no es de esa demanda. | Usar los `stratum_id` de la demanda tal cual. |
| `400` | `CL_STRATUM_ALREADY_DELIVERED` | Algún estrato ya se entregó en otro lote de esa demanda. Se rechaza el lote entero. | Quitar ese estrato; no partir estratos entre lotes. |
| `400` | `CL_MAPPING_INCOMPLETE` | ONEMS aún no tiene configuradas las equivalencias obligatorias (§8.1). | Avisar al equipo de ONEMS. |
| `400` | `CL_FEED_CARRIER_MISMATCH` | Error de configuración interna de ONEMS para este conector. | Avisar al equipo de ONEMS. |
| `400` | `CL_BATCH_NOT_VALIDATED` | El lote guardado ya no se puede procesar (por ejemplo, su demanda caducó mientras se procesaba). Puede llegar como código de `failed` (§9.3). | No reintentar. Avisar a ONEMS. |
| `400` | `CL_BAD_REQUEST` | Otra petición no válida. | Revisar el lote; si persiste, avisar a ONEMS. |
| `401` | — (`Invalid or inactive API key`) | Falta la clave, es incorrecta, está desactivada o caducada. | Revisar la cabecera; pedir clave nueva si caducó. |
| `403` | `CL_FEED_PAUSED` | El conector está pausado en ONEMS: no se aceptan lotes (ni ensayos). | Esperar a que ONEMS lo reactive. |
| `403` | `CL_FEED_TESTING_DRY_RUN_ONLY` | El conector está en pruebas: solo se aceptan ensayos (`?dry_run=true`). | Usar `dry_run` hasta el paso a producción (§10). |
| `403` | `CL_DEMAND_TESTING_DRY_RUN_ONLY` | La demanda se emitió con el conector en pruebas: mientras siga abierta solo admite ensayos (al activar el conector se cierra, §10.2). | Ensayar; esperar a la primera demanda real. |
| `403` | `CL_FORBIDDEN` | Operación no permitida para esta clave. | Avisar a ONEMS. |
| `404` | — (`Not found`) | Ruta desconocida. | Usar `/demands` o `/batches`. |
| `405` | — (`Method not allowed`) | Método equivocado (p. ej. `POST /demands`). | `GET /demands`, `POST /batches`. |
| `409` | `CL_DEMAND_NOT_OPEN` | La demanda no existe para este conector (o el `demand_id` no es válido) o ya no está abierta (cumplida, caducada o anulada). | No reintentar. Volver a leer `GET /demands`. |
| `413` | `CL_BODY_TOO_LARGE` | El cuerpo pasa de 5 MB. | Repartir los estratos en más lotes. |
| `413` | `CL_TOO_MANY_ROWS` | El lote pasa de 5.000 filas. | Repartir los estratos en más lotes. |
| `429` | — (`Rate limit exceeded…`) | Más de 30 peticiones en el último minuto con esta clave. | Esperar un minuto y reintentar el mismo lote. |
| `500` | — (`Internal server error` / `internal`) | Error inesperado en ONEMS. | Reintentar más tarde **con el mismo `batch_id`**; si persiste, avisar. |

**Regla general:** cualquier otro código `CL_…` que no esté en esta tabla: no reintentar y avisar al equipo de
ONEMS con el `demand_id`, el `batch_id` y la respuesta.

Los errores de forma del lote (`400`, `413`) se detectan antes de guardar nada: el lote no queda registrado
y, una vez corregido, se puede enviar con el mismo `batch_id`.

### 9.2. Respuesta `200` a un lote: el resumen

```jsonc
{
  "ingest": {                                     // validación del lote
    "batch": "6f11293e-f22c-4b2e-b6ce-91eb6fa17920",   // id interno de ONEMS (null en un ensayo)
    "status": "validated",                        // "validated" o "rejected"
    "dry_run": true,                              // solo aparece en un ensayo
    "strata": [
      {
        "stratum_id": "0004551b-71cb-4c48-b658-ae65533cb1ff",
        "population_size": 53,                    // la población que declaró el conector
        "rows": 20,                               // filas recibidas
        "candidates": 10,                         // envíos distintos recibidos
        "candidates_valid": 9,                    // envíos válidos (entran en el sorteo de ONEMS)
        "rejected": { "start_after_end": 1 },     // envíos no válidos, por motivo
        "rows_rejected": {}                       // lecturas rechazadas, por motivo
      }
    ]
  },
  "sampling": [                                   // sorteo de ONEMS por estrato (no en ensayo)
    {
      "batch_id": "6f11293e-f22c-4b2e-b6ce-91eb6fa17920",
      "stratum_id": "0004551b-71cb-4c48-b658-ae65533cb1ff",
      "population_size": 53, "candidates_valid": 9,
      "samples_required": 2, "samples_selected": 2,
      "selected_item_ids": ["SP004396827SL", "SP005948951SL"],   // envíos que pasan a ser muestra
      "executed_at": "2026-11-23T11:10:31.589314+01:00"
    }
  ],
  "finish": {                                     // cierre del lote (no en ensayo)
    "batch_id": "6f11293e-f22c-4b2e-b6ce-91eb6fa17920",
    "status": "sampled",                          // lote procesado
    "demand_status": "open",                      // "open" si faltan estratos; si no, "fulfilled" o "partial"
    "strata_pending": []
  }
}
```

Notas sobre el resumen:

- `ingest.batch`, `sampling[].batch_id` y `finish.batch_id` son **identificadores internos de ONEMS** del lote
  guardado, no el `batch_id` del conector. Guárdelos solo para hablar con ONEMS.
- `sampling[].candidates_valid` puede ser **menor** que `ingest.strata[].candidates_valid`: en el sorteo ONEMS
  descarta además los envíos que ya salieron elegidos en otro estrato del mismo lote y los que se leyeron en un
  punto sin ciudad asignada (error de configuración de ONEMS, que recibe un aviso).

**Motivos por envío** (`rejected`): el envío no entra en el sorteo.

| Motivo | Significado |
|---|---|
| `already_sampled` | El envío ya es muestra en ONEMS (de otro estrato o de otra demanda). Normal, no es un error. |
| `unknown_product` | Alguna lectura del envío trae un código de producto desconocido. |
| `product_mismatch` | Alguna lectura válida del envío es de otro producto distinto del medido. |
| `no_start` | Ninguna lectura válida en un punto de inicio del estrato. |
| `no_end` | Ninguna lectura válida en un punto de fin del estrato. |
| `same_reading` | La única lectura de fin es la misma que la de inicio (un punto que es inicio y fin a la vez). |
| `start_after_end` | La última lectura de fin es anterior a la primera de inicio (reloj desajustado, datos erróneos). |
| `end_out_of_period` | La fecha local de la última lectura de fin está fuera del periodo del estrato (§6.1). |

**Motivos por lectura** (`rows_rejected`): se descarta esa lectura; el envío puede seguir siendo válido con
las demás.

| Motivo | Significado |
|---|---|
| `missing_field` | Falta el identificador, la fecha y hora, el lugar o (si se acordó) el producto, o la fila no es un objeto JSON. |
| `bad_value` | Identificador, lugar o tipo de evento de más de 200 caracteres. |
| `bad_timestamp` | Fecha y hora ilegible con el formato acordado. |
| `unknown_product` | Código de producto sin equivalencia. |
| `unknown_reading_point` | Lugar/tipo de evento que no es un punto de lectura dado de alta. |

**Lote rechazado entero** por método de selección: respuesta `200` con

```json
{ "ingest": { "batch": "…", "status": "rejected", "reason": "selection_method",
              "expected": "uniform_random_within_stratum",
              "strata": [ { "stratum_id": "…", "selection_method": "first_n" } ] } }
```

El lote queda registrado como rechazado con ese `batch_id`: corrija el conector y envíe los mismos estratos
en un lote **con un `batch_id` nuevo** (reenviar el mismo devolvería otra vez el rechazo guardado).

### 9.3. Respuestas especiales

- **Reenvío de un lote ya procesado** (mismo `batch_id`): `200` con solo `ingest`, que es el resumen guardado
  de la primera vez (su `status` es el de la validación inicial). No hay `sampling` ni `finish`: no se sortea
  otra vez. Si el contenido enviado ahora es distinto, **se ignora sin aviso**. Con el conector pausado el
  reenvío recibe `403 CL_FEED_PAUSED`, y con el conector en pruebas un reenvío real recibe
  `403 CL_FEED_TESTING_DRY_RUN_ONLY`.
- **Sorteo cortado a medias**: el código HTTP del fallo y un cuerpo con lo hecho hasta entonces:
  `{ "ingest": {...}, "sampling": [ ...estratos ya sorteados... ], "failed": { "stratum_id": "…", "code": "CL_DEMAND_NOT_OPEN" } }`
  (con `"code": "internal"` si fue un `500`). El lote está guardado: reenviar el mismo `batch_id` completa los
  estratos que faltan (si la demanda sigue abierta).

---

## 10. Ensayo y certificación

### 10.1. Modo ensayo (`dry_run`)

`POST .../batches?dry_run=true` hace **todas** las comprobaciones (forma, equivalencias, puntos, motivos de
rechazo) y devuelve el mismo resumen `ingest` con `"batch": null` y `"dry_run": true`, pero **no guarda
nada**: ni lote, ni muestras, ni avisos. Se puede repetir cuantas veces haga falta.

> **Atención:** solo `?dry_run=true` literal (en minúsculas) es un ensayo. Con cualquier otro valor
> (`1`, `TRUE`, `yes`…) el lote se carga **de verdad**.

- Un ensayo no cuenta como entrega: después se puede enviar el mismo lote de verdad (incluso con el mismo
  `batch_id`).
- Si el `batch_id` ya se cargó de verdad antes, el ensayo devuelve el resumen guardado (como un reenvío).
- También comprueba que los estratos no se hayan entregado ya (`CL_STRATUM_ALREADY_DELIVERED`).

### 10.2. Conector en pruebas y conector activo

| Estado del conector en ONEMS | `GET /demands` | Lote de ensayo | Lote real |
|---|---|---|---|
| **En pruebas** (`testing`, estado inicial) | Sí (demandas de prueba) | Sí | No (`403 CL_FEED_TESTING_DRY_RUN_ONLY`) |
| **Activo** (`active`) | Sí | Sí | Sí |
| **Pausado** (`paused`) | Sí (no se emiten demandas nuevas) | No (`403 CL_FEED_PAUSED`) | No (`403 CL_FEED_PAUSED`) |

- Mientras el conector está en pruebas, ONEMS emite **demandas de prueba** según el calendario, iguales a las
  reales, para que el conector se pueda ensayar con datos verdaderos. Mientras una demanda de prueba sigue
  abierta **solo admite ensayos** (`403 CL_DEMAND_TESTING_DRY_RUN_ONLY`).
- Al **activar** el conector, ONEMS cierra (como `failed`) las demandas de prueba que siguieran abiertas:
  desaparecen de `GET /demands` y cualquier lote para ellas, **también un ensayo**, recibe
  `409 CL_DEMAND_NOT_OPEN` (salvo el reenvío de un `batch_id` ya guardado, que devuelve su resumen). El
  `403 CL_DEMAND_TESTING_DRY_RUN_ONLY` solo aparece mientras la demanda de prueba sigue abierta. En el
  siguiente hueco del calendario ONEMS emite la primera **demanda real**.

### 10.3. Lista de comprobación para el paso a producción

Antes de pedir a ONEMS que active el conector:

- [ ] Equivalencias acordadas y configuradas (§8): campos, formato y zona de la fecha, productos, puntos de
      lectura, campos adicionales.
- [ ] La clave se guarda como secreto y se envía en `x-api-key` (o `Authorization: Bearer`).
- [ ] El conector lee `GET /demands` después de la hora de emisión y respeta el límite de 30 peticiones por
      minuto.
- [ ] El conector tiene la lista completa de puntos de lectura que entrega ONEMS (§8.4).
- [ ] La población se calcula con la regla exacta de §6.1 (producto en todas las lecturas de inicio y fin,
      última lectura de fin, fecha local dentro del periodo) y se informa en `population_size`.
- [ ] Los ensayos usan exactamente `?dry_run=true`.
- [ ] El sorteo es uniforme dentro de cada estrato y `selection_method` es `uniform_random_within_stratum`.
- [ ] Se envían todas las lecturas de los candidatos en los puntos de inicio y fin de cualquier estrato de la
      demanda (o todas, con `include_all_scans`).
- [ ] **Ningún dato personal** en las filas; solo los campos acordados.
- [ ] Ningún estrato se parte entre lotes; ninguno se envía dos veces; los estratos con población 0 se envían
      con `rows: []`.
- [ ] Lotes de como mucho 5.000 filas y 5 MB.
- [ ] Reintentos con el **mismo `batch_id`** ante errores de red, `429` y `5xx`; sin reintento ante `400`,
      `403` y `409`.
- [ ] Al menos una demanda de prueba completa ensayada con `dry_run`, revisada con el equipo de ONEMS: sin
      `unknown_reading_point`, `missing_field` ni `bad_timestamp` inesperados, y con `population_size` coherente
      (nunca menor que los candidatos enviados).
- [ ] Se guardan demandas, lotes y respuestas para auditoría.

---

## 11. Ejemplo completo

Ejecución real del conector de referencia contra un carrier simulado (SIMPOST). Los identificadores son
ilustrativos. Los ficheros completos están en [`ejemplo/`](ejemplo/).

> En los ficheros de respuesta (`03` a `07`), cada respuesta va envuelta, solo para ilustrarla, en
> `{ "http_status": <código HTTP>, "body": <cuerpo> }`. La API **no** devuelve ese envoltorio: devuelve el código
> HTTP en la cabecera de estado y, como cuerpo, exactamente lo que hay dentro de `body`.

**Configuración acordada (§8)**: `item_id` = `tracking_no`; `scan_at` = `event_ts`, formato
`DD/MM/YYYY HH24:MI:SS`, zona `Africa/Nairobi`; `place_ref` = `site_code`; `mode_ref` = `event_code`;
`product` = `service` (`STD` y `EXP` tienen equivalencia; `REG` no); campo adicional `weight_g`. Puntos de
lectura: oficinas `NPT-PO`, `SVL-PO` y `EMR-PO`, con admisión `ACC` (inicio) y entrega `DLV` (fin). Calendario:
todos los días a las 06:00 (`Africa/Nairobi`).

**Paso 1 — `GET /demands`** ([`01-get-demands.json`](ejemplo/01-get-demands.json)): una demanda
(`761bcb4a-…`) con 12 estratos: las 6 rutas entre las tres ciudades × semanas 2026-W45 y 2026-W46, con 2 o 3
muestras pedidas y 10 o 15 candidatos por estrato.

**Paso 2 — selección.** Para el estrato `0004551b-…` (EMR-PO `ACC` → SVL-PO `DLV`, semana del 2 al 8 de
noviembre) el conector encuentra 53 envíos cerrados con la última entrega dentro del periodo
(`population_size: 53`) y sortea 10. Envía de cada uno sus lecturas de admisión y entrega: 20 filas. El conector
reparte los 12 estratos en 4 lotes (en el ejemplo se limitó a 100 filas por lote para mostrar varios lotes).

**Paso 3 — ensayo del lote 01** (`POST /batches?dry_run=true` con
[`02-batch-01.json`](ejemplo/02-batch-01.json), 3 estratos) → `200`
([`03-response-01-dry-run.json`](ejemplo/03-response-01-dry-run.json)):

```json
{ "ingest": { "batch": null, "status": "validated", "dry_run": true, "strata": [
  { "stratum_id": "0004551b-…", "population_size": 53, "rows": 20, "candidates": 10, "candidates_valid": 9,
    "rejected": { "start_after_end": 1 }, "rows_rejected": {} },
  { "stratum_id": "615738ca-…", "population_size": 40, "rows": 20, "candidates": 10, "candidates_valid": 10,
    "rejected": {}, "rows_rejected": {} },
  { "stratum_id": "78a12add-…", "population_size": 99, "rows": 31, "candidates": 15, "candidates_valid": 14,
    "rejected": { "unknown_product": 1 }, "rows_rejected": { "bad_timestamp": 1, "unknown_product": 1 } } ] } }
```

Cómo se lee:

- `start_after_end: 1` — el envío `SP008253380SL` tiene la entrega (02/11 10:59) antes que la admisión
  (03/11 15:55): el reloj del lector estaba mal. Contaba en la población (cumple §6.1) y ONEMS lo descarta.
- `bad_timestamp: 1` — la lectura duplicada de `SP002638809SL` con fecha `31/11/2026 25:61:00` se descarta;
  el envío sigue siendo válido con sus otras lecturas.
- `unknown_product: 1` — la entrega de `SP007596103SL` trae el servicio `XX9`, sin equivalencia: se descarta la
  lectura y el envío.
- Ninguna `unknown_reading_point` ni `missing_field`: los puntos y los campos están bien configurados.

**Paso 4 — el mismo lote de verdad** (`POST /batches`) → `200`
([`04-response-01.json`](ejemplo/04-response-01.json)): el mismo `ingest` con `"batch": "6f11293e-…"`, el
sorteo de ONEMS en cada estrato (`samples_selected` 2, 2 y 3; por ejemplo `SP004396827SL` y `SP005948951SL` en
el primero) y `finish` con `"demand_status": "open"`, porque aún faltan 9 estratos.

**Paso 5 — lotes 02, 03 y 04.** Al procesar el último
([`05-response-last-batch.json`](ejemplo/05-response-last-batch.json)) todos los estratos están entregados y
cubiertos: `"demand_status": "fulfilled"`. La demanda deja de aparecer en `GET /demands`.

**Paso 6 — reenvío del lote 01** con el mismo `batch_id` → `200` con solo el `ingest` guardado
([`06-response-replay-batch-01.json`](ejemplo/06-response-replay-batch-01.json)): no se carga ni se sortea
otra vez.

**Paso 7 — un lote nuevo para la demanda ya cumplida** (otro `batch_id`) → `409`
([`07-response-demand-not-open.json`](ejemplo/07-response-demand-not-open.json)):

```json
{ "success": false, "error": "CL_DEMAND_NOT_OPEN" }
```

Ejemplo de llamada con `curl`:

```bash
BASE="https://<proyecto>.supabase.co/functions/v1/carrier-link-ingest"
curl -s -H "x-api-key: $ONEMS_KEY" "$BASE/demands"
curl -s -X POST -H "x-api-key: $ONEMS_KEY" -H "Content-Type: application/json" \
     --data-binary @02-batch-01.json "$BASE/batches?dry_run=true"
```

---

## 12. Preguntas frecuentes

**¿Tenemos que renombrar nuestros campos o códigos?**
No. Envíe sus nombres y valores; ONEMS los traduce con las equivalencias (§8). Solo avísenos si cambian.

**¿Por qué piden más candidatos que muestras?**
Porque ONEMS descarta los no válidos y los que ya son muestra, y luego sortea entre los que quedan. El margen
evita quedarse corto.

**¿Qué pasa si un estrato no tiene envíos?**
Envíelo con `"population_size": 0` y `"rows": []`. Es información útil y cierra el estrato.

**¿Y si la población es menor que `candidates_requested`?**
Envíe todos los envíos de la población.

**¿Podemos elegir los envíos que mejor funcionan, o los primeros que encontremos?**
No. El sorteo tiene que ser uniforme dentro del estrato (§6.2); cualquier otro criterio invalida la medida.

**¿Por qué solo envíos ya entregados?**
Porque hasta la lectura de fin no se sabe a qué ruta pertenece el envío ni cuánto tardó. Los envíos que no
llegan no se ven por esta vía; el regulador lo sabe y lo acepta.

**Un envío se escaneó como entregado en una ciudad equivocada y luego en la buena. ¿Qué lecturas enviamos?**
Todas las que estén en puntos de inicio o de fin de la demanda, de cualquiera de sus ciudades (§6.3). ONEMS
toma la última lectura de fin del estrato y marca el envío como posible mal encaminado. Si la ciudad
equivocada no aparece en ningún estrato de la demanda, el conector no conoce sus puntos y esa lectura no
llegará; no pasa nada, el envío sigue siendo válido.

**¿Qué zona horaria usamos?**
Las suyas, tal como estén en sus sistemas: díganos cuál es (§8.2). Para decidir si un envío cae en el periodo,
use la fecha local del regulador (normalmente la misma del país).

**Se nos cortó la conexión al enviar un lote. ¿Lo reenviamos?**
Sí, con el **mismo `batch_id`**. Si ya había llegado, ONEMS devuelve el resultado guardado sin duplicar nada.

**Hemos recibido `409 CL_DEMAND_NOT_OPEN`.**
La demanda ya se cerró (cumplida, caducada a los 7 días, o era de prueba y el conector se activó) o no es de
su conector. No reintente; vuelva a leer `GET /demands`.

**¿Podemos probar sin afectar a los datos reales?**
Sí: `?dry_run=true` y el estado "en pruebas" del conector (§10).

**¿Cuántas veces podemos consultar?**
Hasta 30 peticiones por clave en cualquier ventana de 60 segundos. Una consulta en cada día del calendario,
a partir de la hora siguiente a la de emisión, es suficiente.

**¿ONEMS se conecta a nuestros sistemas?**
No. Es su conector el que llama a ONEMS, siempre por HTTPS.

---

## 13. Contacto

- Equipo técnico de ONEMS: **[nombre y correo — pendiente]**
- Responsable de la cuenta del regulador: **[nombre y correo — pendiente]**
- Para pedir o desactivar claves, cambiar el calendario o las equivalencias: **[canal — pendiente]**

Al escribirnos por un lote, indique siempre el `demand_id`, el `batch_id`, la hora del envío y el código de
respuesta. **No nos envíe nunca la clave.**
