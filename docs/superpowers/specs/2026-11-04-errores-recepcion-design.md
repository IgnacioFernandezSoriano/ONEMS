# Registro y tratamiento de errores de recepción — diseño

Fecha: 2026-11-04 · Estado: pendiente de aprobación

## 1. Intención

Los panelistas declaran recepciones por el bot de Telegram (flujo n8n «Mark Parcel as received»,
nodo SQL «Find and mark received»). Cuando algo falla, el bot contesta y **no queda rastro**: el
responsable del país no sabe qué ha pasado, el problema no se corrige y la muestra se pierde en
silencio. Caso real 2026-11-04 (Kenya): Angie Gikonyo pegó la etiqueta 00010884 y declaró 00010894;
Cathy Jelimo Koech no podía registrar el paquete y además no había declarado su envío del 3/11 (regla
POBOX).

Queremos:
1. **Registrar cada intento de recepción fallido** en una tabla, para analizar qué pasó.
2. Que **el sistema intente arreglarlo solo**. Si lo arregla, la recepción vale con la **fecha del
   intento**; si no se puede arreglar, la muestra pasa a **compensar** (tabla `deferred_samples`
   existente, spec 2026-10-28-muestras-por-compensar).
3. Que el **responsable de cada país** siga cada día cómo va, por qué falla, quién repite, y pueda
   escribir a un panelista concreto o lanzar un aviso general.
4. Que el **panelista causante** reciba recordatorios automáticos mientras siga cometiendo el error.

Éxito = ningún fallo de recepción se pierde sin dejar rastro; cada uno termina «arreglado» o «por
compensar» (o, si el sistema no sabe, pendiente de decisión del responsable); los fallos repetidos
bajan con los avisos.

## 2. Decisiones del usuario (2026-11-04)

- Lo revisa **el responsable de cada país, desde la web**. El sistema debe intentar arreglarlo solo.
- **El paquete llegó pero el remitente no había declarado el envío** → se anula y se compensa.
- **El paquete es para otro destino**: si el nodo real es de **la misma ciudad** → la recepción vale;
  si es de otra ciudad → ~~se anula y se compensa~~ **(cambiado 2026-11-04 tras prueba real)**: no se toca el
  envío (puede ser un tecleo que acierta un envío sano de otra ciudad); el caso queda pendiente de decisión del
  responsable, sin causante ni recordatorio (outcome `other_city_tag`).
- El seguimiento es **solo en pantalla**; el resumen diario de las 9:00 no cambia.
- Recordatorios automáticos al panelista **mientras siga fallando**, hasta que deje de cometer el error.

Decisiones mías (marcadas para revisión del usuario):
- **[mía]** Etiqueta mal tecleada: el sistema corrige solo si hay **un único candidato**; con varios, decide el responsable.
- **[mía]** Recordatorios: máximo **uno al día por panelista y motivo**; desde el **3.er fallo en 7 días** el mensaje dice que su responsable está informado.
- **[mía]** La pantalla es una **pestaña nueva «Recepciones» en el menú Incidencias** existente.

## 3. Motivos y tratamiento automático

Cada intento fallido se clasifica con el mismo criterio que hoy usa el nodo «Receipt response»
(`kind`), más los casos nuevos. El **causante** es el panelista al que se atribuye el fallo (para
estadísticas y recordatorios).

| Motivo (código) | Detección | Tratamiento automático | Resultado | Causante |
|---|---|---|---|---|
| `invalid_format` | etiqueta no válida | ninguno (el panelista reintenta) | informativo | destinatario |
| `typo_fixed` (antes `not_found`) | etiqueta no existe; hay **un único** envío `sent` hacia el nodo (o la ciudad) del panelista cuya etiqueta difiere en **1 dígito** o en **2 dígitos adyacentes intercambiados** | corrige `tag_id`/`idtag` del envío y registra la recepción con `received_at` = hora del intento | arreglado | **remitente** del envío |
| `not_found` | etiqueta no existe y sin candidato único | se reintenta la búsqueda (incl. la regla de typo) en cada declaración de envío nueva y cada día durante **N días** (constructor; propuesta 5 laborables). Si aparece → arreglado con la fecha del intento | pendiente → arreglado o **pendiente de decisión** | sin atribuir hasta resolverse |
| `ambiguous_typo` | varios candidatos | ninguno | pendiente de decisión | sin atribuir |
| `not_sent` | el envío existe pero está `pending`/`notified` (remitente no lo declaró) | se **anula** y se registra en `deferred_samples` (motivo nuevo `receipt_before_sent`) | por compensar | **remitente** |
| `other_dest_same_city` | el envío va a otro nodo de la **misma ciudad** | registra la recepción con la hora del intento y anota el nodo/panelista real que lo recibió | arreglado | remitente (informativo) |
| `other_city_tag` (antes `other_dest_other_city`) | el envío va a otra ciudad | ninguno: el envío no se toca (cambio 2026-11-04) | pendiente de decisión | — |
| `pobox_absent_*` | la regla POBOX anula la recepción (trigger `pobox_receipt_rule`, ya va a `deferred_samples`) | ninguno extra; se apunta aquí para el seguimiento | por compensar | destinatario |
| `blocked` | envío cancelado / con incidencia abierta por otra causa | ninguno | informativo (ya tratado por su incidencia) | — |
| `already_received` | ya recibido | ninguno | informativo | — |
| `no_panelist`, `no_node` | ficha no encontrada / sin punto | ninguno | pendiente de decisión | — (problema de configuración) |

Reglas comunes:
- **Fecha del intento**: cuando un caso se arregla (solo o por el responsable), `received_at` = el
  momento del primer intento del panelista, no el del arreglo.
- Toda recepción arreglada pasa igualmente por la regla POBOX (el trigger ya existe): puede acabar
  anulada y compensada, y eso se refleja en el registro.
- Un mismo panelista que reenvía la misma etiqueta varias veces = **un solo** caso (se cuentan los
  intentos dentro del caso).
- Ningún fallo del registro puede romper la recepción del bot (fail-open, como los triggers existentes).

## 4. Registro (tabla nueva)

Una fila por caso: cuenta (`account_id`, RLS por cuenta), panelista que lo intentó, etiqueta tal como
la escribió y normalizada, primer y último intento, nº de intentos, motivo, causante, envío
relacionado (si lo hay), estado (`pending` / `fixed` / `compensated` / `informative` /
`needs_decision`), quién y cuándo lo resolvió (sistema o usuario), nota. Los detalles de columnas e
índices quedan al constructor.

## 5. Pantalla «Recepciones» (menú Incidencias)

Solo el responsable de cada país (y superadmin), solo datos de su cuenta, en los 5 idiomas.

1. **Resumen del día** (selector de fecha): intentos, bien a la primera, arreglados por el sistema,
   pasados a compensar, pendientes de decisión; reparto por motivo; gráfica de 30 días.
   «Bien a la primera» sale de las recepciones correctas del día (no hace falta registrarlas en la tabla nueva).
2. **Panelistas con problemas repetidos**: ordenados por fallos en 7 y 30 días, con motivo principal,
   atribuidos al **causante**; muestra si ya se le avisó y cuándo.
3. **Pendientes de decisión**: cada caso con «Arreglar» (corregir etiqueta o destino → recepción con
   fecha del intento) o «Pasar a compensar». Queda quién decidió y cuándo.

## 6. Avisos

- **Recordatorio automático** al causante en cada fallo atribuible, por Telegram, en su idioma,
  explicando el error y qué hacer (con las reglas de la decisión [mía] de §2).
- **Mensaje a un panelista** desde la lista de repetidores: texto preparado según su motivo, editable,
  en su idioma; queda en su historial.
- **Aviso general** a todos los panelistas activos del país: plantillas (p. ej. la lección del POBOX)
  en los 5 idiomas, editable, muestra nº de destinatarios y pide confirmación; registra fecha, texto,
  enviados y fallidos.
- Envío por la cola existente `panelist_notification` + flujo n8n «Deliver panelist notifications»
  (decidido al planificar: `incident_message` exige una incidencia y abre una conversación pendiente
  con el panelista por cada mensaje, efecto no deseado para recordatorios y avisos generales).

## 7. Bot

- La respuesta al panelista dice el **motivo real** y qué hacer, en lugar del genérico «contacta con
  tu gestor».
- Corregir el hueco actual: si la regla POBOX anula la recepción, el bot **no** debe decir
  «✅ recibido» (hoy `registered` es true porque el UPDATE devuelve la fila antes de ver el estado final; verificar).
- n8n: [DEV] primero, luego PROD.

## 7 bis. Decisiones tras la revisión del documento [mías, para revisión del usuario]

1. **Quién es el responsable**: el rol `admin` de la cuenta (más `superadmin`), igual que las pestañas
   actuales de Incidencias (`ProtectedRoute allowedRoles={['superadmin','admin']}`). RLS por `account_id`.
2. **Arquitectura**: una **función de BD** hace en una sola transacción la clasificación, el arreglo
   automático, el registro del caso y la respuesta (motivo final, incluido el resultado de la regla
   POBOX tras el trigger). El nodo SQL del bot la llama y solo pinta el mensaje. Fail-open: si el
   registro falla, la recepción se comporta como hoy.
3. **Reintentos de `not_found`**: en BD — al declararse un envío nuevo (trigger) y una pasada diaria
   con pg_cron durante 5 días laborables; después pasa a «pendiente de decisión». Si se resuelve como
   typo, el causante es el **remitente**.
4. **`other_dest_same_city`**: se **cambia el destino** del envío al nodo/panelista que lo recibió de
   verdad, guardando el original en `original_destination_node_id` (columna existente). La medida E2E
   es entre ciudades y no cambia.
5. **Compensación**: las muestras anuladas van a `deferred_samples` como hoy. `reason` tiene un CHECK
   (corregido 2026-11-04 al planificar): se amplía, igual que `allocation_plan_details.cancellation_reason`,
   con `receipt_before_sent` y `received_wrong_city`. El motor de reintroducción no distingue motivos.
6. **Recordatorios**: se genera uno por fallo atribuible, pero se envía **como máximo uno al día por
   panelista y motivo**. Fuera de 08:00–20:00 hora local de la cuenta, se aplaza a las 08:00.
7. **Búsqueda de typo**: solo dentro de la **misma cuenta**, entre envíos `sent` cuyo destino es la
   **ciudad** del panelista (coherente con la regla de misma ciudad).

## 8. Fuera de alcance

- Cambiar la regla POBOX en sí.
- Fallos de **declaración de envío** (solo recepción en esta fase).
- Recuperar los fallos pasados (no se registraron); como mucho, cargar a mano los casos conocidos.

## 9. Lo que queda al constructor

Nombres de tabla/columnas, N días de reintento de `not_found`, algoritmo exacto de similitud (dentro
de la regla de §3), textos de los mensajes, diseño visual de la pestaña, canal técnico de envío.
