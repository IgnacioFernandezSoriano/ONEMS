# ONEMS Carrier Link — Especificación de interfaz del conector (v4)

| | |
|---|---|
| Documento | Especificación técnica de la interfaz conector del carrier ↔ ONEMS |
| Versión | **4.1** (borrador para revisión) — 2026-11-25 (4.0: 2026-11-23). Sustituye por completo a la versión 1.x (demandas y lotes). |
| Configuración | `schema_version` **4.0** (respuesta de `GET /config`) |
| Destinatarios | Equipo técnico del carrier (desarrollo, integración y operación) |
| Artefactos | [`openapi.yaml`](openapi.yaml) · [`schemas/`](schemas/) (JSON Schema 2020-12) · [`ejemplo/`](ejemplo/) (ejemplo completo) |
| Dirección base | `https://<proyecto>.supabase.co/functions/v1/carrier-link-ingest` (la facilita ONEMS) |
| Herramienta de referencia | Simulador de carrier y conector de referencia: `tools/carrier-simulator/` (Python, sin dependencias) |

Todos los identificadores de los ejemplos son ilustrativos (carrier simulado "SIMPOST", país ficticio).

## Índice

1. [Visión general](#1-visión-general)
2. [Convenciones y requisitos normativos](#2-convenciones-y-requisitos-normativos)
3. [Seguridad y clave del conector](#3-seguridad-y-clave-del-conector)
4. [Calendario y periodos de entrega](#4-calendario-y-periodos-de-entrega)
5. [Definición normativa de «envío completo»](#5-definición-normativa-de-envío-completo)
6. [Formato del fichero](#6-formato-del-fichero)
7. [Totales de control](#7-totales-de-control)
8. [Flujo de una entrega, paso a paso](#8-flujo-de-una-entrega-paso-a-paso)
9. [Referencia de la API](#9-referencia-de-la-api)
10. [Estados y fases de una entrega](#10-estados-y-fases-de-una-entrega)
11. [Errores y motivos de rechazo](#11-errores-y-motivos-de-rechazo)
12. [Idempotencia, reintentos y reenvíos](#12-idempotencia-reintentos-y-reenvíos)
13. [Lo que ONEMS no comunica al carrier](#13-lo-que-onems-no-comunica-al-carrier)
14. [Avisos por correo al carrier](#14-avisos-por-correo-al-carrier)
15. [Modo pruebas y pruebas de conformidad](#15-modo-pruebas-y-pruebas-de-conformidad)
16. [Lista de comprobación para la puesta en marcha](#16-lista-de-comprobación-para-la-puesta-en-marcha)
17. [Ejemplo completo](#17-ejemplo-completo)
18. [Preguntas frecuentes](#18-preguntas-frecuentes)
19. [Glosario](#19-glosario)
20. [Anexos](#20-anexos)

---

## 1. Visión general

### 1.1. Qué hace el carrier y qué hace ONEMS

ONEMS mide la calidad de servicio de un producto postal con **muestras de envíos reales**. Con Carrier Link, las
muestras salen de los registros del propio carrier:

1. En cada **periodo de entrega** (de un día a una semana, según el calendario acordado), el carrier envía a ONEMS
   **un fichero con todos los envíos completos del periodo** (§5): todos, sin elegir ni filtrar.
2. ONEMS comprueba el fichero, cuenta la población de cada ruta y semana, **hace el sorteo** con una semilla que
   registra y se queda **solo** con los envíos elegidos. El resto de los datos recibidos se borra (solo se conservan
   la huella del fichero, los recuentos y la lista de elegidos, para auditoría).
3. Los envíos elegidos entran como muestras en los informes de calidad de servicio del regulador.

El carrier **no sortea ni preselecciona**: lo único que debe hacer es extraer, con la regla de §5, todos los envíos
completos del periodo y entregarlos a tiempo.

### 1.2. Actores

| Actor | Función |
|---|---|
| **Conector** | Programa del carrier. Lee la configuración, extrae los envíos completos de cada periodo, sube el fichero y sigue su proceso. Es siempre el **cliente**: ONEMS nunca abre conexiones hacia el carrier. |
| **ONEMS** | Plataforma del regulador. Publica la configuración del conector, recibe y procesa las entregas, sortea, vigila las entregas que faltan y avisa de incidencias. |
| **Equipo de ONEMS** | Configura el conector en ONEMS (clave, calendario, equivalencias de campos y productos, puntos de lectura), lo pasa de *Pruebas* a *Activo* y atiende las incidencias. |

### 1.3. Flujo

```
 Conector del carrier                                  ONEMS
 --------------------                                  -----
 GET /config  ------------------------------------->   calendario, campos, productos, puntos, next_period, límites
              <-------------------------------------   200
 GET /query?db=…  (opcional) --------------------->   la consulta SQL de extracción de next_period, ya rellenada
              <-------------------------------------   200 {sql, …}
 extrae TODOS los envíos completos de next_period,
 escribe el fichero (JSON Lines o CSV), calcula
 sha256, tamaño y totales de control
 POST /deliveries {periodo, sha256, size_bytes,
                   format, control_totals}  -------->   valida periodo y calendario, crea la entrega
              <-------------------------------------   201 {delivery, upload: {url firmada, PUT, 2 h}}
 PUT <url firmada> (fichero entero, sin clave) ----->  almacén de ficheros (privado)
              <-------------------------------------   200
 POST /deliveries/{id}/complete  ------------------->  comprueba que el fichero está, estado received
              <-------------------------------------   202
                                                        proceso en segundo plano: carga, comprueba sha256,
                                                        valida filas y envíos, cuenta, sortea, guarda solo
                                                        los elegidos, vacía la zona de recepción
 GET /deliveries/{id} (cada minuto) ---------------->
              <-------------------------------------   200 {status: processing, phase: ...} ... processed
 (siguiente periodo: vuelta a GET /config)
```

### 1.4. Principios

- **Entrega completa (población entera).** Cada fichero contiene todos los envíos completos del periodo. Nada de
  muestras, cupos ni filtros de calidad por parte del carrier.
- **Sorteo solo en ONEMS.** El carrier no sabe qué envíos se eligen (§13).
- **Push.** El carrier envía; ONEMS no accede a los sistemas del carrier.
- **Sin datos personales.** Solo viajan los campos acordados (§6.3).
- **Ficheros sin comprimir**, JSON Lines o CSV, subidos en un único PUT a una URL firmada.
- **Integridad verificable.** sha256 y tamaño declarados antes de subir; totales de control declarados (§7).

---

## 2. Convenciones y requisitos normativos

Las palabras **DEBE**, **NO DEBE**, **DEBERÍA** y **PUEDE** tienen el sentido de RFC 2119. Los requisitos
llevan un identificador `CL-REQ-nnn`; las pruebas de conformidad (§15.2) los citan.

### 2.1. Requisitos

| Id | Requisito | § |
|---|---|---|
| CL-REQ-001 | El conector DEBE usar HTTPS en todas las llamadas (API y subida). | 3.1 |
| CL-REQ-002 | El conector DEBE enviar la clave en cada llamada a la API, en `x-api-key` o en `Authorization: Bearer`. | 3.2 |
| CL-REQ-003 | El conector DEBE guardar la clave y las URL de subida como secretos y NO DEBE escribirlas en registros, código o mensajes. | 3.3 |
| CL-REQ-004 | El conector NO DEBE enviar la clave en el PUT del fichero ni seguir redirecciones con la clave. | 3.2, 8 |
| CL-REQ-005 | El conector DEBE leer `GET /config` antes de cada entrega y usar el periodo de `next_period`. | 4.3 |
| CL-REQ-006 | El conector DEBE ignorar propiedades desconocidas de las respuestas. | 9 |
| CL-REQ-007 | El conector DEBE entregar los periodos en orden de calendario, sin saltarse ninguno, solo cuando `deliverable` sea `true`. | 4 |
| CL-REQ-008 | El conector DEBERÍA entregar cada periodo no antes de la hora de entrega (`due_at`) y DEBE hacerlo antes de `due_at` + el margen acordado. | 4.2 |
| CL-REQ-009 | El fichero DEBE contener **todos** los envíos completos del periodo según §5, y solo esos. | 5 |
| CL-REQ-010 | El conector NO DEBE excluir envíos completos por su tiempo de tránsito, por incidencias, por errores de datos o por cualquier otro criterio no previsto en §5. | 5.3 |
| CL-REQ-011 | Cada envío DEBE ir con todas sus lecturas en los puntos acordados, o con todas sus lecturas si `include_all_scans` es `true`. | 5.1 |
| CL-REQ-012 | Cada registro DEBE contener solo los campos acordados (`fields[*].field` y `extra_fields`), con el nombre exacto (distingue mayúsculas). El conector NO DEBE enviar datos personales. | 6.3 |
| CL-REQ-013 | El fichero DEBE ser JSON Lines o CSV, UTF-8, sin comprimir, con el formato de §6. | 6 |
| CL-REQ-014 | `sha256` y `size_bytes` DEBEN ser los del fichero exacto que se sube. | 8 |
| CL-REQ-015 | La entrega DEBE llevar los totales de control de §7, calculados sobre los mismos envíos del fichero. | 7 |
| CL-REQ-016 | El fichero DEBE subirse entero en un único PUT a `upload.url`, con el `Content-Type` indicado, antes de que caduque (2 h). | 8 |
| CL-REQ-017 | Tras subir el fichero, el conector DEBE llamar a `POST /deliveries/{id}/complete`. | 8 |
| CL-REQ-018 | El conector DEBE consultar `GET /deliveries/{id}` hasta un estado final (`processed` o `rejected`) y no más de una vez cada 30 s (DEBERÍA cada 60 s). | 10 |
| CL-REQ-019 | Ante error de red, tiempo agotado, `429` o `5xx`, el conector DEBE reintentar la misma llamada con el mismo contenido, con espera creciente; ante `429` DEBE esperar `Retry-After`. | 12 |
| CL-REQ-020 | Un periodo rechazado DEBE reenviarse corregido (§12.3). Un periodo procesado NO DEBE reenviarse. | 12 |
| CL-REQ-021 | El conector NO DEBE superar 30 peticiones por minuto y clave. | 9 |
| CL-REQ-022 | El conector DEBE respetar los límites de `GET /config` (`limits`). Si un periodo no cabe, el carrier DEBE avisar a ONEMS antes de la fecha de entrega. | 6.5 |
| CL-REQ-024 | El conector DEBERÍA obtener la consulta de extracción de `GET /query` antes de cada entrega (o aplicar §5.1 con el mismo resultado). Las variantes Oracle y SQL Server se publican sin probar: el carrier DEBE comprobarlas antes de usarlas. | 5.2 |
| CL-REQ-023 | El conector DEBERÍA registrar, por cada entrega, el periodo, el `delivery_id`, el sha256, el tamaño, los totales de control y las respuestas, durante al menos 90 días (auditoría). | 7 |

---

## 3. Seguridad y clave del conector

### 3.1. Transporte

Todas las llamadas van por HTTPS (TLS 1.2 o superior) a la dirección base que facilita ONEMS. La subida del fichero
va a una URL firmada del mismo proyecto (`https://<proyecto>.supabase.co/storage/v1/object/upload/sign/...`). El
conector NO DEBE seguir redirecciones: una respuesta `3xx` es un error de configuración.

### 3.2. Autenticación

Cada llamada a la API lleva la clave del conector en una de estas cabeceras (son equivalentes):

```
x-api-key: onems_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
Authorization: Bearer onems_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

La clave identifica **un conector** (un carrier, una configuración). Todo lo que se pide y entrega con esa clave es
de ese conector: el cuerpo de las peticiones nunca indica el conector. Sin clave, o con una clave inactiva,
caducada o que no es de conector, la API responde `401 CL_UNAUTHORIZED`.

El PUT del fichero **no lleva la clave**: la autorización va en el `token` de la URL firmada, válida para un único
fichero y durante 2 horas.

### 3.3. Ciclo de vida de la clave

| Momento | Qué pasa |
|---|---|
| Emisión | Solo un superadmin o el UPU Account Manager de ONEMS crea claves, en la pantalla Conectores. La clave completa se muestra **una sola vez**; ONEMS guarda solo su huella y un prefijo para reconocerla. Se entrega al carrier por un canal seguro acordado. |
| Caducidad | La clave puede tener fecha de caducidad. Después responde `401`. |
| Rotación | ONEMS crea una clave nueva (la antigua sigue activa), el carrier despliega la nueva y avisa, ONEMS desactiva la antigua. Recomendado cada 12 meses. |
| Pérdida o filtración | El carrier avisa de inmediato; ONEMS desactiva la clave y emite otra. |
| Baja del conector | ONEMS desactiva la clave; las llamadas responden `401`. |

### 3.4. Datos personales

El fichero NO DEBE contener nombres, teléfonos, direcciones, correos ni identificadores de personas (remitentes,
destinatarios, carteros). ONEMS descarta al entrar cualquier campo que no sea de la lista acordada (§6.3), pero el
carrier no debe enviarlos nunca. El identificador del envío (número de seguimiento) no es un dato personal y es
obligatorio.

---

## 4. Calendario y periodos de entrega

### 4.1. Calendario

El calendario del conector lo fija ONEMS con el carrier y aparece en `GET /config`:

```json
"calendar": {"delivery_days": [1, 4], "delivery_hour": 3, "timezone": "Africa/Nairobi",
             "deliveries_per_week": 2, "frequency": "several_per_week"},
"date_timezone": "Africa/Nairobi"
```

- `delivery_days`: días de la semana en que se entrega (ISO: 1 = lunes … 7 = domingo).
- `delivery_hour` y `timezone`: hora local a partir de la cual se espera la entrega.
- `date_timezone`: zona en la que se cuentan **las fechas de los periodos** (la de la cuenta del regulador).

### 4.2. Periodo de una entrega

La entrega del día de entrega **D** cubre los días desde el día de entrega anterior hasta **D − 1**, ambos incluidos,
en fechas locales de `date_timezone`:

| Calendario | Periodo de cada entrega |
|---|---|
| Diario (`[1,2,3,4,5,6,7]`) | el día anterior |
| Semanal, lunes (`[1]`) | lunes a domingo de la semana anterior |
| Semanal, martes (`[2]`) | martes a lunes (cruza dos semanas ISO) |
| Lunes y jueves (`[1,4]`) | entrega del jueves: lunes a miércoles; entrega del lunes: jueves a domingo |

- Un periodo **está cerrado** cuando su último día es anterior a hoy (fecha local de `date_timezone`). Solo se
  puede entregar un periodo cerrado (`422 CL_PERIOD_NOT_CLOSED`).
- `due_at` (en `next_period`) es el momento esperado: día D a `delivery_hour` en `timezone`. Se PUEDE entregar
  antes (desde las 00:00 del día D, con el periodo ya cerrado), pero se RECOMIENDA esperar a `due_at` para que la
  extracción incluya las lecturas que llegan con retraso a los sistemas del carrier.
- Si la entrega no llega en `due_at` + margen (6 horas por defecto, lo fija ONEMS por conector), ONEMS abre una
  incidencia *Entrega no recibida* y avisa (§14).

### 4.3. Próximo periodo (`next_period`)

ONEMS calcula el periodo que toca entregar y lo publica en `GET /config`:

```json
"next_period": {"period_start": "2026-11-02", "period_end": "2026-11-04",
                "due_at": "2026-11-05T00:00:00+00:00", "deliverable": true}
```

Cálculo (normativo):

1. Se toma el día siguiente al último periodo ya entregado (entregas en estado `received`, `processing`,
   `processed` o `failed`; las `rejected` y las **de prueba** (§15.1) no cuentan). Sin entregas, el primer día
   del primer plan activo.
2. Si ese día no lo cubre ningún plan activo, se salta al inicio del siguiente plan activo.
3. El periodo es el del calendario que contiene ese día. Su inicio nunca es anterior al día siguiente a lo ya
   entregado (importa si el calendario cambia a mitad de periodo).
4. `deliverable` es `true` si el periodo ya está cerrado.
5. `next_period` es `null` cuando no queda ningún plan activo por cubrir: no hay nada que entregar.

El conector DEBE entregar exactamente `period_start` / `period_end` de `next_period` (CL-REQ-005), uno tras otro
(CL-REQ-007): tras cada entrega, vuelve a leer `GET /config`. Si un periodo se salta, ONEMS no lo vuelve a proponer
y queda como no recibido.

---

## 5. Definición normativa de «envío completo»

### 5.1. Definición

Con los códigos del propio carrier (los que publica `GET /config`), un **envío completo del periodo** es un envío
de un producto del plan que cumple las tres condiciones:

1. **Llegada final dentro del periodo.** Su evento de llegada final —la lectura **más reciente** con hora válida en
   un punto con papel `destination` o `both`— tiene fecha local (`date_timezone`) entre `period_start` y
   `period_end`, ambos incluidos.
2. **Salida anterior.** Tiene una lectura en un punto con papel `origin` o `both`, **anterior** a esa llegada (del
   mismo periodo o de cualquier fecha anterior) y distinta de ella. (ONEMS también acepta una salida con la misma
   hora exacta que la llegada si son lecturas distintas; el carrier PUEDE incluir esos envíos.)
3. **Con todas sus lecturas.** Se envía con **todas** sus lecturas en los puntos acordados (cualquier papel,
   incluidas las de `intermediate`) o, si `include_all_scans` es `true` (el plan tiene diagnóstico), con
   **todas** sus lecturas.

Definiciones de apoyo:

- **Producto del plan**: el código de producto del envío está en `products[*].carrier_codes`.
- **Punto acordado**: un elemento de `points`. Una lectura está en un punto si su lugar es `place_ref` y su modo
  es `mode_ref`; un punto con `mode_ref` `null` vale para cualquier modo en ese lugar.
- Un envío que nunca llega, que sigue en tránsito o que llega a un lugar que no es punto acordado **no es completo**
  y no va en el fichero.
- Cada envío aparece **en un solo periodo**: el de su llegada final. Si después de entregar un periodo un envío
  recibe una nueva lectura de llegada (por ejemplo, un envío mal encaminado que se entrega de nuevo en su destino),
  vuelve a ser completo en el periodo de esa nueva llegada y se incluye en él.

### 5.2. Consulta de ejemplo en el lado del carrier (SQL)

**Consulta ya hecha: `GET /query`.** El carrier no tiene que escribir esta consulta. `GET /query?db=postgresql`
(o `oracle`, o `sqlserver`) devuelve la consulta de su próxima entrega **ya rellenada** con su configuración: sus
nombres de campo y campos extra, sus códigos de producto, sus puntos acordados con su papel, la zona horaria y el
periodo de `next_period` (§9.2). Solo hay que sustituir `carrier_scans` por el nombre de su tabla (o vista) de
lecturas. Como el periodo cambia en cada entrega y la configuración puede cambiar, se pide de nuevo antes de cada
entrega. La variante PostgreSQL está comprobada frente al simulador de referencia; Oracle y SQL Server se publican
**sin probar** (`tested: false`) y el carrier DEBE revisarlas antes de usarlas (CL-REQ-024).

La consulta de abajo es la referencia ilustrativa de la misma regla, para quien prefiera escribirla.

Ilustrativa, para PostgreSQL; adapte los nombres a sus tablas. Supone una tabla de lecturas
`carrier_scans(tracking_no, event_ts timestamptz, site_code, event_code, service, weight_g)` y dos tablas cargadas
desde `GET /config`: `agreed_points(place_ref, mode_ref, role)` y `plan_products(carrier_code)`. Parámetros:
`:p_start`, `:p_end` (de `next_period`), `:tz` (`date_timezone`), `:all_scans` (`include_all_scans`).

```sql
WITH s AS (
  SELECT c.*,
         (c.event_ts AT TIME ZONE :'tz')::date AS local_date,
         EXISTS (SELECT 1 FROM agreed_points p
                  WHERE p.place_ref = c.site_code AND (p.mode_ref IS NULL OR p.mode_ref = c.event_code)
                    AND p.role IN ('destination', 'both')) AS is_arrival,
         EXISTS (SELECT 1 FROM agreed_points p
                  WHERE p.place_ref = c.site_code AND (p.mode_ref IS NULL OR p.mode_ref = c.event_code)
                    AND p.role IN ('origin', 'both')) AS is_departure,
         EXISTS (SELECT 1 FROM agreed_points p
                  WHERE p.place_ref = c.site_code AND (p.mode_ref IS NULL OR p.mode_ref = c.event_code)) AS is_agreed
    FROM carrier_scans c
),
arrival AS (            -- (1) la llegada final: la lectura de llegada más reciente de cada envío
  SELECT DISTINCT ON (tracking_no) tracking_no, event_ts AS arrival_ts, local_date, site_code, event_code
    FROM s WHERE is_arrival AND event_ts IS NOT NULL
   ORDER BY tracking_no, event_ts DESC
),
product AS (            -- producto del envío: el de su primera lectura
  SELECT DISTINCT ON (tracking_no) tracking_no, service
    FROM s WHERE event_ts IS NOT NULL ORDER BY tracking_no, event_ts
),
complete AS (
  SELECT a.*, pr.service
    FROM arrival a JOIN product pr USING (tracking_no)
   WHERE a.local_date BETWEEN :'p_start' AND :'p_end'
     AND pr.service IN (SELECT carrier_code FROM plan_products)
     AND EXISTS (SELECT 1 FROM s d             -- (2) una salida anterior a la llegada
                  WHERE d.tracking_no = a.tracking_no AND d.is_departure AND d.event_ts < a.arrival_ts)
)
-- (3) el fichero: todas las lecturas de los envíos completos en puntos acordados (o todas)
SELECT s.tracking_no, s.service, s.event_ts, s.site_code, s.event_code, s.weight_g
  FROM s JOIN complete c USING (tracking_no)
 WHERE s.is_agreed OR :'all_scans'::boolean
 ORDER BY s.tracking_no, s.event_ts;

-- Totales de control (§7): envíos completos por punto de llegada y producto
SELECT site_code AS place_ref, event_code AS mode_ref, service AS product, count(*) AS delivered
  FROM complete GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;
```

El simulador de referencia aplica la misma regla en `tools/carrier-simulator/carrier_sim/connector.py`
(`complete_shipments`).

### 5.3. Lo que el carrier no filtra

El carrier NO DEBE quitar envíos completos porque (CL-REQ-010):

- tardaron mucho o poco, tuvieron incidencias, reclamaciones o devoluciones;
- sus datos parecen raros (horas incoherentes, lecturas duplicadas, una lectura con un código extraño);
- son de clientes, oficinas o rutas concretas.

ONEMS valida cada lectura y cada envío por su cuenta (§11.3) y descarta lo que no sirve; el carrier lo ve en los
recuentos y motivos de rechazo de cada entrega.

---

## 6. Formato del fichero

### 6.1. Formatos admitidos

| Formato | `format` | `Content-Type` del PUT | Reglas |
|---|---|---|---|
| JSON Lines | `jsonl` (por defecto) | `application/x-ndjson` | Un objeto JSON por línea. Separador LF o CRLF. Las líneas en blanco se ignoran. |
| CSV | `csv` | `text/csv` | RFC 4180: separador coma, comillas dobles para valores con coma, comillas o saltos de línea (`""` dentro), **primera fila de cabecera obligatoria** con nombres únicos y no vacíos. LF o CRLF. |

Ambos: **UTF-8** (se admite BOM al principio), **sin comprimir** (ni gzip ni zip ni ningún otro: `400
CL_COMPRESSION_UNSUPPORTED`), un registro como mucho de 4 MiB (`CL_RECORD_TOO_LONG`). Un registro es **una
lectura** (un escaneo) de un envío; las lecturas de un envío pueden ir en cualquier orden y posición del fichero.

### 6.2. Nombres de campo: los del carrier

El fichero usa **los nombres de campo del propio carrier**. ONEMS guarda la equivalencia con sus campos estándar y
la publica en `GET /config` → `fields`:

| Campo estándar | Significado | Obligatorio | Ejemplo (SIMPOST) |
|---|---|---|---|
| `item_id` | Identificador del envío (número de seguimiento) | sí | `tracking_no` = `SP002116155SL` |
| `scan_at` | Fecha y hora de la lectura | sí | `event_ts` = `02/11/2026 16:05:02` |
| `place_ref` | Lugar de la lectura (código del carrier) | sí | `site_code` = `SVL-PO` |
| `mode_ref` | Modo o evento de la lectura (código del carrier) | si se acordó | `event_code` = `DLV` |
| `product` | Producto (código del carrier) | si se acordó | `service` = `STD` |

- **Fecha y hora** (`fields.scan_at`): `format` es un patrón `to_timestamp` de PostgreSQL (`DD/MM/YYYY HH24:MI:SS`,
  `YYYY-MM-DD HH24:MI`…); si es `null`, ISO 8601 (se recomienda con desplazamiento, `2026-11-02T16:05:02+03:00`).
  Una hora sin desplazamiento se interpreta en `fields.scan_at.timezone` o, si es `null`, en `date_timezone`.
- **Productos** (`products`): cada producto de ONEMS lista los códigos del carrier que le corresponden
  (`"carrier_codes": ["STD"]`).
- **Puntos de lectura** (`points`): lugar y modo del carrier, papel (`origin`, `destination`, `both`,
  `intermediate`) y ciudad.
- Las equivalencias las mantiene ONEMS (pantalla Conectores y Puntos de lectura). Si el carrier cambia un código o
  un nombre de campo, DEBE avisar antes a ONEMS.

### 6.3. Campos permitidos

Solo se envían los campos de `fields[*].field` y los de `extra_fields` (campos adicionales acordados, por ejemplo
el peso). ONEMS descarta cualquier otro campo, pero el carrier NO DEBE enviarlo (CL-REQ-012). Los valores son
escalares (texto, número, booleano o `null`).

Longitudes: `item_id`, `place_ref` y `mode_ref` hasta 200 caracteres (más largo → la lectura se rechaza con
`bad_value`); cada campo adicional hasta 500 caracteres.

### 6.4. Ejemplo

JSON Lines (primeras líneas del fichero del ejemplo, §17):

```
{"tracking_no":"SP002116155SL","service":"STD","event_ts":"28/10/2026 11:49:02","site_code":"NPT-PO","event_code":"ACC","weight_g":727}
{"tracking_no":"SP002116155SL","service":"STD","event_ts":"02/11/2026 16:05:02","site_code":"SVL-PO","event_code":"DLV","weight_g":727}
```

CSV (mismo contenido):

```
tracking_no,service,event_ts,site_code,event_code,weight_g
SP002116155SL,STD,28/10/2026 11:49:02,NPT-PO,ACC,727
SP002116155SL,STD,02/11/2026 16:05:02,SVL-PO,DLV,727
```

### 6.5. Límites

| Límite | Valor | Dónde se ve | Si se supera |
|---|---|---|---|
| Tamaño del fichero | 500 MB por defecto; ONEMS puede fijar menos por conector | `limits.max_file_bytes` | `413 CL_FILE_TOO_LARGE` al abrir, o entrega `rejected` |
| Registros por fichero | 5.000.000 por defecto (configurable hasta 50.000.000) | `limits.max_rows` | entrega `rejected` `CL_TOO_MANY_ROWS` |
| Totales de control | 10.000 | `limits.max_control_totals` | `400 CL_BAD_CONTROL_TOTALS` |
| Cuerpo de `POST /deliveries` | 5 MB | — | `413 CL_BODY_TOO_LARGE` |
| Peticiones a la API | 30 por minuto y clave | — | `429 CL_RATE_LIMITED`, `Retry-After: 60` |
| Validez de la URL de subida | 2 horas, un único PUT | `upload.expires_in_seconds` | pedir otra URL (§12.2) |
| Entrega abierta sin completar | 7 días | — | `rejected` `CL_UPLOAD_EXPIRED` |
| Conservación del fichero en ONEMS | 30 días por defecto (después se borra; se guarda su huella) | `limits.file_retention_days` | — |

Si el volumen previsto de un periodo se acerca a un límite, el carrier DEBE avisar a ONEMS antes de la fecha de
entrega (CL-REQ-022): se puede cambiar el calendario a entregas más frecuentes.

---

## 7. Totales de control

Cada entrega declara, en `control_totals`, cuántos envíos completos del fichero llegaron a cada punto de llegada:

```json
"control_totals": [
  {"place_ref": "EMR-PO", "mode_ref": "DLV", "product": "STD", "delivered": 54},
  {"place_ref": "NPT-PO", "mode_ref": "DLV", "product": "STD", "delivered": 55},
  {"place_ref": "SVL-PO", "mode_ref": "DLV", "product": "STD", "delivered": 54}
]
```

- Una entrada por combinación de lugar (`place_ref`) y modo (`mode_ref`) de la **lectura de llegada final** y
  producto del envío (`product`), con los códigos del carrier. `mode_ref` y `product` PUEDEN omitirse si no se
  usan. `delivered` es un entero ≥ 0.
- La suma de `delivered` DEBE ser igual al número de envíos del fichero.
- Lista cerrada de claves (`place_ref`, `mode_ref`, `product`, `delivered`): otra clave → `400
  CL_BAD_CONTROL_TOTALS`. Una lista vacía es válida (periodo sin envíos).
- ONEMS los **guarda tal como se declaran**, junto a la huella del fichero. Pueden usarse para verificaciones y
  auditorías posteriores (por ejemplo, contrastarlos con otras fuentes de volumen); por eso deben salir de la misma
  extracción que el fichero y el carrier DEBERÍA conservar su cálculo (CL-REQ-023).

---

## 8. Flujo de una entrega, paso a paso

1. **Leer la configuración.** `GET /config`. Si `next_period` es `null` o `deliverable` es `false`, no hay nada
   que entregar todavía.
2. **Extraer.** Con la regla de §5, todos los envíos completos de `next_period`, con sus lecturas.
3. **Escribir el fichero** en disco (JSON Lines o CSV, §6) y calcular su **sha256** (hexadecimal), su **tamaño en
   bytes** y los **totales de control** (§7). A partir de aquí el fichero no se toca.
4. **Abrir la entrega.** `POST /deliveries` con `period_start`, `period_end`, `format`, `size_bytes`, `sha256` y
   `control_totals`. Respuesta `201` con `delivery.delivery_id` y `upload` (o `200` si ya estaba abierta, §12.1).
5. **Subir el fichero.** Un único `PUT` a `upload.url`, con cuerpo = los bytes del fichero, cabecera
   `Content-Type` = `upload.headers.Content-Type` y **sin** la clave. Respuesta `200`. Si el fichero ya estaba
   subido, el almacén responde `409`, o `400` con `"statusCode": "409"` en el cuerpo (según la versión): las dos
   significan «ya subido» y se sigue al paso 6. Si falla o caduca la URL: volver al paso 4 con el mismo
   cuerpo (misma entrega, URL nueva).
6. **Completar.** `POST /deliveries/{id}/complete` (sin cuerpo). `202`: recibida; ONEMS empieza a procesarla en
   menos de un minuto. `409 CL_FILE_NOT_UPLOADED`: el fichero no está; volver al paso 5.
7. **Seguir el proceso.** `GET /deliveries/{id}` cada 60 s (nunca más de una vez cada 30 s) hasta `processed` o
   `rejected` (§10). `failed` no es final: ONEMS reintenta solo.
8. **Siguiente periodo.** Volver al paso 1. Con entregas atrasadas, repetir hasta que `deliverable` sea `false`.

Notas:

- Abrir otra vez el **mismo periodo con otro fichero** mientras la primera entrega espera el fichero la anula
  (`rejected` `CL_SUPERSEDED`): vale la última.
- Una entrega abierta y no completada en 7 días se rechaza (`CL_UPLOAD_EXPIRED`) y el periodo sigue pendiente.
- El conector de referencia (`python -I tools/carrier-simulator/sim.py deliver`) hace exactamente estos pasos,
  con los reintentos de §12 (`Retry-After` en `429`, espera creciente y acotada en errores de red y `5xx`, nueva
  apertura si la subida falla o si `complete` responde `CL_FILE_NOT_UPLOADED`).
- **Periodo sin envíos**: se entrega igual, con `control_totals: []`. Como `size_bytes` debe ser al menos 1, el
  fichero es un CSV con solo la cabecera o un JSON Lines con una sola línea en blanco (ONEMS ignora las líneas en
  blanco). Nunca un fichero de 0 bytes.

---

## 9. Referencia de la API

Dirección base: `https://<proyecto>.supabase.co/functions/v1/carrier-link-ingest`. Todas las rutas requieren la
clave (§3.2). Respuestas en JSON (`Content-Type: application/json`). Las propiedades desconocidas DEBEN ignorarse
(CL-REQ-006). Contrato formal: [`openapi.yaml`](openapi.yaml) y [`schemas/`](schemas/).

| Método y ruta | Qué hace | Respuestas correctas | Esquema |
|---|---|---|---|
| `GET /config` | Configuración del conector y próximo periodo | `200` | [`config-response`](schemas/config-response.schema.json) |
| `GET /query?db=…` | Consulta SQL de extracción del próximo periodo, ya rellenada | `200` | [`query-response`](schemas/query-response.schema.json) |
| `POST /deliveries` | Abre la entrega de un periodo y da la URL de subida | `201` nueva, `200` ya abierta | petición [`delivery-open-request`](schemas/delivery-open-request.schema.json), respuesta [`delivery-open-response`](schemas/delivery-open-response.schema.json) |
| `PUT <upload.url>` | Sube el fichero (almacén, no la API; sin clave) | `200` | bytes del fichero ([`delivery-file-row`](schemas/delivery-file-row.schema.json) por registro) |
| `POST /deliveries/{id}/complete` | Avisa de que el fichero está subido | `202` recibida, `200` ya en curso o terminada | [`delivery-response`](schemas/delivery-response.schema.json) |
| `GET /deliveries/{id}` | Estado, fase, recuentos, motivos y alertas | `200` | [`delivery-response`](schemas/delivery-response.schema.json) |
| `/demands`, `/batches` (v3) | Retiradas | `410 CL_ENDPOINT_GONE` | [`error`](schemas/error.schema.json) |

### 9.1. `GET /config`

Campos principales de la respuesta (ejemplo completo: [`ejemplo/01-get-config.json`](ejemplo/01-get-config.json)):

| Campo | Contenido |
|---|---|
| `schema_version` | `"4.0"` |
| `connector` | `id`, `name`, `status` (`testing`, `active`, `paused`), `carrier` (código) |
| `date_timezone` | Zona de las fechas de los periodos |
| `calendar` | §4.1 |
| `fields`, `mapping_complete`, `extra_fields` | §6.2 y §6.3. Si `mapping_complete` es `false`, falta configurar ONEMS: no entregar y avisar. |
| `include_all_scans` | `true` si algún plan activo tiene diagnóstico: van todas las lecturas (§5.1) |
| `plans` | Planes activos: producto, fechas, `include_all_scans` |
| `products` | Productos con sus códigos del carrier |
| `points` | Puntos acordados: `place_ref`, `mode_ref`, `role`, `city_id`, `city` |
| `next_period` | §4.3 |
| `last_delivery` | Última entrega: `delivery_id`, periodo y `status` |
| `formats` | `{"format": ["jsonl","csv"], "compression": ["none"]}` |
| `limits` | §6.5 |

### 9.2. `GET /query`

Parámetro `db`: `postgresql` (por defecto), `oracle` o `sqlserver`; otro valor → `400 CL_BAD_REQUEST`. Misma clave,
mismos límites de peticiones y mismo conector que `GET /config`. Ejemplo:
[`ejemplo/19-get-query.json`](ejemplo/19-get-query.json).

| Campo | Contenido |
|---|---|
| `db` | Tipo de base pedido |
| `tested` | `true` solo para `postgresql`; `false` = sin probar por ONEMS (cabecera `SIN PROBAR / UNTESTED` en el SQL) |
| `period_start`, `period_end` | Periodo de `next_period` puesto en la consulta; `null` si no hay periodo pendiente (el SQL lleva los marcadores `<PERIOD_START>` y `<PERIOD_END>`) |
| `table_placeholder` | `carrier_scans`: nombre que el carrier sustituye por su tabla de lecturas |
| `sql` | Dos sentencias: (1) las filas del fichero, con los nombres de campo del carrier; (2) los totales de control (§7) |

Supuestos escritos en la cabecera del SQL: una fila por lectura; la columna de hora es fecha/hora **sin** zona horaria,
en la zona de `fields.scan_at.timezone` (UTC si no consta). Si la columna ya lleva zona horaria se quita la primera
conversión; si es texto, hay que convertirla antes. En SQL Server las zonas van con su nombre de Windows; si ONEMS no
conoce la equivalencia, deja un marcador `<WINDOWS_TIME_ZONE_FOR_…>`. Errores: `401`, `422 CL_MAPPING_INCOMPLETE`
(faltan equivalencias de campos en ONEMS), `429`.

### 9.3. `POST /deliveries`

Petición (lista cerrada de claves; otra clave → `400`):

| Campo | Tipo | Obligatorio | Regla |
|---|---|---|---|
| `period_start`, `period_end` | fecha `YYYY-MM-DD` | sí | Exactamente `next_period` |
| `sha256` | 64 hexadecimales | sí | Del fichero exacto que se sube |
| `size_bytes` | entero ≥ 1 | sí | Tamaño exacto; ≤ `limits.max_file_bytes` |
| `format` | `jsonl` \| `csv` | no (`jsonl`) | Un nombre de compresión (`jsonl.gz`, `zip`…) → `CL_COMPRESSION_UNSUPPORTED` |
| `compression` | `"none"` \| `null` | no | Cualquier otro valor → `CL_COMPRESSION_UNSUPPORTED` |
| `control_totals` | lista | sí (puede ser `[]`) | §7 |

Comprobaciones, en este orden: cuerpo y campos (`400`); tamaño declarado frente a `limits.max_file_bytes`
(`413 CL_FILE_TOO_LARGE`, antes que todo lo demás); conector existente y no pausado (`404` / `403`); idempotencia
(mismo periodo, mismo sha256 y misma clase —prueba o real— → `200` con `existing: true`); periodo cerrado (`422
CL_PERIOD_NOT_CLOSED`); sin solape con un periodo ya entregado (`409 CL_PERIOD_ALREADY_DELIVERED`); periodo del
calendario (`422 CL_PERIOD_NOT_IN_CALENDAR`); un plan activo lo cubre (`422 CL_NO_ACTIVE_PLAN`).

Respuesta: `delivery` (§10) más `existing` y `max_file_bytes`, y `upload`:

```json
"upload": {"url": "https://<proyecto>.supabase.co/storage/v1/object/upload/sign/cl-deliveries/<cuenta>/<conector>/<entrega>.jsonl?token=...",
           "method": "PUT", "headers": {"Content-Type": "application/x-ndjson"}, "expires_in_seconds": 7200}
```

`upload` es `null` si la entrega ya no espera el fichero (por ejemplo, la misma petición repetida después de
completar).

### 9.4. `POST /deliveries/{id}/complete`

Sin cuerpo. Respuestas: `202` (`received`, también si se repite mientras sigue `received`); `200` (ya
`processing`, `processed` o `failed`); `409 CL_FILE_NOT_UPLOADED`; `403 CL_FEED_PAUSED` (conector pausado); si la entrega queda o estaba `rejected`, el código HTTP de su error (por ejemplo `409
CL_SUPERSEDED`, `410 CL_UPLOAD_EXPIRED`, `413 CL_FILE_TOO_LARGE`, `422 CL_SHA256_MISMATCH`) con la entrega en el
cuerpo. Un `id` ajeno, inexistente o mal formado responde siempre igual: `404 CL_DELIVERY_NOT_FOUND`.

### 9.5. `GET /deliveries/{id}`

`200` con la entrega (§10) y sus `alerts` (§11.4). Una entrega `rejected` o `failed` también responde `200`: el
motivo está en `delivery.error`.

---

## 10. Estados y fases de una entrega

### 10.1. Estados (`delivery.status`)

```
pending_upload --complete--> received --> processing --> processed
      |                         |              |  ^
      |                         |              v  | (reintento automático, máx. 3 intentos)
      +-----> rejected <--------+-----------  failed
```

| Estado | Significado | Final | Qué hace el conector |
|---|---|---|---|
| `pending_upload` | Abierta, esperando el fichero | no | Subir y completar |
| `received` | Fichero recibido; en cola | no | Esperar |
| `processing` | ONEMS lo está procesando (ver `phase`) | no | Esperar |
| `processed` | Procesada: recuentos y alertas disponibles | **sí** | Siguiente periodo |
| `failed` | Error temporal de ONEMS; se reintenta sola (hasta 3 intentos, cada uno al menos 5 minutos después del anterior) | no | Esperar |
| `rejected` | Rechazada (`error` dice por qué) | **sí** | Corregir y reenviar el periodo (§12.3) |

Una entrega **real** (no de prueba, §15.1) cuenta como **entregada** (para `next_period` y para los solapes) en
`received`, `processing`,
`processed` y `failed`.

### 10.2. Fases (`delivery.phase`) y avance

| Fase | Qué se hace |
|---|---|
| `load` | Lectura del fichero por trozos, cálculo del sha256, carga de los registros (`bytes_loaded`, `rows_loaded`) |
| `resolve` | Equivalencias de cada lectura: producto, punto, fecha y hora |
| `items` | Agrupación por envío y validación de cada envío |
| `strata` | Población por ruta (ciudad a ciudad) y semana ISO de la llegada |
| `draw` | Sorteo |
| `transfer` | Paso de los elegidos a muestras |
| `finish` | Recuentos, alertas y cierre de las semanas que terminan en el periodo |
| `abort`, `cleanup` | Vaciado de la zona de recepción |
| `done`, `failed`, `rejected` | Resultado final |

Recuentos al terminar: `rows_total`, `rows_rejected`, `shipments_total` (envíos del fichero), `shipments_valid`,
`shipments_drawn` (cuántos se sortearon, nunca cuáles), `rejected_reasons` (§11.3).

---

## 11. Errores y motivos de rechazo

### 11.1. Forma de los errores

```json
{"success": false, "error": "CL_PERIOD_NOT_IN_CALENDAR",
 "message": "The period does not match the delivery calendar. Use next_period from GET /config.",
 "detail": "solo en errores de validación de la petición"}
```

`message` es un texto fijo en inglés por código; el conector DEBE decidir por `error`, no por el texto.

### 11.2. Códigos de error de la API

| HTTP | Código | Cuándo | Qué hacer |
|---|---|---|---|
| 400 | `CL_BAD_REQUEST` | Cuerpo no JSON, clave desconocida, fecha, sha256, formato o tamaño inválidos | Corregir la petición |
| 400 | `CL_COMPRESSION_UNSUPPORTED` | Compresión pedida o `Content-Encoding` distinto de identity | Enviar el fichero sin comprimir |
| 400 | `CL_BAD_PERIOD` | `period_start` posterior a `period_end` | Usar `next_period` |
| 400 | `CL_BAD_CONTROL_TOTALS` | Totales mal formados o más de 10.000 | §7 |
| 401 | `CL_UNAUTHORIZED` | Clave ausente, inválida, inactiva o caducada | Revisar la clave (§3.3) |
| 403 | `CL_FEED_PAUSED` | El conector está pausado en ONEMS | No entregar; hablar con ONEMS |
| 403 | `CL_FORBIDDEN` | Prohibido | Hablar con ONEMS |
| 404 | `CL_NOT_FOUND` | Ruta desconocida | Revisar la URL |
| 404 | `CL_DELIVERY_NOT_FOUND` | Entrega inexistente, de otro conector o id mal formado | Usar el `delivery_id` devuelto |
| 404 | `CL_FEED_NOT_FOUND` | El conector de la clave ya no existe | Hablar con ONEMS |
| 405 | `CL_METHOD_NOT_ALLOWED` | Método no admitido en la ruta (cabecera `Allow`) | Revisar el método |
| 409 | `CL_PERIOD_ALREADY_DELIVERED` | El periodo (o parte) ya está entregado | No reenviar; leer `next_period` |
| 409 | `CL_SUPERSEDED` | Otra entrega del mismo periodo con otro fichero la sustituyó | Seguir con la nueva |
| 409 | `CL_FILE_NOT_UPLOADED` | `complete` sin fichero subido | Subir y volver a completar |
| 410 | `CL_ENDPOINT_GONE` | Ruta de la versión 3 (`/demands`, `/batches`) | Migrar a la v4 |
| 410 | `CL_UPLOAD_EXPIRED` | Entrega abierta hace más de 7 días sin completar | Abrir de nuevo el periodo |
| 413 | `CL_BODY_TOO_LARGE` | Cuerpo de la petición de más de 5 MB | Reducir los totales de control |
| 413 | `CL_FILE_TOO_LARGE` | Fichero mayor que `limits.max_file_bytes` | Avisar a ONEMS (§6.5) |
| 413 | `CL_TOO_MANY_ROWS` | Más registros que `limits.max_rows` | Avisar a ONEMS |
| 413 | `CL_RECORD_TOO_LONG` | Un registro de más de 4 MiB | Revisar el fichero |
| 422 | `CL_PERIOD_NOT_CLOSED` | El último día del periodo no ha terminado (zona de la cuenta) | Esperar |
| 422 | `CL_PERIOD_NOT_IN_CALENDAR` | El periodo no es el del calendario | Usar `next_period` |
| 422 | `CL_NO_ACTIVE_PLAN` | Ningún plan activo cubre el periodo | No entregar; `next_period` lo indica |
| 422 | `CL_SHA256_MISMATCH` | El fichero subido no coincide con el sha256 o el tamaño declarados | Reenviar el periodo (§12.3) |
| 422 | `CL_MAPPING_INCOMPLETE` | Faltan equivalencias de campos en ONEMS | Hablar con ONEMS |
| 422 | `CL_BAD_ENCODING` | El fichero no es UTF-8 válido | Corregir y reenviar |
| 422 | `CL_BAD_CSV_HEADER` | CSV sin cabecera, con nombres vacíos o repetidos | Corregir y reenviar |
| 422 | `CL_FILE_MISSING` | El fichero no estaba al empezar el proceso | Reenviar el periodo |
| 422 | `CL_RETRIES_EXHAUSTED` | El proceso falló 3 veces | Reenviar el periodo; si se repite, hablar con ONEMS |
| 429 | `CL_RATE_LIMITED` | Más de 30 peticiones en un minuto (cabecera `Retry-After: 60`) | Esperar y reintentar |
| 500 | `CL_INTERNAL` | Error interno | Reintentar con espera creciente |

`CL_FILE_TOO_LARGE` y `CL_PERIOD_ALREADY_DELIVERED` los devuelve ya `POST /deliveries` (§9.3) y también
`complete`, si la entrega queda rechazada al completarla. Los demás códigos de rechazo del fichero
(`CL_SHA256_MISMATCH`, `CL_TOO_MANY_ROWS`, `CL_RECORD_TOO_LONG`, `CL_MAPPING_INCOMPLETE`, `CL_BAD_ENCODING`,
`CL_BAD_CSV_HEADER`, `CL_FILE_MISSING`, `CL_RETRIES_EXHAUSTED`), `CL_SUPERSEDED` y `CL_UPLOAD_EXPIRED` llegan como
respuesta HTTP solo en `complete` (si la entrega ya está rechazada en ese momento); en cualquier caso se leen en
`delivery.error` con `GET /deliveries/{id}` (`200`).

Errores **temporales** que solo aparecen en `delivery.error` de una entrega `failed` (ONEMS reintenta solo):
`CL_STORAGE_ERROR`, `CL_STORAGE_SHORT_READ`, `CL_FILE_SIZE_UNKNOWN`, `CL_WORKER_ERROR`, `CL_WORKER_LOST`,
`CL_BAD_SHA_STATE`, `CL_PROCESSING_ERROR` (a veces seguido de un código de 5 caracteres). No requieren acción del
carrier.

### 11.3. Motivos de rechazo de lecturas y envíos

Una entrega `processed` puede tener lecturas y envíos rechazados: no se usan, pero la entrega es válida.
`rejected_reasons` da cuántos por motivo:

| Lecturas (`rejected_reasons.rows`) | Significado |
|---|---|
| `bad_record` | El registro no es un objeto JSON, o una fila CSV con distinto número de columnas que la cabecera |
| `bad_value` | `item_id`, `place_ref` o `mode_ref` de más de 200 caracteres |
| `missing_field` | Falta un campo obligatorio (identificador, fecha y hora o lugar) |
| `bad_timestamp` | Fecha y hora ilegible con el formato acordado |
| `unknown_product` | Código de producto sin equivalencia en ONEMS |
| `unknown_reading_point` | Lugar y modo que no son un punto acordado |

| Envíos (`rejected_reasons.shipments`) | Significado |
|---|---|
| `already_sampled` | Ya es una muestra de una entrega anterior |
| `unknown_product` | Alguna lectura del envío tiene un producto desconocido |
| `product_mismatch` | Lecturas con productos distintos, o un producto sin plan en este conector |
| `no_start` | Sin lectura válida en un punto de salida |
| `same_reading` | La única lectura de salida es también la de llegada |
| `no_end` | Sin lectura válida en un punto de llegada |
| `start_after_end` | La salida es posterior a la llegada |
| `reader_without_city` | El punto no tiene ciudad en ONEMS (lo arregla ONEMS) |
| `end_out_of_period` | La llegada final no está dentro del periodo |
| `no_stratum` | La ruta o la semana no están en el plan |

Una proporción alta de motivos que dependen del carrier (`no_start`, `no_end`, `end_out_of_period`,
`start_after_end`…) indica que la extracción no sigue §5.

### 11.4. Alertas visibles para el carrier

`GET /deliveries/{id}` devuelve en `alerts` las alertas de calidad del fichero que el carrier puede corregir o
explicar:

| `type` | `details` | Significado |
|---|---|---|
| `unknown_product` | `values`: códigos | Productos del fichero sin equivalencia |
| `unknown_reading_point` | `points`: `place_ref`, `mode_ref` | Lugares y modos del fichero que no son puntos acordados |
| `rejected_ratio` | `rejected`, `shipments`, `ratio` | Más del 20 % de los envíos rechazados (sin contar `already_sampled`) |
| `reader_without_city` | — | Un punto sin ciudad en ONEMS |
| `insufficient_candidates` | — | En alguna ruta y semana hubo menos envíos válidos que muestras necesarias |
| `delivery_retries_exhausted` | `last_error`, `attempts` | El proceso falló 3 veces |

---

## 12. Idempotencia, reintentos y reenvíos

### 12.1. Idempotencia

- `POST /deliveries` con el **mismo periodo y el mismo sha256** que una entrega no rechazada de la misma clase
  (prueba o real) devuelve esa entrega (`200`, `existing: true`), sin crear otra. Si aún espera el fichero, trae una
  URL de subida nueva. Una entrega real con el mismo fichero que una de prueba es una entrega nueva.
- `POST /deliveries/{id}/complete` repetido devuelve el estado actual: `202` mientras siga `received`, `200` en
  `processing`, `processed` o `failed`.
- `GET` no cambia nada.

Por eso, ante un error de red o un `5xx`, el conector DEBE repetir la misma llamada con el mismo contenido
(CL-REQ-019), con espera creciente (por ejemplo 30 s, 1, 2, 4, 8 minutos).

### 12.2. Subida fallida o URL caducada

Repetir `POST /deliveries` con el mismo cuerpo: misma entrega, URL nueva. Si el PUT responde `409`, o `400` con
`"statusCode": "409"` en el cuerpo (el fichero ya
está), continuar con `complete`.

### 12.3. Reenviar un periodo rechazado

Una entrega `rejected` no cuenta como entregada: el periodo sigue siendo `next_period`. El carrier corrige la causa
(`delivery.error`), regenera el fichero si hace falta y repite el flujo completo (§8) para el **mismo periodo**. Con
el mismo fichero también se puede (por ejemplo tras `CL_SHA256_MISMATCH` por una subida corrupta). Cuando la nueva
entrega queda procesada, ONEMS cierra sola la incidencia *Entrega rechazada*.

### 12.4. Lo que no se puede hacer

- Reenviar un periodo ya `processed` o en curso: `409 CL_PERIOD_ALREADY_DELIVERED`. No hay correcciones de un
  periodo procesado; si el fichero tenía un error grave, el carrier DEBE avisar a ONEMS.
- Partir un periodo en varios ficheros, o juntar varios periodos en uno.

---

## 13. Lo que ONEMS no comunica al carrier

ONEMS **nunca revela qué envíos se sortearon**: ni en las respuestas de la API (solo el número,
`shipments_drawn`), ni en los avisos por correo. Tampoco muestra al carrier las alertas que dependen del sorteo o
que son valoraciones del regulador (posibles envíos mal encaminados entre los elegidos, distribuciones de tiempos
sospechosas, semanas ya liquidadas).

Motivo: la medida es útil para todas las partes solo si la muestra es independiente de quien aporta los datos. Si
se conocieran los envíos elegidos, cualquier tratamiento distinto de esos envíos —aunque fuera involuntario— podría
alterar el resultado y restar credibilidad a la medida. Es la misma regla que se aplica a los envíos de prueba de
los panelistas.

---

## 14. Avisos por correo al carrier

ONEMS envía avisos automáticos al **correo de avisos del carrier** registrado en el maestro de carriers de ONEMS
(un único correo, normalmente de su equipo técnico u operativo). Sin correo registrado, no hay avisos al carrier
(sí al regulador). El idioma es el de la cuenta del regulador. Los avisos solo contienen el nombre del conector,
los periodos y recuentos; nunca datos de envíos.

| Aviso | Cuándo | Se cierra | Qué hacer |
|---|---|---|---|
| **Entrega no recibida** | Pasa `due_at` + margen (6 h por defecto) sin entrega del periodo. Cada periodo que siga sin llegar mientras la incidencia esté abierta genera un nuevo aviso. | Sola, en cuanto se recibe una entrega | Entregar los periodos pendientes en orden |
| **Entrega rechazada** | Una entrega queda `rejected` por el fichero (huella, tamaño, filas, codificación, cabecera CSV, equivalencias) o por agotar los reintentos | Sola, cuando ese periodo tiene una entrega procesada | Corregir y reenviar (§12.3) |
| **Rechazo alto** | Más del 20 % de los envíos de una entrega rechazados | Sola, con la siguiente entrega por debajo del umbral | Revisar `rejected_reasons` y la extracción (§5) |

Los avisos no esperan respuesta. Para dudas, el contacto acordado con el equipo de ONEMS.

---

## 15. Modo pruebas y pruebas de conformidad

### 15.1. Modo pruebas

Un conector nuevo empieza en **Pruebas** (`connector.status = "testing"`). La API, los ficheros y el proceso son
exactamente los mismos, pero las entregas se marcan `is_test: true`:

- se comprueban y cuentan (recuentos y motivos de rechazo en `GET /deliveries/{id}`), pero **no crean muestras**,
  **no generan alertas** (los productos y lugares desconocidos solo se ven como recuentos de motivos), no abren
  incidencias y no avisan;
- **no consumen el periodo**: no cuentan para `next_period` ni para los solapes, así que el mismo periodo se puede
  entregar en prueba tantas veces como haga falta (con el mismo fichero, `POST /deliveries` devuelve la misma entrega
  de prueba; con otro fichero, abre otra) y, al pasar a Activo, ese periodo se entrega de nuevo como real y da sus
  muestras;
- **nunca cubren un periodo**: si el conector ya está Activo, una entrega de prueba que quede (recibida, fallida o
  atascada) no evita el aviso de *Entrega no recibida* del periodo, no retrasa el proceso de las entregas reales y no
  impide liquidar las semanas; se procesa por su cuenta;
- siguen exigiendo un periodo cerrado y del calendario (alineado con las entregas reales) y **un plan activo** que lo
  cubra (`422 CL_NO_ACTIVE_PLAN` si no): para certificar, ONEMS aplica el plan (o un plan de prueba) antes.

Cuando las pruebas pasan, ONEMS lo cambia a **Activo**; desde entonces cada entrega crea muestras y `next_period`
propone el primer periodo real pendiente, aunque ya se hubiera probado. Un conector **Pausado** no acepta entregas
(`403 CL_FEED_PAUSED`).

### 15.2. Pruebas de conformidad

Se ejecutan con el conector en Pruebas. El carrier guarda las peticiones y respuestas de cada prueba.

| Id | Prueba | Resultado esperado | Requisitos |
|---|---|---|---|
| CT-01 | `GET /config` con clave válida (en `x-api-key` y en `Authorization: Bearer`) | `200`, `schema_version` 4.x | 002, 005 |
| CT-02 | `GET /config` sin clave y con una clave inventada | `401 CL_UNAUTHORIZED` | 002 |
| CT-03 | Entrega completa en JSON Lines de `next_period` (§8) | `201`, PUT `200`, `202`, después `processed` | 009–017 |
| CT-04 | Entrega del periodo siguiente en CSV | `processed`; `rows_total` = registros del fichero | 013 |
| CT-05 | Revisión de la entrega: `shipments_total` = envíos del fichero = suma de `control_totals` | Coinciden | 009, 015 |
| CT-06 | Revisión de motivos: sin `end_out_of_period`, `no_start` ni `no_end` salvo los explicados por datos reales | Explicados por escrito | 009–011 |
| CT-07 | Repetir el `POST /deliveries` de CT-03 | `200`, `existing: true`, `upload: null` | 012 (§12.1) |
| CT-08 | Abrir el periodo de CT-03 con otro sha256 (en Pruebas) | `201`, otra entrega de prueba; `next_period` sigue siendo el mismo periodo (las pruebas no lo consumen). Con el conector Activo, el mismo caso tras una entrega real daría `409 CL_PERIOD_ALREADY_DELIVERED` (ejemplo 13) | 007, 020 |
| CT-09 | Abrir un periodo que no es el del calendario | `422 CL_PERIOD_NOT_IN_CALENDAR` | 007 |
| CT-10 | Abrir el periodo en curso (sin cerrar) | `422 CL_PERIOD_NOT_CLOSED` | 007 |
| CT-11 | `POST /deliveries` con `compression: "gzip"` y con una clave extra en el cuerpo | `400 CL_COMPRESSION_UNSUPPORTED` / `400 CL_BAD_REQUEST` | 013 |
| CT-12 | Subir un fichero distinto del declarado (mismo tamaño) y completar | `202`, después `rejected` `CL_SHA256_MISMATCH` | 014 |
| CT-13 | Reenviar el periodo de CT-12 correctamente | `processed` | 020 |
| CT-14 | Completar sin haber subido el fichero | `409 CL_FILE_NOT_UPLOADED` | 017 |
| CT-15 | Subida interrumpida: repetir `POST /deliveries` y subir con la URL nueva | Misma `delivery_id`, `processed` | 016, 019 |
| CT-16 | Datos personales: revisión del fichero y de `extra_fields` | Solo campos acordados | 012 |
| CT-17 | Ritmo: sondeo cada 60 s y respuesta correcta a un `429` simulado | Espera `Retry-After` | 018, 019, 021 |
| CT-18 | `GET /demands` (ruta v3) | `410 CL_ENDPOINT_GONE` | — |
| CT-19 | Secretos: la clave y las URL de subida no aparecen en los registros del conector | Revisión | 003, 004 |

---

## 16. Lista de comprobación para la puesta en marcha

**Antes de empezar (carrier y ONEMS juntos)**

- [ ] Calendario acordado (días y hora) y margen de «no recibida».
- [ ] Nombres de campo del carrier y formato de fecha y hora; zona horaria de las horas sin desplazamiento.
- [ ] Códigos de producto del carrier por producto de ONEMS.
- [ ] Lista de puntos (lugar y modo) con su papel; ciudad de cada uno.
- [ ] Campos adicionales permitidos (ninguno personal).
- [ ] Volumen esperado por periodo frente a los límites (§6.5).
- [ ] Correo de avisos del carrier registrado en ONEMS.
- [ ] Canal seguro para entregar la clave y contacto técnico de cada parte.

**Carrier**

- [ ] Extracción según §5 revisada (consulta §5.2 adaptada) y totales de control (§7).
- [ ] Conector: `GET /config` → abrir → PUT → completar → sondear, con reintentos (§12) y sin secretos en registros.
- [ ] Pruebas CT-01 a CT-19 superadas en modo Pruebas, con evidencias.
- [ ] Programación del conector a partir de `due_at`, con alarma propia si una entrega no termina `processed`.

**ONEMS**

- [ ] Plan aplicado (activo) que cubra los periodos de prueba: sin él, las entregas de prueba responden
      `422 CL_NO_ACTIVE_PLAN`.
- [ ] Revisión de las entregas de prueba: recuentos y motivos de rechazo (`unknown_reading_point`,
      `unknown_product`…). En Pruebas no se crean alertas: los desconocidos se ven solo en los motivos.
- [ ] Conector pasado a **Activo**. Los periodos probados no se pierden: `next_period` vuelve a proponer el primero
      pendiente y el carrier lo entrega como real. Primera entrega real seguida hasta `processed`.

---

## 17. Ejemplo completo

La carpeta [`ejemplo/`](ejemplo/) es la salida real de una ejecución del simulador de carrier contra una base
ONEMS local (`bash tools/carrier-simulator/e2e/run.sh` con `SAVE_EXAMPLES=1`). El carrier ficticio SIMPOST entrega
lunes y jueves a las 03:00 (Africa/Nairobi); el plan cubre las semanas ISO 2026-W45 y W46 (28 muestras). Los
`delivery_id` y las horas cambian en cada ejecución; los ficheros, sha256 y recuentos no (semilla fija). En el
ejemplo la URL de subida es `local://…` (en local no hay almacén real); en ONEMS es `https://…/upload/sign/…`.

| Fichero | Qué es |
|---|---|
| `01-get-config.json` | `GET /config`: `next_period` = 2026-11-02 a 2026-11-04 (la entrega anterior de ese periodo se rechazó, por eso `last_delivery` es `rejected`) |
| `02-delivery-2026-11-02_2026-11-04.jsonl` | El fichero: 163 envíos completos, 385 lecturas y 2 registros rotos a propósito (387 registros), 52.581 bytes |
| `02-…manifest.json` | Lo que calculó el conector: campos, envíos, registros, sha256, tamaño |
| `03-open-request.json` | Cuerpo de `POST /deliveries` (con los totales de control: 54 + 55 + 54 = 163) |
| `04-open-response.json` | `201`: entrega `pending_upload` y `upload` |
| `05-upload-response.json` | Respuesta del PUT |
| `06-complete-response.json` | `202`: `received` |
| `07-status-processed.json` | `GET /deliveries/{id}` final: `processed`; 387 registros, 61 rechazados (2 `bad_record`, 4 `bad_timestamp`, 4 `unknown_product`, 51 `unknown_reading_point`); 163 envíos, 159 válidos, **8 sorteados**; alertas `unknown_product` (`XX9`) y `unknown_reading_point` (lecturas en centros de tratamiento que no son puntos acordados) |
| `08-delivery-2026-11-05_2026-11-08.csv` | El fichero del periodo siguiente en CSV (226 envíos) |
| `09-status-processed-csv.json` | Su estado final (226 envíos, 217 válidos, 6 sorteados) |
| `10-tampered-complete-response.json`, `11-tampered-status-rejected.json` | Primera entrega del periodo con un fichero alterado (un dígito cambiado, mismo tamaño): `202` y después `rejected` `CL_SHA256_MISMATCH`. ONEMS abrió la incidencia *Entrega rechazada* (aviso al regulador y al carrier) y la cerró sola al procesarse el reenvío |
| `12-replay-open-existing.json` | Repetición de `03`: `200`, `existing: true`, `upload: null` |
| `13-error-already-delivered.json` | Mismo periodo con otro sha256: `409 CL_PERIOD_ALREADY_DELIVERED` |
| `14-error-not-in-calendar.json` | 2026-11-16 a 2026-11-17 (el 18 no es día de entrega): `422 CL_PERIOD_NOT_IN_CALENDAR` |
| `15-error-no-active-plan.json` | 2026-11-16 a 2026-11-18 (después del plan): `422 CL_NO_ACTIVE_PLAN` |
| `16-error-delivery-not-found.json` | Entrega inexistente: `404 CL_DELIVERY_NOT_FOUND` |
| `17-error-v3-route-gone.json` | `GET /demands`: `410 CL_ENDPOINT_GONE` |
| `18-get-config-after.json` | Tras los 4 periodos: `next_period` `null` (no queda plan) |

Los 4 periodos (2–4, 5–8, 9–11 y 12–15 de noviembre) dieron 8 + 6 + 8 + 6 = **28 muestras**, exactamente las del
plan; las dos semanas quedaron cumplidas. Los ruidos del ejemplo son deliberados: registros rotos, lecturas en
lugares no acordados de un 8 % de los envíos, una lectura de admisión duplicada con fecha ilegible y lecturas de
entrega con un código de producto corrupto (`XX9`). Los envíos que nunca llegan y los que tienen la llegada
registrada antes de la salida no son completos (§5) y no están en el fichero.

---

## 18. Preguntas frecuentes

**¿Por qué hay que enviar todos los envíos y no una muestra?** Porque el sorteo debe hacerlo un tercero
independiente con una semilla registrada (§13). Enviar la población entera es además más sencillo: no hay que
implementar ningún sorteo.

**¿Y si un periodo no tiene envíos?** Se entrega igual, con `control_totals: []` y un fichero sin registros: un
CSV con solo la cabecera o un JSON Lines con una sola línea en blanco (`size_bytes` debe ser al menos 1).

**¿Puedo entregar antes de `due_at`?** Sí, en cuanto el periodo esté cerrado, pero se recomienda esperar a `due_at`
para incluir las lecturas que llegan tarde a sus sistemas.

**¿Qué pasa si me salto un periodo?** ONEMS abre una incidencia *Entrega no recibida* y avisa. `next_period` sigue
proponiendo el periodo siguiente al último entregado; un periodo saltado se puede entregar tarde con sus fechas
exactas mientras no se solape con otro, pero si su semana ya se liquidó puede no aportar muestras.

**¿Un envío puede aparecer en dos periodos?** Solo si recibe una nueva lectura de llegada después de entregarse
(§5.1). ONEMS lo detecta (`already_sampled` si ya era muestra).

**¿Por qué me rechazan lecturas `unknown_reading_point`?** Son lecturas en lugares o modos que no están en
`points`. Si el plan no tiene diagnóstico, no hace falta enviarlas; si son puntos que deberían estar, avise a ONEMS.

**¿Puedo comprimir el fichero?** No (`CL_COMPRESSION_UNSUPPORTED`). Si el tamaño es un problema, se acuerda un
calendario más frecuente.

**¿Cuánto tarda el proceso?** Del orden de minutos; un fichero de varios cientos de MB puede tardar más. Consulte
`phase`, `bytes_loaded` y `rows_loaded`.

**¿Puedo saber qué envíos se eligieron?** No (§13).

**¿Las entregas de prueba gastan periodos?** No (§15.1): al pasar a Activo se entregan de nuevo como reales.

**¿Hay un entorno de pruebas?** El modo Pruebas del conector (§15.1). Además, el simulador
`tools/carrier-simulator/` incluye un conector de referencia en Python.

---

## 19. Glosario

| Término | Definición |
|---|---|
| Carrier | Operador postal o de mensajería cuyos envíos se miden |
| Conector | Programa del carrier que entrega los datos; y su configuración en ONEMS (calendario, equivalencias, clave) |
| Clave del conector | Secreto que identifica al conector ante la API |
| Calendario | Días y hora de entrega del conector |
| Periodo de entrega | Días cubiertos por una entrega (de un día a una semana), en fechas locales de la cuenta |
| Entrega | Un fichero de un periodo y su proceso en ONEMS (`delivery_id`) |
| Envío completo | §5.1 |
| Lectura | Un escaneo de un envío en un lugar y momento (un registro del fichero) |
| Punto acordado | Lugar (y modo) del carrier dado de alta en ONEMS, con papel de salida, llegada, ambos o intermedio |
| Población | Envíos válidos de una ruta y semana en una entrega |
| Ruta | Par ciudad de origen → ciudad de destino |
| Semana | Semana ISO de la llegada (lunes a domingo); unidad de las cuotas del plan |
| Sorteo | Selección aleatoria, hecha por ONEMS con semilla registrada, de los envíos que pasan a ser muestra |
| Muestra | Envío elegido; entra en los informes con origen «carrier» |
| Totales de control | Recuentos declarados por el carrier por punto de llegada y producto (§7) |
| URL firmada | Dirección temporal (2 h) para subir un fichero sin la clave |
| Incidencia | Problema que ONEMS sigue y avisa (entrega no recibida, rechazada, muchos rechazos) |

---

## 20. Anexos

### Anexo A. OpenAPI 3.1

[`openapi.yaml`](openapi.yaml): rutas, parámetros, respuestas y ejemplos. Los cuerpos referencian los esquemas del
Anexo B.

### Anexo B. JSON Schema (2020-12)

| Fichero | Qué valida |
|---|---|
| [`schemas/config-response.schema.json`](schemas/config-response.schema.json) | Respuesta de `GET /config` |
| [`schemas/delivery-open-request.schema.json`](schemas/delivery-open-request.schema.json) | Cuerpo de `POST /deliveries` |
| [`schemas/delivery-open-response.schema.json`](schemas/delivery-open-response.schema.json) | Respuesta de `POST /deliveries` |
| [`schemas/delivery-response.schema.json`](schemas/delivery-response.schema.json) | Respuesta de `complete` y `GET /deliveries/{id}` |
| [`schemas/delivery.schema.json`](schemas/delivery.schema.json) | La entrega (estados, fases, recuentos, motivos, alertas) |
| [`schemas/delivery-file-row.schema.json`](schemas/delivery-file-row.schema.json) | Un registro del fichero |
| [`schemas/error.schema.json`](schemas/error.schema.json) | Cuerpo de error |

Los esquemas, el OpenAPI y el ejemplo se validan entre sí con `python -I tools/carrier-simulator/tests/test_docs.py`.

### Anexo C. Historial de versiones

| Versión | Fecha | Cambios |
|---|---|---|
| 1.0–1.1 (v3 de diseño) | 2026-11 | ONEMS emitía demandas por estrato; el carrier sorteaba candidatos y los enviaba en lotes (`/demands`, `/batches`). **Retirada.** |
| 4.1 | 2026-11-25 | `GET /query`: la consulta de extracción ya rellenada (PostgreSQL probada; Oracle y SQL Server sin probar). CL-REQ-024. |
| 4.0 | 2026-11-23 | Entrega completa por periodo según calendario; sorteo solo en ONEMS; fichero JSON Lines o CSV sin comprimir con URL firmada; totales de control; estados y fases; avisos por correo al carrier. Las rutas v3 responden `410`. |

### Contacto

Equipo de ONEMS del regulador (dirección y canal seguro acordados al alta del conector).
