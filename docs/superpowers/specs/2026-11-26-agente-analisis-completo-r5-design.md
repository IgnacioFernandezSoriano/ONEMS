# Agente de análisis: investigación completa + arreglo R5 «etiqueta mal escrita» (diseño)

Fecha: 2026-11-26 · Pide: Ignacio (responsable de ONEMS) · Repos: ONEMS (BD) y panelist_n8n (`ops-agent`)

## Intención

Cuando un gestor pulsa **«Analizar»** en Telegram, el agente debe hacer el mismo trabajo que hizo Claude Code
a mano el 26/11 con el caso 00011418 de Kenya (Jacktone Mjomba, PAN-KEN-050):

1. **investigar** hasta encontrar la causa real,
2. **proponer la solución** y que el gestor la pueda **aplicar con un botón** (vista previa → Aplicar →
   Deshacer 24 h),
3. **redactar el mensaje al panelista en su idioma** con el esquema general nuevo.

Hoy no lo consigue y devuelve «prompt para Claude Code»: el paquete de datos (`ops_case._data`) solo trae
líneas con la etiqueta **exacta**; si la etiqueta no está en el plan, el paquete llega vacío y el agente
concluye «no está en el plan». Por qué importa: Ignacio no quiere hacer de intermediario copiando prompts.

### El caso de referencia (00011418)

- Jacktone intentó registrar 00011418 tres veces; el bot dijo «se parece a varios» (`ambiguous_typo`)
  porque el remitente tiene en circulación 00011414/15/16/17/19, todas a 1 cifra.
- La causa: Faith Joseph declaró el 04/11 el envío a Jacktone como **00014118** (dos cifras contiguas
  intercambiadas). Nadie lo recibió → anulado el 19/11 por `not_received_timeout`.
- Las tres búsquedas que lo resolvieron: (a) etiquetas parecidas en la cuenta, (b) envíos que esperaba el
  receptor, también los anulados por plazo, (c) la serie de etiquetas del remitente (11414–11420).
- El arreglo: `revive_timeout_detail(línea)` + `rpc_receipt_case_fix(caso, línea)` → resultado
  `ok_typo_fixed`, recepción con la hora del primer intento, recordatorio automático al remitente.

## Objetivos

- El paquete del análisis trae las tres búsquedas de arriba (solo de la cuenta del caso).
- Nuevo arreglo **R5 «etiqueta mal escrita»** en la BD (preview / apply / undo), con el mismo patrón,
  garantías y botones que R4.
- El agente explica la causa con esos datos y, si R5 aplica, su «solución» dice exactamente lo que hará el
  botón.
- Borrador al panelista del caso en su idioma con el esquema general (ver «Mensajes»).
- **Ahorro**: los casos conocidos se resuelven en un nivel 1 sin modelo (coste 0); el bot aconseja cuándo
  pasar al análisis completo (sección 0).

## No objetivos

- Agente con herramientas que investiga en varias rondas (opción B, descartada por coste/tope de 5 $/mes y
  previsibilidad; podrá añadirse encima más adelante usando la misma lista de arreglos).
- Que la BD o el modelo **elijan solos** entre varios candidatos (desempate automático por la serie del
  remitente, descartado por Ignacio el 26/11): con varios, elige el gestor (ver 2 y 3).
- Aplicar arreglos desde el botón «Analizar» de la web ONEMS (decisión previa de Ignacio: en ONEMS solo
  prompt). La web se beneficia del paquete ampliado y del mejor análisis, sin botón de aplicar.
- Mensaje redactado al remitente (`DRAFT_TO_SENDER` sigue en `False`; el remitente ya recibe el
  recordatorio automático de `enqueue_receipt_reminder`).

## Anti-objetivos (sería un fracaso aunque funcione)

- Que el agente o el bot escriban en la BD sin que el gestor pulse Confirmar.
- Que el paquete o un arreglo toquen datos de otra cuenta.
- Que R5 asigne la etiqueta a un envío sin que una persona haya elegido ese envío concreto viendo su vista
  previa (por eso, con varios candidatos elige el gestor; nunca la máquina).
- Subir de forma notable el coste por análisis (debe seguir en el orden de 4–5 céntimos).

## Restricciones

- Una sola BD: **onems-dev `sehbnpgzqljrsqimwyuz`** (es producción). Migración forward-only nueva
  (`2026112612xxxx_…`), validada primero en el Postgres portable local (5433, BD `onems_t`); aplicar en
  remoto solo con confirmación explícita de Ignacio nombrando proyecto y ref.
- Las funciones de la BD que se reutilizan (`revive_timeout_detail`, `rpc_receipt_case_fix`,
  `register_receipt_with_rules`, …) se comprobó el 26/11 que son idénticas en local y en prod.
- El paquete cabe en `MAX_DATA = 30_000` caracteres: cada lista nueva con límite de filas.
- Agente: tests (`pytest`, hoy 755 verdes) en `ops-agent`; despliegue a Hetzner solo de los ficheros
  cambiados, con copia de seguridad, tras comparar con lo que hay en el servidor (el servidor puede no
  coincidir con `main`).
- No commitear ni pushear sin que Ignacio lo pida.

## Enfoques considerados

- **A. Paquete ampliado + un solo análisis + arreglos con botón** — mismo coste y rapidez; predecible; solo
  ve lo que el paquete trae. **Elegido por Ignacio.**
- **B. Agente investigador con herramientas de solo lectura** — más flexible, 10–20 céntimos y 1–2 min por
  análisis, menos predecible. Descartado por ahora.
- Híbrido (A + herramientas cuando falte algo) — descartado: suma la complejidad de ambos sin necesidad para
  los casos conocidos.

## Diseño

### 0. Dos niveles: rápido (sin modelo) y completo (decisión de Ignacio, 26/11)

Para ahorrar coste. El gasto está en llamar al modelo, no en las búsquedas; por eso el nivel ligero **no
llama a ningún modelo**. (Descartado: usar Haiku como nivel ligero; Ignacio ya rechazó Haiku el 11/11 y no
llamar a nada ahorra más.)

**Flujo.** Al pulsar «Analizar» en Telegram siempre se hace primero el **nivel 1** (gratis, no se cobra al
tope de la cuenta). El bot enseña su tarjeta y **aconseja**: o «caso conocido, este es el arreglo», o «este
caso necesita el análisis completo». El botón **«Análisis completo»** está siempre debajo (marcado como
recomendado cuando toca) y lanza el **nivel 2** = el análisis con Sonnet de este diseño (secciones 1–4), con
su coste y su tope de siempre.

**Nivel 1 — reglas fijas en el código del agente** (Python, sobre el paquete de la sección 1 y las vistas
previas de R4/R5; sin LLM). Patrones, en este orden:

| Patrón | Cuándo | Tarjeta | Botones | Plantilla al panelista del caso |
|---|---|---|---|---|
| P1 etiqueta mal escrita | ancla = caso de recepción y R5 da 1–5 candidatos | problema, causa «etiqueta mal escrita por el remitente (probable)», candidatos con sus marcas | R5 (uno por candidato) + Análisis completo | «no se pudo registrar porque el remitente escribió mal el número; ya lo hemos solucionado» |
| P2 etiqueta de otra ciudad | R4 aplica | problema, causa, solución R4 | R4 + Análisis completo | «el envío estaba asignado a otra ciudad; ya lo hemos solucionado» |
| P3 ya registrado | la etiqueta tiene línea `received` por este panelista | «ya estaba registrado» | Análisis completo | «ya estaba registrado; no tienes que hacer nada» |
| — ninguno | lo demás | «no es un caso conocido» | Análisis completo (recomendado) | ninguna |

**Cuándo el nivel 1 recomienda el completo** aunque haya patrón: el gestor reenvió capturas o texto (más
allá de la etiqueta) que habría que interpretar; el ancla no es un caso de recepción (incidencia u otro);
P1 con **varios** candidatos que las marcas no distinguen (ver abajo); cualquier error al pedir datos.

**Marcas de candidato** (P1, calculadas por código, sin modelo, solo informativas — no eligen): «anulado
por plazo», «en camino», «va al mismo panelista», «fuera de la serie del remitente» (su etiqueta queda lejos
de las demás etiquetas del remitente en `sender_series`, mientras la del caso encaja en ella). Si
exactamente un candidato lleva «fuera de la serie del remitente», la tarjeta lo dice («00014118 no encaja en
la serie de Faith: probablemente es este») sin preseleccionarlo; si ninguno o varios, recomienda el
completo. En el caso de referencia: 00014118 «anulado por plazo · fuera de la serie»; 00011415 «en camino».

**Plantillas** (sección 4, mismo esquema): una por patrón y por idioma del panelista (los idiomas que ya
soporta `case_i18n`), con el nombre y la etiqueta. Como dicen «ya lo hemos solucionado», en P1/P2 el botón
de enviar la plantilla **solo aparece después de aplicar** el arreglo. Ejemplo P1 en inglés: «Hi Jacktone,
thank you for reporting envelope 00011418. The bot couldn't register it because the sender had typed the
number incorrectly. We've already fixed it, so there's nothing else you need to do. Great job!»

**Fuera del nivel 1**: la web ONEMS sigue lanzando directamente el análisis completo, como hoy (sin cambios
de flujo). El nivel 1 no escribe nada en la BD salvo a través de los botones de arreglo de siempre.

### 1. Paquete ampliado (`ops_case._data`, BD)

Nuevas claves, todas filtradas por la cuenta del panelista (`v_acc`), mismo formato compacto que `siblings`:

- **`details[].cancellation_reason`**: añadirlo a las líneas existentes (hoy falta; sin él no se ve
  «anulado por plazo»).
- **`near_tags`** (si hay etiqueta): líneas cuya etiqueta normalizada está a «un error de tecleo» de la del
  caso: **una cifra distinta** (misma longitud) o **dos cifras contiguas intercambiadas**. Cualquier estado.
  Campos: etiqueta, tipo de parecido (`one_digit` / `swap`), estado, motivo de anulación, fecha programada,
  `sent_at`, `received_at`, código y nombre de origen y destino, ciudad de destino. Máx. 20, primero las
  que van a la ciudad del panelista del caso.
- **`expected_for_panelist`**: líneas cuyo destino es el nodo del panelista del caso (o, si no lo hay, su
  ciudad) en estado `sent`, o `cancelled` con `not_received_timeout` y sin `received_at`, declaradas en los
  últimos 45 días. Campos: etiqueta, estado, motivo, `sent_at`, código/nombre del remitente. Máx. 30.
- **`sender_series`**: para cada remitente que aparece en `near_tags` o `expected_for_panelist` (máx. 5
  remitentes), sus etiquetas declaradas en los últimos 45 días (etiqueta, `sent_at`, estado, destino).
  Máx. 30 por remitente.
- **`fix_r5`**: nada aquí; la vista previa de R5 va aparte (ver 3).

La lista de implicados (`v_involved`) suma los remitentes de `near_tags` con parecido a la ciudad del
receptor, para que el agente pueda listarlos en `contacts` (no se les redacta mensaje).

### 2. Arreglo R5 (BD, esquema `ops_fix`, mismo patrón que R4)

Funciones públicas con la **firma actual de R4** (con `p_account`, `p_actor_email`) más la línea elegida:
`ops_fix_r5_preview(p_token, p_case_id, p_account, p_actor_email)`,
`ops_fix_r5_apply(p_token, p_case_id, p_detail_id, p_expected, p_account, p_actor_email)`,
`ops_fix_r5_undo(p_token, p_log_id, p_account, p_actor_email)`. Mismos permisos, mismo control de actor y
de cuenta, mismo registro en el log de arreglos que R4.

**Preview** (solo lectura). Aplica si se cumple todo:
- el caso existe, es de la cuenta, está `pending` o `needs_decision`, su motivo es **`ambiguous_typo` o
  `not_found`** (así nunca se solapa con R4, que exige `other_city_tag`), tiene panelista con nodo y
  `tag_norm`;
- **ninguna** línea de la cuenta tiene exactamente `tag_norm`;
- hay **entre 1 y 5 candidatos**: líneas de la cuenta con etiqueta a un error de tecleo (definición de 1),
  destino en la **misma ciudad** que el receptor, `sent_at` ≤ `first_attempt_at`, y estado `sent` o
  (`cancelled` + `not_received_timeout` + sin `received_at` + no está en `deferred_samples`). Es la misma
  definición que `receipt_typo_candidates` (migración `20261104130000`); reutilizarla si encaja. Con más de
  5, no aplica («demasiados parecidos»).

Devuelve `applicable`, `reason` si no aplica, y **`candidates`** ordenados (primero mismo nodo que el
receptor, luego cifras intercambiadas antes que cifra distinta, luego `sent_at` más antiguo); por cada uno,
para mostrar y para `p_expected`: id de la línea, etiqueta actual → etiqueta nueva, tipo de parecido,
remitente (código, nombre), destino (código, nombre), fecha de envío, estado, si hay que **reactivarla**
(estaba anulada por plazo) y si **cambia el nodo** de destino (misma ciudad, otro nodo). Además
`case_status`. El orden es solo de presentación: la BD **no elige**.

Caso de referencia (comprobado en datos reales el 26/11): candidatos 00014118 (Faith → Jacktone, 04/11,
anulado por plazo, cifras intercambiadas, el bueno) y 00011415 (Faith → Jacktone, 19/11, en camino, una
cifra). Con «exactamente uno» R5 no habría aplicado; por eso elige el gestor.

**Apply**: `p_detail_id` debe ser uno de los candidatos de una vista previa nueva y su ficha coincidir con
`p_expected` («ha cambiado desde la propuesta» si no). Guarda en el log una foto de la línea y del caso
antes de tocar. Luego
`revive_timeout_detail` si hace falta y `rpc_receipt_case_fix(caso, línea)`; exige resultado
`ok_typo_fixed` (o `ok_same_city`), si no aborta sin cambios. Misma comprobación de la copia a ONE DB que
R4 («la copia a ONE DB no se hizo; no toco nada»). Devuelve `log_id`.

**Undo** (≤ 24 h, una vez): restaura la línea (etiqueta, `idtag`, estado, `received_at`, anulación,
destino) y el caso (estado, motivo, `detail_id`, `original_tag`, culpable, `resolved_*`) desde la foto;
borra el recordatorio al remitente de ese caso si aún no se envió; **si ya se envió, deshace igual** y
devuelve `reminder_already_sent=true` para que el bot avise al gestor («el recordatorio a X ya había
salido»). El culpable del caso (`culprit_*`) vuelve al valor de la foto, así que los informes dejan de
contarlo. Deshace la copia a ONE DB igual que R4. Si la línea o el caso cambiaron después del arreglo:
«cambió después del arreglo; no lo deshago».

### 3. Agente (`ops-agent`)

- `repairs.py`: `Kind` admite `"r5"`, con las tres llamadas de arriba.
- **Orden nuevo**: si el ancla es un caso de recepción, se piden las vistas previas de **R4 y R5 antes del
  análisis** (hoy R4 va después) y su resultado entra en los HECHOS CALCULADOS, para que el texto de
  «solución» coincida con el botón. R4 y R5 se excluyen por construcción (R5 exige que la etiqueta no
  exista en el plan); si alguna vez ambos dicen aplicable, se ofrece R4 y se registra un aviso.
- Botones: los de R4 (`case_fix_buttons.py`) pasan a trabajar con el arreglo ofrecido (`fix_kind` guardado
  en el resultado: `r4` o `r5`); mismos estados (`previewed`, `applying`, `applied`, `undoing`, …),
  reconciliación y textos por idioma (`case_fix_texts.py`, `case_i18n.py`).
- **Elección del gestor (R5)**: bajo la tarjeta, un botón por candidato (máx. 5; el callback lleva el
  número de candidato, no el id, por el límite de 64 bytes de Telegram), con etiqueta, remitente y fecha;
  el que recomienda el análisis va marcado («recomendado»). Al pulsar uno: vista previa nueva de la BD de
  **ese** candidato → «Confirmar» / «No aplicar» (vuelve a la lista) → tras aplicar, «Deshacer» 24 h. Con
  un solo candidato, mismo flujo con un único botón. Ejemplo de vista previa: «Etiqueta 00014118 →
  00011418 · envío de Faith Joseph del 04/11 a Jacktone · se reactiva (estaba anulado por plazo) · se
  registra como recibido el 26/11».
- El modelo recibe la lista de candidatos en los HECHOS y devuelve en su salida estructurada un campo nuevo
  `recommended_tag` (etiqueta de uno de los candidatos o `null`) y su porqué en `cause` (serie del
  remitente, fechas, a quién iba). El código ignora un `recommended_tag` que no esté en la lista.
- Un gestor solo aplica en cuentas abiertas a envíos (`case_send_allowed`), igual que R4.
- **Prompt del análisis** (`SYSTEM_ANALYSIS`): explicar qué son `near_tags`, `expected_for_panelist` y
  `sender_series`, y las reglas de razonamiento: si la etiqueta no está en el plan, buscar el error de
  tecleo en esos datos (serie del remitente, destino al receptor, fechas); si la vista previa de R5 aplica,
  la solución dice «R5: corregir la etiqueta del envío X y registrarlo como recibido» y la causa nombra la
  etiqueta mal escrita y quién la declaró; si no aplica, explicar por qué (varios candidatos, ninguno…).
- La línea R4 del prompt para Claude Code (`r4_line`, `build_cc_prompt`) se generaliza a «Arreglo
  automático R4/R5».

### Ramas y despliegue

- ONEMS: rama nueva desde `develop` para la migración y los tests.
- panelist_n8n: rama nueva desde `main` solo con este trabajo (incluido `MESSAGE_RULES`); el arreglo del
  nombre de cuenta del manager (`fix/manager-nombre-cuenta`, sin commit) va por separado y no se mezcla.
- Antes de subir a Hetzner: comparar cada fichero con el del servidor (que ya tiene `manager_bot.py` y
  `store.py` del arreglo del 26/11); subir solo los ficheros de este trabajo, con copia de seguridad.

### 4. Mensajes (ya hecho en código, sin commit, rama `fix/manager-nombre-cuenta` de panelist_n8n)

Regla general de Ignacio (26/11) en `MESSAGE_RULES`: al panelista del caso, en su idioma, escueto y en
positivo: (1) el problema en una frase; (2) causa interna o de otro → «ya lo hemos solucionado», no tiene
que hacer nada; causa suya → qué hacer la próxima vez, como consejo. Entra en este trabajo (se lleva a la
rama nueva). Tras «Aplicado» el bot recuerda en una línea que ya se puede enviar el mensaje al panelista
(el borrador dice «ya lo hemos solucionado»).

## Pruebas

- BD (local `onems_t`): test nuevo `ops_fix_r5.test.sql` con el caso de referencia **tal como era en
  prod** (00014118 anulado por plazo + 00011415 en camino, ambos a Jacktone → caso 00011418): preview da
  los 2 candidatos en el orden definido; apply con 00014118 → `ok_typo_fixed`, línea recibida, caso
  `fixed`, 00011415 intacto; undo deja todo como antes (también con el recordatorio ya enviado → avisa);
  casos de no aplicar (0 candidatos, más de 5, otra ciudad, otra cuenta, motivo `other_city_tag`,
  declarado después del primer intento, ya en `deferred_samples`, etiqueta exacta existente);
  `p_detail_id` que no es candidato o `p_expected` distinto → error. Test del paquete: `near_tags` encuentra cifra distinta y cifras intercambiadas, nunca de
  otra cuenta; límites de filas.
- Nivel 1: tests de cada patrón (P1 con 1 y con 2 candidatos y sus marcas —el caso de referencia da
  «fuera de la serie» solo en 00014118—, P2, P3, ninguno), de cuándo recomienda el completo (capturas,
  ancla no de recepción, candidatos indistinguibles, error), de que **no llama al LLM ni cobra**, de las
  plantillas en cada idioma, y de que el botón de enviar plantilla solo aparece tras aplicar.
- Agente: tests de `repairs` r5, del orden (vistas previas antes del análisis y en los hechos), de botones
  con `fix_kind=r5` (aplicar, deshacer, reconciliar), de textos en los idiomas soportados y de prompt.

## Lo que queda al constructor

- Nombres exactos de funciones internas, estructura del log (reutilizar la tabla y columnas de R4), SQL de
  la distancia (p. ej. comparar cifra a cifra con `generate_series`), índices si hicieran falta.
- Cómo generalizar `case_fix_buttons.py` (parámetro de tipo frente a duplicar), siempre que el comportamiento
  de R4 no cambie y sus tests sigan verdes.
- Redacción exacta de textos de botones en los idiomas soportados.
