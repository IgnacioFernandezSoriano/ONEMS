# Agente de operaciones: análisis de casos concretos

**Fecha:** 2026-11-10
**Estado:** borrador para revisión del usuario
**Amplía:** `2026-11-05-agente-operaciones-design.md` (y sus fases 2 y 3). Todo lo que aquí no se contradice sigue vigente.

---

## 1. Intención

A veces el gestor tiene que investigar un caso concreto que ha salido mal. Hoy lo hace a mano: consulta el plan, averigua quién debía enviar, cuándo, a quién y en qué plazo, mira qué ha pasado en realidad, piensa la causa, decide a quién escribir y redacta los mensajes.

Se quiere que el agente de operaciones haga ese trabajo y devuelva dos cosas:

1. **Para el gestor:** el análisis completo y, si hay alguna, una mejora que evite que el problema se repita.
2. **Para cada panelista implicado:** un mensaje redactado en el idioma de la cuenta. Sale por el bot de los panelistas solo cuando el gestor lo aprueba.

### Caso real de referencia (10/11, KENYA)

Samwel (PAN-KEN-053, Kericho) intenta registrar la etiqueta **00011844**. El bot le contesta *"belongs to a parcel addressed to another city"*. Además le dice que ya tiene una baja que se solapa.

El análisis encontró lo siguiente:

- **Plan:** la etiqueta iba de Arbe Roba (PAN-KEN-048, Marsabit) a James Ngei (PAN-KEN-039, JKIA). Fecha prevista: 27/10. Producto SMALL PACKETS EXPRESS de KENYA POST, con un SLA de 6 h entre Marsabit y JKIA.
- **Realidad:**
  - Arbe declaró el envío el 30/10, 3 días tarde.
  - El sobre lleva escrito el nombre de Samwel.
  - Arbe tenía que mandar a Samwel 3 sobres más ese mismo mes (11846, 11848 y 11850).
  - Ninguno de los 4 sobres consta como recibido.
  - El caso de recepción `other_city_tag` lleva 4 días abierto sin decisión.
- **Causa probable:** error en origen. Arbe escribió la dirección equivocada.
- **Ruido:** el aviso de solape no es un fallo. Samwel ya tenía declarada una baja del 09 al 16/11.

Este caso sirve como prueba de aceptación (apartado 7).

## 2. Objetivos, no-objetivos, anti-objetivos

**Objetivos**

1. **Dos puertas de entrada, un mismo análisis.**
   - **Telegram:** el gestor reenvía la conversación al bot del agente de operaciones (capturas, mensajes reenviados o texto). Añade el nombre o el usuario de Telegram del panelista si no se ve en lo reenviado. Así le llega hoy, desde el grupo de panelistas de cada cuenta.
   - **ONEMS:** botón «Analizar caso» en el detalle de una incidencia (`/incidents/receipts`, `/incidents/panelist-reported`, `/incidents/panelist-availability`). La incidencia ya identifica la cuenta, el panelista y la etiqueta, así que no hay que reenviar nada.
2. **Contenido del análisis:**
   - **Plan:**
     - remitente, destinatario y nodo/ciudad de cada uno;
     - fecha programada;
     - **producto del plan y su SLA exacto**, según la norma de entrega del producto y el par de ciudades origen-destino. Hay varias normas por par de ciudades y la que cuenta es la del producto.
   - **Realidad:**
     - fecha declarada de envío;
     - recepción, si la hay, y quién la registró;
     - intentos del bot y casos de recepción;
     - incidencias abiertas;
     - bajas.
   - **Comparación:** días de retraso en el envío, horas o días fuera de SLA, y si el sobre se ha perdido o se ha desviado.
   - **Causas probables**, ordenadas de más a menos probable, cada una con la prueba en la que se basa. Por ejemplo: "Arbe tenía 3 sobres para Samwel y 1 para James en las mismas fechas".
   - **Ruido:** los mensajes de la conversación que no son un fallo se explican aparte. Por ejemplo, el aviso de baja que se solapa.
   - **A quién contactar y para qué.**
   - **Mejora propuesta** para el gestor, si el agente ve alguna: un cambio de proceso, de bot o de informe. Si no la hay, no la inventa.
3. **Mensajes a panelistas.** Uno por panelista implicado, cuando tenga sentido: el que envió, el que lo recibió y el destinatario previsto. Cada mensaje:
   - va en el idioma de la cuenta;
   - es conciso, sencillo y claro, con un tono constructivo y positivo;
   - **siempre agradece** al panelista su actividad e implicación;
   - explica qué pasó en una o dos frases;
   - da instrucciones precisas de qué hacer ahora, si toca;
   - si el error fue suyo, da un consejo concreto para que no se repita;
   - nunca culpabiliza.
4. **Envío con el OK del gestor, mensaje a mensaje.**
   - En Telegram, cada mensaje lleva un botón «Enviar a <nombre>».
   - En ONEMS, cada mensaje se puede retocar antes de pulsar Enviar.
   - Sale por el bot de los panelistas (`@one_for_panelist_bot`), el canal que ya usan los managers.
5. **Todo queda registrado en la incidencia:**
   - el análisis, como nota interna;
   - cada mensaje enviado;
   - las respuestas del panelista.

   Se usa `incident_message`, que ya guarda bot, panelista, manager y sistema. Si el caso entra por Telegram y no tiene incidencia, se asocia al caso de recepción o a la incidencia que corresponda. Si no hay ninguna, queda guardado en el agente.

**No-objetivos**

- Que el agente cambie datos (plan, estados, bajas, casos) desde el análisis. Si propone cerrar un caso, el gestor lo hace en ONEMS como hoy.
- Analizar casos de forma automática, sin que el gestor lo pida.
- Leer el grupo de panelistas por su cuenta. Solo analiza lo que el gestor le pasa.

**Anti-objetivos**

- Que salga un mensaje a un panelista sin el OK explícito del gestor.
- Escribir a un panelista de otra cuenta, o mezclar datos de cuentas en un análisis.
- Afirmar como hecho lo que es una hipótesis. Las causas van marcadas como «probable» y con su prueba.
- Que, si el panelista no se puede identificar sin dudas, el agente adivine: pregunta al gestor.
- Mensajes largos, técnicos o con tono de reproche.

## 3. Restricciones

- Base de datos: **onems-dev `sehbnpgzqljrsqimwyuz`**, la misma de producción. Toda migración se confirma con el usuario antes de aplicarla y se valida antes en el Postgres local (5433).
- El agente vive en el servidor Hetzner (`panelist_n8n/ops-agent`). Lee la base como hoy, con funciones protegidas por token y la clave pública. **Nunca con service_role.**
- Modelos, como en el resto del agente: Sonnet para el análisis y Haiku para redactar o traducir si conviene.
- Frontend: rama `develop` (lint y build en verde) → PR a `main`, que fusiona el usuario. Textos nuevos en los 4 idiomas.
- n8n: primero [DEV].

## 4. Decisiones del usuario

- Ningún mensaje sale sin su OK.
- Se escribe a cada panelista implicado: al que envió si el problema está en origen, al que recibió y, si hace falta, al destinatario previsto.
- El análisis debe proponer una mejora de proceso si la hay.
- El SLA se saca del producto del plan.
- El panelista se identifica por su nombre de usuario de Telegram, porque lo reenviado viene del grupo de panelistas de cada cuenta.

## 4b. Decisiones tras la revisión del builder (mías, revisables)

- **Canal de envío.** Se reutiliza el de los managers, que ya funciona:
  1. Se inserta una fila `incident_message` con dirección `outbound`, autor `manager` y estado `pending_send`.
  2. El disparador de la base llama al webhook «Push from ONEMS» de n8n (`deliver-incident-messages`), que la envía por el bot de panelistas.

  El agente no guarda el token del bot de panelistas. Las respuestas del panelista ya se guardan como `inbound` en las incidencias `reported` y `unavailability`. Los casos de recepción hoy no tienen tipo en `incident_message`: se añade (`incident_kind='receipt'`, ligado a `receipt_case`), junto con la captura de respuestas en el flujo de n8n correspondiente, primero en [DEV].
- **Identificación del panelista.** La base guarda solo el `telegram_id` numérico del panelista, **no su nombre de usuario de Telegram**.
  - El agente busca por el nombre que se ve en Telegram (por ejemplo «Samwel Mettet») entre los panelistas de la cuenta, apoyándose en la etiqueta para confirmarlo: Samwel tiene un caso abierto con 00011844.
  - Si queda más de un candidato, o ninguno, pregunta al gestor.
  - Guardar el usuario de Telegram cuando el panelista escribe al bot sería una mejora aparte.
- **Idioma.** Cada mensaje va en el idioma del panelista (`panelists.language`) y, si no lo tiene, en el de la cuenta. El árabe se escribe de derecha a izquierda.
- **Disparo desde ONEMS.** El botón crea una petición en una tabla de cola, el agente del servidor la recoge y escribe allí el resultado, y la pantalla lo muestra al terminar. No se abre ninguna puerta nueva en el servidor y no hay límite de tiempo de una edge function.
- **Datos que ve la IA.** Nombres y etiquetas reales: hacen falta para redactar los mensajes y el proveedor es el mismo del informe de operación. Las claves y los teléfonos se tapan como hoy (`masking.py`).
- **Retocar en Telegram.** Cada mensaje tiene, además de «Enviar», un botón «Cambiar». El gestor escribe qué cambiar y el agente lo redacta de nuevo. Retocar el texto a mano solo se puede en ONEMS.
- **Dónde queda el análisis.** Se guarda como nota interna (`internal`, autor `system`) en la incidencia o el caso. Si no hay ninguno, solo en el agente, durante 30 días, igual que los detalles de las pruebas.

## 5. Se deja al builder

- Cómo reconoce el agente las capturas (lectura de imagen) frente a los mensajes reenviados.
- La función de lectura del caso: qué datos devuelve en una sola llamada (plan, recepción, casos, incidencias, bajas, normas de entrega).
- Cómo se dispara el análisis desde ONEMS: una edge function o una llamada al agente; el resultado se muestra en el detalle.
- Diseño de la tarjeta del análisis en ONEMS y en Telegram.
- Qué tipo de incidencia (`incident_kind`) usan los casos de recepción en `incident_message`, si aún no lo tienen.
- Añadir la sección «Análisis de casos» al playbook (`playbook/revisiones.md`), explicada en lenguaje llano.

## 6. Ideas de mejora detectadas en el caso de referencia (fuera de alcance, para decidir aparte)

- Al declarar un envío, el bot recuerda al remitente el nombre y la ciudad que deben ir escritos en el sobre de esa etiqueta, y le pide confirmarlo.
- El informe diario de las 8:00 avisa de los casos «etiqueta de otra ciudad» que llevan más de 2 días sin decidir.

## 7. Aceptación

- Con el caso 00011844 (entrando por Telegram con las dos capturas y "Samwel Mettet", y también desde ONEMS) el análisis da:
  - el plan correcto, con el SLA de 6 h de SMALL PACKETS EXPRESS;
  - los 3 días de retraso en el envío;
  - la causa probable en origen;
  - el aviso de solape explicado como ruido;
  - mensajes para Arbe, Samwel y James en inglés.
- Ningún mensaje sale sin pulsar Enviar. Una vez enviado, aparece en la conversación de la incidencia.
- Las pruebas usan DEMO2 o datos simulados. Nunca se escribe a un panelista real durante las pruebas.
