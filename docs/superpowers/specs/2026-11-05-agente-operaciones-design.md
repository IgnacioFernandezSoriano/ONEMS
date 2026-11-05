# Agente de operaciones de ONEMS — diseño

Fecha: 2026-11-05 · Estado: borrador para aprobación del responsable

## 1. Para qué

Hoy el responsable se entera de los fallos de la app de panelistas (bot de Telegram + flujos n8n)
cuando un panelista se queja en su grupo de Telegram. Quiere un **agente propio** que cada mañana
revise y pruebe la operativa, le cuente en Telegram qué falla, por qué y cómo se arreglaría, y
que aplique el arreglo **solo cuando él lo autorice**. El agente crecerá poco a poco mediante un
**playbook** que se irá definiendo juntos (nuevas comprobaciones, nuevos arreglos, otros módulos).

El responsable no es programador: todo lo que el agente escribe va en español llano, primero el
resultado y luego el detalle.

## 2. Objetivos

1. **Informe diario a las 8:00 hora de Madrid** (Europe/Madrid, sigue el horario de verano),
   enviado por un **bot de Telegram propio del agente**, distinto del bot de panelistas.
2. **Revisión de lo ocurrido**: todas las ejecuciones de las últimas 24 h de los flujos n8n de la
   app de panelistas (PROD y [DEV]).
3. **Prueba activa** cada mañana, antes del informe, con el **panelista de prueba de DEMO2**
   (Ignacio Catorce): recorre los procesos como lo haría un panelista y comprueba que la
   respuesta es la correcta.
4. **Detección de actividad anómala basada solo en datos objetivos** (nunca leyendo conversaciones
   de grupos). "Anómalo" es lo que sufre el panelista:
   - el bot **no le contesta** (mensaje entrante sin respuesta, ejecución cortada a medias);
   - le dice que **no se ha registrado** lo que declaró;
   - le responde algo **fuera de lo normal** al declarar envío/recepción o pedir la lista de paquetes;
   - además: picos de "código no encontrado", un país que deja de declarar, procesos de reloj que
     no se ejecutaron.
5. **Para cada fallo**: qué falla, causa, arreglo propuesto, con un número para autorizarlo.
6. **Arreglos solo con autorización**, por dos vías: contestando en el chat del agente o en una
   sesión de Claude Code con el responsable.
7. **Playbook ampliable** y versionado.

## 3. No-objetivos (v1)

- Avisos en tiempo real durante el día. El responsable se entera por el grupo como hoy; el agente
  solo habla a las 8:00 (más las respuestas a sus órdenes y la alarma de "no hay informe").
- Leer el grupo de Telegram de panelistas o cualquier conversación.
- Cambios en la base de datos desde Telegram.
- Escribir a panelistas reales.
- Módulos de ONEMS distintos de la app de panelistas (vendrán vía playbook).

## 4. Anti-objetivos (sería un fracaso aunque "funcione")

- Que toque producción sin una autorización explícita del responsable.
- Que el silencio se confunda con "todo bien" (si el agente muere, tiene que notarse).
- Que dé falsas alarmas a diario y el responsable deje de leerlo.
- Que repita cada día el mismo fallo como si fuera nuevo.
- Que dispare el gasto de IA o el límite de ejecuciones de n8n.
- Que deje basura de pruebas mezclada con datos reales (Kenia, Senegal).

## 5. Contexto técnico que el constructor debe conocer

- **n8n Cloud** `https://upu-one.app.n8n.cloud` (plan Pro, **10.000 ejecuciones/mes**, ~5.500 usadas
  a 28/10). Hay una **migración pendiente a n8n propio** en el servidor Hetzner (ya instalado, n8n
  2.45.5, sin fecha de corte): la URL y la clave de n8n deben ser configurables.
- 55 workflows; ~35 activos (PROD + [DEV]). Principales: PROD `Telegram - User initiated message`
  `IkVtek2csP5AbWxB`, DEV `eeM4E4RS1UDThvUF`; subflujos (Mark Parcel as received/sent, Parcels to
  send/receive, Process tag/send photo, Save parcel selection, etc.) y flujos de reloj (Deliver
  panelist notifications, Deliver incident messages/replies, Notify unread incident replies,
  On parcel not received, On new parcel to send, Material questions…). La revisión del 05/11 que
  originó esta idea es el modelo del informe: errores por flujo, nodo, causa, panelista afectado,
  y última ejecución de cada flujo de reloj.
- 9 workflows apuntan a un errorWorkflow inexistente (`GL0zZodVtQDuVHO2gu_qJ`).
- **Base de datos**: una sola Supabase, `onems-dev` (ref `sehbnpgzqljrsqimwyuz`), compartida por
  PROD y DEV. Multi-cuenta por `account_id` (RLS). DEMO2 es la cuenta de pruebas.
- Hay dos bots de panelistas (PROD y DEV) con webhooks hacia n8n.
- **Servidor Hetzner** CX33 (`ubuntu-8gb-fsn1-3`, Ubuntu 26.04), compartido con los scrapers del
  responsable (no tocarlos) y con SSH también en el 443 vía `sslh` (no tocarlo). Acceso como
  usuario `ignacio`.
- Reglas vigentes del proyecto que el agente hereda: DEV antes que PROD en n8n; nunca subir la
  frecuencia de los flujos de reloj; claves tapadas en las copias de workflows del repo
  `panelist_n8n`; nunca mostrar claves.

## 6. Decisiones del responsable

1. Es un **agente** (no un flujo n8n fijo), que crece con un playbook definido juntos.
2. Tiene **bot de Telegram propio**.
3. Hace **las dos cosas**: revisar lo ocurrido y probar activamente con el panelista de prueba.
4. Autorización **por Telegram y por sesión de Claude Code**.
5. Anomalías **solo por datos objetivos**.
6. Sin avisos en tiempo real.
7. Acepta todos los guardarraíles y medidas de fiabilidad de las secciones 7 y 8.
8. Acepta el reparto de modelos por tarea de la sección 9 y que el diseño permita otros proveedores.
9. **Reside en el servidor Hetzner.**
10. **Pruebas con una cuenta de Telegram real**: el agente usa desde el servidor la cuenta de
    Telegram del panelista de prueba (Ignacio Catorce) como cliente de usuario (MTProto), y habla
    con el **bot de panelistas de PROD**, como un panelista más. Requiere un número de teléfono
    para esa cuenta y un primer inicio de sesión con código, que hace el responsable.
11. **Permiso permanente para datos de prueba en DEMO2**: cada mañana el agente puede crear los
    paquetes de prueba que necesite y borrarlos después en `onems-dev` (`sehbnpgzqljrsqimwyuz`),
    **solo en la cuenta DEMO2 y solo para el panelista de prueba**. Es la única escritura en BD
    que hace sin preguntar.
12. **Clave de API de Anthropic propia del agente**, con el límite de gasto mensual puesto en la
    consola de Anthropic (además del tope en el código).

## 7. Guardarraíles (aprobados)

1. **Solo obedece al responsable**: se ignora cualquier mensaje que no venga de su chat id de Telegram.
2. **Autorización explícita y con caducidad**: "autorizo N" vale solo para el arreglo N del
   informe de ese día. Antes de aplicar, el agente repite qué va a cambiar.
3. **Pausa**: "pausa" detiene pruebas y arreglos hasta "sigue".
4. **Copia antes de cada cambio** y **"deshaz N"** para volver atrás en un paso.
5. **Siempre DEV primero**; si la verificación en DEV falla, se detiene y no toca PROD.
6. **Desde Telegram solo arregla workflows de n8n.** Cualquier cambio en la base de datos se hace
   en una sesión de Claude Code con la confirmación de siempre (nombrar `onems-dev`
   `sehbnpgzqljrsqimwyuz`). Única excepción: los datos de prueba de DEMO2 (decisión 6.11).
7. **Nunca borra datos reales** ni sube la frecuencia de flujos de reloj.
8. **Las pruebas solo usan el panelista de prueba de DEMO2**; nunca escribe a panelistas reales
   ni toca datos de Kenia u otros países reales. Si no logra limpiar lo que creó, lo dice.
9. **Alarma si el agente no aparece**: si a las 8:30 no hay informe, n8n avisa al responsable.
10. **Registro** de todo: qué revisó, qué probó, qué cambió, quién y cuándo lo autorizó.
11. **Nunca pone claves** en los mensajes; de los panelistas solo código y nombre.

## 8. Fiabilidad (aprobado)

1. **Independiente de lo que vigila**: el agente y su bot no viven en n8n. Vigilancia cruzada:
   el agente revisa n8n; n8n da la alarma de las 8:30 si el agente no ha informado. Cuando n8n se
   migre al mismo servidor, se añade un **vigilante externo gratuito** (tipo "dead man's switch")
   que avise si el agente deja de dar señales *(decisión de Claude)*.
2. **Memoria de problemas abiertos**: cada problema aparece como *nuevo*, *sigue (N días)* o
   *resuelto*.
3. **Línea base de "normal"** por país y tipo de día (laborable/fin de semana/festivo) antes de
   llamar anómalo a algo. Recordar: los envíos son de lunes a viernes.
4. **Informe parcial antes que silencio**: si una comprobación no se puede hacer, se dice y se
   envía el resto.
5. **Informe corto con detalle a petición**: primera línea ✅/⚠️, luego puntos numerados;
   "detalle N" amplía.
6. **Playbook en git** con historial.
7. **Simulacros** de vez en cuando: fallo provocado en [DEV] para comprobar que el agente lo ve.

## 9. Modelos de IA (aprobado)

La mayor parte del trabajo **no usa IA** (consultar n8n, ejecutar pruebas, comparar con la línea
base, interpretar órdenes). Las **órdenes de Telegram son comandos fijos** (no se interpretan con
IA): `autorizo N`, `deshaz N`, `detalle N`, `pausa`, `sigue`, y uno para pedir el estado o repetir
el informe *(el nombre exacto, a criterio del constructor)*.

| Tarea | Frecuencia | Modelo v1 |
|---|---|---|
| Redactar el informe | diaria | Claude Haiku 5.5 (`claude-haiku-5-5`) |
| Diagnosticar un fallo y proponer arreglo | solo si hay fallos | Claude Sonnet 5.5 (`claude-sonnet-5-5`) |
| Aplicar un arreglo autorizado en n8n | solo con autorización | Claude Opus 5.5 (`claude-opus-5-5`) |

- El modelo de cada tarea es **una línea de configuración** cambiable; el diseño debe permitir
  otros proveedores en las tareas de redactar y diagnosticar. v1 arranca solo con Claude.
- Gasto esperado: **< 5 €/mes**. *Decisión de Claude:* tope de 20 €/mes; si se acerca, el agente
  lo dice en el informe y deja de diagnosticar con IA.

## 10. El informe (forma)

En español. Ejemplo de estructura (no literal):

```
✅ Todo funciona — 05/11 · 8:00
Bot: 214 mensajes de panelistas en 24 h, 0 fallos.
Pruebas: envío ✅ · recepción ✅ · lista de paquetes ✅
Procesos automáticos: 9/9 a su hora.
Problemas abiertos: ninguno.
```

```
⚠️ 2 problemas — 05/11 · 8:00
1. NUEVO · Lista de paquetes no responde a 1 panelista (PAN-KEN-060).
   Causa: su ficha no tiene nodo. Arreglo: asignarle nodo (base de datos → sesión con Claude).
2. SIGUE (3 días) · ...  Arreglo propuesto: ...  → "autorizo 2"
```

## 11. Pruebas activas (v1)

Cubren los tres procesos que el responsable citó: **declarar envío, declarar recepción y pedir la
lista de paquetes**. El playbook añadirá el resto (foto de etiqueta, indisponibilidad, materiales,
incidencias…). Se ejecutan antes de las 8:00 para entrar en el informe.

Cada prueba verifica que **el panelista recibe la respuesta correcta** (no solo que la ejecución
acabó "success"), y al final se limpian los datos que creó en DEMO2.

Restricción: cada prueba gasta ejecuciones de n8n (límite 10.000/mes compartido con la operación
real). Las pruebas deben ser pocas y ligeras; el constructor estimará el consumo mensual.

## 12. El playbook

Archivos de texto en git, legibles por el responsable, donde cada entrada dice: qué comprobar,
cómo saber si está bien, qué arreglos son posibles y con qué límites. Se amplía en sesiones de
Claude Code con el responsable; cada cambio queda en el historial.

## 13. Decisiones de Claude (revisables por el responsable)

1. **"Respuesta correcta"** en una prueba = el bot contesta en un tiempo razonable, en el idioma
   del panelista de prueba, con el mensaje y los botones del paso esperado, y el dato queda
   registrado en BD. Se compara con una **referencia por paso** guardada en el playbook (en el
   idioma del panelista de prueba), no con el texto literal, para no dar falsas alarmas.
2. **Datos de prueba aislados**: se crean con marcas reconocibles (p. ej. etiquetas de un rango
   reservado) y la limpieza borra solo lo marcado. El constructor debe comprobar que las pruebas
   no disparan avisos reales (resumen diario de las 9:00, emails al manager de DEMO2, avisos de
   "no recibido") o, si los disparan, que solo llegan a DEMO2.
3. **"Mensaje sin respuesta"** se obtiene de las ejecuciones de n8n: cada mensaje de un panelista
   abre una ejecución del flujo principal; si termina en error o sin pasar por un nodo de envío
   a Telegram, cuenta como "sin respuesta".
4. **Las dos primeras semanas son de aprendizaje**: las anomalías estadísticas se muestran como
   "observación", no como alarma, mientras se acumula la línea base (Kenia solo tiene datos desde
   el 26/10). Los fallos de ejecución y de las pruebas sí alarman desde el primer día.
5. **El calendario esperado de los flujos de reloj** se deduce de sus propios disparadores en n8n.
6. **Arreglos precisos**: cada arreglo propuesto describe exactamente qué nodo cambia y cómo
   (antes → después). "Autorizo N" aplica ese cambio y nada más. La autorización **caduca con el
   siguiente informe**.
7. **DEV → PROD**: el arreglo se aplica a la copia [DEV] del flujo, se verifica con el bot DEV y
   el panelista de prueba, y luego se aplica el mismo cambio a la copia PROD. Si las copias DEV y
   PROD de un flujo no coinciden, el agente no lo arregla por Telegram y lo deja para una sesión.
8. **Arreglos mixtos (BD + n8n)**: el informe separa las dos partes. La de n8n se puede autorizar
   por Telegram; la de BD queda marcada "para sesión con Claude".
9. **Accesos del agente**: clave de API de n8n (tiene permiso de escritura total; los límites los
   pone el código del agente más las copias previas); para leer la BD, un **rol de solo lectura**
   que se crea en una sesión con confirmación; y, para los datos de prueba, un acceso limitado a
   DEMO2 (preferiblemente funciones que solo actúan sobre DEMO2). El agente **no** guarda la clave
   service_role ni la de la Management API de Supabase.
10. **Alarma de las 8:30**: el agente deja una señal de vida tras enviar el informe; un único flujo
    de n8n diario a las 8:30 comprueba esa señal y, si falta, avisa al responsable con el bot del
    agente. Más el vigilante externo de 8.1.
11. **Problema abierto desde el primer día**: los 9 workflows que apuntan al errorWorkflow
    inexistente aparecen en el primer informe con un arreglo propuesto.

## 14. Lo que queda al constructor

- Lenguaje, librerías y forma del agente (p. ej. Claude Agent SDK o Claude API con herramientas).
- La librería de cliente de Telegram para la cuenta de prueba y dónde guardar su sesión de forma segura.
- Dónde guardar memoria de problemas, línea base, registro y copias (en el servidor, dentro de la
  copia de seguridad diaria que ya existe).
- Repositorio del agente y del playbook (nombre y ubicación).
- La forma concreta de la señal de vida y del acceso limitado a DEMO2.
- Estimar cuántas ejecuciones de n8n al mes gastan las pruebas (límite 10.000, compartido).
