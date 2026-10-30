# Reconstrucción de tramos v2 — diseño

Fecha: 2026-10-30. Estado: aprobado en chat ("Implementa esto").

## Por qué

Route Path Analysis (mapa, tiempos, detalle de tramos) y `aggregate_journey_paths`
fueron escritos para una "generación nueva" de tramos (`build_journey_segments`)
que nadie llama. El cron usa `reconstruct_journeys`, que:

- solo forma tránsito entre oficinas cuando hay una **salida** en A seguida de una
  **entrada** en B; una lectura suelta en A (entrada sin salida) no genera tramo,
  así que el mapa queda vacío aunque la etiqueta se haya visto en dos oficinas;
- no rellena los tiempos natural/laborable ni `next_entry_timestamp`, ni las
  ciudades de los centros, ni transportista/producto del envío (hoy lo suple la
  fase `propagation` a posteriori);
- deja las lecturas sueltas con `is_consolidated=false` para siempre (se
  reescanean en cada pasada y figuran como pendientes en monitorización).

`build_journey_segments` no se puede adoptar tal cual: usa otra semántica de fila
(una por visita a centro, tipo según haya siguiente centro) que rompe los CHECK
de `journey_segments`, no aplica SLAs y fallaría con `exit_timestamp NOT NULL`.

## Qué se construye

Una nueva `reconstruct_journeys(p_account_id, p_tag_id)` (misma firma, misma
tabla de retorno) que:

1. Toma las etiquetas de la cuenta con algún evento `is_consolidated=false`.
2. Para cada una, **borra sus tramos y los reconstruye desde todos sus eventos**
   ordenados por `timestamp` (idempotente; las lecturas tardías se integran).
3. Agrupa los eventos en **visitas**: tramos máximos de eventos consecutivos en el
   mismo centro.
4. Por visita con una entrada y una salida posterior: tramo `operational`
   (entry = primera entrada, exit = última salida), con SLA operativo
   (`find_applicable_sla` + `determine_sla_compliance`), `adjusted_time` como hoy,
   `pre_operational_wait`, `natural_time_in_center_minutes` = minutos reales y
   `working_time_in_center_minutes` = `calculate_working_time_minutes` si el centro
   está en `working_days`, si no el natural; `next_entry_timestamp` = primera
   lectura de la visita siguiente.
5. Entre dos visitas consecutivas a centros distintos: tramo `distribution` desde
   la **última lectura** de la visita anterior (salida si la hay, si no su última
   lectura) hasta la **primera lectura** de la siguiente, con SLA de distribución
   (transportista del envío si se conoce, si no el del centro destino como hoy),
   `natural_transit_time_minutes` y `working_transit_time_minutes` (modo del
   centro origen).
6. Todos los tramos llevan `carrier_id/carrier_name_snapshot`,
   `product_id/product_name`, `origin/destination_city_name`,
   `from/to_postal_center_city` y `entry/exit_event_id`, copiados de los eventos.
7. Marca **todos** los eventos de la etiqueta `is_consolidated=true`.

`assemble_journeys` y la fase `propagation` no cambian. Una migración hace un
rebuild único de KENYA (eventos a `is_consolidated=false`, borrar sus tramos y
viajes, rerun del pipeline). DEMO2 no se toca (sus 168 tramos son datos sembrados
sin eventos).

## No objetivos

- `is_missroute` sigue sin calcularse.
- No se tocan las pantallas ni `aggregate_journey_paths`.
- Lecturas sueltas sin visita completa no generan tramo operativo (no hay tiempo
  en oficina que medir); sí cuentan como parada para el tránsito.

## Restricciones

- CHECKs de `journey_segments`: `operational` → `postal_center_id` y nada de
  from/to; `distribution` → from/to y nada de `postal_center_id`;
  `exit_timestamp >= entry_timestamp`; tiempos ≥ 0 o NULL; `sla_compliance` en
  {on_time, warning, critical, violated, no_sla}.
- Validar en local (`supabase/tests/run_tests.sh`) antes de onems-dev; OK
  explícito antes de aplicar.
