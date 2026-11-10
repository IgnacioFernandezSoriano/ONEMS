# Análisis de casos: tarjeta del manager y botón «Aplicar»

**Fecha:** 2026-11-10
**Estado:** borrador para revisión del usuario
**Amplía:** `2026-11-10-agente-analisis-de-casos-design.md` y el sistema de arreglos del agente (fase 3, `2026-11-05-agente-operaciones-fase3-design.md`). Todo lo que aquí no se contradice sigue vigente.

---

## 1. Intención

Hoy el análisis de un caso explica qué ha pasado y redacta mensajes, pero no corrige nada. El manager tiene que ir a ONEMS y arreglar los datos a mano.

Se quiere que, para cada caso, el manager vea **qué pasó, por qué y qué hacer**, y que pueda **aplicar la corrección con un botón** cuando sea un arreglo sencillo. Para los arreglos sencillos se usa el mismo circuito de autorización, aplicación, comprobación y deshacer que ya usa el agente con n8n. Si la solución necesita trabajo guiado, el agente prepara un **prompt para Claude Code** en vez de tocar nada.

## 2. Reglas del usuario que manda

1. **Aprovechar la muestra.** Si una etiqueta tiene origen y destino bien identificados a ambos lados, la muestra se aprovecha aunque el envío fuera erróneo:
   - se registra como **recepción buena**;
   - en la línea del plan se cambia el destino al panelista que la recibió de verdad.

   No se descarta ni se pierde.
2. **Mensajes a panelistas** (ya implantado):
   - muy escuetos;
   - solo al que recibió: causa en una frase, gracias, «lo gestionamos nosotros»; queda liberado del asunto;
   - **de momento ningún mensaje al remitente**: su error lo trata el gestor de panelistas con el informe de panelistas. Más adelante se automatizará.
3. **Arreglo sencillo:** el agente lo aplica tras la pulsación de Ignacio y gestiona la comprobación y el paso a producción, como estaba definido.
4. **Arreglo complejo:** solo un botón que genera el prompt para Claude Code.

## 3. Objetivos

**1. Tarjeta del manager.** Cada análisis empieza con tres apartados cortos:
- **Problema:** qué ha pasado, en una o dos frases.
- **Causa:** la probable, con su prueba.
- **Solución propuesta:** qué hay que corregir y dónde.

Cada apartado tiene 1 o 2 frases y no repite lo que dice otro. Es una petición de Ignacio del 2026-11-10: tarjeta concisa y sin repeticiones.

El análisis detallado (plan, realidad, comparación, ruido, contactos y mejora) no va en la tarjeta: se ve con el botón «📄 Ver detalle».

**2. Botones de la solución:**
- Si la solución es un arreglo del catálogo (§4): **«✅ Aplicar»** y **«❌ No aplicar»**.
  - «Aplicar» enseña primero una **vista previa**: qué fila cambia y de qué valor a qué valor. Se confirma con un segundo botón, igual que los arreglos R1-R3 de hoy.
  - Tras aplicar, el agente comprueba el resultado y ofrece **«↩️ Deshacer»**.
- Si no encaja en el catálogo: **«🧩 Prompt para Claude Code»**.
  - El agente envía un texto listo para pegar en una sesión: problema, causa, datos del caso (cuenta, etiqueta, ids), qué hay que conseguir y las reglas que aplican.
  - No toca nada.
- Puede haber los dos si la solución tiene una parte sencilla y otra compleja.

**3. Quién pulsa.**
- «Aplicar» y «Deshacer»: solo Ignacio, en su chat privado, como hoy con los arreglos.
- En ONEMS, la tarjeta se muestra igual, pero solo con el botón del prompt (copiar al portapapeles). Aplicar desde ONEMS queda fuera de esta fase.

**4. Primer arreglo del catálogo: R4 «Redirigir y registrar la recepción».** Detalle en §4.

**5. Se puede ampliar el catálogo.** Cada arreglo nuevo entra con el visto bueno de Ignacio, por git, como R1-R3. El agente nunca aplica una acción fuera del catálogo.

## 4. Arreglo R4: redirigir y registrar la recepción

**Cuándo se ofrece.** Las cuatro condiciones a la vez:
- Hay un caso de recepción abierto (`pending` o `needs_decision`) de tipo `other_city_tag`.
- La etiqueta corresponde a una única línea del plan en estado `sent`, sin recibir.
- Origen bien identificado: la línea tiene panelista o nodo de origen.
- Destino real bien identificado: el panelista del caso es activo, tiene nodo y es de la misma cuenta.

**Qué hace:**
- **En la línea del plan:**
  - destino (nodo y panelista) = el del panelista que la recibió;
  - se guardan el destino anterior en `original_destination_node_id` (si estaba vacío), `reassignment_reason = 'sender_wrong_address'` y `reassigned_at = now()`;
  - `status = 'received'` y `received_at` = el primer intento de registro del panelista (`receipt_case.first_attempt_at`), que es cuando la tuvo en la mano.
- **En el caso de recepción:** pasa a `fixed`, con la nota «Redirigida al receptor real (error de dirección del remitente)» y el responsable `ops-agent`.
- **Rastro:** todo queda en el registro de arreglos del agente (`ops_fix_log`), igual que R1-R3.
- **SLA:** el que cuenta es el del nuevo par de ciudades (origen → ciudad del receptor real). Lo calcula ONEMS como cualquier otra recepción.

**Vista previa:** muestra la etiqueta, el origen, el destino actual, el destino nuevo, la fecha de recepción que se registrará y el estado del caso.

**Deshacer:** devuelve la línea al destino, estado y fechas anteriores, y el caso a su estado anterior. Solo se puede deshacer si la fila no ha cambiado desde que se aplicó.

**Aviso al panelista:** el que recibió ya tiene su mensaje escueto («lo gestionamos nosotros»). Aplicar R4 no envía nada más.

## 5. No-objetivos

- Aplicar arreglos desde ONEMS (solo ver la tarjeta y copiar el prompt).
- Arreglos que no estén en el catálogo.
- Mensajes automáticos al remitente (más adelante).
- El grupo de managers con bot propio (diseño aparte).

## 6. Anti-objetivos

- Que se aplique un cambio de datos sin la pulsación de Ignacio y sin vista previa.
- Que R4 se aplique con un origen o destino dudoso: si falla cualquier condición del §4, no se ofrece «Aplicar»; solo el prompt.
- Mezclar cuentas: el receptor y la línea deben ser de la misma cuenta.
- Perder una muestra válida cerrando o anulando el caso cuando se puede redirigir.

## 7. Restricciones

- **Base onems-dev `sehbnpgzqljrsqimwyuz`:**
  - toda migración se valida antes en el Postgres local (5433) y se aplica con confirmación explícita;
  - funciones con token (`ops_fix_r4_preview`, `ops_fix_r4_apply`, `ops_fix_r4_undo`) siguiendo el patrón de R1-R3: anon + token y nunca service_role.
- **Agente:** reutiliza el ejecutor de arreglos (`fixer.py` y `repairs.py`) y su flujo de botones; no inventa uno nuevo.
- **La IA no decide si un arreglo es aplicable.**
  - El agente pregunta a la base (`preview`) si R4 aplica a ese caso.
  - La IA solo redacta problema, causa y solución.
  - El botón «Aplicar» aparece si la base dice que se puede.
- **Prompt para Claude Code:**
  - en español;
  - sin claves ni teléfonos (`masking.mask`);
  - con un recordatorio de las reglas del proyecto: confirmar antes de escribir en la base y validar en local.

## 8. Se deja al builder

- El texto exacto de la tarjeta y del prompt.
- Cómo se numeran los arreglos de casos para que «autorizo N» no se confunda con los del informe diario.
- Si la vista previa y la aplicación de R4 comparten función con parámetros o van por separado.
- La relación con `transfer_to_one_db`: al pasar la línea a `received`, el disparador copia la muestra a ONE DB. El builder decide cómo deshacer esa copia en «Deshacer» o, si no es seguro, impide deshacer una vez copiada y lo dice en la vista previa.

## 8b. Decisiones tras la revisión del builder (mías, revisables)

- **Motivo nuevo.** `reassignment_reason` admite hoy `panelist_unavailable`, `manual`, `rebalancing` y `pobox_move`. La migración de R4 amplía el CHECK con `sender_wrong_address`. El builder revisa qué pantallas o informes enumeran esos valores y les añade la traducción en los 5 idiomas.
- **Cómo se encuentra la línea.** Los casos `other_city_tag` no guardan `detail_id`. R4 busca la línea por `normalize_tag(tag_id) = receipt_case.tag_norm` dentro de la cuenta, y exige todo esto:
  - exactamente una línea;
  - en estado `sent`, sin `received_at`;
  - con `sent_at` anterior o igual a `first_attempt_at`;
  - ningún otro caso abierto con la misma etiqueta.

  Solo se ofrece para casos `other_city_tag`.
- **Identificación.** Las funciones R4 reciben el id del caso de recepción (`receipt_case.id`, el ancla del análisis) y lo usan como clave en el registro de arreglos.
- **Sin paso DEV → PROD.** Un arreglo de datos va por el carril de reparaciones de R1-R3, no por el de n8n. Pasos: vista previa, confirmación, aplicación con comprobación por relectura y «Deshacer» disponible 24 horas. Solo se deshace si la fila no ha cambiado desde que se aplicó.
- **Datos del nuevo par.** Se escriben a la vez el nodo, el panelista y los nombres del destino, junto con `status = 'received'` y `received_at`, para que la copia a ONE DB use la ciudad buena.
  - Si no hay norma de entrega para el nuevo par, la vista previa lo avisa («sin SLA para este par»), pero se puede aplicar.
  - Si la línea tiene errores de validación que impedirían copiarla a ONE DB, R4 no se ofrece.
- **Deshacer y ONE DB.** «Deshacer», dentro de las 24 horas, borra en la misma transacción la copia que R4 creó en ONE DB y devuelve la línea y el caso a como estaban.
- **Quién resuelve.** `resolved_by` queda vacío, porque es un usuario de ONEMS. La nota del caso dice que lo resolvió el agente, y el detalle queda en el registro de arreglos.
- **Botones.** La tarjeta se maneja desde el propio análisis de casos (`case_bot.py`), reutilizando el cliente de reparaciones (`repairs.py`) y la memoria del agente. Solo en el chat privado de Ignacio.
- **ONEMS.** El resultado del análisis ya se guarda en `case_analysis_request.result`. Se le añaden `problem`, `cause`, `solution`, `fix` (el arreglo que la base dice aplicable, o vacío) y `prompt`. ONEMS muestra la tarjeta y un botón «Copiar prompt», solo en DEMO2 de momento.
- **Kenya.** En la aceptación con 00011844 solo se pide la vista previa, que es de lectura. Aplicar en Kenya queda para cuando Ignacio lo decida en ese momento.

## 9. Aceptación

- Con el caso de prueba de DEMO2 (etiqueta 99991844):
  - la tarjeta muestra Problema, Causa y Solución;
  - «Aplicar» enseña la vista previa;
  - al confirmar, la línea queda recibida por PAN-DEM-003, con su destino original guardado, y el caso pasa a `fixed`;
  - «Deshacer» lo devuelve todo como estaba.
- Con un caso que no cumple el §4: solo sale «Prompt para Claude Code», con un texto útil.
- Con el caso real 00011844 de Kenya: la tarjeta propone R4. No se aplica sin el visto bueno de Ignacio en ese momento.
