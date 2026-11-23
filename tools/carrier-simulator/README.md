# Carrier simulado (Carrier Link v4)

Herramienta para probar **toda** la integración de Carrier Link sin un carrier real. Sigue el contrato v4: en cada
periodo de entrega el carrier manda **todos** los envíos completos del periodo y ONEMS hace el sorteo
(especificación: [`docs/carrier-link/manual-conexion.es.md`](../../docs/carrier-link/manual-conexion.es.md)).

Tiene dos piezas:

1. **Generador de datos** (`sim.py generate`): crea la "base de datos" de un carrier ficticio, **SIMPOST**, con
   envíos y sus escaneos (admisión, expedición, centro de tratamiento, reparto y entrega), con la hora local y los
   nombres de campo del propio carrier. Incluye a propósito envíos que nunca se entregan, mal encaminados y
   registros defectuosos.
2. **Conector de referencia** (`sim.py deliver`): hace lo que tendrá que hacer el equipo técnico de un carrier, para
   cada periodo pendiente y en orden: `GET /config` → fichero con todos los envíos completos de `next_period` (JSON
   Lines o CSV), sha256, tamaño y totales de control → `POST /deliveries` → `PUT` del fichero a la URL firmada →
   `POST /deliveries/{id}/complete` → consulta `GET /deliveries/{id}` hasta `processed` o `rejected`. Muestra y
   guarda cada petición y respuesta.

Solo usa la librería estándar de Python 3 (no instala nada). Se ejecuta siempre con `python -I`.

## Estructura

| Ruta | Qué es |
|---|---|
| `sim.py` | Programa principal (subcomandos `generate`, `keygen`, `deliver`, `build`, `call`, `status`). |
| `carrier_sim/dataset.py` | Generador de la base de datos del carrier (con semilla: mismo resultado siempre). |
| `carrier_sim/connector.py` | Lógica del conector: definición de «envío completo», filas, ruido, fichero, sha256, totales de control. |
| `carrier_sim/transport.py` | Cómo habla con ONEMS: modo `local` (Postgres local) y modo `dev` (HTTP). |
| `carrier_sim/contract.py` | Copia en Python de `supabase/functions/carrier-link-ingest/lib.ts` (rutas, límites, validación, tabla de errores). Una prueba lee `lib.ts` y falla si se desincronizan. |
| `network.json` | La red del carrier: ciudades, oficinas, centros, servicios, tiempos y porcentaje de cada anomalía. |
| `config.example.json` | Ejemplo de configuración del conector. |
| `tests/test_simulator.py` | Pruebas unitarias (sin base de datos). |
| `tests/test_docs.py` | Comprueba los esquemas JSON, el OpenAPI y el ejemplo de `docs/carrier-link/`. |
| `e2e/` | Prueba de principio a fin contra el Postgres local (`run.sh`, `fixture.sql`, `check.py`, `local_worker.ts`). |
| `examples/` | Ejemplo completo (configuración, ficheros, peticiones y respuestas); la misma copia está en `docs/carrier-link/ejemplo/`. |
| `out/` | Todo lo generado (datos, claves, ficheros, respuestas). Ignorado por git. |

## Cómo se ejecuta

Desde la raíz del repositorio (Git Bash):

```bash
# 1. Pruebas unitarias (no tocan ninguna base de datos)
python -I tools/carrier-simulator/tests/test_simulator.py
python -I tools/carrier-simulator/tests/test_docs.py

# 2. Prueba completa en local (reconstruye la base local onems_t, unos 3-4 minutos)
bash tools/carrier-simulator/e2e/run.sh
#    SAVE_EXAMPLES=1 bash tools/carrier-simulator/e2e/run.sh   -> además renueva examples/ y docs/carrier-link/ejemplo/
```

Antes, el Postgres portable tiene que estar arrancado en `127.0.0.1:5433` (`supabase/tests/run_tests.sh` indica el
comando si no lo está). La prueba completa necesita también `deno` (ejecuta el worker real en local).

Uso suelto de cada pieza (desde `tools/carrier-simulator`):

```bash
# Base de datos del carrier: admisiones del 26/10 al 15/11, "foto" tomada el 16/11 a las 03:00 (hora del carrier)
python -I sim.py generate --seed sim-2026 --from 2026-10-26 --to 2026-11-15 --as-of 2026-11-16T03:00 --out out/dataset
# Conector: entrega todos los periodos pendientes (o como mucho N con --max)
python -I sim.py deliver --config config.example.json
python -I sim.py deliver --config config.example.json --max 1 --format csv
# Entrega con el fichero alterado (mismo tamaño, otro sha256): debe acabar rechazada CL_SHA256_MISMATCH
python -I sim.py deliver --config config.example.json --max 1 --tamper
# Sin red: el fichero de un periodo a partir de una respuesta de GET /config guardada
python -I sim.py build --config-json examples/01-get-config.json --dataset out/dataset --from 2026-11-02 --to 2026-11-04 --out out/build
# Una llamada suelta (pruebas negativas) y el estado de una entrega
python -I sim.py call --config config.example.json --method GET --path demands
python -I sim.py status --config config.example.json --delivery <delivery_id> --wait
```

## Configuración del conector

Fichero JSON (ver `config.example.json`). Las rutas relativas se leen desde la carpeta del propio fichero.

| Campo | Qué es |
|---|---|
| `mode` | `local` (Postgres local) o `dev` (Edge Function de onems-dev por HTTP). |
| `base_url` | Solo `dev`: `https://<ref>.supabase.co/functions/v1/carrier-link-ingest`. |
| `key_file` | Fichero con la clave del conector (la que ONEMS muestra una sola vez). Nunca se escribe en otro sitio. |
| `seed` | Semilla del ruido de cada fichero (qué envíos llevan lecturas de más y dónde van los registros rotos). |
| `dataset_dir` | Carpeta con `scans.csv` (la base de datos del carrier). |
| `out_dir` | Dónde se guarda cada entrega: `<inicio>_<fin>[-tampered]/`. |
| `formats` | Formatos que se alternan entre periodos (`["jsonl"]`, `["csv"]` o los dos). `--format` lo fuerza. |
| `noise` | `unagreed_scans_share`: parte de los envíos que lleva también lecturas en lugares que no son puntos acordados (ONEMS las rechaza como `unknown_reading_point`); `invalid_rows`: registros rotos por fichero (`bad_record`). `{"unagreed_scans_share": 0, "invalid_rows": 0}` = fichero limpio. |
| `pii_fields` | Opcional: más campos personales prohibidos. El conector se niega a arrancar si la configuración de ONEMS pide uno de ellos o de la lista fija (`recipient_name`, `recipient_phone`, `recipient_address`, `sender_email`…). |
| `poll_seconds`, `poll_timeout_seconds` | Solo `dev`: cada cuánto consulta el estado (mínimo 30 s, por defecto 60) y hasta cuándo. |
| `local` | Solo `local`: ruta de `psql`, conexión (`127.0.0.1`, puerto 5433, base `onems_t`) y `process_cmd` (ver abajo). |

## Qué hace el conector en cada periodo

1. Lee `GET /config`: calendario, `next_period`, nombres de campo, productos con sus códigos, puntos con su papel,
   `include_all_scans` y `extra_fields`. Si `next_period` es `null` o no es `deliverable`, termina.
2. Calcula los **envíos completos** del periodo con la definición normativa (manual, §5): producto del plan; la
   lectura de llegada **más reciente** en un punto de llegada tiene fecha local dentro del periodo; hay una lectura
   en un punto de salida **anterior** a esa llegada. Los que no llegan, los que llegan a un lugar no acordado y los
   que tienen la llegada registrada antes de la salida no entran.
3. Escribe todas las lecturas de esos envíos en los puntos acordados (o todas, con `include_all_scans`), solo con
   los campos de la configuración, más el ruido configurado. CSV con cabecera y CRLF; JSON Lines con LF.
4. Calcula sha256, tamaño y totales de control (envíos por lugar y modo de la llegada y producto del envío).
5. Abre la entrega, sube el fichero en un PUT (sin clave), completa y consulta el estado hasta el final.

En `out_dir/<inicio>_<fin>/` quedan `01-get-config.json`, `delivery.jsonl|csv`, `manifest.json`,
`02-open-request.json`, `03-open-response.json`, `04-upload-response.json`, `05-complete-response.json` y
`06-status.json` (cada respuesta como `{"http_status", "body"}`).

## Qué hace cada modo

**Modo `local`** (para pruebas automáticas). No hay servidor HTTP: `transport.LocalTransport` es una copia en Python
de `supabase/functions/carrier-link-ingest/handler.ts` que, contra el Postgres local, hace las mismas comprobaciones
de ruta, método y cuerpo y llama a **las mismas funciones SQL en el mismo orden**, cada una en su transacción y con
el rol `service_role`: `api_key_resolve` → `cl_connector_config` | `cl_delivery_open` | `cl_delivery_complete` |
`cl_delivery_status`. Los errores `CL_*` se convierten en el mismo código HTTP que daría la Edge Function.
Lo que se sustituye (documentado):

- **Almacén de ficheros**: la URL de subida es `local://cl-deliveries/<ruta>`; el "PUT" guarda el fichero en
  `out_dir/storage/<ruta>` y registra el objeto en `storage.objects` (con su tamaño), como hace Supabase Storage. Un
  segundo PUT de la misma ruta responde `409` (sin sobrescribir).
- **Proceso en segundo plano** (pg_cron + Edge Function `carrier-link-worker`): antes de cada consulta de estado se
  ejecuta `local.process_cmd`, normalmente `deno run ... e2e/local_worker.ts`, que usa el **cargador real del
  worker** (`supabase/functions/carrier-link-worker/loader.ts`) contra la base local y después
  `CALL public.cl_delivery_process_run()`. Necesita la función de prueba `public.zz_sim_call` que crea
  `e2e/fixture.sql` (solo en la base local).
- No se imitan el límite de peticiones por minuto ni el registro de uso de la clave.

Solo acepta un Postgres en `127.0.0.1`/`localhost`.

**Modo `dev`** (contra onems-dev, `sehbnpgzqljrsqimwyuz`). Llama por HTTP a la Edge Function `carrier-link-ingest`
con la cabecera `x-api-key` y sube el fichero con un PUT a la URL firmada (sin la clave). **Está construido pero no
se ha ejecutado.** Necesita las migraciones de Carrier Link v4 y las Edge Functions desplegadas, una clave de
conector emitida en ONEMS y la confirmación del responsable: el programa se niega a llamar a un servidor que no sea
local si no se define antes `CONFIRM_REMOTE=<ref del proyecto>` (por ejemplo
`CONFIRM_REMOTE=sehbnpgzqljrsqimwyuz`), exige `https`, no sigue redirecciones y solo sube a una URL `https` del
mismo servidor (así la clave y el token nunca viajan a otra dirección). Recomendación: empezar siempre con el
conector en estado *Pruebas* en ONEMS (las entregas se comprueban y cuentan pero no crean muestras).

Limitación conocida: el simulador no tiene base de datos de zonas horarias (solo librería estándar en Windows), así
que exige que la zona de las horas de lectura sea la de las fechas de los periodos (`date_timezone`). Un conector
real convierte cada hora a esa zona antes de tomar su fecha.

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

`items.json` es la "verdad" de cada envío (origen, destino, anomalía). Solo la usan las pruebas; el conector no la
lee.

Red (`network.json`): ciudades Northport (NPT), Southvale (SVL), Eastmere (EMR) y Ridgefield (RDF); en cada una una
oficina (`<CIUDAD>-PO`) y un centro de tratamiento (`<CIUDAD>-MPC`), más un centro nacional (`HUB-NAT`). En ONEMS
(`e2e/fixture.sql`) solo están dadas de alta las oficinas de NPT, SVL y EMR, con dos puntos cada una: admisión `ACC`
(salida) y entrega `DLV` (llegada). RDF, los centros y el reparto `OFD` no son puntos, a propósito.

Anomalías (porcentajes en `network.json`) y qué pasa con cada una en v4:

| Anomalía | Qué pasa en el carrier | En el fichero / en ONEMS |
|---|---|---|
| `undelivered` | No llega a entregarse. | No es un envío completo: no va en el fichero. |
| `misrouted_corrected` | Se escanea como entregado en otra ciudad por error y luego se entrega en la buena. | Va en el periodo de la última entrega; ruta correcta. |
| `misrouted_lost` | Se entrega en otra ciudad. | Si esa ciudad es punto acordado, cuenta para esa otra ruta; si es RDF, no es completo. |
| `clock_error` | El reloj del lector de entrega está mal: la entrega es anterior a la admisión. | No es completo (la salida no es anterior a la llegada): no va. |
| `bad_service` | La lectura de entrega trae un código de servicio corrupto (`XX9`). | Va (su producto es `STD`); ONEMS rechaza esa lectura y el envío (`unknown_product`) y avisa. |
| `bad_timestamp` | Una lectura duplicada de admisión con la fecha ilegible. | Va; esa lectura se rechaza `bad_timestamp`, el envío sigue siendo válido. |
| `missing_site` | El escaneo de reparto no tiene lugar. | Solo va si se piden todas las lecturas (`include_all_scans`). |

## La prueba de principio a fin (`e2e/run.sh`)

1. Reconstruye la base local `onems_t` (baseline + migraciones) con `.superpowers/sdd/runlocal.sh`.
2. Genera los datos (semilla fija `e2e-2026`), crea una clave de conector (en la base solo queda su huella) y carga
   `fixture.sql`: cuenta SIMLAND, carrier SIMPOST (con correo de avisos), puntos, conector activo con calendario
   **lunes y jueves a las 03:00** y sus equivalencias, estándares de entrega y un plan del 2 al 15 de noviembre con
   cuotas de las semanas 2026-W45 y W46 para las 6 rutas (28 muestras).
3. Primer periodo con el fichero **alterado** (`--tamper`) → `rejected` `CL_SHA256_MISMATCH`, incidencia *Entrega
   rechazada* con aviso a la cuenta y al carrier (`check.py tampered`).
4. El conector entrega los 4 periodos en orden (JSON Lines y CSV alternos) y `check.py deliveries` comprueba cada
   uno contra la verdad y la base: estado `processed`; `rows_total` = registros del fichero; `shipments_total` =
   envíos enviados = suma de los totales de control (guardados tal cual); motivos de rechazo explicados por el ruido
   y las anomalías (y en el número exacto); ningún envío repetido entre periodos ni sin entregar; sorteados =
   muestras = filas de `one_db`; nunca más que la cuota ni que la población; zona de recepción vacía; las dos semanas
   cumplidas (28/28); la incidencia del paso 3 cerrada sola.
5. Respuestas de la API: repetir la apertura del primer periodo (`200`, `existing`), el mismo periodo con otro
   fichero (`409`), un periodo fuera del calendario (`422`), otro sin plan (`422`), una entrega inexistente (`404`),
   la ruta v3 `/demands` (`410`).

## Ejemplo para el manual (`examples/` y `docs/carrier-link/ejemplo/`)

Salida real de la prueba local con `SAVE_EXAMPLES=1`. Cada respuesta es `{"http_status", "body"}` con `body`
exactamente lo que devuelve la API. Los `delivery_id` y las horas cambian en cada ejecución; los ficheros, sha256 y
recuentos no. La lista de ficheros y su explicación está en el manual, §17.
