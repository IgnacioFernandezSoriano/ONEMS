# Bloqueos intermitentes en producción — revisión del código fuente

**Fecha:** 14 de octubre de 2026
**Alcance:** revisión del repositorio (rama `main`, desplegada en producción, y `develop`) y del esquema
de base de datos capturado en `supabase/migrations/`. Complementa el informe
`informe_diagnostico_onems_2026-10-14.md` basado en logs.
**Base de datos:** `onems-dev` (`sehbnpgzqljrsqimwyuz`). **No se ha modificado ningún dato ni ningún
fichero de código.** Este documento es el único fichero nuevo.

**Limitación:** no se ha podido consultar la base viva ni los logs desde esta sesión (el servidor MCP
de Supabase no conectó y la llamada directa a la Management API fue bloqueada por el modo de
permisos). Todo lo que depende de la base viva está marcado como **PENDIENTE DE CONFIRMAR** y
lleva su consulta de solo lectura en la sección 6.

---

## 1. Conclusión

> **Actualizada 14-oct tras la base viva y las métricas de la instancia:** el servidor no se
> satura. La causa más probable del "bloqueo" es **H0** (sección 1-ter): cada fila de la tabla de
> Allocation Plans descarga y parsea el CSV de traducciones; con miles de filas el navegador del
> usuario se congela. H1 (borrado fila a fila) sigue siendo real y agrava el cuadro, pero por el
> volumen de peticiones y porque al terminar repinta la tabla, no por el coste en Postgres.

*Conclusión original (previa a los datos de la base viva):* el código tiene un patrón que, por sí solo, explica que la aplicación "se quede bloqueada para todo
el mundo" mientras una sola persona borra registros, y que se recupere sola al terminar:

**el borrado masivo de detalles de plan hace una petición HTTP por fila, de diez en diez en
paralelo, y cada petición REST paga un coste fijo alto: las políticas RLS consultan `profiles` fila
a fila y las pantallas recargan después la vista de disponibilidad completa.**

Con 3.218 filas eso son 3.218 transacciones, 3.218 preflights CORS y 6.436 evaluaciones de política
contra `profiles`, concentradas en 30–60 segundos y ocupando de forma continua el pool de conexiones
que comparten todos los usuarios. Mientras dura, el resto de pantallas espera. Al acabar, la cola se
vacía y "se recupera".

*(Corrección 14-oct tras consultar la base viva: la hipótesis inicial de una FK sin índice en
`one_db` queda descartada; ver H2 y H2-bis.)*

Esto **no explica** el episodio del 13 de octubre sin borrados. Para ese día la revisión del código
descarta la hipótesis de "triple generación por doble clic" (eran tres planes distintos y el botón
se bloquea mientras procesa) y señala como carga real la **recarga completa de la pantalla tras cada
paso** (una generación dispara unas 60 peticiones de lectura además de los 2 inserts).

Se ha revisado y **descartado** la hipótesis de bloqueo por renovación del token a los 60 minutos
(sección 4).

---

## 1-bis. Actualización con datos de la base viva (14-oct, consultas 6.1–6.4, A, B, C)

Resumen de lo que la base viva confirma, matiza o descarta respecto al análisis de código:

| Punto | Resultado | Dato |
|---|---|---|
| Índice FK `one_db` (H2) | **Descartado** | existe `one_db_unique_allocation_detail`; `one_db` tiene 544 filas |
| Coste DB de cada DELETE fila a fila (H1) | **Barato en SQL** | 20.540 ejecuciones, 4,7 ms de media, 242 ms máx. El problema es el **número** de peticiones HTTP, no el coste de cada una en Postgres |
| Vista de disponibilidad (H4) | **Barata en SQL** | ~2.000 ejecuciones, 25–65 ms de media, 514 ms máx. Se carga demasiadas veces, pero no frena la base |
| Pipeline RFID por cron | **Descartado como causa** | único cron activo (job 4, cada 30 min, 5.999 ejecuciones OK, 0,1 s); el pipeline tarda ~200 ms; sus horas (:00/:30) no coinciden con los incidentes |
| Cron duplicado | **Descartado** | el job 3 (SQL directo) dejó de ejecutarse el 11-jun-2026 |
| **Consulta lenta real** | **Identificada** | `handleDownloadPlan` (`AllocationPlanGenerator.tsx:70-89`): detalles de plan generado con 7 tablas embebidas. 36 ejecuciones, **1.303 ms de media, 5.826 ms máx**. Explica por completo los GET de 5,4 s del 13-oct (eran descargas de CSV, no la generación) |
| Políticas RLS fila a fila (H2-bis) | **Confirmado como coste transversal** | `profiles` (34 filas): 4,2 M recorridos completos desde feb-2026. Cada tabla embebida evalúa sus políticas por fila → ~14.000 lecturas a `profiles` por página de 1.000 filas descargada |
| Periodo de estadísticas | desde **febrero de 2026** (sin reset) | los absolutos son de 8 meses; leer proporciones |

**Lo que la base viva NO muestra:** ninguna sentencia que tarde minutos, ningún bloqueo de locks,
ninguna carga de fondo relevante. En Postgres el peor caso individual son 5,8 s. Un "bloqueo" de
minutos percibido en la interfaz tiene que venir de (a) saturación de CPU/pool de la instancia por
**ráfagas de peticiones** (H1, H3) — lo decide el gráfico de CPU del panel —, o (b) algo en el
navegador (petición colgada sin timeout, error JS) — lo decide la consola/Network durante un
incidente. Ambas pendientes de dato.

## 1-ter. HALLAZGO PRINCIPAL (14-oct, tras descartar el servidor): el bloqueo está en el navegador

Las métricas de la instancia (CPU ≤ 30 % en el minuto peor del 13-oct, < 5 % en medias horarias,
14–18 conexiones de 60, swap estable) y `pg_stat_statements` (peor sentencia 5,8 s) descartan que
el servidor se bloquee. El código sí contiene un patrón que bloquea el **navegador del usuario**:

### H0 — Cada fila de la tabla de Allocation Plans descarga y parsea el CSV de traducciones (HECHO VERIFICADO en `develop` y en `main`)

| Campo | Detalle |
|---|---|
| Evidencia 1 | `src/components/allocation-plans/AllocationPlanDetailRow.tsx:33` → `const { t } = useTranslation()` del **hook directo** (`@/hooks/useTranslation`), no del contexto `useLocale()` |
| Evidencia 2 | `src/hooks/useTranslation.ts:98-145`: cada instancia del hook tiene su propio estado y un `useEffect([locale])` que hace `fetch('/locales/${locale}.csv?v=' + Date.now())` (línea 64). El `Date.now()` anula la caché del navegador |
| Evidencia 3 | `src/pages/AllocationPlans.tsx:818`: `filteredDetails.map(detail => <AllocationPlanDetailRow …/>)` **sin paginación**; filtros iniciales vacíos (línea 32) → se pintan todas las filas de la cuenta |
| Evidencia 4 | Cada instancia arranca con `locale = 'en'` (línea 83) y cambia al idioma del perfil en un segundo efecto (línea 89-95) → **dos descargas por fila** (`en.csv` + idioma) |
| Tamaño | `public/locales/*.csv`: 139–176 KB cada uno |
| Aritmética | 6.000 filas (KENYA antes del 14-oct) ≈ **12.000 peticiones HTTP a Netlify y ~1,7 GB** descargados por cada apertura de la pantalla, 12.000 parseos de CSV en el hilo principal, 36.000 `console.log` |
| Desde cuándo | commit `c3c0525` (2025-12-31) "Complete i18n implementation" |
| Alcance | 99 ficheros importan el hook directo; 7 usan el contexto. Otros componentes por fila afectados: `diagnosis/IncidentDetailsRow.tsx`, `admin/AccountResetCard.tsx` |
| Relación con el síntoma | "Funciona al principio" (Dashboard: pocas instancias) → "se bloquea al cabo de un tiempo" (al abrir Allocation Plans, o al terminar un borrado masivo, cuyo `fetchAll()` repinta la tabla) → "tarda en recuperarse" (hasta que terminan las miles de descargas). Ocurrió "ayer sin borrados" porque basta con abrir la pantalla. Supabase no lo ve porque el CSV lo sirve Netlify |
| Posible relación con i18n roto en prod | Si Netlify limita o corta miles de peticiones al CSV, el hook falla, cae a inglés o se queda sin mapa y `t()` devuelve las claves. **Hipótesis**, pendiente de la consola del navegador |
| Verificación | **HECHA el 14-oct en producción, cuenta Senegal (4.765 envíos):** abrir Allocation Plans = **4.839 peticiones**, 17,2 MB transferidos, 99,8 MB de recursos, más de 100 s de actividad, **9.650 errores en consola**. Cientos de `en.csv` terminan en `(failed)`: el navegador rechaza abrir tantas conexiones simultáneas. Con la tabla vacía (KENYA) la misma pantalla hace ~20 peticiones al CSV, una por componente |
| Relación con "producción no traduce" | **Confirmada como misma causa:** cada fila cuya descarga del CSV falla se queda sin mapa de traducciones y `t()` devuelve las claves en crudo (`useTranslation.ts:184`). Las dos incidencias abiertas (bloqueo e i18n) tienen un único origen |
| Corrección | (1) `AllocationPlanDetailRow` y el resto de componentes deben usar `useLocale()` del `LocaleContext` (una sola carga para toda la app); (2) paginar o virtualizar la tabla; (3) quitar el `Date.now()` del fetch o sustituirlo por el hash de build. Sin cambios de base de datos |

## 2. Hallazgos verificados en el código

### H1 — Borrado masivo fila a fila (HECHO VERIFICADO)

| Campo | Detalle |
|---|---|
| Evidencia | `src/lib/hooks/useAllocationPlanDetails.ts` líneas 178–204 (idéntico en `main`, líneas 179–191) |
| Qué hace | `for` en lotes de 10 → `Promise.allSettled(batch.map(id => supabase.from('allocation_plan_details').delete().eq('id', id)))` |
| Botón | `src/pages/AllocationPlans.tsx:363` → `BulkOperationsPanel.tsx:118` (hay `confirm()` y bandera `processing` que desactiva los botones; **no hay doble clic**) |
| Relación con logs | Ráfagas de 3.218 / 1.947 / 2.020 `DELETE` + 964 `OPTIONS` del 14-oct ([E1]). Un DELETE desde navegador siempre lleva preflight CORS: 2 peticiones HTTP por fila |
| Coste por petición | autenticación JWT + 2 políticas RLS de DELETE (una consulta a `profiles` cada una) + triggers de FK (ver H2) + commit y WAL propios |
| Después | `await fetchAll()` recarga **todos** los detalles por la vista pesada (ver H4) |

Peticiones esperadas para un borrado lógico de N filas: **2N + ~8** hoy; **~3** con un RPC o
`.in('id', ids)` por lotes.

### H2 — Clave foránea sin índice en `one_db` — **DESCARTADA con datos de la base viva (14-oct)**

> **Corrección:** la consulta 6.1 ejecutada en la base viva muestra el índice
> `one_db_unique_allocation_detail` (UNIQUE sobre `allocation_detail_id`), que **no está en el repo**
> (la BD va por delante de `main`). Además `one_db` tiene solo **544 filas vivas**. El coste por
> DELETE **no** viene de aquí. Se conserva el análisis original debajo como registro de lo revisado.
> El hallazgo real que sustituye a este es **H2-bis**.

### H2-bis — RLS evaluada fila a fila contra `profiles` y vista de disponibilidad (HECHO VERIFICADO con `pg_stat_user_tables`, 14-oct)

| Tabla | Filas vivas | Recorridos completos | Filas leídas en recorridos | Accesos por índice |
|---|---:|---:|---:|---:|
| `profiles` | 34 | **4.228.930** | 41.671.725 | 1.196.372 |
| `panelists` | 48 | 592.653 | 7.854.384 | 135.265 |
| `panelist_unavailability` | 5 | 25 | 49 | **10.584.018** |
| `one_db` | 544 | 20.786 | 13.244.827 | 41.015 |
| `allocation_plan_details` | 6.119 | 1.216 | 1.359.792 | 42.325 |
| `generated_allocation_plan_details` | 9.693 | 222 | 261.005 | 4.608 |

| Campo | Detalle |
|---|---|
| Qué significa `profiles` | 4,2 millones de recorridos a una tabla de 34 filas solo pueden venir de las políticas RLS: `current_user_account_id()` (SQL, `SECURITY DEFINER`, por tanto **no inlinable**) y el `EXISTS (select 1 from profiles where id = auth.uid() and role = 'superadmin')` de las políticas `superadmin_*`. Postgres las evalúa **por cada fila** que la consulta toca. Cargar 6.000 detalles = ~12.000 consultas a `profiles` solo para decidir permisos. Es exactamente el aviso `auth_rls_initplan` del advisor (95 políticas) |
| Qué significa `panelist_unavailability` | 10,5 millones de accesos a una tabla de 5 filas = las 4 subconsultas correlacionadas de `v_allocation_details_with_availability` (H4), una por fila de detalle y por carga. Equivale a unos 2,6 millones de filas-detalle evaluadas en el periodo de estadísticas |
| Qué significa `panelists` | 592.653 recorridos completos: los `LEFT JOIN panelists ON node_id = …` de la misma vista (no hay índice sobre `panelists.node_id` en el repo) y sus 2 subconsultas por fila |
| Periodo | Las estadísticas son acumuladas desde el último reset (consulta 6.8). Las proporciones son lo relevante, no los absolutos |
| Conclusión | El coste unitario de cada petición REST lo marcan **RLS + vista**, no las FKs. Multiplicado por los miles de peticiones de H1 y las ~60 de H3, es lo que satura la CPU y el pool |

Mitigación estándar (sin tocar la semántica de seguridad): envolver las llamadas en las políticas
como `(select current_user_account_id())` y `(select is_user_superadmin())`, para que Postgres las
evalúe **una vez por consulta** (InitPlan) en lugar de una vez por fila. Validar con
`EXPLAIN (ANALYZE, BUFFERS)` en la base local antes y después.

<details><summary>Análisis original de H2 (descartado)</summary>

| Campo | Detalle |
|---|---|
| Evidencia | `supabase/migrations/00000000000000_baseline_prod_schema.sql:1172` → `one_db.allocation_detail_id REFERENCES allocation_plan_details(id) ON DELETE SET NULL` |
| Índices de `one_db` | líneas 1389–1395: `account_id`, `(account_id, carrier_name)`, `(account_id, tag_id)`, `(carrier_name, product_name)`, ciudades, `sent_at`. **Ninguno sobre `allocation_detail_id`.** Ninguna migración posterior lo añade |
| Consecuencia | Por cada fila borrada en `allocation_plan_details`, Postgres ejecuta internamente `UPDATE one_db SET allocation_detail_id = NULL WHERE allocation_detail_id = $1`. Sin índice, eso es un **recorrido secuencial de `one_db`** por cada DELETE. 3.218 borrados = 3.218 recorridos completos |
| Las otras 3 FKs | `shipment_incident.parcel_id` (idx 1477), `panelist_reassignment_proposal` (idx_prp_detail), `panelist_incident` (idx_pi_detail): **sí** tienen índice |
| Es el aviso del advisor | De las 62 FKs sin índice que señala el Performance Advisor, **esta** es la única que está en la cadena del borrado. No hace falta crear 62 índices: hace falta medir este |
| Confirmación | consultas 6.1 y 6.2 → **ejecutadas: índice presente, 544 filas. Descartada.** |

</details>

### H3 — Generación: no hay duplicado, pero cada clic recarga todo dos veces (HECHO VERIFICADO)

| Campo | Detalle |
|---|---|
| Flujo | `AllocationPlanGeneratorForm.tsx:138` `handleSubmit` → `setLoading(true)` (botón `disabled={loading}`, línea 545) → cálculo en el navegador → `onGenerate` → `AllocationPlanGenerator.tsx:32` → `createPlan` + `createPlanDetails` |
| Doble clic / reintento | **No posible**: el botón queda desactivado hasta que termina; no hay `useEffect` que relance; no hay cron ni trigger que genere |
| Los tres lotes de 1.311 del 13-oct | Son **tres planes distintos** (Standard / Express / Economy) de la cuenta KENYA con los mismos parámetros (1.500 muestras, mismo rango de fechas, mismas ciudades) → el algoritmo determinista produce las mismas 1.311 filas. Verificado en la sesión anterior con los datos reales de `generated_allocation_plans` |
| Carga real por clic | `useAllocationPlans.ts:151` y `:174`: `createPlan` termina con `fetchAll()` y `createPlanDetails` **otra vez** con `fetchAll()`. Cada `fetchAll` = 1 lectura de planes + **una consulta `count` por cada plan existente, todas en paralelo** (líneas 44–58) + carriers + products + cities + nodes. Con 25 planes: ~30 lecturas × 2 = **~60 peticiones por generación**, 25 de ellas simultáneas |
| Relación con logs | **Corregido con la consulta C:** los `GET` de 5,19 s p95 del 13-oct son la **descarga de CSV** (`handleDownloadPlan`, 7 embebidos, 1,3 s media / 5,8 s máx), no los `count`. Los `count`/lecturas planas de `generated_allocation_plan_details` salen a 132 ms de media y 2,1 s máx (1.902 ejecuciones) |
| Sin transacción | `applyPlan` (líneas 226–305) inserta cabecera, luego detalles por lotes, luego cambia el estado, en **3+ peticiones sin transacción**. Si falla a mitad, queda una cabecera sin detalles |
| Déficit 1.500 → 1.311 | `allocationPlanCalculator.ts` redondea hacia abajo en varios pasos (`Math.floor` en líneas 84, 126, 280, 470; `Math.round` en 244) y descarta rutas con 0 (`continue` en 242–253). Es un defecto funcional, **no** de rendimiento |

### H4 — La vista de detalles se carga completa en Dashboard y en Allocation Plans (HECHO VERIFICADO; coste en SQL **bajo** según consulta C: 25–65 ms de media)

| Campo | Detalle |
|---|---|
| Vista | `v_allocation_details_with_availability` (baseline): 6 `LEFT JOIN` + **6 subconsultas correlacionadas por fila** (2 a `panelists`, 4 a `panelist_unavailability` con comparación de fechas) |
| Quién la carga entera | `useAllocationPlanDetails.ts:29–52`: paginación de 1.000 en 1.000 **hasta agotar**; montado en `Dashboard.tsx:103` y `AllocationPlans.tsx:30` |
| Superadmin | Si no hay cuenta seleccionada, `effectiveAccountId` es `null` y **no se filtra**: carga las 6.127 filas de todas las cuentas (7 páginas) cada vez que entra al Dashboard |
| Relación con logs | Parte de las ~27 peticiones de carga del panel ([E5]); además se repite completa tras **cada** operación masiva (`fetchAll()` al final de `bulkDeleteDetails`, `bulkUpdateDetails`, `updateDetail`, `createDetail`) |

### H5 — Pool de conexiones compartido (INFERENCIA RAZONADA)

PostgREST atiende todas las peticiones REST con un pool de conexiones fijo y pequeño, dimensionado
por el tamaño de la instancia. Diez `DELETE` concurrentes sostenidos durante 30–60 s, cada uno con
un recorrido de `one_db`, pueden ocupar ese pool por completo. Mientras tanto cualquier otra
petición (de cualquier usuario) **espera en cola**: la interfaz no da error, simplemente no
responde. Al terminar la ráfaga, la cola se drena y "se recupera". Es la mecánica que mejor encaja
con "funciona, deja de funcionar, tarda en recuperarse" con 2–4 usuarios. Confirmación: consulta 6.5
y tamaño de instancia en el dashboard de Supabase.

---

## 3. Qué pasó probablemente el 14 de octubre (INFERENCIA, confirmable con logs)

Los tres borrados del 14-oct suman **7.185** filas. Los cinco planes aplicados de KENYA tenían
**6.041** detalles (3 × 1.311 + 2 × 1.054) y los 172 envíos de Lodwar que "desaparecieron" suman
**6.213**. Es decir, los borrados del 14-oct por la mañana son, con mucha probabilidad, el motivo por
el que esa tarde los planes aplicados de KENYA aparecían con SAMPLES = 0 y Lodwar sin envíos: **no
fue un fallo del paso "apply", fue un borrado manual desde la pantalla Allocation Plans**. Las 972
filas restantes serían de otras cuentas o re-selecciones. Confirmar con el `auth_user` de las
peticiones DELETE en `edge_logs` (el informe de logs ya lo tiene: "una sola sesión autenticada").

---

## 4. Hipótesis revisadas y descartadas

| Hipótesis | Resultado | Por qué |
|---|---|---|
| Doble clic / reintento en generación | **Descartada** | Botón desactivado durante el proceso; tres planes distintos con parámetros iguales |
| Cron / trigger que genera detalles | **Descartada** | No hay `cron.schedule` en el repo; los triggers de las tablas de planes solo rellenan `account_id` y `updated_at` |
| Bloqueo por renovación del token (60 min) | **Descartada para el código actual** | `AuthContext.tsx:33` llama a `loadProfile` dentro del callback de `onAuthStateChange`, patrón que la librería desaconseja. Pero el callback **no es `async` ni hace `await`**, así que la renovación no espera a la consulta y el cierre reentrante de `auth-js 2.86.2` (`_acquireLock`, líneas 1091–1131) la encola sin bloquear. Si alguien convierte ese callback en `async`, sí se produciría el bloqueo. Recomendación: mover `loadProfile` a `setTimeout(…, 0)` por seguridad |
| Chunk 404 tras despliegue | **Descartada** | No hay `React.lazy`; la app es un único bundle; `vite.config.ts` usa `Date.now()` en los nombres para romper caché |
| Checkpoints lentos como causa | **Matizada** | Un checkpoint de 22–72 s con el tiempo en `write` es el comportamiento **normal** de Postgres: reparte las escrituras a lo largo del intervalo a propósito (`checkpoint_completion_target`). Solo sería señal de problema si los logs dicen `checkpoint starting: wal` (forzado por volumen) o `checkpoints are occurring too frequently`. Consulta 6.6 |
| Número de usuarios | **No sustentada** | Una sola acción de un usuario genera miles de operaciones (H1) o decenas de lecturas (H3) |

---

## 5. Cambios candidatos (ordenados por relación coste/efecto; ninguno aplicado)

1. ~~Índice en `one_db(allocation_detail_id)`~~ — **ya existe en la base viva**; descartado.
1-bis. **Políticas RLS con `(select …)`** — reescribir las políticas de las tablas calientes
   (`allocation_plan_details`, `generated_allocation_plan_details`, `allocation_plans`, `panelists`,
   `panelist_unavailability`) para que `current_user_account_id()` e `is_user_superadmin()` se evalúen
   una vez por consulta. Misma semántica de seguridad; validar con `EXPLAIN (ANALYZE, BUFFERS)`.
2. **Borrado por lote** — sustituir el bucle por un RPC `SECURITY INVOKER` que reciba `uuid[]` y haga un único `DELETE … WHERE id = ANY($1)`; RLS sigue aplicándose fila a fila dentro del mismo statement. Parche transitorio: `.in('id', lote)` en lotes de ~200. 3.218 peticiones → 1 (o ~16).
3. **Quitar el doble `fetchAll()`** en generación y **sustituir los N `count` en paralelo por una sola consulta agregada** (vista o RPC `plan_id, count(*) group by plan_id`). ~60 peticiones → ~6.
3-bis. **Descarga de CSV** (`handleDownloadPlan`): sustituir los 7 embebidos por una vista o RPC
   que devuelva las columnas ya resueltas (códigos de carrier, producto, nodo y ciudad). De 1,3–5,8 s
   por página a decenas de ms; también elimina ~14.000 lecturas a `profiles` por página.
4. **`applyPlan` como RPC transaccional** — cabecera + detalles + cambio de estado en una transacción; evita cabeceras huérfanas.
5. **Vista de disponibilidad** — reescribir las 6 subconsultas correlacionadas como `LEFT JOIN LATERAL` o precalcular; y que el Dashboard **no** cargue los 6.000 detalles cuando solo necesita contadores.
6. **`AuthContext`** — `setTimeout(() => loadProfile(id), 0)` dentro del callback (defensa, no causa actual).

Criterio de aceptación antes de desplegar cualquiera: prueba con 1.500–3.000 detalles en la base
local (`C:\Users\fernandezi\pgportable`, puerto 5433), `EXPLAIN (ANALYZE, BUFFERS)` del DELETE con y
sin índice, conteo de peticiones en la pestaña Network, y `npm run lint` + `npm run build` en verde.

---

## 6. Consultas de SOLO LECTURA para confirmar con la base viva

Ejecutar en el SQL Editor de **onems-dev (`sehbnpgzqljrsqimwyuz`)**. Ninguna modifica nada.

**6.1 — ¿Existe ya el índice en la base viva? (la BD puede ir por delante del repo)**
```sql
select indexname, indexdef
from pg_indexes
where schemaname = 'public' and tablename = 'one_db'
order by indexname;
```
Esperado si H2 es correcta: ninguna fila con `allocation_detail_id`.

**6.2 — Tamaño de `one_db` y cuántas veces se ha recorrido entera**
```sql
select relname,
       n_live_tup        as filas_vivas,
       seq_scan          as recorridos_completos,
       seq_tup_read      as filas_leidas_en_recorridos,
       idx_scan          as accesos_por_indice,
       n_tup_del         as borradas,
       n_tup_upd         as actualizadas
from pg_stat_user_tables
where relname in ('one_db','allocation_plan_details','generated_allocation_plan_details',
                  'panelist_unavailability','panelists','profiles')
order by seq_tup_read desc;
```
Esperado si H2 es correcta: `one_db` con `seq_scan` del orden de los miles (≈ número de DELETEs).

**6.3 — El UPDATE interno de la FK, con su coste acumulado**
```sql
select calls,
       round(total_exec_time)       as ms_totales,
       round(mean_exec_time, 2)     as ms_medio,
       rows,
       left(query, 160)             as consulta
from pg_stat_statements
where query ilike '%one_db%allocation_detail_id%'
order by total_exec_time desc
limit 5;
```
Esperado: una fila `UPDATE ONLY "public"."one_db" SET "allocation_detail_id" = NULL WHERE …` con
`calls` ≈ 7.185 y `ms_medio` proporcional al tamaño de `one_db`.

**6.4 — Las 15 consultas que más tiempo total consumen**
```sql
select calls,
       round(total_exec_time)    as ms_totales,
       round(mean_exec_time, 1)  as ms_medio,
       round(max_exec_time)      as ms_max,
       left(query, 140)          as consulta
from pg_stat_statements
where query not ilike '%pg_stat%'
order by total_exec_time desc
limit 15;
```
Buscar: `DELETE FROM "public"."allocation_plan_details" WHERE "id" = $1`, los `count` sobre
`generated_allocation_plan_details`, y la vista `v_allocation_details_with_availability`.

**6.5 — Pool de conexiones: cuántas usa PostgREST y cuántas esperan**
```sql
select usename, application_name, state, wait_event_type, count(*)
from pg_stat_activity
where datname = current_database()
group by 1,2,3,4
order by 5 desc;
```
Mejor ejecutarla **durante** un borrado grande. Además, anotar en el dashboard de Supabase:
Settings → Compute (tamaño de instancia) y Database → Connection pooling (pool size).

**6.6 — Checkpoints: ¿por tiempo (normal) o forzados por volumen (problema)?**
En Logs → Postgres, filtrar los días 13 y 14 por `checkpoint starting`. Si pone `time` es el
comportamiento normal; si pone `wal` o aparece `checkpoints are occurring too frequently`, el
volumen de escritura sí está forzando checkpoints y conviene mirar `max_wal_size`.

**6.8 — Desde cuándo acumulan las estadísticas (para dimensionar 6.2)**
```sql
select stats_reset from pg_stat_database where datname = current_database();
```

**6.7 — Quién hizo los borrados del 14-oct (cierra la sección 3)**
En Logs → Edge, Logs Explorer:
```sql
select
  datetime(timestamp) as ts,
  r.method,
  r.path,
  sb.auth_user
from edge_logs
cross join unnest(metadata) as m
cross join unnest(m.request) as r
cross join unnest(r.sb) as sb
where r.method = 'DELETE'
  and r.path like '/rest/v1/allocation_plan_details%'
  and timestamp between '2026-10-14T08:00:00Z' and '2026-10-14T13:00:00Z'
limit 20;
```
Comparar `auth_user` con el id del usuario que creó/aplicó los planes de KENYA
(`a39cae17-4e74-497e-9852-7335a21378a8`).

---

## 7. Qué capturar en el próximo bloqueo

- Hora UTC exacta, qué pantalla y qué acción se estaba haciendo (y si alguien más estaba borrando o
  generando en ese momento).
- Consola del navegador (F12 → Console) y pestaña Network: ¿las peticiones salen y se quedan en
  `pending`, o devuelven error? Exportar HAR si es posible.
- Ejecutar la consulta 6.5 **mientras** dura el bloqueo.

## 8. Estado de calidad del repositorio

- No existe suite de tests de frontend: **DATO NO ENCONTRADO EN EL REPOSITORIO**. La puerta de
  calidad es `npm run lint` (0 warnings) y `npm run build`.
- Producción (`main`) está en el commit `7c598a1` del 2026-07-15; `develop` va 53 commits por
  delante. Todos los hallazgos H1–H5 están presentes **también en `main`** (verificado con
  `git show main:…`).
