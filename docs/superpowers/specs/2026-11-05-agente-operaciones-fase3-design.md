# Agente de operaciones — Fase 3: arreglos autorizados por Telegram

Fecha: 2026-11-05 · Estado: borrador para aprobación del responsable.
Diseño base (vinculante salvo donde este documento lo amplía): `2026-11-05-agente-operaciones-design.md`.
Código: repo `panelist_n8n`, carpeta `ops-agent/` (fases 1 y 2 en `main`, desplegadas en Hetzner).

## 1. Para qué

Hoy, cuando algo falla, el agente lo detecta y lo explica en el informe, pero arreglarlo exige una
sesión de Claude Code. La fase 3 deja que el responsable **autorice desde Telegram arreglos
pequeños y conocidos**, que el agente aplica con red de seguridad: copia previa, prueba en DEV,
segunda confirmación para PROD y `deshaz`.

El responsable no es programador: lo que el agente le enseñe antes de autorizar tiene que poder
entenderse sin leer código (qué cambia, dónde, antes → después).

## 2. Objetivos

1. `autorizo N` aplica el arreglo N del informe más reciente (o de la última `revisa ahora`).
2. Dos tipos de arreglo autorizable:
   - **n8n sencillo**: cambio de parámetros en pocos nodos existentes de un flujo.
   - **Reparación de datos de una lista cerrada** (sección 5).
3. `deshaz N` devuelve todo lo que cambió el arreglo N a como estaba.
4. Nueva orden `revisa ahora`: revisión completa (incluidas las pruebas del bot) fuera de las 8:00.
5. Al día siguiente el informe dice si el problema arreglado ha desaparecido.

## 3. Fuera de alcance / prohibido (anti-objetivos)

- Crear, borrar, activar o desactivar flujos; crear o borrar nodos; cambiar conexiones entre nodos.
- Subir la frecuencia de un flujo de reloj (regla vigente).
- SQL libre, cambios de esquema, funciones, políticas RLS o permisos en la base.
- Tocar datos fuera de las reparaciones de la sección 5.
- Arreglar por Telegram cuando las copias DEV y PROD del flujo no coinciden (diseño base 13.7).
- Obedecer a cualquier chat que no sea el del responsable.
- Avisos espontáneos a mediodía: el agente solo habla a las 8:00 o cuando el responsable le
  escribe (preferencia ya expresada).

Sería un fracaso aunque "funcione": que un arreglo cambie algo distinto de lo que se enseñó, que
llegue a PROD sin el segundo sí, que `deshaz` no deje las cosas exactamente como estaban, o que
una reparación toque datos de otra cuenta.

## 4. Flujo de un arreglo n8n (decidido con el responsable)

1. En el informe (o en `revisa ahora`) cada problema autorizable lleva "→ autorizo N". El resto
   lleva "para sesión con Claude" (arreglos grandes, mixtos o que no encajan en las reglas).
2. `autorizo N`: el agente repite qué va a cambiar (flujo, nodo, campo, antes → después) y pide
   confirmar *(decisión de Claude: botón "Sí, aplicar en DEV" / "Cancelar", para que una
   autorización no sea un solo mensaje sin vuelta atrás)*.
3. Guarda copia completa del flujo DEV y del PROD, aplica el cambio en el flujo **[DEV]** y lo
   verifica (sección 6).
4. Si la verificación falla: restaura DEV desde la copia, lo dice, y no toca PROD.
5. Si sale bien: "DEV probado ✅, ¿lo paso a PROD?" (botones). **Segunda autorización obligatoria**
   (decisión del responsable, opción B).
6. Con el sí, aplica el mismo cambio a PROD y lo verifica igual. Si falla en PROD, restaura PROD y
   DEV y lo dice.
7. Ambas autorizaciones caducan con el siguiente informe de las 8:00 *(decisión de Claude)*.
8. `deshaz N` restaura DEV y, si llegó, PROD desde las copias *(decisión de Claude)*. Si alguien
   cambió el flujo después del arreglo (versión distinta de la que dejó el agente), no restaura y
   lo deja para sesión, para no pisar trabajo ajeno.

**"n8n sencillo"** *(acordado: prudente al empezar)*: como máximo 3 nodos de un único flujo,
solo parámetros de nodos existentes, sin cambiar credenciales, disparadores de reloj, conexiones
ni la lista de nodos. El cambio que propone la IA se guarda como datos estructurados (flujo,
nodo, ruta del parámetro, valor antes, valor después); el agente comprueba con código, no con IA,
que el cambio cumple estas reglas y que "antes" coincide con lo que hay ahora en DEV y en PROD.
Lo que se aplica es exactamente lo enseñado: la IA no vuelve a intervenir entre la autorización y
la aplicación. (Esto sustituye al "Opus aplica el arreglo" del diseño base: el modelo propone
una vez, el código aplica; el modelo de la tarea de proponer sigue siendo configurable.)

## 5. Reparaciones de datos (decidido con el responsable)

La base es **única para DEV y PROD** (onems-dev, `sehbnpgzqljrsqimwyuz`): no hay paso por DEV, así
que solo se permiten reparaciones preparadas y probadas de antemano, de una lista cerrada:

| # | Reparación | Qué cambia | Límites |
|---|---|---|---|
| R1 | Desatascar la conversación de un panelista con el bot | Borra su estado de conversación (`panelist_context`) | Un panelista; no toca envíos ni ficha |
| R2 | Asignar nodo a un panelista sin nodo | `node_id` de su ficha | Solo si no tiene nodo y su ciudad tiene un único nodo activo de su cuenta |
| R3 | Rellenar días sin envío de una ciudad POBOX | Fechas de envíos de esa ciudad, con el balanceo existente (`rpc_balance_city_v2`, fence = hoy, como el 5/11 en Moyale/Machakos/Nakuru) | Una ciudad que el aviso `pobox_no_send` señala; solo envíos pendientes |

Reglas comunes:
- Cada reparación es una **función de base de datos propia**, protegida con el token del agente
  (como `ops_test_*` de la fase 2). El agente **no** recibe service_role ni otra clave amplia.
- Cada función guarda el estado anterior de todo lo que toca (para R3, la fecha de cada envío
  movido) y tiene su función de deshacer, que solo deshace si los datos siguen como los dejó.
- La propuesta y la confirmación nombran la base (onems-dev `sehbnpgzqljrsqimwyuz`), la cuenta, la
  ficha o ciudad y el antes → después. Para R3: cuántos envíos se mueven y de qué días a qué días.
- Una sola autorización (no hay DEV): `autorizo N` → repite el cambio → botón "Sí, aplicar".
- Las funciones se crean con una migración que se aplica en una sesión de Claude Code con la
  confirmación de siempre. Añadir reparaciones nuevas a la lista = nueva sesión.
- El informe solo ofrece una reparación cuando la detecta un aviso del propio agente (p. ej.
  `pobox_no_send` → R3); la IA no inventa reparaciones fuera de la lista.

Descartadas por ahora: corregir `telegram_id` mal puestos (requiere el dato de una persona) y
deshacer declaraciones de envío/recepción (afectan a la medida E2E).

## 6. Verificación

- Arreglo n8n: el flujo cambiado queda válido y con la versión esperada; si el flujo forma parte
  de las pruebas del bot (fase 2), se pasa esa prueba con la cuenta de prueba contra el bot
  correspondiente (DEV o PROD). Si el flujo no tiene prueba que lo cubra, el agente lo dice al
  pedir la segunda autorización ("no he podido probarlo en DEV más allá de que el flujo es
  válido") y el responsable decide.
- Reparación de datos: releer el dato y comprobar que quedó como se anunció (y para R3, que
  `pobox_no_send` ya no señala esa ciudad).
- Al día siguiente, el problema arreglado debe salir como *resuelto*; si sigue, sale como *sigue*
  con nota "se aplicó el arreglo N el día X".

## 7. `revisa ahora`

Revisión completa como la de las 8:00 (n8n, pruebas del bot, avisos de operativa) y respuesta con
el mismo formato numerado. Máximo 3 al día *(decisión de Claude, por gasto de ejecuciones n8n)*.
Sus números de arreglo valen hasta la siguiente revisión o informe.

## 8. Restricciones heredadas

- `pausa` detiene también arreglos y `revisa ahora`.
- Registro de todo (qué se propuso, quién autorizó y cuándo, qué cambió, resultado, deshacer).
- Copias de flujos en el servidor, dentro de la copia de seguridad diaria del agente.
- Nunca claves en los mensajes; de los panelistas solo código y nombre.
- La sesión de Telegram de prueba sigue sin ir a las copias de seguridad.
- La futura migración de n8n a Hetzner cambia ids de flujos: el emparejamiento DEV↔PROD no debe
  depender de ids fijos escritos a mano.

## 9. Decisiones de Claude tras la revisión (revisables por el responsable)

1. **Vida de las autorizaciones.** El primer `autorizo` caduca con el siguiente informe de las 8:00.
   El segundo sí (pasar a PROD) dura **24 h desde que DEV quedó probado**. Si caduca sin respuesta,
   el agente **restaura DEV** desde la copia y lo dice, para que DEV y PROD vuelvan a coincidir.
   Mientras un arreglo está a medias (DEV cambiado, PROD no), no se ofrece otro arreglo sobre el
   mismo flujo. Cada arreglo es un registro con estado persistente
   (propuesto → DEV aplicado → PROD aplicado | caducado | deshecho | fallido).
2. **"Flujo válido"** = el flujo se relee de n8n tras el cambio, tiene exactamente el valor nuevo
   en el parámetro cambiado, el resto del flujo es idéntico a la copia y pasa la validación
   estructural. **El agente no ejecuta a mano flujos de reloj en DEV**: la base es compartida y
   podrían escribir datos o mandar mensajes reales. Para flujos sin prueba del bot, la segunda
   autorización avisa de que solo se ha comprobado que el flujo es válido.
3. **Bot DEV.** La base es compartida y el bot identifica al panelista por su Telegram, así que el
   panelista de prueba sirve también para el bot DEV. Paso único del responsable: pulsar Start en
   el bot DEV con su cuenta. El agente admite como interlocutor solo esos dos bots, por usuario
   fijo en la configuración.
4. **Escritura en n8n.** Se envía el flujo entero modificado (PUT). Justo antes se relee el flujo y
   se comprueba que su versión es la que se copió; si alguien lo ha tocado entretanto, no aplica.
   Las copias completas (sin tapar claves, porque hacen falta para restaurar) viven solo en el
   servidor, carpeta del agente con permisos 0700, dentro de su copia de seguridad diaria;
   nunca en el repo.
5. **Origen de los arreglos n8n.** Se amplía el diagnóstico actual (`diagnose.py`): además de la
   explicación, la IA devuelve el cambio estructurado (sección 4) o "no autorizable". El código
   decide si es "sencillo". La huella del problema no cambia al arreglarlo; el registro del
   arreglo guarda esa huella para la nota "se aplicó el arreglo N el día X".
6. **Reparaciones de datos.** Mismo mecanismo de acceso que la fase 2 (funciones con el token del
   agente como parámetro). R3 hace la copia de las fechas y llama al balanceo **dentro de la misma
   función**, en una sola transacción (sin carreras), y devuelve los envíos movidos (antes →
   después). Solo mueve envíos en estado `pending`. R2 usa el esquema real (`panelists.node_id`,
   nodos activos de la misma ciudad y cuenta); si hay más de un nodo, no se ofrece.
   **R1 no tiene deshacer**: borra un estado de conversación atascado y volver a ponerlo no tiene
   sentido; la confirmación lo dice.
7. **`revisa ahora`.** El tope de 3 al día no cuenta el informe de las 8:00. Cada revisión
   renumera los problemas; los arreglos ya autorizados y en curso conservan su propio número de
   arreglo para `deshaz`. Sus datos de prueba usan el mismo mecanismo de la fase 2 (preparar,
   probar, limpiar en cada pasada).

## 10. Lo que queda al constructor

- Cómo emparejar cada flujo PROD con su [DEV] y comparar que "coinciden" (ignorando ids/credenciales
  propias de cada copia).
- Cómo la cuenta de prueba habla también con el bot DEV (la fase 2 solo permite el bot PROD como
  interlocutor; añadir el DEV de forma igual de estricta).
- Forma de los botones y textos exactos, en español llano.
- Diseño de las tablas de copia/registro y de las funciones R1–R3 y sus deshacer.
- Pruebas: cada regla de la sección 4 y 5 con su test; simulacro en DEV de un arreglo y su deshacer.
