# Muestras por compensar (balanceo) — diseño

Fecha: 2026-10-28. Estado: borrador para aprobación. Amplía `2026-10-27-load-balancing-v2-design.md`.

## 1. Intención

Hoy una muestra pendiente cuyo nodo origen o destino no tiene panelista se queda «congelada» en el plan: nadie
puede enviarla ni recibirla, ensucia las vistas y se avisa con `no_valid_cell`. En Kenya son unas 296 muestras con
origen en Busia, Moyale y Narok y 304 con destino en un nodo sin panelista (Senegal: 100 con destino sin panelista).

Nuevo comportamiento: el balanceo **intenta reasignar** esas muestras a otro nodo de la misma ciudad. Si no es
posible, **las borra del plan y las anota** en un registro de «muestras por compensar», para que no se pierdan. Más
adelante, en un balanceo posterior, **se reintroducen** respetando el plan original (mismo plan, misma ruta
ciudad→ciudad, mismo número total de muestras). Un contador en el menú avisa de cuántas hay pendientes de
reintroducir.

## 2. Decisiones del usuario (2026-10-28)

1. Una muestra borrada se **copia a un registro aparte y se elimina de `allocation_plan_details`**.
2. Se borra y anota en estos casos: **nodo origen sin panelista**, **nodo destino sin panelista**, **día sin panelista
   y sin otro día posible**; y **cuando el origen o el destino no se puede asignar a otro nodo de la misma ciudad**.
3. La reintroducción va **dentro de «Balancear»**, con vista previa («N muestras a reintroducir»).
4. Si una ciudad no tiene ningún panelista, sus muestras **se pasan a otros nodos de la misma ciudad si los hay, o
   esperan** en el registro hasta que haya panelista.
5. Debe haber un **contador visible en la opción de menú** de Load Balancing con las muestras pendientes de
   reintroducir.
6. Mientras está borrada, la muestra **cuenta como pendiente del plan** en Allocation Plans e informes de avance
   (el total del plan no baja; las anotadas se suman a las pendientes como «por compensar»).
7. Al reintroducir, **todas las que quepan sin picos**: se reparten entre los días laborables que quedan del plan sin
   superar 1 envío extra por nodo y día respecto a lo ya programado; el resto espera al siguiente balanceo.

## 3. Reglas

### 3.1 Qué se hace con cada muestra `pending` problemática (orden de prioridad)
Se aplica en `rpc_balance_city_v2`, ciudad por ciudad, solo a muestras `pending` con fecha ≥ hoy y dentro del periodo
del balanceo:

1. **Origen sin panelista activo (o nodo inactivo):** se intenta **reasignar el origen** a otro nodo activo con
   panelista de la **misma ciudad** (el reparto normal elige cuál, por carga). Si no hay ninguno → paso 4.
2. **Destino sin panelista activo:** se intenta **reasignar el destino** a otro nodo activo con panelista de la
   **ciudad destino** (el menos cargado en recepciones de esa semana). Si no hay ninguno → paso 4.
   *Esto sustituye la regla anterior «el destino nunca se cambia»: ahora puede cambiar, solo dentro de la misma
   ciudad.* Las muestras con destino válido siguen sin cambiar de destino.
3. **Día sin hueco:** la muestra está en un día en que el panelista del origen o del destino está ausente o que no es
   laborable, y no existe ninguna celda válida (nodo/día) en la ciudad dentro del periodo y de las fechas del plan
   donde moverla → paso 4. (Hoy es el caso `no_valid_cell` por día.)
4. **Borrar y anotar:** se copia la fila completa al registro con el motivo y se elimina del plan. Motivos:
   `origin_no_panelist`, `dest_no_panelist`, `no_valid_day`.

No se borran: muestras no `pending`, muestras con origen = destino que no se pueden intercambiar (siguen avisando
`origin_equals_destination`). Las muestras **anteriores a hoy** se tratan igual que las demás: primero se intenta
moverlas hacia delante (como hoy) y, si su origen o destino no tiene panelista y no hay alternativa, se borran y
anotan.

**Precisiones (decisiones mías tras la revisión del constructor):**
- **Reasignar destino:** se aplica a toda muestra `pending` con destino sin panelista activo (hoy esas muestras se
  «congelan»; pasan a reasignarse o borrarse). El nuevo destino debe cumplir día laborable y ausencias igual que el
  origen. Se guardan `original_destination_node_id` (columna ya existente, solo la primera vez),
  `destination_panelist_id/name` actualizados y `reassignment_reason = 'rebalancing'`.
- **Orden respecto al motor actual:** la reasignación de origen **es el reparto normal** (las muestras de nodos sin
  celda ya se reparten como «fuera de celda»); solo se borra cuando la ciudad no tiene ningún nodo válido. Las
  muestras que se van a borrar se apartan **antes** de calcular objetivos y desviaciones: no cuentan en los totales
  del mes ni en `stddev_before/after`; se informan aparte.
- **«Día sin hueco»:** se busca primero en el mismo mes (como hoy); si no hay celda, en los demás meses del periodo
  dentro de las fechas del plan (mover de mes es preferible a borrar); solo si tampoco hay, se borra. Se añade el
  filtro por fechas del plan también en el reparto normal (hoy solo lo tiene POBOX).
- **Reintroducción, nodos:** la ruta se mantiene a nivel de ciudad; se usa el nodo original si tiene panelista y, si no,
  el menos cargado de la misma ciudad. La fila nueva lleva `id` nuevo, `generation_source = 'compensation'` y los
  nodos originales en `original_origin_node_id` / `original_destination_node_id` cuando cambian. Entra en
  `matrix_after` y en la desviación.
- **Ámbito:** solo planes `active`; cuenta = la de la ciudad (un superadmin opera sobre la cuenta seleccionada). Se
  reintroducen las anotaciones cuyo plan tiene días válidos dentro de la **intersección** del periodo de la pantalla y
  de las fechas del plan (el usuario controla con el filtro). Una ejecución sobre la ciudad A puede reintroducir
  muestras con destino en B sin bloquear B (el único efecto es la carga de recepciones de B; aceptable).
- **Deshacer:** no se construye función de deshacer; `row_snapshot` conserva la fila original completa, incluido su
  `id`, y la tabla de respaldo previa cubre la primera aplicación. Un deshacer manual es posible a partir del snapshot.
- **Avance del plan (decisión 6):** la vista `v_allocation_details_with_availability` y los contadores de Allocation
  Plans suman las anotaciones `pending` de `deferred_samples` como estado `deferred` (una fila sintética por
  anotación) para que el total del plan y el % de avance no cambien. El constructor decide el punto de unión mínimo
  (vista o RPC de resumen); los informes E2E/SLA no las ven (no han viajado).
- **Contador del menú:** cuenta la cuenta efectiva (`useEffectiveAccountId`); se carga al entrar y se refresca tras
  aplicar un balanceo; sin sondeo periódico.
- **Rendimiento:** la vista previa de «todas» sigue siendo ciudad a ciudad desde el cliente (8 s por llamada, no por
  total); el objetivo por ciudad sigue siendo < 1 s.

### 3.2 Reintroducción (dentro de «Balancear», después del reparto y antes de POBOX)
Para cada ciudad **origen** de la ruta de las muestras anotadas:
1. Se toman las anotaciones `status='pending'` de esa ciudad origen cuyo **plan sigue `active`** y cuyo periodo
   (`start_date`..`end_date`) incluye algún día válido ≥ hoy.
2. Se coloca cada una en un hueco válido: nodo origen con panelista de la ciudad origen (el original si lo tiene; si
   no, el menos cargado), nodo destino con panelista de la **misma ciudad destino** de la anotación (idem), día
   laborable sin ausencia de ninguno de los dos y dentro de las fechas del plan, repartido por la regla de equidad
   (día con menos envíos del nodo). **Tope (decisión 7):** como máximo 1 envío extra por nodo y día respecto a lo ya
   programado tras el reparto; las que no caben esperan al siguiente balanceo (motivo de espera `no_capacity`).
3. Si la ciudad origen o la ciudad destino no tiene ningún nodo con panelista, **se queda en el registro** (espera).
4. Al aplicar, la muestra reintroducida se inserta en `allocation_plan_details` con `plan_id` original,
   `generation_source = 'compensation'` y la anotación pasa a `reintroduced` con fecha y el id de la fila creada.
5. La vista previa informa por ciudad: muestras que se **borrarán y anotarán**, que se **reasignarán a otro nodo** y
   que se **reintroducirán**, más las que **esperan** (y por qué).

Las reintroducidas cuentan como muestras normales del plan (informes, SLA, stock), igual que las de POBOX.
El orden dentro de una ejecución es: reasignar/borrar → reparto equitativo → reintroducir → POBOX.

### 3.2 bis POBOX y las muestras anotadas (decisión del usuario, 2026-10-28)
Cuando POBOX encuentra un día laborable sin ningún envío en la ciudad y no puede cubrirlo moviendo excedentes, antes
de **crear** una muestra nueva **tira de las anotadas**: reintroduce una muestra `pending` de `deferred_samples` cuya
ciudad origen sea esa ciudad, cuyo plan esté `active` y cuyas fechas incluyan ese día, eligiendo el destino de la
misma ruta (ciudad destino de la anotación) con nodo con panelista. Solo si no hay ninguna anotada que sirva se crea
una muestra nueva como hasta ahora. Así cubrir el día y compensar la deuda es la misma acción y el plan no se infla
mientras haya borradas esperando.

Una muestra **creada** por POBOX (porque no había anotadas) sigue siendo extra (`generation_source = 'pobox'`) y **no
descuenta** la deuda de ningún plan: el contador de «por compensar» solo baja con reintroducciones
(`generation_source = 'compensation'`, enlazadas a su anotación). Con esto el control es **por plan**: para cada plan
se puede ver total original, programadas, enviadas/recibidas, por compensar y extras POBOX.

La vista previa distingue, en POBOX: días cubiertos moviendo, días cubiertos reintroduciendo anotadas y días
cubiertos creando muestras nuevas.

### 3.3 Registro y contador
Tabla `public.deferred_samples` (una fila por muestra borrada):
`id`, `account_id`, `plan_id`, `origin_city_id`, `dest_city_id`, `origin_node_id`, `destination_node_id`,
`fecha_programada` (original), `reason`, `row_snapshot jsonb` (fila completa), `status` (`pending` | `reintroduced`),
`created_at`, `created_by`, `reintroduced_at`, `reintroduced_detail_id`.
RLS por `account_id` (lectura para la cuenta; escrituras solo por las funciones del balanceo).

Contador: `rpc_deferred_samples_summary(p_account_id)` devuelve `{pending_total, by_city:[{city_id,city_name,count,
waiting_reason}], by_plan:[{plan_id,plan_name,total_samples,scheduled,done,deferred,pobox_extra}]}` (control por
plan: `scheduled` = filas del plan, `deferred` = anotaciones pendientes, `pobox_extra` = filas con
`generation_source='pobox'`). El menú «Load Balancing» muestra un **badge** con `pending_total` cuando es > 0. La pantalla
tiene una sección «Muestras por compensar» con el desglose por ciudad y el motivo de espera.

### 3.4 Invariantes
- Solo muestras `pending` se borran/reasignan; nunca enviadas, recibidas, notificadas ni con incidencia.
- La vista previa **no escribe nada** (ni registro ni plan).
- El borrado y la anotación van en la **misma transacción** (si falla uno, no se hace ninguno); la ciudad se serializa
  con el candado por ciudad que ya existe.
- Nunca se reintroduce una muestra fuera de las fechas de su plan, en festivo, en fin de semana de la cuenta, en día de
  ausencia de origen o destino, ni en un nodo sin panelista.
- Una anotación se reintroduce una sola vez (idempotencia) y queda enlazada a la fila creada.
- Las funciones nuevas son `SECURITY DEFINER` con el mismo control de acceso que las demás (superadmin o misma
  cuenta) y sin sentencias `UPDATE/DELETE` sin `WHERE` (protección `safeupdate` de PostgREST).
- La copia de seguridad previa a la primera aplicación real es obligatoria (ver 5).

## 4. Interfaz
- **Vista previa (ciudad y «todas»):** nueva columna/bloque «Borradas y anotadas / Reasignadas / Reintroducidas /
  En espera». Aviso destacado en rojo cuando hay muestras a borrar, con el número exacto, antes de «Aplicar».
- **Menú:** badge en «Load Balancing» (y sobre el icono de la sección Allocation si el menú está plegado).
- **Tarjeta de ciudad / Recomendaciones:** nuevo hallazgo «N muestras por compensar esperando panelista» y el de
  «N muestras se borrarán al balancear».
- **Sección «Muestras por compensar»** en la pantalla: tabla por ciudad (pendientes, motivo, plan) y tabla **por
  plan** (total original, programadas, hechas, por compensar, extras POBOX) — solo lectura.
- Textos en EN/ES/FR/AR.

## 5. Impacto en datos de producción (Kenya, 2026-10-28)
La primera aplicación real anotaría y borraría del plan del orden de **600 muestras** de Kenya (296 con origen en
Busia/Moyale/Narok y ~304 con destino en esos nodos, con solape) y unas 100 de Senegal. Se mantienen las 28 ciudades,
pero Busia, Moyale y Narok quedarían sin envíos pendientes hasta que tengan panelista. Antes de aplicar: copia de
`allocation_plan_details` pendientes (tabla de respaldo, borrada solo cuando el usuario lo confirme) y vista previa
de «Balancear todas» revisada por el usuario.

## 6. Fuera de alcance
- No se reintroducen muestras en otra ciudad ni se cambia la ruta ciudad→ciudad (decisión 4).
- No hay botón separado de reintroducción: va dentro de «Balancear».
- No se recalcula `allocation_plans.total_samples` (sigue siendo el objetivo original; el contador refleja la deuda).
- No se tocan informes ni SLA salvo que las muestras reintroducidas cuentan como normales.

## 7. Lo que queda al constructor
- Estructura SQL de los pasos 3.1–3.2 dentro de `rpc_balance_city_v2` sin degradar el rendimiento (objetivo: vista
  previa de una ciudad < 1 s) y cómo informar el JSON de resultado (claves nuevas `deferred`: `removed`,
  `reassigned`, `reintroduced`, `waiting`).
- Diseño visual del badge, de la sección y de la columna de la vista previa.
- Textos en los 4 idiomas.
