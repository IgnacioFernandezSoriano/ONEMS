# Carrier Link — consulta de extracción servida por la API (`GET /query`)

Fecha: 2026-11-25 · Estado: borrador para aprobación · Rama: `feat/cl-consulta-carrier`

## Por qué

El carrier tiene que extraer de su base **solo** los envíos completos del periodo (productos del plan, puntos
acordados), y hoy solo tiene una SQL "ilustrativa" en el manual (§5.2) que debe adaptar a mano. Ahí se equivoca o
manda de más (volumen). El carrier **no accede a ONEMS**: tiene que poder obtener la consulta él solo, sin que
nadie de ONEMS intervenga, y siempre al día con su configuración.

## Objetivos

- Nueva llamada de la API del conector, con la misma clave que `GET /config`: **`GET /query?db=postgresql|oracle|sqlserver`**
  (por defecto `postgresql`).
- Devuelve la consulta **ya rellenada** con su configuración vigente (la misma fuente que `GET /config`:
  `cl_connector_config`): nombres de campo del carrier, campos extra, códigos de producto del plan, puntos acordados
  con su papel, zona horaria de fechas, `include_all_scans` y el periodo de `next_period`.
- Incluye la consulta de **totales de control**.
- El carrier solo adapta **el nombre de su tabla** de lecturas (marcador `carrier_scans`, avisado arriba).
- Misma regla de "envío completo" que el manual §5.1 y que el simulador (`complete_shipments`).

## No objetivos

- Sin rutas (decisión de Ignacio: evitar problemas de maestros entre ambos lados).
- Sin botón en ONEMS por ahora (opcional, más adelante).
- No cambia qué se envía: siguen siendo todos los envíos completos del periodo (R24, anti-sesgo). No hay muestreo.
- ONEMS no se conecta a la base del carrier; nada de inyección de datos.
- Sin compresión ni cambios de formato.

## Enfoques considerados

- **Botón en Conectores que descarga el `.sql`** — descartado: el carrier no entra en ONEMS; obligaría a enviarle el
  fichero a mano y a reenviarlo en cada cambio de configuración.
- **Endpoint `GET /query` en la API del conector** — elegido: autoservicio, siempre al día, automatizable por su
  programa conector.

## Diseño

- **Dónde:** Edge Function `carrier-link-ingest` (nueva ruta `query`, misma autenticación, límite de peticiones y
  estado del conector que `config`). Sin cambios en la base de datos: lee `cl_connector_config` y construye el texto
  con una función pura `buildCarrierQuery(config, db)` con tests.
- **Respuesta:** JSON `{ db, tested, period_start, period_end, table_placeholder, sql }`. `tested` es `true` solo
  para `postgresql`; Oracle y SQL Server salen con `tested: false` y un aviso "SIN PROBAR" en la cabecera del SQL
  (decisión de Ignacio: no instalar Oracle/SQL Server aquí).
- **Forma común a los tres dialectos:** última llegada con `ROW_NUMBER()` (no `DISTINCT ON`); productos y puntos
  como listas de valores dentro de la consulta; periodo como dos parámetros al principio, rellenos con
  `next_period` (si no hay periodo pendiente, quedan como marcadores con un comentario).
- **Diferencias por dialecto:** comillas de identificadores (`"x"` / `[x]`), escape de literales, sintaxis de los
  parámetros y conversión a la zona horaria de fechas (PostgreSQL `AT TIME ZONE`; Oracle `FROM_TZ … AT TIME ZONE`;
  SQL Server `AT TIME ZONE` con nombres de zona de Windows → tabla IANA→Windows incluida; zona no reconocida → marcador
  y comentario). La zona de origen de las horas sale del mapeo de `scan_at` (UTC si no hay).
- **Supuesto explícito en la cabecera:** la columna de hora es de tipo fecha/hora nativo; si es texto, el carrier
  debe convertirla.
- **Errores:** mapeo de campos incompleto → mismo error que ya usa la API para ese caso; `db` desconocido →
  `400 CL_BAD_REQUEST`.
- **Documentación:** manual de conexión (§5.2 apunta a `GET /query`; requisito nuevo "DEBERÍA usar `GET /query`"),
  `openapi.yaml` y guía de usuario (una línea).

## Verificación

- Tests unitarios del constructor (los tres dialectos, escapes, sin periodo, `include_all_scans`).
- **PostgreSQL de verdad:** ejecutar la SQL generada en el Postgres local (`127.0.0.1:5433`) contra los datos del
  simulador y comprobar que saca **exactamente** los mismos envíos y lecturas que `complete_shipments` del simulador.
- Desplegar la Edge Function en onems-dev (`sehbnpgzqljrsqimwyuz`) **con confirmación previa** y llamar a
  `GET /query` con la clave del conector de DEMO2.

## Queda al criterio del constructor

Nombres internos, orden exacto de las CTE, texto de los comentarios del SQL y la lista concreta de zonas IANA→Windows
(como mínimo las de las cuentas existentes).
