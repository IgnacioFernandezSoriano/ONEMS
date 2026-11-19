# Carrier Link — muestras desde las lecturas del carrier (estudio y diseño, v3)

> **Fecha:** 2026-11-19 (v3, tras contra-análisis independiente)
> **Proyecto:** ONEMS · Supabase `onems-dev` (`sehbnpgzqljrsqimwyuz`)
> **Estado:** diseño propuesto, pendiente de aprobación del responsable
> **Sustituye a:** [2026-10-23-muestras-desde-datos-del-carrier-design.md](2026-10-23-muestras-desde-datos-del-carrier-design.md). Este documento es completo por sí mismo: el anterior ya no hace falta para construir. La numeración de decisiones es nueva (R = responsable, D = diseño) y no se corresponde con la del documento anterior.

---

## 0. Resumen

Hoy ONEMS mide con envíos de prueba que mueven panelistas (E2E) y con lecturas RFID en centros postales (diagnóstico). **Carrier Link** añade una tercera fuente: para los carriers que lo permitan, ONEMS extrae **al azar**, periodo a periodo, envíos reales de los datos de lectura del propio carrier y los usa como muestras.

- **Sección propia en el menú**, separada de Allocation Plans. El camino de los panelistas no se toca.
- **El punto de lectura sustituye al panelista.** Un envío de prueba tiene panelista de origen y de destino; una muestra del carrier tiene **punto de lectura de inicio** y **punto de lectura de fin**. El tiempo E2E va de uno a otro.
- **Se aprovechan los maestros existentes.** Los puntos de lectura son filas del maestro de lectores, cada una en un centro postal y por tanto en una ciudad.
- **Cada carrier tiene sus equivalencias** de campos y valores, definidas en ONEMS. Lo que entra queda siempre estandarizado.
- **Lo normal es solo E2E; el diagnóstico es opcional por plan.**
- **No hay informes nuevos.** Los datos aparecen en los informes actuales, con el **origen de cada lectura** visible.
- **Tiempo de equivalencia.** La lectura del carrier no incluye el último tramo hasta el destinatario ni los retrasos de declaración que sí lleva la medida con panelistas. El estándar de entrega admite un tiempo añadido para que las dos medidas sean comparables.

## 1. Decisiones

### 1.1. Del responsable (no reabrir)

| # | Decisión |
|---|---|
| R1 | Informes: los mismos que hoy, sin informes aparte. Los datos del carrier aparecen integrados en E2E y en diagnóstico. |
| R2 | El origen del dato se puede distinguir, y la base de datos lo guarda **para cada lectura**. |
| R3 | Capa intermedia ("muro") por carrier. ONEMS define por carrier la **equivalencia de campos y valores**; puertas adentro todo está estandarizado. Una cuenta tiene varios carriers. |
| R4 | Base de muestreo: **entregas cerradas en el periodo**. |
| R5 | ONEMS publica la **demanda**; el lado del carrier devuelve un **lote de candidatos** (5-10× lo pedido) extraído al azar; ONEMS hace el sorteo final. Principio rector: **representatividad estadística y aleatoriedad**. |
| R6 | El identificador del envío es el del carrier, **texto opaco**. |
| R7 | Cada demanda y cada lote son de **un carrier y un producto**. La cadencia se define en el plan. |
| R8 | Carrier Link es una **sección propia**, con sus menús y sus tablas, separada de Allocation Plans. |
| R9 | Se conserva la lógica del plan (cuántas muestras, qué rutas, qué semanas). El balanceo no aplica. El plan reparte por **ciudad → ciudad y semana**, sin fijar el punto concreto. |
| R10 | **Punto de lectura de inicio = panelista de origen; punto de lectura de fin = panelista de destino.** Son lugares dados de alta en la topología como lectores de un centro postal. |
| R11 | Un mismo lugar puede tener lectura RFID y lectura del carrier; son lectores distintos y sus eventos van separados. |
| R12 | Lo normal es **solo E2E**; el diagnóstico no se descarta y debe poder activarse. |
| R13 | **Aprovechar los maestros existentes**, añadiendo campos si hace falta. |
| R14 | El conector entrega **una fila por evento**: una lectura, en un punto de lectura, en un instante. La traducción se aplica dentro de ONEMS, en la entrada. |
| R15 | **Toda lectura de inicio y de fin se cuenta**, aunque no encaje en la ruta pedida; puede indicar un envío mal encaminado. Si se compensa o no, se verá más adelante. |
| R16 | Un plan **no se activa** hasta que cada ciudad tiene sus puntos de inicio y de fin. |
| R17 | Cuota semanal no cubierta: se pueden hacer **varias peticiones en la misma semana** para completar; lo que falte se **reparte entre las semanas restantes del mes** y, si no cabe, entre las de los meses siguientes hasta completarlo. |
| R18 | Ruta sin estándar de entrega: **se recogen las lecturas** y se avisa para que se corrija. |
| R19 | Datos personales: solo se guardan campos de una lista permitida; el resto se descarta en la entrada. |
| R20 | El estándar de entrega admite, para este tipo de lectura, **un tiempo añadido** que hace equivalentes los análisis con los de panelistas. |
| R21 | Permisos por rol según la tabla de §7. |
| R22 | La **barrera de conexión** (el conector del muro) define **cómo** (modelo de extracción) y **cuándo** (calendario local: días de la semana y hora) se conecta ONEMS con cada carrier, para no interferir con su base de datos. Las peticiones solo se emiten en ese hueco. |

### 1.2. De diseño (revisables)

| # | Decisión | Por qué |
|---|---|---|
| D1 | Tablas nuevas con prefijo `cl_`. Ninguna columna nueva en `allocation_plans` ni `allocation_plan_details`. | Hoy 80 funciones usan la tabla de envíos del plan y su trigger de etiquetas alteraría el identificador del carrier. |
| D2 | El punto de lectura **es una fila de `readers`**, con campos nuevos (§3.2). Un lugar con RFID y con lectura del carrier tiene dos filas en el mismo centro postal. | R10, R11, R13. |
| D3 | Papel E2E del punto: `origin`, `destination`, `both`, `none`. Para una ruta A → B valen como inicio los puntos `origin` de A y como fin los `destination` de B. Solo pueden tener papel los puntos cuyo centro postal tiene ciudad. | R10. |
| D4 | Punto = lugar + modo. Si un lugar tiene además un punto "cualquier modo", el específico tiene preferencia. | Un lugar puede registrar admisión, salida y entrega como modos distintos. |
| D5 | Tiempo E2E de una muestra: de su **primera** lectura en un punto de inicio a su **última** lectura en un punto de fin. Todas las lecturas de inicio y fin se guardan (R15). Una muestra con lecturas de inicio o fin en más de un punto, o en una ciudad distinta de la pedida, se marca `possible_misrouting`; cuenta igual para la cuota de la ruta para la que se extrajo. | R15. |
| D6 | La muestra entra en `one_db` con las ciudades **reales** de sus puntos de inicio y fin. | Es lo que los informes muestran como origen y destino. |
| D7 | El identificador se guarda **tal como llega**, sin prefijos ni cambios, en `one_db.tag_id`, en la muestra y en cada lectura (decisión del responsable, 19/11). El carrier va en **su propio campo** en cada lectura transformada (`carrier_id`, que `rfid_events_raw` y `processed_events` ya tienen) y en la muestra. Una lectura se identifica por carrier + identificador. | R6. Consecuencia para la fase 4: el diagnóstico cruza hoy por cuenta + etiqueta, sin carrier; antes de activar el diagnóstico hay que comprobar que un identificador del carrier no coincide con una etiqueta de panelista o de otro carrier de la cuenta, o hacer que el cruce tenga en cuenta el carrier (§10). |
| D8 | `one_db.source`: `panelist` (defecto) \| `carrier`. El valor `rfid` no se crea hasta que se defina. Cada lectura guarda su origen por el lector que la produjo (`readers.capture_source`). | R2. |
| D9 | Tiempo de equivalencia (R20): dos campos en `delivery_standards`, **primer tramo** y **último tramo**, en la misma unidad que el estándar. Se suman al tiempo medido. `one_db` guarda el tiempo medido y el tiempo añadido por separado; el "en plazo" y los tiempos que usan los informes son los equivalentes. | Comparable con panelistas sin perder el dato real. |
| D10 | La semilla del sorteo se fija **al emitir la demanda**, antes de recibir el lote. | Nadie puede elegir la semilla después de ver los candidatos. |
| D11 | El lado del carrier informa la **población** de cada estrato. ONEMS registra semilla, población, candidatos y elegidos. | R5: reproducible ante un auditor. |
| D12 | Un identificador solo puede ser muestra una vez por cuenta y carrier. Los ya usados se descartan al validar el lote y no cuentan como rechazo. | Evita duplicados entre peticiones (R17). |
| D13 | La demanda guarda la **foto** de los puntos de inicio y fin que se enviaron. El lote se valida contra esa foto. | Los puntos pueden cambiar entre la demanda y el lote. |
| D14 | Alertas en tabla propia `cl_alerts`. | `incidents` alimenta el contrato de monitorización externo. |
| D15 | Claves de API de los conectores **hasheadas**, con ámbito limitado a su conector. La protección de las 6 claves actuales de la API E2E se hace como entrega previa independiente. | Hoy están en claro. |
| D16 | Los conectores solo hablan con la API (Edge Functions), nunca con la base. | 60 conexiones directas. |
| D17 | `account_id` siempre explícito en las tablas `cl_*`; no se usa el trigger `set_account_id`. | Con `service_role` devuelve vacío y con superadmin pone su propia cuenta. |
| D18 | Diagnóstico: las lecturas van a `rfid_events_raw` en la misma transacción que la entrada en `one_db`, y siguen el pipeline RFID sin modificarlo. | Evita incidencias `unknown_tag`. |

### 1.3. Anti-objetivos

- Que un carrier pueda **elegir** qué envíos manda sin que ONEMS lo detecte.
- Que las muestras de carrier y de panelista se mezclen sin poder separarse.
- Que el camino de panelistas se rompa o se ralentice.
- Que ONEMS guarde todo el tráfico de un operador, o datos personales.

## 2. Cómo funciona, de principio a fin

```
 Plan Carrier Link ──▶ cuotas (ruta ciudad→ciudad × semana)
        │  al vencer la semana + plazo de cierre
        ▼
 DEMANDA (estratos con sus puntos de inicio y de fin, semilla fijada)
        ▼
 CONECTOR del carrier: extrae envíos al azar, cuenta la población
        ▼
 LOTE: una fila por lectura, con los campos y valores del carrier
        ▼
 ENTRADA en ONEMS: aplica las equivalencias del carrier ─▶ lecturas estándar
        │ agrupa por envío, valida
        ▼
 SORTEO por estrato (reproducible)
        ▼
 Muestra + sus lecturas
        ├──▶ one_db (source='carrier': inicio → fin, + tiempo de equivalencia) ──▶ informes E2E actuales
        └──▶ (plan con diagnóstico) rfid_events_raw ──▶ pipeline RFID ──▶ diagnóstico actual
```

## 3. Modelo de datos

### 3.1. Maestros que se reutilizan tal cual

`carriers`, `products` (ya son por carrier), `cities`, `postal_centers`, calendario laboral y festivos de la cuenta.

### 3.2. Maestros con campos nuevos

| Tabla | Campos nuevos |
|---|---|
| `readers` | `capture_source` (`rfid` \| `carrier_scan`, defecto `rfid`); `carrier_id`; `carrier_place_ref`; `carrier_mode_ref` (vacío = cualquier modo); `e2e_role` (`origin\|destination\|both\|none`, defecto `none`). Único por cuenta + carrier + lugar + modo, tratando el modo vacío como un valor más. El `reader_id` de un punto del carrier se genera: `CL:<cuenta>:<carrier>:<lugar>[:<modo>]` (el `reader_id` es único entre todas las cuentas). Las políticas de escritura de `readers` y `postal_centers` aceptan además la opción `cl_reading_points`. |
| `delivery_standards` | `cl_first_mile_time`, `cl_last_mile_time` (numéricos, defecto 0, en la unidad del estándar). |
| `one_db` | `source` (defecto `panelist`); `cl_sample_id` (único, `ON DELETE CASCADE` desde la muestra); `carrier_id`; `measured_total_hours`, `measured_total_days`, `measured_business_hours`, `measured_business_days` (lo medido); `equivalence_hours`, `equivalence_days` (lo añadido). Índice `(account_id, source)`. |
| `api_keys` | `key_hash`, `key_prefix`, `name`, `scope` (`onedb_read\|carrier_feed`), `feed_id`, `expires_at` (D15). |
| `access_option`, `account_access`, `access_template` | Cinco opciones nuevas del grupo `carrier_link` (§7), dadas de alta también en `account_access` de **todas las cuentas existentes** según la plantilla. |

Convenciones al escribir en `one_db`: `carrier_name = carriers.name`, `product_name = products.description`, ciudades por `cities.name`, `plan_name` el del plan Carrier Link, `source_data_snapshot` con los ids de muestra, plan, lectores y ciudades y los campos permitidos de `extra`.

### 3.3. Tablas nuevas

**Plan**
- `cl_plans`: `account_id`, `plan_name`, `carrier_id`, `product_id`, `total_samples`, `start_date`, `end_date`, `status` (`draft|active|closed`), `close_lag_days` (defecto 7), `oversampling_factor` (defecto 5), `feed_id`, `feed_diagnosis` (defecto falso).
- `cl_plan_quotas`: `plan_id`, `origin_city_id`, `destination_city_id`, `iso_year`, `iso_week`, `period_start`, `period_end`, `samples_planned` (lo que salió del generador), `samples_carried_in` (déficit recibido de semanas anteriores, R17), `samples_obtained`, `status` (`pending|open|fulfilled|carried|unfilled`).

**Conector y equivalencias** (por cuenta y carrier)
- `cl_feeds`: `account_id`, `carrier_id`, `name`, `extraction_model` (texto: `push_api`, `pull_rest`, `file_drop`, `db_query`, `manual_upload`…), `config`, `emit_days` (días ISO 1-7), `emit_hour` (0-23), `emit_timezone` (vacío = zona de la cuenta) — calendario de conexión (R22), `secret_ref` (nunca el secreto), `status` (`testing|active|paused`), `last_batch_at`, `last_error`.
- `cl_field_mappings`: `account_id`, `carrier_id`, `standard_field`, `carrier_field`, `format`, `timezone`. Campos estándar: `item_id`, `product`, `scan_at`, `place_ref`, `mode_ref`. Lecturas sin zona horaria usan la del mapeo; si tampoco la hay, la de la cuenta.
- `cl_value_mappings`: `account_id`, `carrier_id`, `kind` (`product`), `carrier_value`, `onems_value`.
- `cl_extra_fields`: `account_id`, `carrier_id`, `carrier_field`: lista de campos adicionales permitidos (R19).

**Captura**
- `cl_demands`: `plan_id`, `quota_ids`, `status` (`open|fulfilled|partial|failed`), `random_seed`, `payload` (incluye la foto de puntos, D13), `requested_at`.
- `cl_batches`: `demand_id`, `batch_id` del conector (único: repetirlo no carga dos veces), `status` (`received|validated|sampled|rejected|undone`), `summary`, `raw_payload` (se borra a los 90 días).
- `cl_batch_scans`: una fila por lectura recibida: `batch_id`, `stratum_id`, `item_id`, `product_id`, `scan_at`, `place_ref`, `mode_ref`, `reader_id` (resuelto o vacío), `status` (`valid|rejected`), `reject_reason`. Las de envíos no elegidos se borran a los 90 días.
- `cl_sampling_runs`: `demand_id`, `stratum_id`, `population_size`, `candidates_valid`, `samples_required`, `samples_selected`, `random_seed`, `selected_item_ids`.
- `cl_alerts`: `account_id`, `plan_id`, `batch_id`, `alert_type`, `severity`, `details`, `status` (`open|acknowledged|dismissed`).

**Muestra**
- `cl_samples`: `account_id`, `plan_id`, `quota_id`, `batch_id`, `carrier_id`, `product_id`, `item_id`, `start_reader_id`, `start_at`, `end_reader_id`, `end_at`, `origin_city_id`, `destination_city_id`, `possible_misrouting`, `extra`, `status` (`active|voided`). Único por cuenta + carrier + `item_id`.
- `cl_sample_scans`: una fila por lectura de la muestra: `sample_id`, `reader_id`, `scan_at`, `role` (`start|end|intermediate`), `place_ref`, `mode_ref`. Las intermedias solo existen con diagnóstico.

Todas llevan RLS: lectura con nivel `view` y escritura con nivel `edit` sobre la opción de su pantalla (`has_any_access`), y siempre limitadas a la cuenta.

## 4. El contrato con el conector

**Demanda** (ONEMS → conector): `demand_id`, el calendario del conector (`schedule`), valores de carrier y de producto **tal como los conoce el carrier** (equivalencia inversa), y por estrato: `stratum_id`, periodo (inicio, fin, semana ISO), `start_points` y `end_points` (cada uno `{ place_ref, mode_ref }` con valores del carrier), `samples_required`, `candidates_requested`, y `include_all_scans` si el plan tiene diagnóstico.

El conector debe, por estrato: tomar los envíos del producto con una lectura en algún punto de inicio y otra en algún punto de fin, con la de fin dentro del periodo (R4); contarlos (`population_size`); extraer al azar `candidates_requested` (o todos si hay menos); y devolver **todas** las lecturas de esos envíos en puntos de inicio o de fin de cualquier ciudad (y todas sus lecturas si `include_all_scans`).

**Lote** (conector → ONEMS): `demand_id`, `batch_id`, y por estrato `stratum_id`, `population_size`, `selection_method` (debe ser `uniform_random_within_stratum`) y `rows`: una fila por lectura con los nombres de campo y valores del carrier.

**Entrada**, en este orden:
1. Lote repetido (`batch_id` ya visto) → se devuelve el resultado anterior.
2. Aplicar `cl_field_mappings` y `cl_value_mappings`; descartar campos fuera de `cl_extra_fields`.
3. Resolver cada lectura contra los puntos de lectura del carrier (D4); las del estrato, contra la foto de la demanda (D13).
4. Agrupar por `item_id`. Un candidato es válido si tiene al menos una lectura de inicio y una de fin, con inicio ≤ fin y la de fin dentro del periodo. No válidos → `rejected` con motivo.
5. Descartar identificadores ya usados (D12).

Llamadas de la API en las fases 0-1: `GET demands` y `POST carrier-link-ingest` (con `dry_run`). Límites: tamaño máximo del cuerpo y máximo de filas por lote (valores a fijar en el plan), y peticiones por minuto por clave. La clave de un conector solo ve las demandas de su conector y solo puede entregar lotes para ellas.

## 5. Sorteo, cuotas y destinos

**Sorteo**, en una transacción por estrato (límite de 2 minutos por sentencia): ordenar los `item_id` válidos, barajar de forma determinista con la semilla de la demanda, tomar los primeros `samples_required`. Si hay menos válidos que pedidos, se toman todos. Se escribe `cl_sampling_runs`.

**Cuota no cubierta** (R17):
1. Mientras la población del estrato sea mayor que lo ya recibido, se emite otra demanda para la misma semana (hasta 3 por semana), pidiendo solo lo que falta.
2. Lo que siga faltando se reparte a partes iguales entre las semanas restantes del mismo mes de esa ruta (`samples_carried_in`); si no quedan, entre las de los meses siguientes hasta el fin del plan. La cuota de origen queda `carried`.
3. Lo que falte al acabar el plan queda `unfilled`, con alerta.

**Cambios en un plan activo:** las muestras obtenidas no se tocan; los cambios afectan a las cuotas aún `pending`.

**Entrada en E2E** por cada muestra: insertar en `one_db` con `source='carrier'`, `tag_id` = el identificador tal como llega (D7), `sent_at = start_at`, `received_at = end_at`. El trigger existente `one_db_compute_transit` calcula horas y días. Después, el muestreador busca el estándar de la ruta (carrier, producto, ciudad de origen, ciudad de destino), guarda lo medido en `measured_*`, suma el tiempo de equivalencia (D9) y calcula `on_time_delivery` con `one_db_on_time`. Sin estándar: la muestra entra sin "en plazo" y se abre la alerta `missing_standard` (R18); al crear el estándar se recalcula.

**Entrada en diagnóstico** (solo planes con `feed_diagnosis`), en la misma transacción: una fila en `rfid_events_raw` por lectura con punto conocido (`tag_id` = el identificador, `carrier_id` el del carrier, `reader_id` el del lector, `event_id` = huella de identificador + lector + hora). Las lecturas en lugares sin punto dado de alta se conservan en `cl_batch_scans`, abren la alerta `unknown_reading_point` y entran al dar de alta el punto.

**Deshacer un lote** (`cl_undo_batch`): marca el lote `undone`, anula sus muestras, borra sus filas de `one_db` y sus eventos de diagnóstico, libera los identificadores y recalcula las cuotas.

**Alertas:** `insufficient_candidates`, `empty_stratum`, `population_drop` (< 30 % de la mediana de 6 periodos), `population_incoherent` (población menor que los candidatos recibidos), `suspicious_distribution` (100 % en plazo con n ≥ 20), `late_batch`, `unknown_product`, `unknown_reading_point`, `possible_misrouting`, `missing_standard`, `rejected_ratio` (> 20 %), `quota_unfilled`, `feed_silent` (conector activo sin lote tras una demanda vencida).

## 6. El origen de cada lectura en los informes

- **E2E** (informes actuales y API de extracción): columna y filtro "Origen del dato" (Todos / Panelistas / Carrier). En el detalle de un envío del carrier se ven sus lecturas de inicio y de fin con su punto, y el tiempo medido junto al tiempo de equivalencia añadido.
- **Diagnóstico** (pantallas actuales de rutas y tramos): cada lectura muestra si viene de RFID o del carrier, tomado del lector que la produjo; filtro por tipo de captura.
- **Lectores y centros postales**: columna y filtro por tipo de captura, para que los puntos del carrier no se confundan con lectores RFID.
- Cuando un informe mezcla orígenes, muestra una nota metodológica.

## 7. Pantallas y permisos

Sección **Carrier Link** en el menú, junto a E2E y RFID:

| Pantalla | Qué se hace | Opción |
|---|---|---|
| **Planes de muestreo** | Crear el plan (carrier, producto, periodo, total, plazo de cierre, casilla de diagnóstico). Cuotas por ruta y semana: previstas, arrastradas, obtenidas. No deja activar si falta algún punto de inicio o de fin (R16) y avisa de rutas sin estándar. | `cl_plans` |
| **Muestras** | Muestras con sus lecturas de inicio y de fin; marca de posible envío mal encaminado. | `cl_samples` |
| **Puntos de lectura** | El maestro de lectores filtrado a los del carrier: alta de cada lugar/modo en un centro postal y su papel (inicio, fin, ambos, intermedio). Lugares recibidos sin dar de alta. | `cl_reading_points` |
| **Conectores** | Conector de cada carrier, equivalencias de campos y valores, campos adicionales permitidos, clave de API (se muestra una vez), lote de prueba. | `cl_connectors` |
| **Monitor de capturas** | Demandas, lotes, rechazos, alertas; deshacer un lote. | `cl_monitor` |

| Rol | Planes | Muestras | Puntos | Conectores | Monitor |
|---|---|---|---|---|---|
| Account Manager / UPU Account Manager | Edit | View | Edit | Edit | Edit |
| Allocation Plan Manager | Edit | View | View | — | View |
| DO Coordinator | View | View | Edit | — | View |
| Panelist Manager / Materials Supplier | — | — | — | — | — |

En **SLA E2E** (pantalla actual de estándares de entrega): dos campos nuevos por ruta, tiempo de primer tramo y de último tramo para lecturas del carrier.

Todo texto nuevo pasa por `useTranslation()` en todos los idiomas de la app; la sección lleva su página de ayuda.

## 8. Limitaciones y riesgos

| Punto | Tratamiento |
|---|---|
| **Entregas cerradas** (R4): lo no entregado no entra; el indicador puede salir algo mejor. | Nota metodológica; la población informa del volumen. |
| **Lectura a lectura ≠ buzón a buzón.** | Tiempo de equivalencia (D9), origen visible y nota al mezclar. El tiempo añadido es una estimación que fija la cuenta: se guarda aparte del dato medido. |
| **El carrier podría filtrar candidatos.** | Población y método obligatorios, semilla fijada antes del lote, alertas de plausibilidad. La población declarada no se puede verificar desde fuera: se dice con claridad al regulador. |
| **Hueco de lectura** en un centro. | Tramo incompleto en diagnóstico, como hoy con un lector caído. |
| **Lectores de tipo Mixed** en diagnóstico: el pipeline los parte por tiempo entre lecturas. | Los puntos del carrier se dan de alta como Entry o Exit. |
| **Vistas `v_reporting_*`**: clasifican por nodo y dejarían las muestras del carrier sin clasificar. | Ninguna pantalla las usa hoy; quedan fuera de alcance y anotadas. |
| **Reinicio de cuentas de prueba** (`admin_reset_*`): no conocen las tablas `cl_*`. | Se amplían en la fase 0. |
| **Romper lo actual.** | Ninguna tabla de panelistas cambia; en las compartidas solo columnas con valor por defecto. Validar en el Postgres local antes de aplicar. |

## 9. Fases

| Fase | Entregable | Qué permite |
|---|---|---|
| **Previa** | Proteger las claves de la API E2E (hash, convivencia y re-emisión de las 6 actuales). Comprobar que la API E2E en servicio funciona. | Independiente; necesaria antes de dar una clave a un carrier. |
| **0. Base** | Campos nuevos en maestros (§3.2), tablas `cl_*`, opciones de acceso en todas las cuentas, reinicios de prueba ampliados. Sin menú visible. Validado en local. | El modelo existe sin efecto para nadie. |
| **1. Motor E2E** | Entrada con equivalencias, validación, sorteo, cuotas y arrastre, paso a `one_db` con tiempo de equivalencia, alertas, deshacer lote, emisión de demandas. Columna y filtro de origen en los informes E2E. Prueba completa en DEMO2 con un lote inventado. | Un plan se alimenta de principio a fin y sus muestras se ven, separables, en los informes E2E. |
| **2. Pantallas** | Sección Carrier Link (5 pantallas), campos de equivalencia en SLA E2E, tipo de captura en lectores y centros, traducciones, ayuda, subida manual de un lote. | Un gestor crea y sigue un plan sin ayuda técnica. |
| **3. Primer conector real** | Conector del primer carrier, certificado con lotes de prueba. | Datos reales. |
| **4. Diagnóstico** (cuando un carrier lo necesite) | Petición de todas las lecturas, entrada en `rfid_events_raw`, origen de la lectura en las pantallas de diagnóstico. | Las muestras del carrier aparecen en el diagnóstico actual. |

Cada fase se despliega a `onems-dev` con confirmación explícita.

## 10. Lo que queda al constructor

- Algoritmo exacto del barajado determinista y orden de `item_id` (byte a byte), documentados para un auditor.
- Cómo aplica el tiempo de equivalencia según la unidad del estándar (horas o días) sin alterar el cálculo de las muestras de panelista.
- Comprobar que `recalculate_on_time_delivery_on_sla_change` recalcula también las muestras del carrier, incluido el tiempo de equivalencia.
- Límites concretos de tamaño de lote y de peticiones; reparto del trabajo entre Edge Function y base para no pasar de 2 minutos.
- Frontend: opciones nuevas en `src/lib/access.ts`, `accessAdmin.ts`, menú lateral y rutas protegidas.
- (Fase 4) Cruce de `consolidate_rfid_events` por cuenta + etiqueta sin carrier (D7): resolver las posibles coincidencias de identificador antes de activar el diagnóstico; borrado de lectores con muestras asociadas (`processed_events` lo restringe).
- Diseño visual siguiendo los componentes existentes.

## 11. Pendiente del responsable

- Primer carrier y cómo entregaría los datos (decide la fase 3).
- Qué significa el origen **RFID** en E2E; hasta entonces no existe ese valor.
- Si un envío mal encaminado debe compensarse con otra muestra (R15: "ya veremos").
