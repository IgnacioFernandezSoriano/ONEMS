# Recepción en POBOX tras una ausencia del panelista — diseño

Fecha: 2026-10-30. Estado: borrador para aprobación. Amplía `2026-10-28-muestras-por-compensar-design.md`
(registro de muestras por compensar) y `2026-10-27-load-balancing-v2-design.md` (política POBOX).

## 1. Intención

En una ciudad con **POBOX** el panelista no recibe en casa: va a la oficina de correos a depositar sus envíos y,
estando allí, mira el apartado. Por eso el balanceo le programa **al menos un envío cada día laborable**: así va
todos los días y recoge lo que haya llegado.

Si un día **no fue** (estaba indisponible, o simplemente no declaró ningún envío), lo que recoge al día siguiente
pudo haber llegado el día que faltó. La fecha de recepción que declara no es la fecha real de entrega y la medida
E2E de ese envío queda inflada.

Nuevo comportamiento: cuando el panelista de destino declara una recepción en una ciudad POBOX y **no fue al
apartado el último día de recogida anterior**, ONEMS **no la cuenta para E2E**: el envío queda anulado con su
traza, y la muestra vuelve al registro de **muestras por compensar** con un motivo que lo explica, para que el
siguiente balanceo la reintroduzca como pendiente.

## 2. Decisiones del usuario (2026-10-30)

1. La comprobación se hace **en el momento de declarar la recepción**, y **solo** cuando la ciudad de destino
   tiene POBOX efectivo (política de la ciudad o, en su defecto, de la cuenta).
2. La prueba de que el panelista fue al apartado un día es que **declaró algún envío ese día**: en POBOX hay al
   menos un envío programado por nodo y día laborable, así que "sin envío declarado" equivale a "no fue".
3. Si no fue el último día de recogida anterior, la recepción **no vale**: fuera de E2E, anulada, y la muestra
   **se replanifica como pendiente** entrando en el registro de muestras por compensar.
4. El motivo visible en el balanceo es **"Posible retraso de recepción por vacaciones del panelista"**, en el
   idioma de la cuenta (es decir, traducido en la interfaz como el resto de motivos del registro).
5. La **ayuda** de Balanceo de carga explica el motivo nuevo en los cuatro idiomas.
6. **No** se captura la posición GPS de la declaración (se trató y se descartó por ahora).
7. **No hay marcha atrás** de una anulación. La disciplina es "declara lo que recoges el día que lo recoges": si
   el panelista declara el lunes lo que recogió el viernes, esa medida se pierde y la muestra se repite.
8. Una muestra por compensar cuyo plan **ya ha terminado** no se queda esperando: el balanceo la coloca en los
   próximos días laborables aunque sean posteriores a la fecha de fin del plan, mientras el plan siga **activo**.
   Vale para **todas** las muestras por compensar, no solo para las anuladas por esta regla.
9. La **pantalla de gestión del registro** de muestras por compensar (detalle con filtros por causa y fecha
   original; borrar, editar, reintroducir o no) es un **proyecto aparte**, inmediatamente posterior a este.

## 3. Reglas

### 3.1 Cuándo se evalúa
Al pasar un envío de `allocation_plan_details` a `status = 'received'` **desde el bot o una integración**
(sesión sin usuario web: `auth.uid()` es NULL). Las recepciones marcadas a mano por el gestor desde la web
(`mark_detail_received_manual`) son una decisión humana y **no** pasan por la regla (decisión del diseñador).
Los scripts de mantenimiento (Management API, `execute_sql`) también corren sin usuario: para que no anulen nada
sin querer pueden desactivar la regla en su transacción con `SET LOCAL onems.skip_pobox_receipt_rule = 'on'`
(decisión del diseñador). Hoy solo el bot marca recepciones; el ETL RFID no toca `allocation_plan_details`.

Condiciones previas, todas necesarias; si falla alguna la recepción es válida y todo sigue como hoy:
- la ciudad del nodo de destino tiene POBOX efectivo (`effective_city_policy(ciudad).pobox_enabled`);
- se conoce el nodo de destino del envío;
- la ciudad de destino tiene **un solo nodo activo** (`nodes.status = 'active'`). En ciudades con varios nodos la
  regla **no se aplica por ahora**: hay que estudiar aparte quién va al apartado y por quién cuenta la visita
  (decisión del usuario, 2026-10-30);
- el envío recibido **pudo estar en el apartado el día D**, según el estándar de entrega de su transportista,
  producto y ruta (`delivery_standards.time_unit`):
  - estándar en **días** (correo ordinario, J+n): pudo estar si salió **antes** de D (fecha local de `sent_at` < D).
    Si salió el día D o después, la recepción es válida aunque el panelista no fuera el día D (evita anular los J+1
    enviados el viernes y recogidos el lunes);
  - estándar en **horas** (servicios express, llegan el mismo día): pudo estar si salió **el día D o antes**
    (`sent_at` local <= D). Solo si salió después de D la recepción es válida sin más;
  - **sin estándar** para esa ruta y producto: se trata como "días", el caso general (decisión del diseñador).
  Esta condición mira el paquete **que se recibe** (viene de otra ciudad); los envíos que salen del nodo del receptor
  son otros paquetes y se usan solo como prueba de visita (3.3).

### 3.2 El "último día de recogida anterior" (D)
- La fecha de recepción `R` es `received_at` convertida a la zona horaria de la cuenta (`accounts.timezone`).
- `D` es el día laborable de la cuenta (`is_account_working_day`: lunes a viernes salvo configuración propia, y
  sin festivos de la cuenta) **más cercano anterior a `R`**. Se busca hacia atrás un máximo de 14 días; si no
  aparece ninguno (configuración extraña) la recepción es válida.
- Ejemplos: recibe el lunes → D = viernes; recibe el miércoles con el martes festivo → D = lunes; recibe en
  sábado → D = viernes.

### 3.3 ¿Fue al apartado el día D?
Dos paquetes distintos intervienen y no hay que mezclarlos: los envíos que **salen** del nodo del receptor hacia
otras ciudades (prueba de visita, este apartado) y el paquete que el receptor **recibe**, que viene de otra ciudad
(su `sent_at` se usa solo en la condición previa de 3.1 "salió antes de D").

Se mira el **nodo del panelista de destino** (el nodo de destino del envío):

1. **Fue** si existe algún envío de la cuenta con ese nodo como origen y `sent_at` cuya fecha local (zona de la
   cuenta) sea `D`. La recepción es **válida**, aunque ese día tuviera una indisponibilidad declarada (fue de
   todos modos).
2. Si no fue, se distingue el motivo:
   - **Indisponible**: **algún panelista activo del nodo de destino** (el único nodo de la ciudad) tiene una fila de
     `panelist_unavailability` con `status = 'active'` y `start_date <= D <= end_date` (por nodo, igual que la
     prueba de visita y que las ausencias del balanceo; el `destination_panelist_id` de la fila puede ser un
     titular antiguo del nodo; decisión del diseñador). Motivo `pobox_absent_unavailable` ("Posible retraso de
     recepción por vacaciones del panelista").
   - **No fue sin motivo**: estaba disponible y existía al menos un envío programado ese día desde su nodo
     (`fecha_programada = D`, status distinto de `cancelled`) que no declaró. Motivo `pobox_absent_no_visit`
     ("Posible retraso de recepción: el panelista no fue al apartado el día anterior").
   - **Sin prueba**: ni indisponibilidad ni envío programado ese día (día POBOX sin cubrir o aún sin balancear).
     Beneficio de la duda: la recepción es **válida**.

### 3.4 Qué pasa con una recepción anulada
Todo ocurre en la misma sentencia en que el bot marca la recepción, de forma que el bot **no cambia**:

1. El envío **no se copia a `one_db`** (no entra en E2E).
2. La fila de `allocation_plan_details` queda con `status = 'cancelled'`, conservando `tag_id`, `sent_at`,
   `received_at` y los panelistas (traza), y con dos columnas nuevas: `cancellation_reason` (uno de los dos
   motivos) y `cancelled_at`.
3. Se inserta una anotación en `deferred_samples` con el mismo plan, ruta ciudad→ciudad, nodos, `fecha_programada`
   original, `reason` = motivo, `row_snapshot` = la fila antes de anular y `created_by` NULL (bot).
4. La muestra cuenta desde ese momento como **por compensar** del plan; el envío anulado deja de contar como
   realizado (los `cancelled` no cuentan en ningún total). El total del plan no cambia.
5. La reintroducción es la ya existente: al balancear la **ciudad de origen** de la muestra, se reintroduce como
   `generation_source = 'compensation'` con un día laborable futuro y, al enviarse, llevará una etiqueta nueva.
   La etiqueta del envío anulado no se reutiliza (sigue en la fila anulada).
6. **No hay restauración**: ni RPC ni botón para volver una fila anulada a recibida (decisión del usuario, 2.7).

### 3.4 bis Reintroducción más allá del fin del plan (todas las muestras por compensar)
Hoy `rpc_balance_city_v2` solo reintroduce dentro de `[inicio del plan, fin del plan]` y, si el plan ya acabó, la
anotación espera con `waiting_reason = 'outside_period'`. Nuevo comportamiento (decisión del usuario, 2.8):
- la ventana de reintroducción pasa a ser `[max(inicio del plan, inicio del balanceo, mañana), fin del periodo de
  balanceo]`: la **fecha de fin del plan deja de acotar**;
- condición única: el plan sigue `active`. Si no, espera con `plan_inactive` como hasta ahora;
- `outside_period` queda solo para el caso en que no haya ningún día laborable en esa ventana (periodo de balanceo
  anterior al inicio del plan, o sin días laborables);
- las muestras reintroducidas tras el fin del plan son muestras normales del plan (`generation_source =
  'compensation'`), cuentan en su plan y en los informes por su fecha real de envío;
- la **sustitución de Extra POBOX** ya existente (migración `20261028200000`) sigue aplicándose: si el día elegido
  tiene una muestra `pobox` pendiente en el nodo de origen, la compensación ocupa su lugar en vez de sumar un
  envío. Las anuladas por esta regla entran por el mismo camino (recordatorio del usuario, 2026-10-30);
- la ayuda de Balanceo actualiza la fila "Fuera del periodo del plan" y el párrafo "Y después".

### 3.5 Lo que ve cada uno
- **Panelista**: el bot le contesta exactamente igual ("Paquete recibido"). La anulación es un asunto del gestor.
  Si vuelve a escanear la misma etiqueta, el bot encuentra la fila anulada y responde con su mensaje ya
  existente para envíos cancelados ("no se puede registrar porque está cancelado o tiene una incidencia abierta,
  contacta con tu gestor"); se acepta sin tocar n8n (decisión del diseñador).
  La guía del panelista añade una regla para ciudades POBOX: declarar cada envío y cada recepción **el mismo día**
  que se deposita o se recoge.
- **Gestor**, en Balanceo de carga → "Muestras por compensar":
  - la tabla **Por ciudad de origen** gana una columna **Motivo** con el desglose por motivo de anotación (por
    ejemplo "3 · Posible retraso de recepción por vacaciones del panelista"); los motivos anteriores
    (`origin_no_panelist`, `dest_no_panelist`, `no_valid_day`) también se muestran ahí con su etiqueta;
  - la columna actual "Motivo de espera" no cambia;
  - la tabla **Por plan** no cambia (la muestra ya cuenta en "Por compensar").
- **Ayuda de Balanceo** (`public/help/load-balancing.{es,en,fr,ar}.html`, bloque "Muestras por compensar"): un
  párrafo nuevo "Recepciones en POBOX tras una ausencia" con la regla en lenguaje llano, el ejemplo del lunes, y
  los dos motivos en la tabla, con la columna "Qué hacer" = "Nada: la muestra se reintroduce sola en el siguiente
  balanceo de la ciudad de origen. Si se repite con el mismo panelista, recuérdele declarar los envíos el mismo
  día".
- **Guía del panelista** (`public/help/panelist-guide.{es,en,fr,ar}.html`, sección "Enviar un paquete"): una nota
  "Si recoges en apartado de correos (POBOX), declara el envío el mismo día que lo depositas; si lo declaras al
  día siguiente, ONEMS entenderá que ese día no fuiste".

### 3.6 Riesgos asumidos
- `sent_at` es la hora de la **declaración**, no la del depósito. Un panelista que deposita hoy y declara mañana
  aparece como "no fue hoy", y la recepción que declare mañana se anulará. Es la consecuencia buscada (2.7): se
  mitiga con la guía del panelista; no se cambia el bot y no hay restauración.
- La prueba de visita es por **nodo**, no por persona. Si dos panelistas comparten nodo y uno declara un envío,
  cuenta como visita del nodo. Es el mismo supuesto que usa POBOX al programar por nodo.
- Las ciudades POBOX con **varios nodos** quedan fuera de la regla hasta que se estudie el caso; mientras, sus
  recepciones tardías siguen entrando en E2E como hoy.
- El beneficio de la duda del punto 3.3 deja pasar recepciones el día después de un día POBOX sin cubrir.

## 4. Goals, non-goals, anti-goals

**Goals**: E2E sin fechas de recepción infladas en POBOX; la muestra no se pierde (vuelve al plan, incluso si el
periodo del plan ya pasó); el gestor ve el motivo; el bot no cambia; regla permanente y para todas las cuentas
con POBOX.

**Non-goals**: GPS de la declaración (descartado por ahora); cambiar la fecha de recepción "a la real" (no se
conoce); aplicar la regla en ciudades sin POBOX o con varios nodos; avisar al panelista; corregir recepciones ya registradas antes
de la migración (no hay backfill: la regla rige desde que se aplica); restaurar una anulación; la pantalla de
gestión del registro de muestras por compensar (proyecto siguiente).

**Anti-goals**: anular recepciones en ciudades sin POBOX; anular cuando el panelista sí fue (declaró envío) aunque
tuviera indisponibilidad; romper la respuesta del bot o dejar al panelista sin confirmación; tocar n8n.

## 5. Restricciones
- Una sola base Supabase `onems-dev` (`sehbnpgzqljrsqimwyuz`); escrituras solo con confirmación explícita.
- Migración forward-only con timestamp posterior a `20261030145555`; validada antes en el Postgres portable local
  con `supabase/tests/run_tests.sh`.
- RLS por `account_id`; `deferred_samples` solo se escribe desde funciones `SECURITY DEFINER`.
- Toda cadena visible pasa por `useTranslation` y existe en los 4 CSV de `public/locales/`.
- `npm run lint` (0 warnings) y `npm run build` deben pasar.

## 6. Cómo se construye (decisiones del diseñador)

### 6.1 Base de datos (una migración)
- `allocation_plan_details`: columnas `cancellation_reason text NULL` con CHECK en
  (`pobox_absent_unavailable`, `pobox_absent_no_visit`) y `cancelled_at timestamptz NULL`.
- `deferred_samples.reason`: CHECK ampliado con los dos motivos nuevos.
- Función `pobox_previous_collection_day(p_account_id uuid, p_date date) RETURNS date` (STABLE): el día laborable
  anterior según 3.2, NULL si no lo hay en 14 días.
- Función `pobox_receipt_check(p_detail allocation_plan_details) RETURNS text` (STABLE): devuelve NULL (válida) o
  el motivo según 3.1–3.3. Separada para poder probarla sola.
- Trigger `BEFORE UPDATE OF status ON allocation_plan_details` → `tg_pobox_receipt_rule()`:
  - condición: `NEW.status = 'received' AND OLD.status IS DISTINCT FROM 'received' AND auth.uid() IS NULL AND
    COALESCE(current_setting('onems.skip_pobox_receipt_rule', true), '') <> 'on'`;
  - si `pobox_receipt_check(NEW)` devuelve motivo: `NEW.status := 'cancelled'`, `NEW.cancellation_reason`,
    `NEW.cancelled_at := now()`, y `INSERT INTO deferred_samples` con `row_snapshot = to_jsonb(NEW)` (antes de
    cambiar el status, para que el snapshot refleje la recepción declarada);
  - al quedar `status = 'cancelled'`, el trigger `trigger_transfer_to_one_db` (AFTER) no copia nada;
  - la consulta del bot (`UPDATE … WHERE status = 'sent' RETURNING id`) sigue devolviendo la fila: el bot
    responde "Paquete recibido" sin cambios.
- `rpc_deferred_samples_summary`: en `by_city` añadir `by_reason` (jsonb motivo→conteo).
- `rpc_balance_city_v2`: en la construcción de los candidatos a reintroducir (`lb2_rcand`), `pe` pasa de
  `LEAST(pl.end_date, p_end_date)` a `p_end_date`; el resto de la fase R no cambia. Es la única modificación de
  esa función (se re-emite completa, como en las migraciones anteriores del balanceo).
- Sin backfill.

### 6.2 Frontend
- `src/hooks/useNodeLoadBalancing.ts`: tipo de `by_city` con `by_reason?: Record<string, number>`.
- `src/components/NodeLoadBalancing/DeferredSamplesSection.tsx`: columna "Motivo" con el desglose, etiquetas
  `lb2.deferred.reason.<motivo>` para los cinco motivos.
- `public/locales/{en,es,fr,ar}.csv`: `lb2.deferred.col_defer_reason` y `lb2.deferred.reason.*` (5 motivos).

### 6.3 Ayuda
- `public/help/load-balancing.*.html`: bloque "Muestras por compensar" (párrafo nuevo + dos filas en la tabla +
  fila "Fuera del periodo del plan" y párrafo "Y después" actualizados con la reintroducción tras el fin del plan).
- `public/help/panelist-guide.*.html`: nota en "Enviar un paquete" y en "Recibir un paquete".

### 6.4 Pruebas (harness local `supabase/tests/`)
Fichero `pobox_receipt_after_absence.test.sql`, cuenta de prueba con POBOX y zona horaria fija:
1. Lunes recibe, viernes indisponible y sin envío → anulada con `pobox_absent_unavailable`, fila en
   `deferred_samples`, nada en `one_db`.
2. Martes recibe, lunes disponible con envío programado y no declarado → anulada con `pobox_absent_no_visit`.
3. Martes recibe, lunes declaró un envío aunque tuviera indisponibilidad → válida, fila en `one_db`.
4. Miércoles recibe, martes festivo de la cuenta, lunes indisponible → anulada (salta el festivo).
5. Lunes recibe, viernes sin envío programado ni indisponibilidad → válida (beneficio de la duda).
6. Ciudad sin POBOX, viernes indisponible → válida.
6b. Ciudad POBOX con **dos nodos activos**, viernes indisponible y sin envío → válida (regla no aplicable).
7. Recepción con `auth.uid()` simulado (gestor) → válida aunque se cumpla la regla; ídem con
   `SET LOCAL onems.skip_pobox_receipt_rule = 'on'`.
8. Lunes recibe un envío con estándar en **días** que **salió el viernes** (D), viernes sin visita → válida.
8b. Mismo caso con estándar en **horas** (express) → anulada (pudo llegar el viernes).
8c. Express que salió el **lunes** y se recibe el lunes, viernes sin visita → válida (salió después de D).
8d. Sin estándar para la ruta, salió el viernes → válida (se trata como días).
9. Indisponibilidad de **otro** panelista activo del mismo nodo de destino → cuenta como indisponible del nodo.
10. La muestra anulada se reintroduce con `rpc_balance_city_v2(ciudad de origen, apply)` como `compensation`.
11. Plan con `end_date` anterior al periodo de balanceo y `status = 'active'`: su muestra por compensar se
    reintroduce en el periodo (antes esperaba con `outside_period`); con el plan inactivo sigue esperando con
    `plan_inactive`. Se actualiza la aserción correspondiente de `ds_balance_defer.test.sql` si la hay.

## 7. Lo que queda al constructor
- Nombre exacto de la migración y orden de los triggers BEFORE (solo importa que el de normalización de etiqueta y
  este no dependan entre sí).
- Formato visual de la columna "Motivo" (lista corta "n · etiqueta").
- Redacción final de las traducciones FR y AR.
