# Incidencias de baja: resolución 100 % automática, la incidencia solo informa

**Fecha:** 2026-11-09
**Estado:** revisado por builder-check (2026-11-09); pendiente de aprobación del usuario
**Modifica a:** `2026-10-20-incidencias-indisponibilidad-resolucion-automatica-design.md`.
Todo lo que aquí no se contradice sigue vigente. Lo que cambia son sus apartados 5.2 (paso 5), 5.3, 5.4, 6 y 2.

---

## 1. Intención

Hoy, cuando un panelista declara una baja, el sistema resuelve solo una parte de las muestras afectadas y deja el resto en «Pending manager decision». El manager tiene que confirmar o anular cada una.

En la práctica esto ha creado dos problemas:

- **El manager tiene que intervenir en casi todas las bajas.** En KENYA hay 6 incidencias abiertas (09/11).
- **Hay líneas atascadas.** Una misma muestra puede estar afectada por dos bajas a la vez: la del panelista que la envía y la del que la recibe. Si el manager la anula en una incidencia, la línea de la otra se queda pendiente. Al pulsar Confirm sale el error "Sample … is cancelled and cannot be cancelled". Hay 13 líneas así, todas de KENYA.

Lo que quiere el usuario:

- **Al declarar la baja, el sistema decide él solo qué hacer con cada muestra afectada:** moverla o anularla. Nunca pide una decisión al manager.
- **La incidencia pasa a ser informativa.** Dice quién se ha dado de baja, en qué fechas, cuántos envíos y recepciones afecta, y qué se ha hecho con cada uno.

## 2. Objetivos, no-objetivos, anti-objetivos

**Objetivos**

1. Ninguna línea queda pendiente de decisión. Cada muestra afectada acaba en uno de estos estados:
   - **movida** (otra fecha, otro nodo o ambos), con estado `auto_resolved`;
   - **anulada**, con estado `auto_resolved` y `final_action='cancel'`;
   - **informativa**, con estado `info`.
2. Orden de resolución por muestra. Los pasos 1 y 2 son los de hoy; el 3 y el 4 son nuevos.
   1. Retrasar dentro del mes de la muestra, en el mismo nodo.
   2. Pasar a otro nodo de la misma ciudad dentro del mes, como hoy: primero la misma fecha y después otras fechas del mes.
   3. **Nuevo:** si no cabe en el mes, pasarla a la primera fecha laborable posterior en la que quepa sin saturar. Puede ser en el mismo nodo o en otro de la ciudad. El horizonte es de 8 semanas desde la fecha original. Es exactamente la propuesta que hoy calcula `incident_suggest` para el manager; ahora se aplica directamente.
   4. **Nuevo:** si no hay hueco en esas 8 semanas, anular la muestra.
3. Emisión y recepción siguen las reglas ya especificadas (spec del 20/10, 5.2):
   - una muestra `sent`/`received` no se toca;
   - si el panelista de baja es el receptor y el envío ya salió, la línea es informativa (`in_transit`);
   - si la recepción cae el último día de la baja, la línea es informativa (`back_before_arrival`).
4. **Muestra ya resuelta por otra incidencia.** Si la muestra ya está anulada, o ya se movió por otra baja, la línea nace o pasa a `info` con el motivo `handled_by_other_incident` y no da error.
   Además, cuando una incidencia anula o mueve una muestra, cualquier línea `pending` de esa muestra en otra incidencia se cierra igual.
5. Estado de la incidencia:
   - `auto_resolved` («Resuelta automáticamente») al terminar el motor;
   - `new` solo mientras no ha corrido.

   `pending_manager` deja de producirse. El valor se mantiene en el tipo para no romper datos antiguos.
6. Pantalla (`/incidents/panelist-availability`):
   - **Bandeja:** quitar «Pending manager decision» de los filtros. El filtro por defecto pasa a «All», ordenado por fecha de declaración, la más reciente primero. La columna «Pending» sale de la tabla. El badge del menú deja de contar incidencias pendientes (ya no hay) y pasa a mostrar las bajas declaradas en los últimos 7 días.
   - **Detalle:** cabecera igual que hoy (panelista, nodo, fechas, motivo, estado) más un resumen legible, por ejemplo «16 muestras afectadas: 3 retrasadas, 1 a otro nodo, 9 anuladas, 3 sin cambios». El bloque «Pending your decision» y los botones Confirm/Void desaparecen. Queda una sola tabla con todas las líneas: muestra, rol, fecha original, qué se hizo (nueva fecha y nodo, o anulada, o sin cambios y por qué) y cuándo.
   - Se mantienen el panel de carga de la ciudad, el arrastrar una muestra a otra casilla (`apply_sample_move`) y el campo «Resolución final». Así el manager puede corregir a mano una decisión automática si quiere.
7. Avisos por Telegram: sin cambios respecto al spec del 20/10 (5.5). Se avisa de los cambios que caen en la semana en curso a los panelistas afectados, incluidas las anulaciones de los pasos 3 y 4.

**No-objetivos**

- Cambiar los pasos 1 y 2, los umbrales de saturación (6 / 20 %) o la detección de muestras afectadas.
- Avisar al manager por correo o Telegram de cada baja. Ya lo cubre el informe de operación por cuenta (L-X-V).
- Cambiar n8n: la declaración de bajas por Telegram sigue igual.

**Anti-objetivos**

- Tocar una muestra `sent`/`received`.
- Mover una muestra a otra ciudad.
- Saturar un nodo para no anular: si no cabe sin saturar en 8 semanas, se anula.
- Que un fallo del motor impida declarar la baja o editar el plan (sigue siendo best-effort, con un WARNING).
- Dejar una línea `pending` en cualquier circunstancia. Si el motor falla en una muestra concreta, la línea queda `info` con el motivo `engine_error` y el mensaje del error, no `pending`.

## 3. Restricciones

- Una sola BD: **onems-dev `sehbnpgzqljrsqimwyuz`**, compartida con producción. La migración se confirma con el usuario antes de aplicarla.
- Migración forward-only nueva, validada antes en el Postgres local (5433) con tests en `supabase/tests/`.
- Frontend en `develop` (lint y build en verde) → PR a `main`, que fusiona el usuario.
- Textos nuevos en los 4 idiomas (`useTranslation()`).

## 4. Puesta al día de las incidencias abiertas (decidido por el usuario)

Al aplicar la migración, el sistema resuelve solo, con la regla nueva, todo lo que hoy está pendiente:

- **13 líneas atascadas** (la muestra ya está anulada desde otra incidencia): pasan a `info` con `handled_by_other_incident`. No se toca ninguna muestra.
- **12 líneas pendientes de Nancy Weru** (Embu, 09–13/11; 5 recepciones y 7 envíos): ninguna tiene hueco en las 8 semanas siguientes según `incident_suggest`, así que se anulan.
  - Las que caen esta semana generan el aviso de Telegram de siempre.
  - Una es del 09/11 y está `notified`; se anula igual que el resto, porque no ha salido.
- Las 6 incidencias de KENYA pasan a «Resuelta automáticamente».

Esta lista se recalcula justo antes de aplicar; los números pueden haber cambiado.

## 5. Datos y funciones (para el builder)

- `resolve_unavailability_incident`:
  - donde hoy deja la línea `pending` con la propuesta, aplica la propuesta (`incident_apply_change` en modo `auto`) o anula (`incident_apply_cancel` en modo `auto`);
  - si la muestra ya no está `pending`/`notified` por obra de otra incidencia, la línea pasa a `info`.
- `incident_apply_cancel` / `incident_apply_change`:
  - si la muestra ya está anulada y la acción es anular, cierran la línea en vez de dar error;
  - al aplicar, cierran también las líneas `pending` de la misma muestra en otras incidencias.
- `incident_recompute_status`: nunca devuelve `pending_manager`. Con 0 pendientes ya sale `auto_resolved` o `resolved`.
- `suggest_for_week`, `apply_manager_decision`, `suggest_for_cell` y `apply_manager_move`: se quedan en la BD (no estorban) pero la pantalla deja de usarlos.
- `incident_attention_counts` (badge del menú): deja de contar `pending_manager` para las bajas.
- Motivos nuevos en `suggested_reason`: `handled_by_other_incident`, `engine_error`, `shift_later_week`, `alt_node_later_week`. Los dos últimos ya existen; ahora aparecen también en líneas `auto_resolved`.

## 5b. Decisiones tras la revisión del builder (mías, revisables)

- **Disponibilidad del destino del traslado.** Ya está cubierta: `incident_node_fits` exige `is_node_available` en el nodo y la fecha nuevos. Por eso el paso 3 nunca asigna la muestra a un panelista que esté de baja ese día, sea el mismo panelista en una baja posterior u otro.
- **Muestra afectada por dos bajas (A = quien envía, B = quien recibe):**
  - `handled_by_other_incident` solo se usa cuando la muestra **ya está anulada**.
  - Si A la mueve y la nueva posición sigue cayendo dentro de la baja de B, la línea de B se reevalúa sobre la muestra ya movida y se resuelve con la misma regla: se mueve otra vez o se anula. Si la nueva posición ya no afecta a B, la línea `pending` de B se retira, como hace hoy el paso (a) del motor.
  - Para ello, `incident_apply_change` vuelve a ejecutar el motor de las demás bajas activas que cubren la posición antigua o la nueva de la muestra, con la guarda `onems.in_incident_engine` para que no entre en bucle.
- **Estado de la incidencia.**
  - Pasa a `auto_resolved` cuando el motor ha terminado y todas las líneas son automáticas o informativas.
  - Pasa a `resolved` si el manager ha cambiado alguna muestra a mano desde la pantalla, igual que hoy.
  - Rellenar «Resolución final» no cambia el estado.
- **Fallo del motor en una muestra.** Cada muestra se procesa en su propio subbloque `BEGIN…EXCEPTION`, que ya existe, así que el fallo no revierte las demás. La línea queda `info`, con `suggested_reason='engine_error'` y el mensaje en `resolution_note`, una columna que ya existe.
- **Badge del menú.** Cuenta las bajas con `created_at` en los últimos 7 días según `now()`, solo de la cuenta seleccionada. No se pone a cero al abrir la pantalla.
- **Muestras anuladas: no se recuperan** (decidido por el usuario). No se añade ninguna vía para reactivarlas. La corrección a mano solo vale para las que se movieron.
- **Avisos en la puesta al día.** Se envían. Se le dijo al usuario antes de que respondiera «resuélvelas tú».

## 6. Se deja al builder

- Diseño exacto de la tabla del detalle y del resumen legible.
- Nombres de claves i18n.
- Si las funciones del manager que ya no se usan se retiran ahora o más adelante.
