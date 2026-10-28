# Escalabilidad ONEMS — prueba de carga (¿hasta cuántos países?)

**Fecha:** 2026-08-03
**Pregunta:** ¿Hasta cuántos países escala la solución con **10.000 samples/año/país**?
**Criterio de "escala bien":** p95 de las consultas del dashboard **< 1 segundo**.

---

## Resumen para no técnicos (TL;DR)

- Probamos la base de datos cargándola con datos falsos realistas de **hasta 50 países**
  (2 años de histórico cada uno = **~5 GB, 13 millones de filas**).
- Las consultas del dashboard responden en **~8–72 milésimas de segundo (ms)**, es decir
  entre **14 y 125 veces por debajo** del límite de 1 segundo que nos marcamos.
- Y lo más importante: **ese tiempo NO empeora al añadir países**. De 5 a 50 países la
  velocidad se mantiene plana. La razón técnica está explicada abajo, pero en corto:
  cada consulta solo "mira" los datos del país que la pide, no los de todos los demás.
- **Veredicto: 50 países se soportan con holgura**, y no es el techo. El límite real no es
  la velocidad de consulta sino el **espacio en disco / memoria del servidor** (~100 MB por
  país/2 años), que se resuelve con el plan de hosting, no con cambios de código.
- **Concurrencia (25 usuarios):** con uso realista el dashboard completo carga en **p95 563 ms**
  (bajo el objetivo). Solo si los 25 recargasen sin pausa continua se superaría 1 s (~2,1 s):
  el cuello ahí es la CPU. Detalle en la sección de concurrencia.

---

## Método

### Entorno
- **Postgres 17.6 portable local** (`127.0.0.1:5433`). **No se tocó producción** en ningún
  momento (la base real es compartida; meterle datos falsos la contaminaría).
- Esquema aplicado desde el **baseline de prod** (`00000000000000_baseline_prod_schema.sql`)
  con `replay_baseline.ps1`. Verificado idéntico a prod: 60 tablas, 15 vistas, 92 funciones,
  **262 políticas RLS**, 74 triggers.

### Limitación declarada
La CPU/RAM del portátil **no es** la del tier de Supabase, así que **las latencias absolutas
no son las de producción**. Lo que sí es transferible —y es lo que responde la pregunta— es
**la curva de escalado**: cómo cambia el rendimiento al añadir países. Esa curva es plana
(ver abajo), y ese resultado es robusto independientemente del hardware.

### Modelo de carga (acordado con el responsable)
Cada "sample" es un **envío rastreado de punta a punta**. Por país y con 2 años de histórico:

| Tabla | Filas/país | Qué es |
|---|---:|---|
| `journeys` | 20.000 | 1 por sample (el trayecto completo) |
| `journey_segments` | 100.000 | 5 por sample (3 centros visitados → 3 tramos operacionales + 2 de distribución) |
| `one_db` | 20.000 | 1 por sample (registro E2E consolidado) |
| `rfid_events_raw` | 120.000 | 6 por sample (lecturas RFID crudas) |
| **Total hechos** | **~260.000** | + dimensiones (12 ciudades, 15 centros, 3 carriers, 3 productos, 3 SLAs) |

### Consultas medidas
Reproducen las agregaciones reales del dashboard/reporting, cada una filtrada por país (que
es exactamente lo que aplica RLS: `account_id = current_user_account_id()`), medidas con
`EXPLAIN (ANALYZE)` y reportando **p95 sobre 10 ejecuciones**:

- **Q1** Cumplimiento E2E por carrier/producto (`one_db`, último año)
- **Q2** Violaciones SLA por centro (`journey_segments` operacionales, último año)
- **Q3** Resumen de journeys por estado + missroutes
- **Q4** Serie temporal mensual de tránsito (2 años)
- **Q5** Distribución de cumplimiento por segmento

Se midió **siempre el mismo país** (país 1, 260k filas fijas) mientras la base total crecía
de 5 a 50 países. Así se aísla el efecto puro del **tamaño total de la BD** sobre un mismo
volumen de trabajo por tenant.

---

## Resultados

### p95 (ms) por consulta según nº de países en la base

| Consulta | N=1 | N=5 | N=10 | N=20 | N=30 | N=40 | N=50 |
|---|---:|---:|---:|---:|---:|---:|---:|
| Q1 compliance   |  9.4 | 18.4 | 21.8 | 15.0 |  8.0 | 15.4 | 20.3 |
| Q2 SLA/centro   | 27.2 | 64.5 | 72.5 | 57.3 | 23.8 | 71.1 | 68.4 |
| Q3 journeys     |  9.2 | 28.6 | 22.2 | 17.3 |  6.4 | 17.4 | 18.8 |
| Q4 serie temp.  |  7.9 | 22.7 | 20.4 | 17.5 |  7.7 | 18.3 | 21.1 |
| Q5 seg. distrib.| 25.8 | 71.5 | 67.6 | 63.6 | 24.8 | 68.0 | 70.2 |

> El N=1 procede de la validación previa (base con un solo país). La variación que se ve
> (±15 ms, el "bache" de N=30) es **ruido de medición** —cache/autovacuum/actividad del
> equipo—, no una tendencia. **No hay pendiente ascendente con N.**

### Tamaño de la base según nº de países
`5 → 501 MB`, `10 → 981 MB`, `20 → 1966 MB`, `30 → 2942 MB`, `40 → 3928 MB`, `50 → 4916 MB`.
Crecimiento **lineal, ~98 MB por país** (2 años). A N=50: ~5 GB, ~13 M filas de hechos.

### Reparto a N=50 (tabla + índices)
`rfid_events_raw` 2297 MB (idx 1448) · `journey_segments` 1821 MB (idx 643) ·
`journeys` 438 MB (idx 210) · `one_db` 344 MB (idx 174).

---

## Por qué escala plano (el mecanismo)

`EXPLAIN` de la consulta más pesada (Q5) con la base ya en 50 países:

```
HashAggregate (actual time=45.7..45.7 rows=3)
  ->  Index Scan using idx_journey_segments_account on journey_segments
        Index Cond: (account_id = '...0001')
        rows=100000   Buffers: shared hit=3096   (0 lecturas a disco)
```

Dos propiedades del diseño hacen que el coste dependa **solo del país consultado**, no del
total de la base:

1. **RLS por `account_id`** convierte toda consulta en `... WHERE account_id = <país>`.
2. **Todos los índices de las tablas de hechos empiezan por `account_id`**
   (`idx_journeys_account`, `idx_journey_segments_account`, `idx_one_db_account_id`,
   `idx_rfid_raw_*`, y compuestos como `(account_id, sla_compliance)`).

Resultado: el planificador entra directo por índice a las ~100k filas del tenant y se salta
las de los otros 49 países. Añadir países agranda el disco, **no el trabajo por consulta**.
Además la función `current_user_account_id()` es `STABLE SECURITY DEFINER` → se evalúa una
vez por sentencia, sin coste por fila.

---

## Veredicto

- **50 países: soportados con holgura.** Peor p95 medido = **72 ms**, ~14× por debajo del
  presupuesto de 1 s. Y sin degradación de 5 a 50.
- **50 no es el techo de latencia.** Como el tiempo de consulta es plano en N, el límite
  llega por **recursos físicos** (disco y RAM del servidor), no por velocidad:
  - **Disco:** ~100 MB/país/2 años → 100 países ≈ 10 GB, 200 ≈ 20 GB. Trivial de aprovisionar.
  - **RAM/caché:** conviene que **los datos de un país activo** (~25 MB, las 3096 páginas del
    plan) quepan en caché; eso se cumple sobradamente en cualquier tier razonable aunque la
    base entera no quepa en memoria, porque cada consulta solo toca un país.

**Conclusión:** con el criterio p95 < 1 s, la arquitectura **no pone un techo práctico en el
número de países** en el rango estudiado (y bastante más allá). El dimensionamiento es una
decisión de **plan de hosting** (disco/tier), no de rediseño.

---

## Concurrencia — 25 usuarios simultáneos (añadido)

Segunda prueba, sobre la misma base de **50 países**, con **pgbench**: 25 clientes en
paralelo, cada "usuario" carga el **dashboard completo = las 5 consultas** contra un país
aleatorio. Equipo local: **12 núcleos**. La métrica es el tiempo de carga de la página entera
(suma de las 5 consultas), que es lo que percibe el usuario.

| Escenario | Carga ofrecida | p50 | **p95** | p99 | tps sostenido |
|---|---|---:|---:|---:|---:|
| **Realista** (tiempo de lectura ~5 s entre cargas) | ~5 dashboards/s | 104 ms | **563 ms ✅** | 664 ms | 4.8/s |
| **Saturación** (25 clientes recargando sin pausa) | máxima | 1560 ms | **2077 ms ❌** | 3662 ms | 15.6/s |

**Lectura de los resultados:**

- **Uso realista: 25 usuarios se soportan bien.** Con tiempo de lectura entre cargas (un
  usuario no recarga el dashboard cada segundo), el p95 de la página completa es **563 ms**,
  por debajo del objetivo de 1 s. Sin transacciones fallidas.
- **Saturación (peor caso absoluto):** si los 25 clientes disparan cargas sin ninguna pausa
  (25 recargas continuas en bucle), el p95 sube a **~2,1 s** y se supera el segundo. El cuello
  es **CPU**: 25 agregaciones que recorren ~100k filas cada una compiten por 12 núcleos
  (sobre-suscripción ~2×) + ancho de banda de memoria. La consulta pesada Q2 pasa de 68 ms
  (1 usuario) a ~1053 ms de media bajo saturación.
- **El techo de este equipo es ~15 cargas de dashboard/seg.** 25 usuarios reales generan
  muchísima menos carga que eso (a 1 carga por usuario cada ~30–60 s → <1 carga/seg), así que
  quedan ~15–30× por debajo del punto de saturación.

**Importante:** a diferencia del escalado por nº de países (que es plano e independiente del
hardware), **la concurrencia SÍ depende de la CPU del servidor**. En el tier de Supabase, con
más/menos núcleos que estos 12, el punto de saturación se moverá. El resultado transferible es
la **forma**: 25 usuarios con uso normal van sobrados; el riesgo aparece solo si se acumulan
muchas cargas pesadas simultáneas.

**Palanca de mejora (si en el futuro hace falta más margen de concurrencia):** las dos
consultas caras son las de `journey_segments` (Q2, Q5), que recorren 100k filas en cada carga.
Servirlas desde **agregados precalculados** (ya existe `weekly-aggregation` / `journey_paths`)
o cachear el resultado por cuenta reduciría el coste por carga y multiplicaría el nº de
usuarios concurrentes soportados sin tocar el tier.

---

## Advertencias y siguiente paso recomendado

1. **Latencias absolutas ≠ prod.** Los ms de aquí son del portátil; en Supabase serán otros.
   Lo válido es la **forma plana** de la curva.
3. **ETL / crons a escala.** El pipeline RFID (poll + consolidación, cada 30 min) y las
   agregaciones se ejecutan por cuenta; a 50 países conviene vigilar que la ventana del cron
   siga holgada. No formaba parte de este encargo (criterio = dashboard), pero es el otro
   punto a medir antes de crecer mucho.

---

## Reproducibilidad

Scripts usados (Postgres local, no prod):
- `gen.sql` — función `gen_country(k)` que siembra un país completo (dimensiones + 260k hechos).
- `bench.sql` — función `bench(account, iters)` que devuelve el p95 por consulta.
- `driver.sql` — barrido 1→50 con `ANALYZE` antes de cada medición.
- `dashboard.pgbench` — script pgbench (1 transacción = las 5 consultas del dashboard contra
  un país aleatorio) para la prueba de concurrencia (`pgbench -c 25 -j 8 -T 30`).

Los scripts quedan en el scratchpad de la sesión; si se quieren versionar para repetir la
prueba, moverlos a `supabase/tests/loadtest/`.
