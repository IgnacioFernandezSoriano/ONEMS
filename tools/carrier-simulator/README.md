# Carrier simulado (Carrier Link)

Herramienta para probar **toda** la integración de Carrier Link sin un carrier real. Tiene dos piezas:

1. **Generador de datos** (`sim.py generate`): crea la "base de datos" de un carrier ficticio, **SIMPOST**, con
   envíos y sus escaneos (admisión, expedición, centro de tratamiento, reparto y entrega), con la hora local y los
   nombres de campo del propio carrier. Incluye envíos que nunca se entregan, mal encaminados y algunos registros
   defectuosos, a propósito.
2. **Conector de referencia** (`sim.py run`): hace lo que tendrá que hacer el equipo técnico de un carrier: lee las
   demandas abiertas de ONEMS, elige al azar los envíos de cada estrato, arma los lotes, los envía (también en modo
   de prueba, `dry_run`) y muestra y guarda las respuestas.

Solo usa la librería estándar de Python 3 (no instala nada). Se ejecuta siempre con `python -I`.

## Estructura

| Ruta | Qué es |
|---|---|
| `sim.py` | Programa principal (subcomandos `generate`, `keygen`, `run`, `post`). |
| `carrier_sim/dataset.py` | Generador de la base de datos del carrier (con semilla: mismo resultado siempre). |
| `carrier_sim/connector.py` | Lógica del conector: población, sorteo, filas y reparto en lotes. |
| `carrier_sim/transport.py` | Cómo habla con ONEMS: modo `local` (Postgres local) y modo `dev` (HTTP). |
| `carrier_sim/contract.py` | Copia en Python de los límites y comprobaciones de `supabase/functions/carrier-link-ingest/lib.ts`. |
| `network.json` | La red del carrier: ciudades, oficinas, centros, servicios, tiempos y porcentaje de cada anomalía. |
| `config.example.json` | Ejemplo de configuración del conector. |
| `tests/test_simulator.py` | Pruebas unitarias (sin base de datos). |
| `e2e/` | Prueba de principio a fin contra el Postgres local (`run.sh`, `fixture.sql`, `check.py`). |
| `examples/` | Ejemplo completo (demanda, lote y respuestas) que reutiliza el manual de conexión. |
| `out/` | Todo lo generado (datos, claves, lotes, respuestas). Ignorado por git. |

## Cómo se ejecuta

Desde la raíz del repositorio (Git Bash):

```bash
# 1. Pruebas unitarias (no tocan ninguna base de datos)
python -I tools/carrier-simulator/tests/test_simulator.py

# 2. Prueba completa en local (reconstruye la base local onems_t, ~1-2 minutos)
bash tools/carrier-simulator/e2e/run.sh
#    SAVE_EXAMPLES=1 bash tools/carrier-simulator/e2e/run.sh   -> además renueva examples/
```

Antes, el Postgres portable tiene que estar arrancado en `127.0.0.1:5433`
(`supabase/tests/run_tests.sh` indica el comando si no lo está).

Uso suelto de cada pieza:

```bash
cd tools/carrier-simulator
# Base de datos del carrier: admisiones del 26/10 al 15/11, "foto" tomada el 19/11 a las 06:00 (hora del carrier)
python -I sim.py generate --seed sim-2026 --from 2026-10-26 --to 2026-11-15 --as-of 2026-11-19T06:00 --out out/dataset
# Conector: lee las demandas y manda los lotes en modo prueba (dry_run) o de verdad (--real)
python -I sim.py run --config out/config.json --dry-run
python -I sim.py run --config out/config.json --real
# Reenviar un lote ya guardado (por ejemplo para ver que repetir el mismo batch_id no carga dos veces)
python -I sim.py post --config out/config.json --real --file out/runs/<demand_id>/batch-01.json
```

## Configuración del conector

Fichero JSON (ver `config.example.json`). Las rutas relativas se leen desde la carpeta del propio fichero.

| Campo | Qué es |
|---|---|
| `mode` | `local` (Postgres local) o `dev` (Edge Function de onems-dev por HTTP). |
| `base_url` | Solo `dev`: `https://<ref>.supabase.co/functions/v1/carrier-link-ingest`. |
| `key_file` | Fichero con la clave del conector (la que ONEMS muestra una sola vez). Nunca se escribe en otro sitio. |
| `seed` | Semilla del sorteo del conector. Misma semilla y misma demanda = mismos envíos y mismos `batch_id`. |
| `dataset_dir` | Carpeta con `scans.csv` (la base de datos del carrier). |
| `out_dir` | Dónde se guardan demandas, lotes, respuestas y el manifiesto de cada ejecución. |
| `dry_run` | `true` = solo valida, no guarda nada en ONEMS. Se puede forzar con `--dry-run` o `--real`. |
| `max_rows` | Máximo de filas por lote (como mucho 5.000, el límite de ONEMS). Con un valor bajo salen varios lotes. |
| `output_fields` | Campos que se envían de cada lectura. Por defecto, sin datos personales. |
| `local` | Solo `local`: ruta de `psql` y conexión (`127.0.0.1`, puerto 5433, base `onems_t`). |

## Qué hace cada modo

**Modo `local`** (para pruebas automáticas). No hay servidor HTTP: el conector llama, contra el Postgres local, a
las **mismas funciones SQL que la Edge Function y en el mismo orden**, cada una en su propia transacción:
`api_key_resolve` (la clave da el conector) → demandas abiertas de ese conector (`GET /demands`) → para cada lote:
comprobaciones del sobre (tamaño, filas, campos obligatorios), estado del conector (pausado / en pruebas),
`cl_ingest_batch`, y si el lote es real y queda `validated`: `cl_sample_stratum` por cada estrato del resumen y
`cl_finish_batch`. Los errores `CL_*` de la base se convierten en el mismo código HTTP que daría la Edge Function.
Lo único que no se imita es el límite de peticiones por minuto y el registro de uso de la clave.
Solo acepta un Postgres en `127.0.0.1`/`localhost`.

**Modo `dev`** (contra onems-dev, `sehbnpgzqljrsqimwyuz`). Llama por HTTP a la Edge Function `carrier-link-ingest`
con la cabecera `x-api-key`: `GET .../demands` y `POST .../batches` (con `?dry_run=true` en modo prueba).
**Está construido pero no se ha ejecutado.** Necesita una clave de conector emitida en ONEMS y la confirmación del
responsable: el programa se niega a llamar a un servidor que no sea local si no se define antes
`CONFIRM_REMOTE=<ref del proyecto>` (por ejemplo `CONFIRM_REMOTE=sehbnpgzqljrsqimwyuz`). Recomendación: empezar
siempre con `dry_run: true` y el conector en estado *testing* en ONEMS.

## La base de datos del carrier (`out/dataset/`)

`scans.csv`: una fila por escaneo, con los nombres del carrier:

| Campo | Ejemplo | Equivalencia en ONEMS |
|---|---|---|
| `tracking_no` | `SP004396827SL` | `item_id` |
| `event_ts` | `10/11/2026 09:05:07` (hora local, sin zona) | `scan_at`, formato `DD/MM/YYYY HH24:MI:SS`, zona `Africa/Nairobi` |
| `site_code` | `NPT-PO` | `place_ref` |
| `event_code` | `ACC`, `DSP`, `ARR`, `OFD`, `DLV` | `mode_ref` |
| `service` | `STD`, `EXP`, `REG` | `product` (`STD` → `SIM-STD`, `EXP` → `SIM-EXP`; `REG` no existe en ONEMS) |
| `weight_g` | `1425` | campo adicional permitido |
| `recipient_name`, `recipient_phone` | | datos personales: están en la base del carrier, el conector **no** los envía |

`items.json` es la "verdad" de cada envío (origen, destino, anomalía). Solo la usan las pruebas; el conector no la lee.

Red (`network.json`): ciudades Northport (NPT), Southvale (SVL), Eastmere (EMR) y Ridgefield (RDF); en cada una una
oficina (`<CIUDAD>-PO`) y un centro de tratamiento (`<CIUDAD>-MPC`), más un centro nacional (`HUB-NAT`). En ONEMS
(`e2e/fixture.sql`) solo están dadas de alta las oficinas de NPT, SVL y EMR, con dos puntos de lectura cada una:
admisión `ACC` (inicio) y entrega `DLV` (fin). RDF, los centros y el reparto `OFD` no son puntos, a propósito.

Anomalías que genera (porcentajes en `network.json`):

| Anomalía | Qué pasa en el carrier | Qué hace ONEMS con ella |
|---|---|---|
| `undelivered` | No llega a entregarse. | No es un envío cerrado: el conector no lo cuenta (R23). |
| `misrouted_corrected` | Va a otra ciudad, se escanea como entregado allí por error y luego se entrega en la buena. | Muestra válida; si sale elegida, `possible_misrouting`. |
| `misrouted_lost` | Se entrega en otra ciudad. | Cuenta para la ruta real (otra ciudad de destino). |
| `clock_error` | El reloj del lector de entrega está mal: la entrega es anterior a la admisión. | Candidato rechazado `start_after_end`. |
| `bad_service` | La lectura de entrega trae un código de servicio corrupto (`XX9`). | Candidato rechazado `unknown_product` (y esa lectura). |
| `bad_timestamp` | Una lectura duplicada de admisión con la fecha ilegible. | Esa lectura se rechaza `bad_timestamp`; el envío sigue siendo válido. |
| `missing_site` | El escaneo de reparto no tiene lugar. | Solo llega si se piden todas las lecturas (`include_all_scans`). |

## Qué hace el conector con cada demanda

Por cada estrato de la demanda:

1. **Población**: envíos del producto pedido (el servicio de su primera lectura legible está en `products`) con una
   lectura en algún punto de inicio y otra en algún punto de fin **cuya fecha local cae dentro del periodo**.
   Solo cuentan las lecturas con hora legible. Un punto sin modo (`mode_ref` vacío) vale para cualquier evento de ese lugar.
2. **Sorteo**: elige al azar, con la misma probabilidad para todos, `candidates_requested` envíos de la población
   (o todos si hay menos). El sorteo depende de la semilla, la demanda y el estrato: es repetible.
3. **Filas**: devuelve **todas** las lecturas de los elegidos en los puntos de inicio o de fin de **cualquier**
   estrato de la demanda (de cualquier ciudad), o todas sus lecturas si la demanda trae `include_all_scans: true`.
   Solo los campos de `output_fields`.
4. **Lote**: `population_size`, `selection_method: "uniform_random_within_stratum"` y las filas.

Los estratos se meten enteros en lotes de como mucho `max_rows` filas (y 5 MB). Un estrato nunca se parte en dos
lotes: ONEMS acepta cada estrato una sola vez por demanda. El `batch_id` es
`SIM-<8 primeros de la demanda>-<huella de la semilla>-<nº>`: reintentar el mismo lote devuelve el resultado guardado.

En `out_dir/<demand_id>/` quedan `demand.json`, `batch-NN.json`, `response-NN[.dry_run].json` y
`manifest[.dry_run].json` (población, candidatos y lote de cada estrato).

## La prueba de principio a fin (`e2e/run.sh`)

1. Reconstruye la base local `onems_t` (baseline + migraciones) con `.superpowers/sdd/runlocal.sh`.
2. Genera los datos (semilla fija `e2e-2026`), crea una clave de conector (en la base solo queda su huella) y carga
   `fixture.sql`: cuenta SIMLAND, carrier SIMPOST (captura `both`), puntos, conector activo con sus equivalencias,
   estándares de entrega y un plan con cuotas de las semanas 2026-W45 y W46 para las 6 rutas (28 muestras).
3. Emite la demanda (`cl_emit_due_demands` a las 06:05 del 19/11).
4. Conector en prueba (`dry_run`, 100 filas por lote → 4 lotes) y `check.py dry`.
5. Los mismos lotes de verdad y `check.py real`: muestras, filas en `one_db`, demanda `fulfilled`, sin alertas inesperadas.
6. Repite el lote 01: devuelve el mismo resumen y no sortea otra vez.
7. Un lote nuevo para la demanda ya cumplida: `409 CL_DEMAND_NOT_OPEN`.

`check.py` compara cada respuesta con la verdad de `items.json`: los únicos rechazos permitidos son los provocados
a propósito (`start_after_end`, `unknown_product`, `bad_timestamp`, y `already_sampled` solo para un envío elegido en
dos estratos). Cualquier otro rechazo (`unknown_reading_point`, `missing_field`, `no_start`, `end_out_of_period`…)
hace fallar la prueba.

## Ejemplo para el manual (`examples/`)

Salida real de una ejecución de la prueba local (`SAVE_EXAMPLES=1`). En cada respuesta, `http_status` es el código
HTTP y `body` es exactamente lo que devuelve la API.

| Fichero | Qué es |
|---|---|
| `01-get-demands.json` | Respuesta de `GET /demands`: una demanda con 12 estratos. |
| `02-batch-01.json` | Primer lote que envía el conector (3 estratos). |
| `03-response-01-dry-run.json` | Respuesta a ese lote con `?dry_run=true` (solo validación). |
| `04-response-01.json` | Respuesta al mismo lote de verdad: validación, sorteo de cada estrato y cierre del lote. |
| `05-response-last-batch.json` | Respuesta al último lote: la demanda queda `fulfilled`. |
| `06-response-replay-batch-01.json` | Repetición del lote 01 con el mismo `batch_id`: el resumen guardado. |
| `07-response-demand-not-open.json` | Lote nuevo para una demanda ya cerrada: `409 CL_DEMAND_NOT_OPEN`. |
| `08-connector-manifest.json` | Lo que calculó el conector: población, candidatos y lote de cada estrato. |
