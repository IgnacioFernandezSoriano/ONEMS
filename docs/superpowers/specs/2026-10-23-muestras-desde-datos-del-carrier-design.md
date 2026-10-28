# Muestras desde los datos de escaneo del carrier (EDI) — Estudio y diseño

> **Fecha:** 2026-10-23
> **Proyecto:** ONEMS · Supabase `onems-dev` (`sehbnpgzqljrsqimwyuz`)
> **Estado:** diseño propuesto, pendiente de aprobación del responsable
> **Relacionados:** [ETL_RFID_PIPELINE_TECNICO.md](../../ETL/ETL_RFID_PIPELINE_TECNICO.md) · [2026-06-11-rfid-aws-ingestion-design.md](2026-06-11-rfid-aws-ingestion-design.md) · [reporting_module_design.md](../../reporting_module_design.md) · [DIRECTORIO_TABLAS.md](../../database/DIRECTORIO_TABLAS.md)

---

## 0. Resumen ejecutivo

Hoy ONEMS mide la calidad del servicio postal con **envíos de prueba** que mueven panelistas. Este estudio propone una **segunda fuente de muestras**: para los carriers que lo permitan, ONEMS se conectará periódicamente a sus datos de escaneo (eventos EDI de envíos reales, cada uno con el identificador propio del carrier), elegirá **al azar** los envíos que pide el plan y los tratará como muestras.

Lo esencial del planteamiento:

- **Para el usuario es transparente.** Un plan se crea igual; solo se indica su **fuente**: *panelistas* o *datos del carrier*. Los informes son los mismos, con un filtro nuevo para distinguir el origen del dato.
- **Un "muro" entre ONEMS y cada carrier.** Del muro hacia fuera, un conector distinto por carrier (fuera de este alcance). Del muro hacia dentro, **un único formato común** que ONEMS entiende sea cual sea el origen. Este documento define el lado interior.
- **Principio rector: representatividad estadística y aleatoriedad.** ONEMS publica la *demanda* del plan (qué estratos y cuántas muestras), el muro devuelve un *lote de candidatos* extraído al azar junto con el tamaño de la población, y ONEMS hace la elección final al azar, la registra de forma reproducible y vigila la plausibilidad de cada lote.
- **Dos destinos para la misma muestra.** **E2E** (la muestra entra en `one_db` y alimenta los informes de calidad extremo a extremo) y **diagnóstico** (los eventos de escaneo del carrier entran en la red de centros como hoy las lecturas RFID). El E2E es la prioridad; el diagnóstico va detrás y se construye sobre el pipeline RFID existente sin modificarlo.
- **Se reutiliza lo que ya existe.** `one_db` ya es el formato común interno del que beben todos los informes; el patrón de captura externa ya está resuelto en el ETL RFID (tabla de aterrizaje + estado del conector + resolutor + cron). El cambio es incremental, no una reescritura.

---

## 1. Situación actual (qué hay y qué se reutiliza)

### 1.1. Ciclo de vida de una muestra de panelista

1. El **generador de planes** (`src/lib/allocationPlanCalculator.ts`, pantalla `AllocationPlanGenerator`) reparte `total_samples` de un plan (carrier + producto + periodo) entre pares de ciudades según la matriz A-B-C y entre semanas (con estacionalidad opcional), y asigna nodos origen/destino de forma equilibrada. Resultado: `generated_allocation_plans` + `generated_allocation_plan_details` (borrador).
2. Al **aplicar** el plan se copia a `allocation_plans` + `allocation_plan_details`. **Una fila = una muestra**: `origin_node_id`, `destination_node_id`, `fecha_programada`, `week_number/month/year`, `status` (`pending → notified → sent → received`, o `cancelled`/`incident`), panelistas, `tag_id`, `sent_at`, `received_at`.
3. Cuando la fila pasa a `received`, el trigger `transfer_to_one_db()` **valida** (fechas, tag, panelistas) y la copia **aplanada** a **`one_db`**: `carrier_name`, `product_name`, `origin_city_name`, `destination_city_name`, `sent_at`, `received_at`, `total_transit_days`, `business_transit_days`, `on_time_delivery` (contra `delivery_standards`), `source_data_snapshot`.
4. **Todos los informes leen `one_db`**: vistas `v_reporting_general_performance`, `v_reporting_compliance_by_classification`, `v_reporting_by_locality`, `v_reporting_individual_tracking`, funciones `get_route_performance`, `get_carrier_comparison`, `calculate_compliance_percentage`, la Edge Function `weekly-aggregation`, y la API externa `onedb-api`.

> **Consecuencia clave:** si una muestra de carrier llega a `one_db` con los mismos campos y una columna nueva `source`, el reporting entero la entiende sin reescribirlo.

### 1.2. El molde: la captura RFID desde el proveedor externo

El ETL RFID ya resuelve "conectarse a un sistema externo cada X tiempo e integrar lo que trae":

| Pieza RFID | Papel | Equivalente propuesto para carriers |
|---|---|---|
| `rfid_ingest_state` | estado del polling por fuente (cursor, última corrida, errores, conteos) | `carrier_feeds` (estado por conector) |
| `rfid_provider_reads` | tabla de aterrizaje "tal cual", con `match_status` y motivo | `carrier_sample_candidates` (lote de candidatos en formato común) |
| `resolve_provider_reads()` | normaliza y resuelve cuenta/lector; lo que no cuadra se queda en aterrizaje con motivo | `resolve_carrier_candidates()` (valida códigos y fechas) |
| Edge Function `rfid-provider-poll` + `pg_cron` | disparo periódico, idempotente, con presupuesto por corrida | Edge Functions `carrier-samples-ingest` (push) / `carrier-sample-pull` (pull) + cron por cadencia del plan |
| `incidents` tipo `unknown_reader`/`unknown_tag` | lo que no se puede integrar se registra, no se pierde | incidencias de lote (estrato vacío, lote corto, códigos desconocidos) |

### 1.3. Lo que hoy no encaja

- `allocation_plan_details` exige **nodos** y la validación de `transfer_to_one_db()` exige **panelistas**; una muestra de carrier se queda a nivel de **ciudad** y no tiene panelistas.
- El identificador del envío es el **tag RFID**; en el carrier será **el identificador que use ese carrier** (S10 u otro formato propio). ONEMS lo trata como texto opaco.
- No existe el concepto de **origen del dato** en `one_db` ni en los filtros de reporting.

---

## 2. Objetivo, principios y alcance

### 2.1. Objetivo

Que un plan de medición pueda alimentarse de **envíos reales escaneados por el carrier**, elegidos al azar según el propio plan, y que esas muestras entren en el sistema exactamente igual que las de panelista, distinguibles en los informes.

### 2.2. Principios (en este orden de prioridad)

1. **Representatividad estadística y aleatoriedad.** Cualquier atajo técnico que comprometa la representatividad de la muestra queda descartado. La aleatoriedad final la ejecuta ONEMS y es reproducible.
2. **Un solo formato común hacia dentro.** ONEMS no sabe ni le importa cómo guarda sus datos cada carrier.
3. **Transparencia para el usuario.** Misma app, mismos informes, un selector más.
4. **Incremental y seguro para prod.** Columnas nuevas opcionales, triggers con rama por `source`, nada que altere el camino actual de los panelistas.

### 2.3. Decisiones tomadas por el responsable (esta conversación)

| # | Decisión | Detalle |
|---|---|---|
| U1 | Transparencia | El usuario no nota la diferencia; solo cambia la **forma de obtener** las muestras para determinados carriers. Cada carrier/producto tiene su plan; unos usan panelistas y otros datos del carrier. |
| U2 | El muro | Capa intermedia individual por cliente/carrier que termina en un **formato común**. Este diseño cubre **del muro hacia ONEMS**; los conectores carrier a carrier se tratarán caso a caso después. |
| U3 | Origen visible en informes | Debe poderse distinguir el origen del dato: **panelista** o **carrier**. |
| U4 | Base de muestreo | **Entregas cerradas en el periodo**: se muestrea entre los envíos entregados en el periodo. Lo no entregado es muy raro y no entra. |
| U5 | Reparto del trabajo con el muro | ONEMS publica la **demanda** del plan; el muro devuelve un **lote de candidatos** reducido (5-10× lo pedido) extraído al azar; ONEMS elige al azar sobre el lote. |
| U6 | Principio rector | La **representatividad estadística y la aleatoriedad** deben respetarse siempre. |
| U8 | Identificador del envío | **No tiene por qué ser S10.** Cada carrier tendrá su propio formato de identificador de la muestra; ONEMS no lo interpreta. |
| U9 | Orígenes del dato | El origen del dato puede ser **panelistas, carrier o RFID**: tres valores, no dos. |
| U10 | Cadencia de extracción | Se define **al generar el plan**, y solo cuando el plan se genera para este sistema de extracción (fuente carrier). No es una configuración global ni del conector. |
| U11 | Modelos de extracción | Hay que prever **cómo se organizan y definen distintos modelos de extracción** de datos de los carriers, y cómo los maneja la aplicación, aunque los conectores concretos vengan después. |
| U12 | Unidad de extracción | La extracción es **por carrier/producto**: cada demanda y cada lote corresponden a un carrier y un producto (el del plan). |
| U7 | Dos destinos | Según lo que se quiera medir, la muestra va al **E2E** o al **diagnóstico** de red. Hay que poder hacer ambas; si la de diagnóstico resulta muy complicada, se empieza por la E2E. |

### 2.4. Decisiones mías (mi criterio; revisables)

| # | Decisión | Por qué |
|---|---|---|
| C1 | La **fuente** (`panelist`/`carrier`) es una propiedad del **plan**, elegida al crearlo | Encaja con "cada carrier/producto tiene su plan" y no toca el modelo de carriers. |
| C2 | El muro entrega **códigos ya traducidos a los de ONEMS** (carrier `code`, product `code`, city `code`). Las **tablas de correspondencia** (código del carrier → código ONEMS) viven en ONEMS, las mantiene el manager y el conector las consulta por API (§5.6) | La traducción se ejecuta en el lado exterior del muro, pero la **fuente de verdad** del mapeo es una sola y editable sin tocar el conector. ONEMS valida que los códigos existan. |
| C3 | El formato común lleva **identificador del envío (texto opaco, U8), admisión, entrega, ciudad origen/destino** y, opcionalmente, la **cadena de eventos** del operador | Lo mínimo para una muestra equivalente + materia prima para el diagnóstico de red en el futuro. |
| C4 | El muro informa la **población total** de cada estrato | Sin ella no hay representatividad verificable, ni ponderación, ni detección de filtrado (U6). |
| C5 | ONEMS **registra la extracción** (semilla, población, tamaño de lote, elegidos) | Reproducible ante un auditor o ante el propio carrier. |
| C6 | **Controles de plausibilidad** por lote, que generan **incidencias** al manager en vez de descartar en silencio | Un lote filtrado por el carrier debe hacerse visible, no desaparecer. |
| C7 | La cadencia de captura (U10) lleva además un **plazo de cierre** del periodo (`close_lag_days`) | Hay que dejar que las entregas del periodo se consoliden en el sistema del carrier antes de pedirlas. |
| C8 | Una muestra de carrier se guarda **como una fila más** en `allocation_plan_details` (a nivel ciudad, sin nodos ni panelistas) | Mantiene "una fila = una muestra" y el camino `received → one_db` intacto para todo lo que hay aguas abajo. |
| C9 | **Un identificador solo puede ser muestra una vez** por cuenta y carrier | Evita duplicados si dos lotes se solapan; se acota al carrier porque dos carriers podrían usar identificadores iguales (U8). |
| C10 | Transporte del formato común: **API de ONEMS** (Edge Function autenticada con `api_keys` por conector) en modo *push*, y un modo *pull* opcional | Reutiliza `api_keys`/`api_usage_log`; el push evita que ONEMS deba conocer la red de cada carrier. |
| C11 | El destino **diagnóstico** se implementa **reutilizando el pipeline RFID sin modificarlo**: cada oficina del carrier es un centro postal con dos lectores virtuales (entrada/salida), los códigos de evento EDI se traducen a entrada/salida y los eventos de las muestras elegidas se insertan en `rfid_events_raw` (§7.6) | Evaluado 2026-10-23: el pipeline solo necesita tag + lector + hora, y ya resuelve consolidación, segmentos, trayectos y SLAs. La complejidad está en la configuración (oficinas → centros, códigos → tipo), no en el código. Prioridad detrás del E2E (U7). |
| C17 | `source` admite desde el principio **tres valores**: `panelist`, `carrier`, `rfid` (U9). `rfid` queda **reservado** para muestras cuyas fechas de envío/recepción provengan de lecturas RFID (primera y última lectura del tag) en vez de la declaración del panelista; este diseño no implementa ese camino, solo deja el valor en el modelo, en el filtro de informes y en la API | Evita una migración y un cambio de filtros cuando se construya; hoy las lecturas RFID alimentan el diagnóstico, no `one_db`. **Es mi interpretación de U9**: si el responsable entiende otra cosa por "origen RFID", se corrige aquí. |
| C18 | Se separan tres conceptos: **modelo de extracción** (catálogo: *cómo* se extrae, p. ej. "pull API REST", "fichero por SFTP"), **conector** (instancia de un modelo para un carrier de una cuenta, con su configuración) y **mapeos** (correspondencias de códigos del carrier). Catálogo gestionado por superadmin; conectores y mapeos por la cuenta | Permite añadir una forma nueva de extraer sin tocar el esquema, y reutilizar un mismo modelo para varios carriers (§5.5). |
| C19 | Los conectores se implementan preferentemente como **workflows n8n a partir de una plantilla**, y como Edge Function o servicio externo cuando n8n no baste. Todos terminan llamando a la misma API de ONEMS con el formato común | n8n ya está en el stack, es visual y permite un workflow por carrier; la API común garantiza que ONEMS no distinga el origen. |
| C20 | Todo conector tiene un **ciclo de vida** (`draft → testing → active → paused → retired`) y un **modo de prueba** (`dry_run`) que valida un lote contra el contrato sin muestrear | Se puede certificar un conector nuevo sin contaminar datos. |
| C16 | Cada plan carrier declara sus **destinos**: `e2e` (siempre) y opcionalmente `diagnosis`. El diagnóstico usa **las mismas muestras** elegidas para el E2E, con su cadena de eventos | Una sola extracción aleatoria sirve para ambas medidas; evita dos muestreos y dos demandas al muro. |
| C12 | El **estrato temporal es siempre la semana ISO**, sea cual sea la cadencia de captura; una demanda mensual lleva varios estratos ruta × semana, cada uno con su periodo | Conserva el reparto semanal y la estacionalidad del generador (principio 1). Las celdas con cuota 0 no se emiten. |
| C13 | Las alertas de lote van a una **tabla propia** (`carrier_batch_alerts`), no a `incidents` ni a `panelist_incident` | `incidents` alimenta el contrato de monitorización externo (`monitoring.incidents_summary`/`health`) y lo distorsionaría; `panelist_incident` es el flujo del bot/panelistas. Se muestran en el monitor de capturas y en el detalle del plan. |
| C15 | `onedb-api` devuelve **ambos orígenes por defecto**, con `source` por fila y filtro opcional | El responsable confirmó que es una API genérica de extracción; nadie pierde datos sin pedirlo y el origen es siempre visible. |
| C21 | Las **API keys de los conectores se guardan hasheadas** (`pgcrypto`, SHA-256) con `name`, `scope`, `feed_id` y `expires_at`; `api_keys` hoy guarda la clave **en claro** y sin ámbito (verificado 2026-10-23 en la BD viva, §14.4) | Una clave de carrier en claro en la BD es la misma exposición que la service_role en los nodos n8n. Se migra `onedb-api` a la comparación por hash en la misma fase para no tener dos mecanismos. |
| C22 | Se activa la extensión **`pg_jsonschema`** (disponible, no instalada) para validar en la BD el `config` de cada conector contra el `config_schema` de su modelo y el **lote** contra el esquema del contrato | Una sola validación, en el sitio donde viven los datos; la Edge Function no tiene que reimplementar el contrato. |
| C23 | Los conectores **nunca se conectan a la BD**: solo a la API (Edge Functions). El modelo `db_query` se ejecuta en el lado del conector (n8n/externo) o, si el carrier expone Postgres, con `postgres_fdw`/`wrappers` desde ONEMS | El proyecto tiene **60 conexiones directas** (§14.1); un conector mal hecho podría agotarlas. |
| C14 | El código de ciudad del contrato es `cities.code`, y la fase 0 añade **UNIQUE (account_id, code)** en `cities` | Hoy `cities.code` solo es único por región, pero comprobado 2026-10-23 en la BD viva: no hay duplicados por cuenta. Así el contrato queda estable sin exigir región. |

### 2.5. Fuera de alcance (no-objetivos)

- Los conectores concretos (SFTP, API del operador, ficheros EDI EMSEVT, consulta a su base). Caso a caso, más adelante.
- Muestreo en el momento de la admisión (descartado en U4; ver §9 limitaciones).
- Modificar el pipeline RFID (`consolidate_rfid_events` y siguientes): el destino diagnóstico lo **usa**, no lo cambia (C11).
- Cambiar el modelo estadístico de los informes actuales.

### 2.6. Anti-objetivos (qué sería un fracaso aunque "funcione")

- Que un carrier pueda **elegir** qué envíos nos manda sin que ONEMS lo detecte.
- Que las muestras de carrier y de panelista se **mezclen sin poder separarse**.
- Que el camino actual de panelistas **se rompa o se ralentice**.
- Que ONEMS acabe guardando **todo el tráfico** de un operador.

---

## 3. Arquitectura general

```
   ONEMS (Supabase)                                 MURO (por carrier)              CARRIER
 ┌─────────────────────────────────────────────┐   ┌─────────────────────────┐   ┌──────────────┐
 │ 1. Plan con source='carrier'                │   │                         │   │              │
 │    └─ cuotas por estrato                    │   │  Conector específico    │   │  Base EDI /  │
 │       (ruta ciudad→ciudad × periodo × prod.)│   │  (traduce códigos,      │   │  escaneos    │
 │                                             │   │   extrae al azar,       │   │  (id propio) │
 │ 2. DEMANDA  ───────────────────────────────▶│──▶│   cuenta población)     │◀─▶│              │
 │    { plan, periodo, estratos[], n_pedido }  │   │                         │   │              │
 │                                             │   └───────────┬─────────────┘   └──────────────┘
 │ 3. LOTE DE CANDIDATOS  ◀────────────────────│◀──────────────┘  (formato común, §5)
 │    carrier_sample_candidates (aterrizaje)   │
 │        │ resolve_carrier_candidates()       │
 │        ▼                                    │
 │ 4. MUESTREADOR  sample_from_candidates()    │
 │    · elige n al azar por estrato            │
 │    · registra semilla/población/lote        │
 │    · controles de plausibilidad → alertas de lote │
 │        │                                    │
 │        ▼                                    │
 │ 5. allocation_plan_details (source=carrier, │
 │    status='received', tag_id=id carrier,    │
 │    sent_at=admisión, received_at=entrega)   │
 │        │ trigger transfer_to_one_db (rama)  │
 │        ▼                                    │
 │ 6. one_db (source='carrier')  ──▶ informes  │
 │       (filtro "origen del dato")            │
 └─────────────────────────────────────────────┘
```

Las piezas 1, 4, 5 y 6 son ONEMS puro. Las 2 y 3 son el **contrato del muro** (§5). El conector es ajeno a este documento.

---

## 4. El plan con fuente "carrier"

### 4.1. Campos nuevos en el plan

En `generated_allocation_plans` y `allocation_plans`:

| Columna | Tipo | Valores / notas |
|---|---|---|
| `source` | text NOT NULL default `'panelist'` | `panelist` \| `carrier` \| `rfid` (CHECK; `rfid` reservado, C17) |
| `capture_frequency` | text | `weekly` (defecto) \| `biweekly` \| `monthly` \| `custom_days` — solo `carrier`; se fija **en el generador del plan** (U10) |
| `capture_every_days` | integer | si `custom_days` |
| `close_lag_days` | integer default 7 | días que se espera tras acabar el periodo antes de pedir sus entregas cerradas (C7) |
| `oversampling_factor` | numeric default 5 | tamaño del lote pedido = cuota × factor (U5) |
| `carrier_feed_id` | uuid | conector del muro que atiende este plan (§5.4) |
| `feed_diagnosis` | boolean default false | si además del E2E las muestras alimentan el diagnóstico de red (C16, §7.6); obliga a `include_events: true` en la demanda |

### 4.2. Qué genera el plan para `source='carrier'`

El generador reutiliza **tal cual** la matriz A-B-C y el reparto semanal, pero **se detiene en el nivel ciudad**: no asigna nodos ni panelistas. El resultado por plan es un conjunto de **cuotas**:

```
(plan_id, origin_city_id, destination_city_id, product_id, period_start, period_end, week_number, year, samples_required)
```

Se guardan en una tabla nueva `plan_sample_quotas` (una fila por estrato × periodo). A partir de ellas se construye la demanda (§5.1) y contra ellas se mide el cumplimiento del plan (pedidas / obtenidas).

> **Nota:** las muestras de panelista también podrían describirse como cuotas, pero no se tocan: el camino actual sigue igual (C8, principio 4).

### 4.3. Reparto temporal y "periodo"

El estrato temporal es **siempre la semana ISO** (C12), coherente con `week_number/year` existentes. La **cadencia de captura** (§4.1) solo decide cada cuánto se emite demanda: una demanda mensual agrupa las 4-5 semanas vencidas, cada una como estratos ruta × semana con su propio `period`. Una semana se considera **vencida** cuando han pasado `close_lag_days` desde su fin.

La "fecha" de una muestra de carrier a efectos de informes es su **fecha de admisión** (`sent_at`), igual que hoy se usa `sent_at` para agrupar en `v_reporting_general_performance`. El filtro de "entregas cerradas en el periodo" (U4) se aplica sobre la **fecha de entrega**: se piden envíos **entregados** dentro de la semana. (Ver §9.2 sobre la frontera entre periodos.)

Con planes pequeños, muchas celdas ruta × semana tendrán cuota 0 o 1: es el mismo reparto que hoy produce el generador para panelistas; las celdas a 0 simplemente no se emiten.

---

## 5. El contrato del muro: formato común

Dos mensajes JSON, versionados (`"schema_version": "1.0"`). Todo código es un código **de ONEMS** (C2). Todas las fechas en ISO-8601 con offset.

### 5.1. Mensaje de DEMANDA (ONEMS → muro)

```json
{
  "schema_version": "1.0",
  "demand_id": "7e1c…",
  "account_code": "KENYA",
  "carrier_code": "POSTA",
  "product_code": "LETTER-PRIO",
  "plan_id": "a3f0…",
  "basis": "delivered_at",
  "requested_at": "2026-11-02T03:00:00Z",
  "strata": [
    { "stratum_id": "s1", "product_code": "LETTER-PRIO",
      "origin_city_code": "NBO", "destination_city_code": "MBA",
      "period": { "start": "2026-10-19", "end": "2026-10-25", "iso_week": "2026-W43" },
      "samples_required": 6, "candidates_requested": 30 },
    { "stratum_id": "s2", "product_code": "LETTER-PRIO",
      "origin_city_code": "NBO", "destination_city_code": "MBA",
      "period": { "start": "2026-10-26", "end": "2026-11-01", "iso_week": "2026-W44" },
      "samples_required": 6, "candidates_requested": 30 }
  ],
  "rules": {
    "selection": "uniform_random_within_stratum",
    "include_events": true,
    "exclude_item_ids_already_sampled": true
  }
}
```

- Una demanda es siempre de **un carrier y un producto** (U12): los del plan. El `product_code` se repite en cada estrato por comodidad del conector, pero no puede diferir del de la cabecera.
- `basis: delivered_at`: cada estrato son los envíos **entregados** dentro de su `period` (U4). Cada estrato lleva su propio periodo (semana ISO, C12); una demanda puede cubrir varias semanas.
- `origin_city_code`/`destination_city_code` son `cities.code` de la cuenta, únicos por cuenta (C14).
- `candidates_requested = samples_required × oversampling_factor`; si la población es menor, el muro devuelve **toda** la población del estrato.
- `exclude_item_ids_already_sampled`: ONEMS adjunta (o el muro consulta) la lista de identificadores ya usados para el carrier (C9); opcional, ONEMS lo vuelve a comprobar.

### 5.2. Mensaje de LOTE DE CANDIDATOS (muro → ONEMS)

```json
{
  "schema_version": "1.0",
  "demand_id": "7e1c…",
  "batch_id": "b91d…",
  "produced_at": "2026-11-02T03:12:41Z",
  "connector": { "id": "posta-ke-edi", "version": "1.3.0", "item_id_format": "S10" },
  "strata": [
    { "stratum_id": "s1",
      "population_size": 48213,
      "selection_method": "uniform_random_within_stratum",
      "candidates": [
        { "item_id": "RR123456789KE",
          "product_code": "LETTER-PRIO",
          "origin_city_code": "NBO", "destination_city_code": "MBA",
          "accepted_at": "2026-10-20T09:14:00+03:00",
          "delivered_at": "2026-10-22T11:02:00+03:00",
          "events": [
            { "code": "EMA", "at": "2026-10-20T09:14:00+03:00", "office_code": "KENBOA", "office_city_code": "NBO" },
            { "code": "EMC", "at": "2026-10-20T18:40:00+03:00", "office_code": "KENBOC" },
            { "code": "EMI", "at": "2026-10-22T11:02:00+03:00", "office_code": "KEMBAD", "office_city_code": "MBA" }
          ],
          "extra": { "weight_g": 20, "format": "P" }
        }
      ]
    }
  ]
}
```

Reglas del lote:

| Regla | Obligatoria | Qué comprueba ONEMS |
|---|---|---|
| `population_size` por estrato | sí | si `< samples_required` → estrato insuficiente (incidencia) |
| `selection_method = uniform_random_within_stratum` | sí | cualquier otro valor → lote rechazado |
| `item_id` no vacío y **único dentro del lote** | sí | vacíos/repetidos → se descartan y se cuentan. ONEMS no interpreta el formato (U8); `connector.item_id_format` es informativo. Si el conector declara `S10`, ONEMS puede aplicar además el dígito de control como comprobación opcional |
| `accepted_at ≤ delivered_at`, `delivered_at` dentro del `period` del estrato | sí | fuera → se descartan y se cuentan |
| códigos de producto/ciudad existentes en la cuenta | sí | desconocidos → se descartan, incidencia `unknown_code` |
| `events` | no | si vienen, se guardan en JSONB para uso futuro (C3, C11) |
| `extra` | no | JSONB libre (peso, formato…), se guarda en `source_data_snapshot` |

### 5.3. Transporte (C10)

- **Push (principal):** el muro llama a una Edge Function `carrier-samples-ingest` (`POST`), desplegada con `verify_jwt = false` (como `rfid-provider-poll`) y autenticada con una **API key por conector** (`api_keys` hasheadas, C21; uso registrado en `api_usage_log`). Idempotente por `batch_id`. Responde con el resumen de aceptados/descartados. Lotes grandes: el cuerpo se guarda tal cual en el bucket privado `carrier-batches` (Storage) y la validación/aterrizaje se hace por estratos, dentro del límite de tiempo de la función (§14.3).
- **Pull (opcional):** una Edge Function `carrier-sample-pull` (cron) llama al endpoint del muro con la demanda y recibe el lote. Mismo formato. Permite carriers cuyo muro no pueda iniciar conexiones.
- La **demanda** se publica en ambos casos: como endpoint `GET …/demands?connector=…&status=open` (modo push: el muro la consulta) o como cuerpo de la llamada (modo pull).

### 5.4. Registro de conectores

Tabla `carrier_feeds` (una fila por conector, por cuenta): `id`, `account_id`, `carrier_id`, `product_ids uuid[]` (NULL = todos los productos del carrier; permite un conector distinto por producto si el carrier los sirve por canales distintos, U12), `name`, `extraction_model_id` (§5.5), `config jsonb` (parámetros no secretos, validados contra el esquema del modelo), `secret_ref` (nombre de la credencial en n8n o del secret de la Edge Function; **nunca el secreto**), `api_key_id` (clave con la que el conector llama a ONEMS), `schema_version`, `status` (`draft|testing|active|paused|retired`, C20), `last_batch_at`, `last_status`, `last_error`, `notes`, `contact`.

### 5.5. Modelos de extracción: organización para el futuro (U11)

**Tres conceptos, tres tablas** (C18):

| Concepto | Qué es | Dónde vive | Quién lo gestiona |
|---|---|---|---|
| **Modelo de extracción** | *Cómo* se extraen los datos: la técnica. Catálogo global, versionado. | `extraction_models` (`code`, `name`, `description`, `runtime` `n8n|edge_function|external|manual`, `direction` `push|pull`, `config_schema jsonb` (JSON Schema de la configuración), `template_ref` (p. ej. id del workflow plantilla en n8n), `version`, `status`) | Superadmin (ONE) |
| **Conector** | Un modelo aplicado a un carrier de una cuenta, con su configuración y credenciales. | `carrier_feeds` (§5.4) | Cuenta (admin) |
| **Mapeos** | Correspondencias código del carrier → código ONEMS. | `carrier_code_mappings` (`account_id`, `carrier_id`, `kind` `product|city|office|event_code`, `carrier_value`, `onems_value`, `valid_from`, `valid_to`, `notes`) | Cuenta (manager) |

**Catálogo inicial de modelos** (se dan de alta desde el principio como filas del catálogo; su implementación llega conector a conector):

| Código | Técnica | Caso típico | Runtime previsto |
|---|---|---|---|
| `push_api` | El muro del carrier llama a la API de ONEMS con el formato común | Carrier con equipo técnico propio; es el **modelo por defecto** (§5.3) | el del carrier |
| `pull_rest` | ONEMS (vía workflow) consulta la API del carrier, traduce y publica el lote | Carrier con API de tracking | n8n |
| `file_drop` | El carrier deja ficheros (EDI EMSEVT, CSV, XML) en SFTP/S3/correo; el workflow los lee y traduce | Carriers con intercambio EDI clásico | n8n |
| `db_query` | Consulta de solo lectura a una réplica de la base del carrier con una plantilla SQL | Operador que abre una réplica | n8n o servicio externo |
| `manual_upload` | El manager sube un CSV/Excel con el lote desde la app, que lo valida con el mismo contrato | Pilotos, carriers pequeños, contingencia | ONEMS (Edge Function) |
| `upu_gateway` | Datos vía plataformas UPU (p. ej. mensajería EMSEVT por IPS/PTC) | A futuro | externo |

**Cómo encajan con el formato común:** todos los modelos terminan en el mismo punto, `carrier-samples-ingest` (§5.3), con el mismo JSON. El modelo solo cambia **quién** hace la traducción y **cómo** se dispara. Por eso añadir un modelo nuevo es dar de alta una fila en el catálogo y una plantilla; el núcleo de ONEMS no cambia.

**Dónde corre la lógica de cada conector** (C19): la **plantilla n8n** `carrier-connector-template` tiene la estructura fija *leer demanda abierta (GET /demands) → extraer del carrier → aplicar mapeos (GET /feeds/{id}/mappings) → construir lote → POST carrier-samples-ingest (primero con `dry_run=true`, luego real) → registrar resultado*; cada carrier se clona de la plantilla y solo se toca el bloque "extraer". Cuando un carrier exige algo que n8n no cubre (volumen, protocolo, seguridad), el conector es una Edge Function o un servicio externo, pero respeta las mismas llamadas. Los conectores n8n se guardan en el repo `panelist_n8n` (o uno propio `carrier_connectors`) con las claves tapadas, como se hace ya con el bot.

**Ciclo de vida de un conector** (C20):

```
draft ──▶ testing ──▶ active ◀──▶ paused ──▶ retired
  │          │
  │          └─ solo acepta lotes con dry_run=true; se valida el contrato y los mapeos, no se muestrea
  └─ configuración incompleta; no puede recibir demandas
```

Un conector pasa a `active` cuando ha superado al menos un lote `dry_run` sin rechazos de contrato. La app guarda el informe de esa prueba.

### 5.6. API de apoyo a los conectores

Además de `carrier-samples-ingest` y `GET /demands` (§5.3):

| Llamada | Para qué |
|---|---|
| `GET /feeds/{id}/mappings?kind=…` | El conector descarga las correspondencias vigentes (C2) para traducir productos, ciudades, oficinas y códigos de evento. |
| `POST /carrier-samples-ingest?dry_run=true` | Valida el lote contra el contrato y los mapeos y devuelve el informe de rechazos **sin** aterrizar ni muestrear (C20). |
| `GET /feeds/{id}/status` | Último lote, demandas abiertas, alertas; permite al conector autodiagnosticarse. |
| `POST /feeds/{id}/heartbeat` | El conector avisa de que está vivo aunque no haya demanda; alimenta el monitor. |

Todas autenticadas con la API key del conector (`api_keys`) y limitadas a su cuenta y carrier.

---

## 6. El muestreador

### 6.1. Tablas

- `carrier_demands`: demanda emitida (`id`, `plan_id`, `feed_id`, `carrier_id`, `product_id` (U12), `period_start/end`, `status` `open → fulfilled | partial | failed`, `requested_at`, `payload jsonb`).
- `carrier_batches`: lote recibido (`id`, `demand_id`, `received_at`, `connector_version`, `raw_payload jsonb`, `status`, `summary jsonb`).
- `carrier_sample_candidates` (aterrizaje): una fila por candidato (`batch_id`, `stratum_id`, `item_id`, códigos, `accepted_at`, `delivered_at`, `events jsonb`, `extra jsonb`, `resolve_status` `pending|valid|rejected|selected|not_selected`, `reject_reason`). RLS por `account_id`.
- `carrier_sampling_runs`: auditoría de cada extracción (`demand_id`, `stratum_id`, `population_size`, `candidates_received`, `candidates_valid`, `samples_required`, `samples_selected`, `random_seed`, `algorithm` (`fisher_yates_seeded`), `selected_item_ids text[]`, `executed_at`). (C5)

### 6.2. Algoritmo, por estrato de la demanda

1. **Resolver** candidatos (`resolve_carrier_candidates(batch_id)`): validar identificador, fechas, códigos → `valid`/`rejected`.
2. Si `candidates_valid < samples_required` → tomar todos los válidos y abrir incidencia `insufficient_candidates`.
3. Si no: generar `random_seed` (o aceptar uno dado para re-ejecución), barajar con **Fisher-Yates determinista** sobre la lista de `item_id` ordenada, tomar los `samples_required` primeros. Escribir `carrier_sampling_runs`.
4. Por cada elegido, **insertar** en `allocation_plan_details`: `plan_id`, `source='carrier'`, `origin_city_id/destination_city_id`, `fecha_programada = accepted_at::date`, `week_number/month/year` (del periodo), `tag_id = item_id` (texto tal cual lo envía el carrier), `sent_at = accepted_at`, `received_at = delivered_at`, `status='received'`, `carrier_candidate_id`. El trigger existente lleva la fila a `one_db` (§7.2).
5. Marcar candidatos `selected`/`not_selected`; actualizar `plan_sample_quotas.samples_obtained`; cerrar la demanda (`fulfilled`/`partial`).

Toda la función corre en **una transacción por estrato** (no por lote completo: el `statement_timeout` del proyecto es de 2 minutos, §14.1); es idempotente por `demand_id + stratum_id` (una demanda ya muestreada no se vuelve a muestrear salvo re-ejecución explícita con la misma semilla).

> El trigger `transfer_to_one_db` se dispara hoy `AFTER UPDATE`. Como el muestreador inserta la fila ya en `received`, hará falta que el trigger también cubra `INSERT` (o que el muestreador inserte en `pending` y actualice a `received` en la misma transacción). Decisión del constructor; cualquiera de las dos vale.

### 6.3. Controles de plausibilidad (C6) → `carrier_batch_alerts`

| Control | Señal | Severidad |
|---|---|---|
| `insufficient_candidates` | válidos < pedidos | medium |
| `empty_stratum` | `population_size = 0` para una ruta con cuota | medium |
| `population_drop` | población del estrato < 30 % de la mediana de los últimos 6 periodos | low |
| `suspicious_distribution` | 100 % en plazo con n ≥ 20, o desviación típica de tránsito ≈ 0 | medium |
| `late_batch` | lote recibido pasados `close_lag_days + 7` | low |
| `unknown_code` | códigos de ciudad/producto no reconocidos | low |
| `rejected_ratio` | > 20 % de candidatos rechazados por formato/fechas | medium |

Las alertas se guardan en una tabla propia `carrier_batch_alerts` (`account_id`, `batch_id`, `demand_id`, `stratum_id`, `alert_type`, `severity`, `details jsonb`, `status` `open|acknowledged|dismissed`, `acknowledged_by/at`) con RLS por cuenta (C13). **No** se escriben en `incidents` (alimenta el contrato de monitorización externo) ni en `panelist_incident` (flujo de panelistas/bot). Se muestran en el **monitor de capturas** y como contador en el **detalle del plan** (§8). **Ninguna** descarta el lote salvo `selection_method` distinto de uniforme (§5.2).

---

## 7. Entrada en el sistema y efectos aguas abajo

### 7.1. `allocation_plan_details`

| Cambio | Detalle |
|---|---|
| `source text NOT NULL default 'panelist'` | CHECK (`panelist`,`carrier`,`rfid`) — `rfid` reservado (C17) |
| `origin_city_id`, `destination_city_id` (uuid, nullable) | se rellenan para `carrier`; para `panelist` se derivan del nodo como hoy |
| `origin_node_id`, `destination_node_id` → **nullable** | con CHECK: `source='panelist'` ⇒ nodos NOT NULL; `source='carrier'` ⇒ ciudades NOT NULL |
| `carrier_candidate_id uuid` | traza al candidato |
| UNIQUE parcial por **cuenta + carrier + `tag_id`** `WHERE source='carrier'` (el carrier se toma del plan; el constructor decide si lo desnormaliza en la fila) | C9, U8 |

Las vistas que hoy asumen nodo (`allocation_details_full`, `v_allocation_details_with_availability`, `v_node_load_analysis`) deben **excluir** `source='carrier'` o usar `COALESCE(ciudad del nodo, origin_city_id)`. El motor de reasignación, incidencias de panelista, stock de materiales y el bot de Telegram **no se ven afectados**: operan sobre filas `panelist`.

### 7.2. `transfer_to_one_db()`

Rama por `NEW.source`:
- `panelist`: comportamiento actual, sin cambios.
- `carrier`: valida solo fechas y `tag_id`; resuelve ciudades por `origin_city_id/destination_city_id`; calcula `total_transit_days`, `business_transit_days` y `on_time_delivery` **con las mismas funciones** (`calculate_business_days`, `delivery_standards`); inserta en `one_db` con `source='carrier'` y `source_data_snapshot` = fila + `events` + `extra`.

Un detalle a vigilar: la conversión de zona horaria (`AT TIME ZONE v_account_timezone`) se aplica igual; las fechas del lote traen offset, así que el cálculo es correcto.

### 7.3. `one_db`

- `source text NOT NULL default 'panelist'` con CHECK (`panelist`,`carrier`,`rfid`) + índice `(account_id, source)`.
- `items_population integer` (población del estrato; permite ponderar en el futuro) y `sampling_run_id uuid`.
- `onedb-api` expone `source` en su salida (campo nuevo, compatible) y acepta un filtro opcional `source=panelist|carrier|rfid`. **Por defecto devuelve todos los orígenes** (C15): es una API genérica de extracción sin consumidores con expectativas fijas, y cada fila lleva su `source`.
- El esquema `monitoring` (contrato con la plataforma de monitorización externa) **no lee `one_db`** ni `allocation_plan_details`, así que no se ve afectado; sí lee `incidents`, motivo de C13.

### 7.4. Informes

- Las vistas `v_reporting_*` y las funciones `get_*` incorporan `source` en el `SELECT`/`GROUP BY` o como parámetro opcional de filtro (`p_source text DEFAULT NULL` = todos).
- El **contexto de filtros** (`ReportingFiltersContext`) añade "Origen del dato: Todos / Panelistas / Carrier / RFID" (U9) y las tablas/gráficas lo muestran como columna o leyenda cuando el valor es "Todos". La opción RFID aparece aunque hoy no haya filas con ese origen.
- `weekly-aggregation` agrega también por `source`.
- Donde se mezclen ambos orígenes, el informe muestra un aviso de nota metodológica (ver §9.1), traducido a los 4 idiomas.

### 7.5. ETL RFID

Sin cambios de código. Las lecturas RFID se cruzan con `one_db.tag_id`; los identificadores del carrier no aparecerán como tags leídos por lectores físicos y no generan incidencias `unknown_tag`.

### 7.6. Destino diagnóstico (U7, C11, C16)

**Cómo funciona hoy el diagnóstico:** `rfid_events_raw` (tag, `reader_id` texto, hora) → `consolidate_rfid_events` busca el lector en `readers` (por `reader_id`) y su centro en `postal_centers`, y el envío en `one_db` (por `tag_id`) → `processed_events` (entrada/salida por centro) → `journey_segments` (operativos y de distribución, con SLA) → `journeys` → `journey_paths`. Todo corre en el cron existente.

**Qué hace falta para que entren los eventos del carrier** (todo configuración + una función de inserción; el pipeline no se toca):

| Pieza | Detalle |
|---|---|
| **Oficinas → centros** | Tabla `carrier_offices` (`account_id`, `carrier_id`, `office_code`, `postal_center_id`, `name`, `city_id`). El `office_code` es el que viene en `events[].office_code` del lote. Un `office_code` sin fila → alerta `unknown_office` y sus eventos se guardan pero no se insertan. Opción: alta automática del centro + oficina al primer evento, marcada como "pendiente de revisar". |
| **Lectores virtuales** | Por cada centro de carrier, dos filas en `readers`: `<office_code>-IN` (`type='Entry'`) y `<office_code>-OUT` (`type='Exit'`). Se crean con la oficina. |
| **Códigos de evento → tipo** | Tabla `carrier_event_codes` (`account_id`, `carrier_id` nullable = defecto, `code`, `direction` `entry|exit|ignore`). Valores por defecto según EMSEVT: `EMA` entrada (admisión), `EMB` salida, `EMC` entrada, `EMD` salida, `EME` entrada, `EMF` salida, `EMG` entrada, `EMH` ignorar (intento), `EMI` salida (entrega). Editable por cuenta/carrier. |
| **Inserción** | Función `feed_diagnosis_events(sampling_run_id)`: para cada muestra **ya transferida a `one_db`** (requisito: si no, el pipeline la marcaría `unknown_tag`), inserta en `rfid_events_raw` una fila por evento con `tag_id = item_id`, `reader_id = <office_code>-IN/-OUT` según la dirección del código, `read_local_datetime = at`, `event_id = item_id||code||at` (idempotente por la UNIQUE existente `(account_id, event_id)`), `carrier_id`, `product_id`. Se ejecuta al final de `sample_from_candidates()` si el plan tiene `feed_diagnosis = true`. |
| **Horarios de los centros virtuales** | Se crean con `calculation_mode = 'natural_days'` salvo que el usuario configure horarios; evita que el ajuste a jornada laboral invente esperas. |

**Lo que se obtiene sin más trabajo:** segmentos operativos (tiempo dentro de cada oficina), de distribución (entre oficinas), cumplimiento de SLA por tramo (`slas`/`find_applicable_sla`), trayectos y rutas agregadas, visibles en las pantallas de diagnóstico actuales. Los centros de carrier conviven con los centros RFID de la cuenta; se distinguen por `postal_centers.carrier_id` y por el prefijo de los lectores virtuales.

**Límites honestos:** la granularidad es la del escaneo del operador (una oficina sin escaneo de salida solo tendrá entrada → segmento incompleto, como ocurre hoy con un lector caído); y los eventos son solo de las muestras elegidas, no de todo el tráfico, lo cual es coherente con un sistema de medición por muestreo.

---

## 8. Pantallas

| Pantalla | Cambio |
|---|---|
| **Generador de planes** | Selector "Fuente de las muestras": *Panelistas* / *Datos del carrier*. Al elegir carrier: ocultar lo relativo a nodos/panelistas; mostrar conector (`carrier_feeds` del carrier), cadencia, plazo de cierre, factor de sobremuestreo. Vista previa = cuotas por ruta y semana. |
| **Detalle del plan (carrier)** | Tabla de cuotas: ruta, periodo, pedidas, obtenidas, población, estado de la demanda, último lote. Enlace a las muestras. |
| **Modelos de extracción** (solo superadmin) | Catálogo `extraction_models`: alta, versión, esquema de configuración, plantilla asociada. |
| **Mapeos del carrier** (manager) | Tabla editable de `carrier_code_mappings` por tipo (productos, ciudades, oficinas, códigos de evento), con importación CSV y detección de valores sin mapear a partir de las alertas `unknown_code`/`unknown_office`. |
| **Oficinas y códigos del carrier** (Admin/Configuración) | Alta de `carrier_offices` (oficina → centro postal, con creación del centro y sus dos lectores virtuales en un paso) y edición de `carrier_event_codes`. Solo si el plan tiene destino diagnóstico. |
| **Conectores del carrier** (Admin/Configuración) | Alta de `carrier_feeds` eligiendo un modelo del catálogo; formulario generado desde `config_schema`; API key (se muestra una vez); ciclo de vida (`draft → testing → active → paused → retired`) con el informe del último `dry_run`; última recepción, errores. Botones "Emitir demanda ahora", "Lote de prueba" y "Re-ejecutar muestreo (misma semilla)". |
| **Monitor de capturas** | Reutilizar el patrón de la pantalla de monitorización del ETL (`ETL_MONITORING_SCREEN_DESIGN.md`): corridas, lotes, rechazados, incidencias. |
| **Reporting** | Filtro "Origen del dato" (Panelistas / Carrier / RFID) + columna/leyenda. |
| **Alertas de lote** | Lista de `carrier_batch_alerts` dentro del monitor de capturas (reconocer / descartar) y contador en el detalle del plan. No se mezclan con el menú "Incidencias" de panelistas. |

Todo texto nuevo pasa por `useTranslation()` y se añade a `en/es/fr/ar`.

---

## 9. Riesgos, limitaciones y cómo se tratan

### 9.1. Limitaciones metodológicas (documentadas, no ocultas)

| Limitación | Efecto | Tratamiento |
|---|---|---|
| **Entregas cerradas** (U4) | Los envíos no entregados o entregados fuera del periodo no entran; el indicador puede salir algo mejor que la realidad | Decisión del responsable (es raro). Se documenta en la nota metodológica del informe y `population_size` permite estimar el volumen. Si en el futuro se quisiera, el mismo contrato admite `basis: accepted_at` con cierre diferido. |
| **Escaneo a escaneo vs. buzón a buzón** | Una muestra de carrier mide admisión→entrega (escaneos); la de panelista mide depósito→recepción. No son estrictamente comparables | Por eso U3: se separan en informes y se avisa al mezclar. No se "corrige" automáticamente. |
| **Dependencia del muro** | El carrier podría filtrar u ordenar candidatos | `population_size` obligatorio, `selection_method` obligatorio, controles de plausibilidad (§6.3), auditoría reproducible (§6.1). Nunca se elimina del todo: hay que decirlo con claridad al regulador. |
| **Calidad de los escaneos** | Un envío entregado sin escaneo de entrega no existe para el muro | Se refleja en `population_size` (menor) y en `population_drop`. |

### 9.2. Riesgos técnicos

| Riesgo | Mitigación |
|---|---|
| Frontera entre periodos: un envío admitido en la semana 43 y entregado en la 44 cuenta en la 44 | Regla explícita (`basis: delivered_at`); la agrupación de informes usa `sent_at` como hoy, así que un envío puede figurar en la semana 43 del informe aunque se muestreó en la 44. Es coherente y se documenta. |
| Códigos de ciudad: un carrier conoce oficinas, no ciudades de ONEMS | Responsabilidad del conector (C2); los desconocidos generan `unknown_code` y se ve dónde falta mapeo. |
| Volumen de `carrier_sample_candidates` | Solo llega el lote (≈5-10× la cuota). Política de retención: `not_selected` se purgan a los 90 días; `selected` se conservan. |
| Duplicados entre lotes | UNIQUE parcial por identificador dentro del carrier (C9) + idempotencia por `batch_id`. |
| Secretos | API keys **hasheadas** en `api_keys` (hoy en claro: C21); credenciales de pull en secrets de Edge Function o en **Supabase Vault** (instalado, §14.2); en n8n solo como credenciales de n8n, nunca en nodos. Nada en el repo. |
| Multi-tenant | Todas las tablas nuevas con `account_id` y RLS; la API key identifica cuenta y conector. |
| Romper el camino actual | Todas las columnas nuevas con default; trigger con rama; vistas de nodos excluyen `carrier`. Validar en el Postgres local (`supabase/tests/replay_baseline.ps1`) antes de prod. |

---

## 10. Fases de implantación

| Fase | Entregable | Qué permite |
|---|---|---|
| **0. Base** | Migración: activar `pg_jsonschema` (C22); `source` en planes/detalles/`one_db`, ciudades en detalles, nodos nullable con CHECK, UNIQUE `(account_id, code)` en `cities`, rama en `transfer_to_one_db`, tablas `extraction_models` (con el catálogo inicial de §5.5), `carrier_feeds`, `carrier_code_mappings`, `plan_sample_quotas`, `carrier_demands`, `carrier_batches`, `carrier_sample_candidates`, `carrier_sampling_runs`, `carrier_batch_alerts`. Vistas que asumen nodo filtradas a `source='panelist'`. Validada en local. | El modelo admite muestras de carrier sin tocar nada visible. |
| **1. Muestreador + API** | `api_keys` hasheadas y con ámbito + migración de `onedb-api` (C21); bucket privado `carrier-batches`; `resolve_carrier_candidates()`, `sample_from_candidates()`, Edge Function `carrier-samples-ingest` (con `dry_run`), `GET demands`, `GET mappings`, `status`/`heartbeat`; controles de plausibilidad → `carrier_batch_alerts`. Pruebas con un lote sintético en DEMO2 (modelo `manual_upload` sin pantalla, vía API). | Un muro (aunque sea un script de prueba) puede alimentar un plan de principio a fin. |
| **2. Informes** | `source` en vistas/funciones/`weekly-aggregation`/`onedb-api`; filtro "Origen del dato"; nota metodológica; i18n ×4. | U3 cumplido. |
| **2b. Destino diagnóstico** | Tablas `carrier_offices`, `carrier_event_codes` (con defectos EMSEVT), lectores virtuales, `feed_diagnosis_events()`; alerta `unknown_office`. Prueba en DEMO2 con un lote sintético con `events`. | U7 cumplido: la misma muestra alimenta el diagnóstico de red. Si durante la fase 1 aparece una complicación no prevista, esta fase pasa detrás de la 3 sin bloquear nada. |
| **3. Pantallas** | Generador con selector de fuente y cuotas; detalle del plan carrier; catálogo de modelos (superadmin); conectores con ciclo de vida; mapeos; monitor de capturas; subida manual (`manual_upload`). | Un manager crea y sigue un plan carrier sin ayuda técnica. |
| **4. Plantilla n8n + primer conector real** | Workflow plantilla `carrier-connector-template` (C19) y el primer conector clonado de ella para el primer carrier (proyecto aparte, caso a caso), certificado con `dry_run`. | Datos reales. |
| **5. Extensiones** | Ponderación por `population_size`; alta automática de oficinas desde los eventos; `basis: accepted_at` si se decide. | Fuera de este alcance. |

Cada fase se valida en el Postgres local y se despliega a `onems-dev` con confirmación explícita (regla del proyecto). El orden 0→1→2 permite probar el flujo completo con datos sintéticos antes de construir pantallas.

---

## 11. Lo que queda al constructor

- Nombres finales de columnas/tablas y la forma exacta de los CHECK y la UNIQUE parcial.
- Implementación del Fisher-Yates determinista en PL/pgSQL (o en la Edge Function) con semilla registrada; basta que sea reproducible con la misma semilla y la misma lista ordenada de `item_id`.
- Comprobación opcional del dígito de control cuando el conector declare `item_id_format: "S10"` (algoritmo UPU S10, pesos 8-6-4-2-3-5-9-7); nunca obligatoria (U8).
- Umbrales de los controles de plausibilidad (los de §6.3 son valores iniciales razonables, configurables por cuenta en `account_config`).
- Cómo disparar `transfer_to_one_db` para filas insertadas ya en `received` (§6.2).
- Diseño visual de las pantallas, siguiendo los componentes existentes.
- Decidir si `plan_sample_quotas` se materializa también para planes `panelist` (no requerido ahora).

---

## 12. Pendiente del responsable

> Nota: la numeración de secciones sigue el orden de redacción; §14 (capacidades del servidor) va antes del glosario (§13).

- Confirmar la interpretación de **origen RFID** (C17): muestras cuyas fechas salen de la primera y última lectura RFID del tag; valor reservado, no se construye en este alcance.
- (Resuelto) La duda sobre `onedb-api` se cerró en C15: API genérica de extracción sin consumidores concretos.

## 14. Capacidades del servidor Supabase para este diseño (verificado 2026-10-23, solo lectura)

Proyecto `onems-dev` (`sehbnpgzqljrsqimwyuz`), región `eu-central-2`, estado `ACTIVE_HEALTHY`.

### 14.1. Base de datos

| Dato | Valor | Qué implica para el diseño |
|---|---|---|
| Versión | PostgreSQL 17.6 (aarch64) | Todo lo propuesto (CHECK, UNIQUE parcial, JSONB, `SECURITY DEFINER`, RLS) está disponible. |
| Tamaño actual | **53 MB** en total; `allocation_plan_details` 9.748 filas, `one_db` 544 filas, `rfid_events_raw` 198 | Hay margen de sobra: un plan carrier de 2.000 muestras/año con sobremuestreo ×5 son ~10.000 candidatos/año (unos pocos MB). |
| Cómputo | `shared_buffers` 224 MB, `work_mem` ~2 MB, 2 workers paralelos, 6 procesos | Instancia **pequeña** (perfil "Micro"). Suficiente para el volumen esperado; no para procesar "todo el tráfico" de un operador, lo cual refuerza U5 (lotes reducidos). |
| Conexiones directas | **60** | Los conectores **no** deben conectarse a la BD, solo a la API (C23). El pooler cubre el frontend. |
| `statement_timeout` | **2 minutos** | El muestreador trabaja **por estrato** y la ingesta valida por estratos (§6.2, §5.3); nada debe correr como una sola sentencia de minutos. |
| Roles | `service_role` salta RLS; `monitoring_reader` solo lectura del esquema `monitoring` | Las Edge Functions usan `service_role` (como hoy); las tablas nuevas llevan RLS para el frontend. |
| Avisos del asesor (performance) | 6 avisos, ninguno bloqueante: 1 `auth_rls_initplan`, 1 `multiple_permissive_policies`, 1 `duplicate_index`, 1 FK sin índice, 1 índice sin uso | Las políticas RLS nuevas se escriben con `(select auth.uid())` y una sola política permisiva por acción, para no añadir avisos. |

### 14.2. Extensiones

| Extensión | Estado | Uso en este diseño |
|---|---|---|
| `pg_cron` 1.6.4 | **instalada**; 1 job activo (`rfid-provider-poll-every-30min`), 336 ejecuciones en 7 días, 100 % correctas | Emisión de demandas por cadencia del plan y purga de candidatos `not_selected`. |
| `pg_net` 0.19.5 | **instalada**; 12 llamadas HTTP en 7 días, 100 % correctas | Patrón cron → `net.http_post` → Edge Function ya probado; se reutiliza para `carrier-sample-pull` y para avisar a conectores n8n. |
| `pgcrypto` | **instalada** | Hash SHA-256 de las API keys (C21) y de la semilla aleatoria reproducible. |
| `supabase_vault` | **instalada** | Alternativa a los secrets de Edge Function para credenciales del modo pull. |
| `uuid-ossp`, `pg_stat_statements` | instaladas | Como hoy. |
| `pg_jsonschema` 0.3.3 | disponible, **no instalada** | **Activar en fase 0** (C22): validar `config` y lotes contra JSON Schema dentro de la BD. |
| `pgmq` 1.5.1 | disponible, no instalada | Opcional a futuro: cola para procesar lotes grandes por partes sin bloquear la ingesta. |
| `postgres_fdw`, `wrappers` 0.5.6 | disponibles, no instaladas | Opción para el modelo `db_query` si un carrier expone una réplica Postgres (C23). |
| `pgtap` | disponible, no instalada | Pruebas automáticas del muestreador (reproducibilidad de la semilla) en el Postgres local. |
| `http` (síncrona) | disponible, no instalada | No necesaria: `pg_net` cubre el caso. |

### 14.3. Edge Functions, Storage y automatización

- **7 funciones desplegadas** (8 en el repo). Dos patrones ya en producción que se reutilizan tal cual: **cron → pg_net → función con `CRON_SECRET`** (`rfid-provider-poll`, `verify_jwt = false`) y **API externa con API key en `Authorization: Bearer`** (`onedb-api`, con límite de 10 peticiones/minuto por clave).
- Límites de plataforma a respetar: tiempo máximo por invocación (del orden de minutos en plan de pago) y memoria limitada. Por eso la ingesta de un lote grande se trocea por estratos y el cuerpo crudo se archiva en Storage antes de procesar.
- **Storage:** 3 buckets (`translations`, `incident-photos`, `training-videos`). Se añade el bucket **privado** `carrier-batches` para el archivo de lotes y las subidas del modelo `manual_upload`.
- **Observabilidad disponible sin construir nada:** `cron.job_run_details` y `net._http_response` guardan el historial de ejecuciones y llamadas; el monitor de capturas (§8) puede leerlos directamente.

### 14.4. Hallazgo de seguridad previo al diseño

`api_keys` guarda la clave **en texto claro** (`api_key text`), sin nombre, ámbito ni caducidad, aunque la documentación interna decía "hasheadas". Hoy hay 6 claves y 13 usos registrados. Antes de repartir claves a carriers hay que corregirlo (C21): columna `key_hash` (SHA-256), `key_prefix` para identificarla, `name`, `scope` (`onedb_read` \| `carrier_feed`), `feed_id`, `expires_at`; `onedb-api` pasa a comparar por hash; las claves actuales se re-emiten. Es trabajo de la fase 1 y conviene hacerlo aunque este proyecto se retrasara.

### 14.5. Veredicto

El servidor **tiene todo lo necesario** para las fases 0-3 sin cambiar de plan ni de cómputo: cron, HTTP desde la base, funciones, almacenamiento, cifrado y validación de JSON (esta última, activándola). Las tres cautelas de diseño que impone son: trabajar **por estratos** (timeout de 2 min), mantener a los conectores **fuera de la BD** (60 conexiones) y **hashear las claves** antes de dar la primera a un carrier. Si algún día un carrier aportara volúmenes muy superiores, el primer cuello de botella sería el cómputo de la instancia, no el diseño.

## 13. Glosario

- **Identificador del envío (`item_id`)**: el código con que el carrier identifica cada envío; ONEMS lo guarda tal cual. Puede ser un **S10** (identificador UPU de 13 caracteres, p. ej. `RR123456789KE`) o cualquier formato propio del operador.
- **EDI / EMSEVT**: mensajes electrónicos de eventos de seguimiento entre operadores (EMA admisión … EMI entrega).
- **EMSEVT / códigos EMA…EMI**: EMA admisión · EMB salida de la oficina de origen · EMC llegada a la oficina de cambio de salida · EMD salida de ella · EME llegada a la oficina de cambio de entrada · EMF salida de ella · EMG llegada a la oficina de entrega · EMH intento de entrega · EMI entregado.
- **Estrato**: combinación ruta ciudad→ciudad × periodo dentro de un plan (que ya es de un carrier y un producto) sobre la que el plan fija una cuota.
- **Población**: número total de envíos que cumplen las condiciones del estrato en el sistema del carrier.
- **Lote de candidatos**: subconjunto aleatorio de la población que el muro entrega a ONEMS.
- **Muro**: capa intermedia por carrier que traduce sus datos al formato común.
- **Modelo de extracción**: técnica genérica para obtener los datos de un carrier (push API, pull REST, fichero, consulta a BD, subida manual…). **Conector**: un modelo configurado para un carrier concreto de una cuenta. **Mapeo**: correspondencia entre un código del carrier y el código equivalente en ONEMS.
- **Origen del dato (`source`)**: de dónde salen las fechas de una muestra: `panelist` (declaración del panelista), `carrier` (escaneos del operador vía el muro) o `rfid` (lecturas RFID; reservado, C17).
