# Load Balancing v2 — diseño

Fecha: 2026-10-27. Estado: borrador para aprobación.

## 1. Intención

Hoy la carga de envíos se reparte dos veces: el **generador** crea los envíos de un plan y el botón
**Balancear** de Node Load Balancing reordena los pendientes. Ninguno de los dos evita picos: el
balanceador reparte por semana y conserva el día de la semana, puede mover envíos a nodos sin
panelista, carga siempre +1 a los primeros nodos y mueve más envíos de los necesarios. Kenya tuvo
que repartirse a mano el 26/10 (hasta 15 envíos en un día para un panelista y semanas vacías).

Queremos que ambos mecanismos obedezcan unas mismas **políticas de cuenta**, repartan de forma
equitativa a tres escalas (día, semana, nodo), respeten los días laborables configurados y las
ausencias de cada panelista, y permitan la política **POBOX** (al menos un envío por ciudad y día
laborable).

## 2. Objetivos, no objetivos, antiobjetivos

**Objetivos**
- Políticas definidas una vez por cuenta, visibles y editables en la cabecera de Load Balancing,
  con excepción por ciudad.
- Reparto equitativo: sin picos para un panelista ni entre panelistas de una ciudad.
- Balanceo de todas las ciudades de golpe, manteniendo el ciudad a ciudad.
- Vista por día, semana y mes, con ausencias sombreadas.
- POBOX: cubrir cada día laborable por ciudad moviendo excedentes y, si no alcanza, creando envíos.
- El generador aplica las mismas reglas al crear planes.

**No objetivos**
- No se cambia el bot: sigue avisando por `fecha_programada`.
- No se tocan envíos que no estén `pending`.
- No se balancea entre ciudades (un envío nunca cambia de ciudad de origen).
- No se cambian los informes ni los SLA: los envíos creados por POBOX cuentan como muestras normales.

**Antiobjetivos (sería un fracaso aunque funcione)**
- Mover un envío al pasado, a un día no laborable, a un nodo sin panelista o a un panelista ausente.
- Cambiar envíos ya notificados, enviados o recibidos.
- Perder la traza de qué se movió y por qué.

## 3. Criterios que se conservan

Todo lo que no se cambia aquí sigue igual (ver el artifact de estudio del 2026-10-27):
- Solo envíos `pending` entran en el balanceo; nunca al pasado (hoy según zona horaria de la cuenta).
- Traza en `allocation_plan_details`: `original_fecha_programada`, `original_origin_node_id`,
  `reassignment_reason`, `reassigned_at`, `reassigned_by`.
- Vista previa antes de aplicar, con desviación típica antes/después y matrices.
- Generador: reparto por semanas ponderado por días laborables y estacionalidad; sobrante sorteado;
  rotación origen/destino por ruta; solo nodos activos con panelista.
- Semáforo de la pantalla (`rpc_get_node_load_by_period`, referencia 6, desviación 20 %): sin cambios.

## 4. Políticas (cabecera)

Se guardan en `account_config` (una fila por cuenta) y se muestran y editan en un bloque nuevo de la
cabecera de Node Load Balancing, encima de los filtros actuales. Aplican a todas las ciudades salvo
excepción.

| Política | Valores | Por defecto | Excepción por ciudad |
|---|---|---|---|
| Días laborables de la semana | 7 selectores L–D | Lo que haya en `weekly_schedule`; si no hay filas, L–V | No |
| Política de fecha | `weekly` / `daily` | `daily` | Sí |
| POBOX | sí / no | no | Sí |

**Días laborables.** No se crea nada nuevo: los selectores leen y escriben `weekly_schedule`
(`is_working_day` por `day_of_week`, filas de cuenta con `postal_center_id` nulo). Es la misma tabla
que ya edita Account Configuration. Un día es laborable cuando `is_working_day` es verdadero y no está
en `non_working_days` de la cuenta. Las funciones de base que hoy tienen L–V fijo pasan a consultar esto.

**Política de fecha.**
- `daily`: cada envío lleva su día exacto dentro de la semana laboral.
- `weekly`: todos los envíos de una semana llevan como `fecha_programada` el **primer día laborable
  de esa semana**. El panelista se organiza durante la semana. El bot no cambia: avisa en esa fecha.

**POBOX.** Si está activa, la política de fecha de esa cuenta (o ciudad) se fuerza a `daily`; el selector
queda bloqueado mostrando el motivo.

**Quién edita.** Cualquier usuario que tenga acceso a Load Balancing puede cambiar las políticas de la
cuenta y las excepciones por ciudad (decisión del usuario). Un superadmin edita las de la cuenta
seleccionada (`useEffectiveAccountId`).

**Excepción por ciudad.** Dos columnas opcionales en `cities`: `date_policy` (`weekly`/`daily`/nulo) y
`pobox_enabled` (verdadero/falso/nulo). Nulo = hereda de la cuenta. Se editan desde la tarjeta de cada
ciudad en Load Balancing (un pequeño desplegable y una casilla junto al nombre). La política efectiva
de una ciudad es la de la ciudad si no es nula, si no la de la cuenta.

## 5. Reglas de reparto (balanceador y generador)

Se aplican en este orden de prioridad. Una regla superior nunca se rompe para cumplir una inferior.

1. **Fechas válidas.** Solo días laborables de la cuenta, nunca antes de hoy, dentro del periodo.
2. **Nodos válidos.** Solo nodos activos con panelista activo. Un nodo sin panelista no recibe envíos.
3. **Ausencias.** Un envío no se programa (ni como origen ni como destino) en un día en que el panelista
   del nodo tiene una ausencia activa en `panelist_unavailability` (estado `active`, fecha dentro de
   inicio–fin).
4. **Equidad diaria** (solo con política `daily`): dentro de cada semana, la diferencia entre el día más
   cargado y el menos cargado de un mismo panelista es como máximo 1.
5. **Equidad semanal:** cada semana tiene un **objetivo** proporcional a su peso (días laborables de
   la semana × porcentaje de estacionalidad de su mes, si el plan la usa). Para cada nodo, la carga de
   cada semana se desvía como máximo 1 de su objetivo. Sin estacionalidad todas las semanas pesan igual
   y la regla equivale a «diferencia máxima 1 entre semanas». **Manda la estacionalidad** (decisión del
   usuario): afecta por igual a todos los nodos de la ciudad, así que la equidad entre nodos se mantiene.
   Como la estacionalidad es mensual y no se guarda en el plan aplicado, el **balanceador** conserva el
   total de cada mes de la ciudad y reparte ese total entre las semanas del mes por sus días laborables;
   nunca mueve envíos de un mes a otro. El **generador** sí conoce la estacionalidad y la aplica como hoy.
6. **Equidad entre nodos:** dentro de una ciudad, la diferencia de carga total entre nodos es como
   máximo 1.
7. **Sobrante rotativo.** Cuando el total no divide exacto, los +1 se reparten empezando por un nodo
   distinto cada vez. El punto de inicio se guarda por ciudad (`cities.balance_rotation_offset`,
   entero) y avanza **solo al aplicar** (no en vista previa) y **solo si hubo sobrante** que repartir.
   En el generador, el sobrante se sortea como hoy.
8. **Mínimos movimientos.** El balanceador calcula primero el objetivo de cada celda (nodo × semana ×
   día en `daily`, nodo × semana en `weekly`) y solo mueve envíos **desde celdas por encima de su
   objetivo hacia celdas por debajo**. Un envío que ya está en una celda dentro de objetivo no se toca.
   Al elegir qué envío sacar de una celda sobrecargada se prefiere el de fecha más lejana; al elegir
   destino, la celda deficitaria más cercana en fecha.

**Nota sobre la regla 4 en `weekly`:** no aplica porque todos los envíos de la semana llevan la misma
fecha. Las reglas 5 y 6 sí.

**Precisiones (decisiones mías tras la revisión):**
- **Qué puede cambiar el balanceador:** la fecha y el **nodo origen** (dentro de la misma ciudad). El
  nodo destino no se toca nunca. El nuevo origen debe cumplir las reglas 2 y 3 en la fecha del envío.
  El balanceador no intenta mantener la rotación origen/destino por ruta del generador.
- **Celdas y objetivos:** una celda es nodo × día laborable (en `daily`) o nodo × semana (en `weekly`).
  Las celdas en las que el panelista está ausente, o que caen en día no laborable o en el pasado, no
  existen: no reciben objetivo ni envíos. El objetivo de cada celda se calcula repartiendo el total de la
  ciudad entre las celdas existentes según su peso (regla 5). Cuando ≤1 es imposible de cumplir en todas
  las escalas a la vez, se cumple en el orden 4 > 5 > 6 y se acepta la desviación mínima; la medida de
  éxito sigue siendo la desviación típica antes/después que ya muestra la vista previa.
- **Envíos sin hueco válido:** si un envío `pending` está en una celda que no existe (ausencia, día no
  laborable, pasado) y no hay ninguna celda válida en la ciudad dentro del periodo, se queda donde
  está y la vista previa lo lista como **aviso** («N envíos sin hueco válido en <ciudad>»). No se aborta.
- **Política `weekly` y el pasado:** la fecha de la semana es el primer día laborable de la semana que
  sea ≥ hoy. Si para un nodo ese día es de ausencia, ese nodo usa su siguiente día laborable libre de
  la semana. Si no tiene ninguno, sus envíos de esa semana se tratan como «sin hueco válido».
- **Cambio de política:** cambiar `daily`/`weekly` o POBOX no reescribe nada por sí solo. Las fechas se
  recalculan al pulsar Balancear (ciudad o todas). En `weekly` el balanceador fija la fecha de la semana
  para todos los envíos pendientes de esa semana.

## 6. POBOX

Regla: con POBOX activa, **cada ciudad debe tener al menos un envío de origen por cada día laborable**
del periodo, sumando todos los planes y productos. El objetivo es que un panelista de la ciudad pase
cada día por la oficina y pueda declarar lo recibido.

Ámbito (decisiones mías): se cuentan **todos los planes `active` de la cuenta**, no solo los del
filtro; el periodo es el de los filtros de la pantalla (fecha inicio–fin), empezando en hoy; los días
pasados sin envío se ignoran. Un envío nuevo toma `plan_id`, carrier y producto del plan elegido; los
demás campos obligatorios de `allocation_plan_details` (`account_id`, nodos, fecha, estado,
`week_number`, `month`, `year`) se rellenan como hace el generador.

Pasos, por ciudad y día laborable sin ningún envío de origen (`pending` o posterior):

1. **Mover.** Buscar, en la misma ciudad y la misma semana, días con más de un envío `pending`. Tomar
   uno del día más cercano al hueco (primero hacia atrás dentro de la semana, luego hacia delante;
   nunca al pasado). Si la semana no tiene excedente, ampliar a las semanas contiguas (±1, ±2…) hasta el
   fin del periodo. El envío movido conserva nodo origen y destino; solo cambia la fecha. Motivo:
   `pobox_move`.
2. **Crear.** Si no hay excedente que mover, crear un envío nuevo con estos criterios, en este orden:
   - **Plan:** entre los planes `active` de la cuenta cuyo periodo incluye el día, el que tenga menor
     porcentaje de envíos no pendientes (menos avanzado). Empate: el de fecha de fin más lejana.
   - **Nodo origen:** nodo válido de la ciudad con menos envíos de origen en esa semana. Empate: el que
     menos tenga en el periodo.
   - **Nodo destino:** nodo válido de **otra** ciudad de la cuenta (una ruta que ya exista en el plan si
     la hay; si no, cualquier ciudad) con menos envíos de destino en esa semana. Empate: la ciudad con
     menos recepciones en el periodo.
   - Estado `pending`, `fecha_programada` = el día a cubrir, `generation_source = 'pobox'`.
     Cuenta como muestra normal en todo lo demás (informes, SLA, stock de material).
3. **Informar.** La vista previa muestra, por ciudad, cuántos días estaban sin cubrir, cuántos se cubren
   moviendo y cuántos creando. El usuario ve esa cifra antes de aplicar.

POBOX se ejecuta **después** del balanceo de equidad y solo sobre las ciudades con POBOX efectiva.
Si un día no puede cubrirse porque ningún nodo válido está disponible (todos ausentes), se deja sin
cubrir y aparece en la vista previa como aviso.

En el **generador**, POBOX se aplica al final de la generación con los mismos pasos, sobre los envíos
recién generados y antes de guardar. El total del plan puede superar `total_samples`; el formulario
avisa de cuántos envíos se añadieron por POBOX.

## 7. Balancear todas las ciudades

Botón nuevo en la cabecera: **Balancear todas las ciudades**. Recorre todas las ciudades de la cuenta
con algún envío pendiente en el periodo y llama a la función de ciudad **una ciudad tras otra desde el
cliente**, con barra de progreso. Cada ciudad se aplica en su propia transacción (atómica por ciudad);
no es todo o nada entre ciudades. Motivo (decisión mía): una sola transacción de 28 ciudades y ~3.000
envíos chocaría con el límite de 8 s por llamada de Supabase. Si una ciudad falla, se informa y se
sigue con las demás. La vista previa muestra una tabla con una fila por ciudad (movimientos, desviación
antes/después, días POBOX cubiertos y sin cubrir, avisos) y los totales. El botón por ciudad se
mantiene con la misma vista previa reducida a esa ciudad.

## 8. Vista día / semana / mes

En la tarjeta de cada ciudad, un selector de escala con tres opciones. Las columnas son días, semanas
ISO o meses del periodo filtrado. Las filas siguen siendo los nodos y la última fila el total.

- **Semana** (actual): sin cambios de contenido.
- **Mes:** suma por mes; la columna «media» pasa a media mensual.
- **Día:** una columna por día del periodo. Con periodos largos la tabla se desplaza en horizontal con
  la primera columna fija. Celdas sombreadas:
  - **Ausencia del panelista** (gris con rayas diagonales): el nodo tiene una ausencia activa ese día.
  - **Día no laborable** (gris liso): fin de semana según `weekly_schedule` o `non_working_days`.
  Si una celda sombreada tiene envíos, el número se muestra en rojo: es un conflicto que el balanceo
  resolverá.

El semáforo por nodo (normal/alta/saturada) no cambia de cálculo; se muestra en cualquier escala.

## 9. Datos

Una sola migración nueva (`supabase/migrations/2026MMDDHHMMSS_load_balancing_v2.sql`):

- `account_config`: `date_policy text not null default 'daily' check in ('weekly','daily')`,
  `pobox_enabled boolean not null default false`.
- `cities`: `date_policy text null check in ('weekly','daily')`, `pobox_enabled boolean null`,
  `balance_rotation_offset integer not null default 0`.
- `allocation_plan_details`: `generation_source text not null default 'plan'` (`plan` | `pobox`).
  Valores nuevos de `reassignment_reason`: `pobox_move` (además de `rebalancing`).
- Función `public.is_account_working_day(p_account_id, p_date)`: verdadero si el día de la semana es
  laborable en `weekly_schedule` (sin filas = L–V) y no está en `non_working_days`. Sustituye el L–V fijo
  de `working_day_in_range`, que pasa a usarla.
- Función `public.rpc_balance_city_v2(p_city_id, p_start_date, p_end_date, p_apply_changes)`: aplica
  las reglas de la sección 5 y luego POBOX (sección 6) para una ciudad. Devuelve el mismo JSON que hoy
  más `pobox_days_missing`, `pobox_days_moved`, `pobox_days_created`, `pobox_days_uncovered` y
  `matrix_before/after` a escala día cuando la política es `daily`.
- Función `public.rpc_balance_cities_pending(p_account_id, p_start_date, p_end_date)`: devuelve la
  lista de ciudades de la cuenta con envíos pendientes en el periodo, para que el cliente recorra
  `rpc_balance_city_v2` ciudad a ciudad.
- `rpc_balance_node_load_by_period` se mantiene hasta que el frontend deje de llamarla; se elimina en una
  migración posterior.
- RLS: las columnas nuevas viven en tablas que ya tienen RLS por `account_id`. Las funciones comprueban
  que el usuario pertenece a la cuenta de la ciudad (como hoy).
- Ausencias que se tienen en cuenta: `panelist_unavailability` con `status = 'active'`.

Validar la migración en el Postgres portable local (`supabase/tests/replay_baseline.ps1`) antes de
aplicarla en onems-dev. Hacer copia de `fecha_programada` y `origin_node_id` de los `pending` del
periodo antes de la primera aplicación real, como en `backup_kenya_fechas_20261026`.

## 10. Frontend

- `NodeLoadBalancing.tsx`: bloque de políticas en la cabecera (selectores de días, política de fecha,
  POBOX), botón «Balancear todas las ciudades», selector de escala pasado a cada tarjeta.
- `CityLoadCard.tsx`: escala día/semana/mes, sombreados, controles de excepción por ciudad.
- `BalancePreviewModal.tsx`: tabla por ciudad cuando el resultado es de cuenta; cifras POBOX.
- `useNodeLoadBalancing.ts`: llamadas a las funciones v2; carga de ausencias y días no laborables del
  periodo para el sombreado.
- `useAccountConfig.ts`: las dos políticas nuevas y la escritura de `weekly_schedule` desde la cabecera.
- `allocationPlanCalculator.ts`: días laborables desde `weekly_schedule` en lugar de L–V fijo; política
  `weekly` (fecha = primer día laborable de la semana); equidad diaria dentro de la semana; POBOX al
  final. `AllocationPlanGeneratorForm.tsx` muestra la política efectiva y el aviso de envíos POBOX.
- Todo texto nuevo pasa por `useTranslation()` en los 4 idiomas (`public/locales/*.csv`).
- Sustituir los `alert()` de la pantalla por el patrón de aviso que use el resto de la app.

## 11. Decisiones tomadas por mí (a revisar al leer)

1. Días laborables solo a nivel cuenta; reutilizo `weekly_schedule`.
2. Orden de prioridad de la equidad: día > semana > nodo.
3. Sobrante rotativo con un contador por ciudad; en el generador se mantiene el sorteo.
4. POBOX: plan menos avanzado; origen con menos carga semanal; destino en otra ciudad con menos
   recepciones semanales, prefiriendo rutas ya existentes en el plan.
5. Envíos POBOX marcados con `generation_source = 'pobox'` solo como traza; no afectan a informes.
6. Sombreado: rayas para ausencias, gris liso para no laborables, número en rojo si hay conflicto.
7. «Balancear todas» va ciudad a ciudad desde el cliente, atómico por ciudad, con progreso.
8. La función antigua se conserva una versión más y se borra después.
9. El balanceador cambia fecha y nodo origen; nunca el destino.
10. Envíos sin hueco válido se quedan y se avisan; no se aborta.
11. `weekly`: fecha = primer día laborable de la semana ≥ hoy; por nodo, siguiente día libre si ausencia.
12. Cambiar una política no reescribe nada hasta pulsar Balancear.
13. Rotación del sobrante avanza solo al aplicar y solo si hubo sobrante.
14. POBOX cuenta todos los planes activos de la cuenta; periodo = filtros de pantalla desde hoy.

**Decisiones del usuario (2026-10-27):** cualquier usuario con acceso a Load Balancing edita las
políticas; manda la estacionalidad sobre la equidad semanal.

## 12. Lo que queda al constructor

- Algoritmo concreto para cumplir las reglas 4–8 de la sección 5 (se sugiere: calcular objetivos por
  celda, ordenar celdas por exceso, mover de mayor exceso a mayor déficit con las preferencias de
  cercanía indicadas).
- Rendimiento con periodos largos (Kenya: ~3.000 pendientes, 28 ciudades, 134 días). Objetivo: vista
  previa de cuenta en menos de 10 s.
- Diseño visual del bloque de políticas y del selector de escala, coherente con la pantalla actual.
- Textos en los 4 idiomas.
