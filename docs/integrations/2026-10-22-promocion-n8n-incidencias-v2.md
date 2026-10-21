# Promoción a producción del bot de Telegram (n8n): incidencias v2, conversación y materiales

Fecha de la revisión: 2026-10-21. Revisión solo de lectura: no se ha modificado ningún workflow ni la base de datos.
Base de datos: **onems-dev**, ref **`sehbnpgzqljrsqimwyuz`**. Es la única base: "DEV" y "PROD" en n8n solo indican qué bot de Telegram usa cada workflow.

---

## 1. Resumen para el responsable

**Qué hay construido.** Todo el trabajo nuevo del bot está en copias de prueba ("[DEV] …") o en workflows nuevos que siguen apagados. El bot real (@OneMSBot) sigue funcionando como antes. Lo nuevo es esto:

- El panelista puede **reportar un problema con sus palabras**. El bot lo clasifica, le pregunta "¿Es así?" y lo resuelve solo cuando puede: paquete roto, etiqueta ilegible, problema con la foto de la etiqueta o cambio de teléfono, email, idioma o dirección. Si no puede, avisa al responsable.
- El **asistente de IA "conversador" desaparece**. Ahora la IA (un modelo barato) solo decide qué botón corresponde a lo que escribe el panelista. Es más barato, más predecible, y la IA ya no promete cosas que no hace.
- **Conversación de ida y vuelta**: el responsable escribe desde la web, el panelista lo recibe en Telegram y puede contestar con texto o con foto.
- **Falta de material**: el bot pregunta al panelista que dona el material y al que lo recibe, y pide las cantidades recibidas. Además deja de insistir con los envíos que no se pueden hacer hasta que llegue el material.

**Lo más importante.** No existe un bot de pruebas: nada de esto se ha probado nunca de punta a punta con Telegram real. La primera prueba real será en producción. Por eso la promoción se hace:

1. por fases y en un orden concreto;
2. con una copia de seguridad de cada workflow antes de tocarlo;
3. con una prueba inmediata con el panelista de pruebas de DEMO2;
4. con un plan para volver atrás en minutos.

**Cambios que notarán los panelistas reales** (cuenta KENYA y demás). Conviene avisar a los responsables:

- Ya no se puede "charlar" con el bot. Si se le escribe algo que no entiende, responde con el menú de botones.
- Las preguntas tipo "¿cómo preparo el paquete?" generan ahora una incidencia y un email al responsable.
- Si el responsable abre una conversación, todo lo que escriba el panelista en las 48 horas siguientes va al responsable. Esto dura hasta que el panelista pulse «Volver al menú».

**Veredicto.** Se puede promocionar cuando se cumplan las **6 condiciones bloqueantes** del apartado 3. Casi todas son de procedimiento: cómo y en qué orden copiar. No son fallos del diseño.

Aparte de la promoción hay un **riesgo de seguridad antiguo y grave**: el alta de panelistas nuevos por Telegram mete el texto escrito directamente en una consulta SQL. No lo introduce este trabajo, pero conviene corregirlo cuanto antes.

---

## 2. Qué se revisó (técnico)

Se leyeron en vivo, por REST GET, los 31 workflows implicados (DEV, nuevos y PROD). Sobre ellos se hicieron estas comprobaciones:

- un análisis por script de credenciales, SQL con `{{ }}`, llamadas entre workflows, nodos desactivados, cadenas con forma de secreto, triggers y alcanzabilidad;
- `n8n_validate_workflow` de los workflows nuevos;
- consultas SELECT de solo lectura en la BD.

### 2.1 ¿Se guardó todo lo que dicen los informes?
Sí.
- **DEV main `eeM4E4RS1UDThvUF`**: 187 nodos, versión publicada = borrador (`9d344f7f…`), la misma que cita el informe de las tareas 4-5. Todos los nodos que citan los informes existen en vivo, entre ellos Log incident conversation, Stash conversation logs, Reopen/Close conversation ctx, Upload reply photo, Prepare tag code ctx, Validate contact value, Mark picked parcel received, Text route (no AI) y Classify free text.
- Los workflows nuevos y las copias DEV también tienen sus nodos clave. Ningún nodo Postgres con `$1` le falta `queryReplacement`.
- **Validación**:
  - DEV main: solo los 2 errores conocidos ("typeVersion 2 exceeds 1.3" en Call Save parcel selection y Call Process send photo; también están en PROD y funcionan) y 28 avisos, todos ya conocidos.
  - Deliver incident messages, Material questions y [DEV] On new parcel to send: válidos.
  - [DEV] Material receipt: válido. Tiene 3 avisos porque las salidas de error de Telegram no están conectadas; es deliberado.
- **El DEV main no ha perdido nada de PROD.** No hay ningún nodo que esté en PROD y falte en DEV. Los 41 nodos comunes no tocados son idénticos. Las diferencias en los demás son las esperadas (prefijo `=`, repunteos, desactivaciones). Solo faltan 3 conexiones de PROD, eliminadas a propósito: la ruta al AI Agent, el incident_subagent y la conexión Get pending incident ctx→Call Report incident, que se rehízo.

### 2.2 Precedencia de enrutado (Route & Identify, en vivo)
El orden real del código es:

1. `/start` y `/myid`.
2. **Botones explícitos**: `conv_*`, `inc_*`, `start_receipt`, `another_parcel`, `finish_session`, `unav_*` y `material_*`/`mat_*`.
3. **Cantidad de material escrita** (`pending_material_qty` < 1 h, salvo que haya un flujo más reciente).
4. **Conversación abierta** (`pending_incident_reply` < 48 h, sin un flujo pendiente creado después del último mensaje; foto → `incident_reply_photo`, texto → `incident_reply`).
5. **Flujos pendientes**: cambio de contacto → baja → confirmación Sí/No → descripción de incidencia → recepción.
6. Adivinanzas de etiqueta o foto.
7. Registro, email y número.
8. `text` → `Free text needs classify?` → **clasificador barato** → botones, o menú si no entiende.

Comparado con la regla pedida ("conversación abierta > flujos pendientes > botones > clasificador"), hay **dos diferencias deliberadas y razonables**:
- Los **botones** ganan a la conversación, porque un botón siempre expresa una intención explícita.
- La **cantidad de material** gana a la conversación.

Además, la conversación cede ante cualquier flujo iniciado **después** del último mensaje del responsable. No he encontrado ningún caso que lleve a un camino muerto, salvo los riesgos aceptados del apartado 3.2.

### 2.3 SQL con texto del usuario
- **Copias DEV nuevas** (Report incident, Process send photo, Mark Parcel as received, Material receipt, Parcels to send, On new parcel to send, Deliver, Notify, Material questions): **cero `{{ }}` con texto del panelista**. Todo va con `$n` y `queryReplacement`.
  - Quedan `{{ }}` en [DEV] Report incident (Update incident with email metadata y Delete contexts), pero solo con datos de la BD y el `telegram_id`.
- **DEV main**: quedan `{{ }}` en Link telegram to panelist, Check send context, Save/Get pending incident ctx, Clean session contexts, Clear selected parcel ctx, Save pending receipt ctx y Clean pending receipt ctx. Solo llevan `telegram_id` (el `from.id` numérico de Telegram), `panelist_id` y `panelist_language` (ambos de la BD). El riesgo es bajo y viene de antes.
- Validación de etiquetas (`^[A-Za-z0-9._-]{3,40}$`) en las copias DEV:
  - Hoy hay en PROD **5 filas de `allocation_plan_details` con texto libre guardado como `tag_id`**, por ejemplo "Tell me the posting plan for this week". Es el fallo de `tag_code` de PROD.
  - La validación nueva lo impide.
  - Efecto colateral: una etiqueta escrita con espacios se rechaza con "formato no válido".

### 2.4 Secretos
- `Lookup email` (Code) lleva una **clave JWT service_role escrita**, tanto en PROD como en DEV. Es la deuda DT-2, que viene de antes. Al copiar el DEV main a PROD no empeora, pero sigue ahí. No se reproduce en este documento.
- `Unwrap harness body` (solo DEV) contiene el token del arnés. **No debe ir a PROD** (bloqueante 2).
- No hay más cadenas con forma de clave en los workflows nuevos.

### 2.5 Credenciales Telegram
| Workflow | Nodos Telegram | Credencial ahora | En PROD debe ser |
|---|---|---|---|
| [DEV] main `eeM4E4RS1UDThvUF` | 50 activos + 1 desactivado, más el Trigger | DEV `XWH25E2sLytLHGeZ` | PROD `rp79mLnvGH8hxiaL` (los 51 y el Trigger) |
| [DEV] Material receipt `cZdV1mCISEQREJVA` | 3 | DEV | PROD |
| [DEV] Parcels to send `WiDzFz7Y9NakVr9C` | 1 (saludo) | DEV | PROD |
| [DEV] On new parcel to send `mWtLvurQ9PpDrf9x` | 2 | DEV | PROD |
| Deliver incident messages `D8dRPQGK2HiMKzDZ` | 1 | **PROD** (ya) | — |
| Material questions `iYlRf37ly1xbCPxp` | 2 | **PROD** (ya) | — |
| Panelist unavailability `TWeVlUeFF0WzGH86` (lo llama el main) | 14 | PROD | sin cambios |

Las demás credenciales son las mismas en DEV y PROD: Postgres `735a8hxfuUEDPIYD`, OpenAI `zOYEIQHrRbAww7px`, Supabase `x5N8V225SfTxBA7Q` (subida de fotos y Parcels to send) y Resend (a través de `ZLb752muvdIHpFYp`).

### 2.6 Logs de mensajes del bot (`p_status='sent'`)
Revisados todos los `log_incident_message` de salida:
- Log reply ack, Log conv reply prompt, Log question y Log incident conversation (el Code pone `status:'sent'` en cada fila del bot);
- Material receipt / Log conversation (`Build reply`, bot = `sent`);
- Log release message (`Prepare release logs`).

Todos pasan `'sent'`. Las notas internas (system) y los mensajes de entrada no lo necesitan.

En BD hoy:
- 7 mensajes outbound/bot, todos `sent`;
- 1 fila en `pending_send`: el "hola" de prueba de DEMO2 `efc2c2ba…`, que será lo primero que entregue Deliver al activarse;
- `panelist_incident.reply_status='pending_send'`: 0.

### 2.7 Nodos desactivados o inalcanzables
- Desactivados a propósito (no reactivar): AI Agent, OpenAI Chat Model, los 5 tools de envíos, time_off_subagent, incident_subagent, declare_time_off, send_*_to_manager, las 3 memorias, User Message, Clean pending tag context, Escape _ for markdown v2, Send AI Agent response y Restore free text for agent.
- Inalcanzables desde antes, también en PROD: Call Process tag photo (y su variante (text)), Action is assign pending?, Send tag list, Send tag response y Send tag code response. Siguen así; **no conviene reconectarlos sin arreglar antes DT-6** en Process tag photo, Assign tag to parcel y Assign tag to parcel (direct).
- La salida fallback del Main Router no está conectada (viene de antes): una acción desconocida no recibe respuesta. Es inofensivo, porque todas las acciones tienen salida.

### 2.8 Casos límite
- **Panelista sin nodo.** En KENYA hay **22 panelistas con Telegram y los 22 sin `node_id`**; es un problema de datos que viene de antes. Con el bot nuevo:
  - las listas salen vacías;
  - en B no hay candidatos y va al responsable;
  - en G, "Primero elige el envío" lleva a una lista vacía.
  
  Nada se rompe, pero esos panelistas no pueden usar las funciones de envíos ni hoy ni después. Hay que revisarlo con el responsable de KENYA.
- **Telegram con forma de enlace** (35 panelistas con `t.me/…` u otro texto no numérico):
  - Deliver los marca `failed` ("chat not found");
  - Material questions los trata como no entregables (nota interna y un solo email);
  - si el panelista escribe al bot, Identify no lo reconoce, entra en el alta por email y `Link telegram to panelist` sustituye el enlace por el id numérico (comportamiento de antes).
- **Árabe**: textos en los 4 idiomas y RTL simulado. El árabe real en Telegram no se ha visto nunca: hay que verificarlo en la prueba.
- **Textos muy largos**:
  - el log de conversación corta a 4000 caracteres;
  - Deliver quita la cabecera si se pasan los 4096 (si el cuerpo solo ya pasa de 4096, falla igual que antes);
  - el clasificador recibe el texto entero, con salida limitada a 300 tokens.
- **Nombre con `_` o `*`**: `Send start menu` usa `parse_mode: Markdown` (viene de antes) y un nombre así puede hacer que Telegram rechace el menú.

### 2.9 Partes NO tocadas (regresión)
- Registro (Panelist known?, Ask for email, Lookup email, Link telegram, Register new panelist): mismos nodos, solo el prefijo `=`.
- `/myid`: ahora sí evalúa la plantilla. En PROD el texto no lleva `=` y se envía literal.
- Envío de fotos (Get photo file → Analyze image → Process send photo): mismo camino, con la validación DT-6 añadida.
- Recepción: mismo camino → Mark Parcel as received (DT-6).
- Baja (Panelist unavailability, el workflow PROD llamado igual que antes; el texto libre de fechas ahora abre el menú de baja).
- Material receipt: la versión nueva sustituye a la vieja. Sus botones antiguos `material_pick_`/`material_ok_` abren el flujo de cantidades.
- Botones antiguos ya enviados por el bot viejo (`show_pending_parcels`, `report_incident`, `start_receipt`, `unav_*`, `material_*`): el main nuevo los sigue entendiendo.

---

## 3. Triage

### 3.1 BLOQUEANTES (hay que cumplirlos antes de la promoción o durante ella)

1. **Credencial PROD en nodos nuevos: hay que verificarla.**
   - La API a veces ha ignorado en silencio los cambios a nodos con la credencial Telegram PROD. En el proyecto personal llegó a **rechazar** un nodo nuevo con esa credencial (informe 1b).
   - Hay que cambiar 57 nodos (tabla 2.5) y unos 26 del main son nuevos.
   - Método obligatorio:
     - copiar con un usuario que tenga acceso a la credencial `rp79mLnvGH8hxiaL`, por la interfaz de n8n (importar o pegar el JSON) o por REST dentro del proyecto "One Panelist";
     - **releer** el workflow;
     - comprobar con un script que queda **0** nodos con `XWH25E2sLytLHGeZ` y que todos los nodos Telegram tienen `rp79mLnvGH8hxiaL`.
2. **No copiar el arnés DEV y conservar el Trigger de PROD.**
   - Hay que quitar `DEV test harness (webhook)` (ruta `dev-telegram-harness`, sin autenticación de n8n, protegida solo por un token en el código; permite suplantar cualquier `telegram_id`) y `Unwrap harness body`, con su conexión a Set fields1.
   - Hay que mantener el nodo `Telegram Trigger` de PROD (webhookId `0b654649…`).
   - **Nunca** activar el DEV main con la credencial PROD: robaría el webhook del bot real (Telegram solo admite un webhook por bot).
3. **Orden obligatorio** (apartado 4): primero las copias DT-6 y los subflujos compatibles; después el **main junto con Material receipt**; y solo entonces activar Deliver incident messages y Material questions. Si se activan antes, sus botones `conv_*` y `mat_*` llegan a un main viejo que se los pasa al AI Agent.
   - El main nuevo envía texto escrito a Process send photo por la ruta G, así que **la versión DT-6 de Process send photo y de Mark Parcel as received tiene que estar en PROD antes que el main**, o a la vez.
4. **Aplicar la migración `20261022100000_incident_conversation_unread.sql` antes de activar "Notify unread incident replies".**
   - Esa migración crea las funciones `due_unread_reply_notifications`, `mark_unread_reply_notified` y `mark_incident_conversation_read`, que hoy **no existen** en la BD (verificado), y los triggers que cierran la conversación al resolver.
   - El filtro de `report_flow`, `callback` y `material%` ya está incluido (concern 1 de las tareas 4-5: resuelto).
5. **No desactivar "Deliver incident replies" (`zpCm5uOEeDTXUIco`) todavía.**
   - La web de producción (`main`) sigue usando `reply_to_panelist` (ReportedIncidentPanel). La función `resolve_panelist_incident` escribe `reply_status='pending_send'`, y eso solo lo entrega el workflow viejo.
   - Los dos workflows pueden convivir sin duplicar mensajes: usan tablas distintas y `resolve_panelist_incident` solo escribe una nota interna `sent` en `incident_message`.
   - El viejo se desactiva cuando la web de `develop` (conversación) esté en `main` y no queden filas `pending_send`.
6. **Mover los workflows del proyecto personal a "One Panelist" antes de sobrescribirlos.**
   - Están en el proyecto personal: `Report incident` PROD `hwsO71yoXRHIOfHC`, `[DEV] Report incident` `3F2KV0w8GFaTqP1b`, `[DEV] Process send photo` `ajyoC6IgRnv6mjjj` y `[DEV] Mark Parcel as received` `dg9yQ4eqCYnB2tcl`. También `Assign tag to parcel (direct)` y `Deliver panelist notifications`, que no se tocan.
   - En el proyecto personal la API ha descartado en silencio cambios en nodos con credencial (todos estos llevan Postgres `735a8…`).
   - Después de cada PUT: releer y comparar.

### 3.2 Riesgos aceptables (conocidos y documentados)
- **Sin prueba de punta a punta.** Es una decisión del usuario, porque no hay bot DEV. Se mitiga con la prueba DEMO2 inmediata y el rollback preparado. Nunca se han ejecutado con Telegram real:
  - la ruta `open` con email de Report incident;
  - las escrituras de B y H;
  - la forma real de la respuesta de Telegram en Deliver;
  - el flujo de material completo.
- **Conversación abierta**: todo texto va al responsable durante 48 h, hasta pulsar «Volver al menú» o hasta que se resuelva la incidencia (lo segundo, con la migración aplicada).
- Con un `selected_parcel` activo, cualquier texto se toma como etiqueta (viene de antes). Ahora un texto no válido recibe "formato no válido" en lugar de guardarse como `tag_id`.
- Un `pending_receipt` viejo (hoy quedan 11, del 2026-10-07) captura el primer texto de esos panelistas como código de recepción. Recomendado: limpiarlos antes. Es una escritura en la BD y requiere confirmación.
- Deliver pone botones (Responder / Volver al menú) también en los mensajes que no vienen del responsable (un único nodo Telegram).
- B muestra un mensaje por candidato.
- Si falla un envío de Telegram en Material receipt, se pierde sin registro.
- Si el insert de auditoría falla después de aplicar un cambio de B o H, el dato queda bien pero sin fila de incidencia.
- Material questions solo pregunta envíos con incidencia `open` o `in_progress`. Los 28 envíos `pending` de KENYA sin incidencia nunca se preguntan (no hay spam). Hoy `due_material_questions(now())` devuelve 0.
- Los emails llevan enlace a `https://onems.edgeavs.net/...`: **confirmar que es la URL real de la web** (en el repo solo aparece `glossary-onems.edgeavs.net`).
- `errorWorkflow` `GL0zZodVtQDuVHO2gu_qJ` (main, Parcels to send y otros) no existe entre los workflows: los errores no avisan a nadie. Viene de antes.
- `Lookup email` usa `ilike` (el `_` actúa de comodín) y lleva el JWT escrito (DT-2). Viene de antes.
- Coste y latencia: una llamada a gpt-4o-mini por cada texto escrito (unos 0,9 s y unos 0,0001 $).
- Los datos de prueba `[TEST-V2-N8N]` de DEMO2 están pendientes de limpiar cuando el usuario lo diga.

### 3.3 Urgente pero independiente de la promoción (seguridad, viene de antes)
- **`Register new panelist` `2L2RHXdu7i94amgd` → nodo `Insert panelist`.** Mete en el SQL, con `'{{ … }}'`, el nombre, el email, el teléfono, la dirección, la ciudad, el país y el código postal **escritos por un desconocido** durante el alta por Telegram.
  - Es alcanzable por cualquiera que escriba al bot, en PROD y en DEV.
  - Es la inyección SQL más grave del bot.
  - Arreglo: `queryReplacement` con `$n`.

---

## 4. CHECKLIST DE PROMOCIÓN (en orden)

> Antes de cada escritura en la BD o en un workflow PROD hay que nombrar el proyecto y pedir confirmación explícita al usuario. BD: onems-dev `sehbnpgzqljrsqimwyuz`.
> Ventana recomendada: un día laborable a media mañana, fuera de las 07:00 (recordatorio) y de las 09:00 (On new parcel to send), y lejos de las 10:00 y 16:00 (Deliver incident replies).

### Fase 0 — Preparación (sin efectos)
- [ ] Exportar a `panelist_n8n/workflows/backups/` (carpeta gitignored) el JSON vivo de cada PROD que se va a tocar, y anotar su `versionId` actual:

  | PROD | id | versionId antes |
  |---|---|---|
  | Telegram - User initiated message | `IkVtek2csP5AbWxB` | `fe34e48b…` |
  | Report incident | `hwsO71yoXRHIOfHC` | `1b190ed8…` |
  | Process send photo | `07Kx1L9S29BfbLrV` | `c152fcbf…` |
  | Mark Parcel as received | `pEOWvi8uU4JhYUf4` | `1e4920cc…` |
  | Material receipt | `UJiafr1Mt02dtpUy` | `0349fbe9…` |
  | Parcels to send | `Tm2yrywGUDq0PEj3` | `8bad5a38…` |
  | On new parcel to send | `p8497yoHcX1Z3cfH_9j5S` | `6e7eb045…` |
  | Deliver incident replies | `zpCm5uOEeDTXUIco` | `9ee922d4…` (no se toca) |
- [ ] Volver a leer los DEV justo antes de copiar, por si alguien los cambió después del 2026-10-21 19:08Z.
- [ ] Confirmar que ninguna otra copia consume `pending_incident_messages`. Hoy solo `D8dRPQGK2HiMKzDZ` (inactivo) lo hace. "Deliver panelist notifications" `592sTnywfgiIGKI7` usa otra tabla (`panelist_notification`) y no se toca.
- [ ] Mover a "One Panelist" (`3p4DsIlSNKeYlFOh`): `hwsO71yoXRHIOfHC`, `3F2KV0w8GFaTqP1b`, `ajyoC6IgRnv6mjjj` y `dg9yQ4eqCYnB2tcl` (bloqueante 6).
- [ ] Preparar el script de verificación posterior. Por cada workflow promocionado debe comprobar:
  - (a) 0 nodos con `XWH25E2sLytLHGeZ`;
  - (b) ningún `executeWorkflow` apunta a `3F2KV0w8GFaTqP1b`, `ajyoC6IgRnv6mjjj`, `dg9yQ4eqCYnB2tcl`, `cZdV1mCISEQREJVA` ni `WiDzFz7Y9NakVr9C`;
  - (c) no queda ningún webhook `dev-telegram-harness`;
  - (d) número de nodos y de conexiones igual al de la fuente (menos los 2 del arnés).

### Fase 1 — Base de datos
- [ ] Con confirmación explícita: aplicar `supabase/migrations/20261022100000_incident_conversation_unread.sql` en onems-dev `sehbnpgzqljrsqimwyuz`.
- [ ] Verificar con SELECT:
  - existen la columna `incident_message.read_at` y las 4 funciones;
  - `SELECT * FROM due_unread_reply_notifications(now())` devuelve solo filas reales (las de prueba quedan marcadas como leídas por el backfill).
- [ ] Opcional (escritura, con confirmación): borrar los `panelist_context` `pending_receipt` de más de 7 días (hoy 11).

### Fase 2 — Subflujos compatibles con el main viejo (DT-6 incluida)
En cada fila se copia el contenido de la copia DEV **sobre el id de PROD**. Así se conservan el id, los llamadores, el historial de versiones y los ajustes de PROD (`errorWorkflow`, `callerPolicy`).

| Copiar de (DEV) | Sobre (PROD) | Cambios al copiar |
|---|---|---|
| `[DEV] Process send photo` `ajyoC6IgRnv6mjjj` | `Process send photo` `07Kx1L9S29BfbLrV` | Ninguno (no tiene Telegram). Mantener los settings de PROD. |
| `[DEV] Mark Parcel as received` `dg9yQ4eqCYnB2tcl` | `Mark Parcel as received` `pEOWvi8uU4JhYUf4` | Mantener el `errorWorkflow` y el `callerPolicy: any` de PROD. |
| `[DEV] Report incident` `3F2KV0w8GFaTqP1b` | `Report incident` `hwsO71yoXRHIOfHC` | Ninguno. Es compatible con el main viejo: las entradas nuevas toman valores por defecto (`other`/`open`). Cambio visible: ya no pone el envío en estado `incident`. |
| `[DEV] Parcels to send` `WiDzFz7Y9NakVr9C` | `Parcels to send` `Tm2yrywGUDq0PEj3` | Nodo "Send Messege Garthering Information" → credencial PROD `rp79mLnvGH8hxiaL`. |

- [ ] Releer cada workflow y pasar el script de verificación.
- [ ] Prueba rápida con el bot real todavía viejo: pedir "mis envíos" a la IA vieja (sigue llamando a Parcels to send) y responder un número. Debe funcionar igual que antes.

### Fase 3 — Main y Material receipt (juntos, en pocos minutos)
1. [ ] `Material receipt` `UJiafr1Mt02dtpUy` ← contenido de `[DEV] Material receipt` `cZdV1mCISEQREJVA`, con los 3 nodos Telegram (Send reply, Send reply (1 button), Send reply (2 buttons)) en credencial PROD.
   - **Inmediatamente después**:
2. [ ] `Telegram - User initiated message` `IkVtek2csP5AbWxB` ← contenido de `[DEV] Telegram - User initiated message` `eeM4E4RS1UDThvUF`, con estos cambios:
   - quitar los nodos `DEV test harness (webhook)` y `Unwrap harness body`, y sus conexiones;
   - **conservar el nodo `Telegram Trigger` de PROD** (webhookId `0b654649-803c-41a4-86d0-559099262afa`, credencial PROD);
   - los 51 nodos Telegram, incluidos `Get photo file`, `Get reply photo file` y `Send conv reply prompt`, en credencial PROD `rp79mLnvGH8hxiaL`;
   - repuntar los Execute Workflow:

     | Nodo | DEV apunta a | PROD debe apuntar a |
     |---|---|---|
     | Call Report incident | `3F2KV0w8GFaTqP1b` | `hwsO71yoXRHIOfHC` |
     | Call Process send photo / (text) | `ajyoC6IgRnv6mjjj` | `07Kx1L9S29BfbLrV` |
     | Call Mark Parcel as received (text) / (image) | `dg9yQ4eqCYnB2tcl` | `pEOWvi8uU4JhYUf4` |
     | Call Material receipt (cb) | `cZdV1mCISEQREJVA` | `UJiafr1Mt02dtpUy` |
     | Call Parcels to send (direct) | `WiDzFz7Y9NakVr9C` | `Tm2yrywGUDq0PEj3` |
     | (sin cambio) Call Parcels to receive (direct), Panelist unavailability (cb/text), Register new panelist (×2), Save parcel selection, Assign tag to parcel, Process tag photo (inalcanzable) | PROD | PROD |
     | Tools desactivados (parcels_to_*, mark_parcel_*, all_parcels, confirm_send_selection, send_*_to_manager) | PROD | dejarlos como están (desactivados) |
   - mantener los settings de PROD: `errorWorkflow`, `callerPolicy: workflowsFromSameOwner`, `executionOrder v1`.
   - Si se hace por REST: el PUT de un workflow activo **se publica al momento**. Releer enseguida y pasar el script de verificación (bloqueante 1).
3. [ ] Prueba mínima inmediata con PAN-DEM-003: `/start`, "Hola" y "mis envíos" (pasos 1–3 del apartado 5). Si algo falla, rollback del main y de Material receipt.

### Fase 4 — Activar los workflows nuevos que envían botones
- [ ] Activar **Deliver incident messages** `D8dRPQGK2HiMKzDZ` (credencial PROD ya puesta; añadir etiqueta PROD).
  - Lo primero que entregará será el "hola" de DEMO2 `efc2c2ba…`.
  - **Mantener activo "Deliver incident replies" `zpCm5uOEeDTXUIco`** (bloqueante 5).
- [ ] Activar **Material questions** `iYlRf37ly1xbCPxp` (credencial PROD ya puesta). Hoy no tiene nada pendiente; empieza a preguntar cuando haya envíos `pending` ligados a incidencias abiertas.

### Fase 5 — Tarea diaria de envíos
- [ ] `On new parcel to send` `p8497yoHcX1Z3cfH_9j5S` ← contenido de `[DEV] On new parcel to send` `mWtLvurQ9PpDrf9x`:
  - Execute Workflow → `Tm2yrywGUDq0PEj3`;
  - "Send parcel list" y "Send release message" en credencial PROD;
  - conservar el Schedule 09:00 y los settings de PROD.
- [ ] **No activar nunca** `mWtLvurQ9PpDrf9x`: dejarlo inactivo o archivarlo.

### Fase 6 — Avisos de respuestas sin leer
- [ ] Solo después de la Fase 1: activar **Notify unread incident replies** `uW4wQDhodSus7b5z`.
  - Comprobar la primera ejecución (cada 15 min): sin errores y sin emails sobre datos de prueba.

### Fase 7 — Retirada de lo viejo (días después, cuando todo esté estable)
- [ ] `Notify manager (AI tool)` `Z63nZ0hYRwbtKYbC`: después de la Fase 3 ya no lo llama nadie, porque sus dos tools están desactivados. Dejarlo activo unos días, para poder volver atrás, y luego desactivarlo o archivarlo.
- [ ] `Deliver incident replies` `zpCm5uOEeDTXUIco`: desactivarlo cuando la web de `develop` esté desplegada en `main` y `SELECT count(*) FROM panelist_incident WHERE reply_status='pending_send'` sea 0.
- [ ] Las copias DEV (`3F2KV0w8GFaTqP1b`, `ajyoC6IgRnv6mjjj`, `dg9yQ4eqCYnB2tcl`, `cZdV1mCISEQREJVA`, `WiDzFz7Y9NakVr9C`) pueden quedarse para el próximo desarrollo. **Hay que borrar el nodo del arnés del DEV main**: es un webhook público.
- [ ] Volver a exportar a `panelist_n8n/workflows/` (sin secretos, `grep -c eyJ` = 0), actualizar este documento y la memoria.

### DT-6 — subflujos PROD que siguen vulnerables
| Workflow PROD | Nodos con `{{ }}` en SQL | Origen del dato | Estado tras la promoción |
|---|---|---|---|
| Process send photo `07Kx1L9S29BfbLrV` | Mark as sent (`tag_id`), Get panelist, Get/Delete send pending tag context | **texto escrito / OCR** | **Corregido en la Fase 2** (copia DEV) |
| Mark Parcel as received `pEOWvi8uU4JhYUf4` | get allocation plan details id (`tag_id`) | **texto escrito / OCR** | **Corregido en la Fase 2** |
| **Register new panelist** `2L2RHXdu7i94amgd` | **Insert panelist** (todos los datos del alta), Create new context (Supabase) | **texto de un desconocido** | **Sigue vulnerable — urgente (3.3)** |
| Process tag photo `PrbIkeUhaKrxP0KC` | Get panelist, Check tag in allocation plan (`tag_id`), Mark as received, Get pending parcels, Save assignment context (`tag_id`, `$json.response`) | OCR / texto | Vulnerable; hoy inalcanzable desde los dos main |
| Assign tag to parcel (direct) `NXKOurAMtMNsDeTw` | Assign tag (`tag_id`, `parcel_id`), Delete selected parcel ctx | viene de Process tag photo | Vulnerable; inalcanzable |
| Assign tag to parcel `XFrm8PniT7fUeHNv` | Get pending tag context, Assign tag to parcel (`tag_id` del contexto, segundo orden), Delete pending context | contexto | Vulnerable; solo le llegan dígitos |
| Save parcel selection `wMuV1xhvaaHkR8sd` | Save pending tag context (destino, transportista, producto, fecha…) | BD (un apóstrofo rompe la consulta) | Vulnerable (bajo); alcanzable |
| Confirm send selection `J8QKXqjuyqLcvwrw` | Get pending list context, Get parcel details, Save send pending tag context | `$fromAI` | Inalcanzable (tool desactivado) |
| Mark Parcel as sent `HnQ56xWLSalU4UDn` | get allocation plan details id (`scheduled_date`, nodos) | `$fromAI` | Inalcanzable (tool desactivado) |
| Parcels to receive `jbuilD2MD4nU3iPN` | Get allocation plans (`node_id`) | BD | Riesgo bajo; alcanzable |
| All parcels for a specific user `PH1JaG4CqVwyuHJs` | Get all parcels… (`node_id`) | BD | Inalcanzable |
| Notify manager (AI tool) `Z63nZ0hYRwbtKYbC` | Lookup panelist + account (`telegram_id`) | Telegram id | Inalcanzable |

---

## 5. Prueba en el bot real (DEMO2), justo después de la Fase 3 y de la Fase 4

Panelista: **PAN-DEM-003** (telegram `8349275418`, ya vinculado al bot real @OneMSBot). Para B hace falta además un panelista DEMO2 con envíos `sent` hacia su nodo (PAN-LA-02 o PAN-SAC-01) o un envío preparado con confirmación.

Antes de empezar, anotar con un SELECT el `mobile`, `email`, `language` y `address_line1` de PAN-DEM-003.

| # | Acción en Telegram | Resultado esperado |
|---|---|---|
| 1 | `/start` | Saludo y menú de 7 botones. |
| 2 | "Hola" | Menú con "Elige una opción:". No responde ninguna IA. En n8n, `Classify free text` se ejecuta una vez y el AI Agent ninguna. |
| 3 | "mis envíos" → «Ver más» → escribir "8" | Lista de 5 en 5 y luego el mensaje de selección del n.º 8. |
| 4 | Botón «Ver paquetes a recibir» | Lista de recepción o "No tienes…". |
| 5 | "no puedo participar del 5 al 10 de noviembre" | Se abre el menú de baja. Cancelar. |
| 6 | Reportar incidente → "El paquete está roto" → Sí | "Registrado, gracias por avisar." y fila `parcel_damaged`/`auto_resolved` con 6 mensajes en su conversación. |
| 7 | "Me han devuelto el envío" → «No, es otra cosa» | Menú y **ninguna** fila nueva. |
| 8 | "Me han devuelto el envío" → Sí | Fila `open` y **email al responsable de DEMO2** (primera prueba real de esta ruta). |
| 9 | "Mi nuevo teléfono es 600 123 456" → Sí → Teléfono → valor → Sí | "Datos actualizados." `mobile` cambiado, `telegram_id` intacto. **Restaurar el teléfono anterior.** |
| 10 | Seleccionar un envío → Reportar incidente → "No consigo hacer la foto del tag" → Sí → escribir `TEST-G-001` | "✅ … declared as sent", sin fila de incidencia. **Restaurar la muestra.** |
| 11 | Con un envío seleccionado, escribir "ya lo he enviado" | "⚠️ La etiqueta no tiene un formato válido…" y nada guardado. |
| 12 | Declarar recepción → foto de etiqueta | El flujo de recepción, como antes. |
| 13 | (Fase 4) Esperar ≤ 5 min | Llega el "hola" de DEMO2 con cabecera y botones «Responder» / «Volver al menú». En la BD: `efc2c2ba…` en `sent` con `telegram_message_id`. |
| 14 | Escribir "gracias, recibido" y después una foto | Un solo acuse ("Tu mensaje llega a tu responsable…"), 2 filas inbound (la foto con `meta.photo_path`) y la foto visible en la web. |
| 15 | «Volver al menú» y después "Hola" | Sale el menú. El "Hola" ya no va a la incidencia. |
| 16 | Escribir en árabe (poner el idioma `ar` en el paso 9 y luego restaurarlo) | Textos RTL bien formados. |
| 17 | Material (solo si hay datos: donante y receptor DEMO2 con Telegram y un suministro `pending` ligado a una incidencia abierta) | Guion del informe de las tareas 2-3, apartado 5: pregunta al donante → «Ya lo he enviado» dos veces → pregunta al receptor → cantidades. |
| 18 | `/myid` | Muestra el id real, sin `{{ }}` sin evaluar. |

Comprobaciones de solo lectura al terminar:
```sql
SELECT created_at, category, status, payload FROM panelist_incident
 WHERE panelist_id = (SELECT id FROM panelists WHERE panelist_code='PAN-DEM-003') ORDER BY created_at DESC LIMIT 10;
SELECT direction, author, status, count(*) FROM incident_message GROUP BY 1,2,3;   -- outbound/bot siempre 'sent'
SELECT count(*) FROM incident_message WHERE status='pending_send' AND author='bot'; -- debe ser 0
SELECT telegram_id, mobile, email, language, address_line1 FROM panelists WHERE panelist_code='PAN-DEM-003';
```
En n8n: ninguna ejecución con error en el main, en Material receipt, en Deliver ni en Material questions.

**Criterio para volver atrás:**
- cualquier error en el main;
- un mensaje enviado por el bot DEV a un usuario real;
- un botón que no responde;
- un texto normal que se registra como incidencia sin pasar por el Sí.

---

## 6. Plan de vuelta atrás (rollback)

El orden importa: **primero apagar lo que envía botones nuevos y después restaurar el main**. Si se hace al revés, el main viejo recibiría botones `conv_*` y `mat_*` que no entiende.

1. Desactivar **Material questions** `iYlRf37ly1xbCPxp`, **Deliver incident messages** `D8dRPQGK2HiMKzDZ` y, si estaba activo, **Notify unread incident replies** `uW4wQDhodSus7b5z`.
   - "Deliver incident replies" `zpCm5uOEeDTXUIco` sigue activo, así que las respuestas de la web vieja se siguen entregando.
2. Restaurar el **main** `IkVtek2csP5AbWxB` a `fe34e48b…`:
   - por la interfaz de n8n: Workflow → historial de versiones → Restaurar;
   - o con un PUT del backup de la Fase 0;
   - después, comprobar que el Trigger sigue con la credencial PROD y que el workflow está activo.
3. Restaurar del mismo modo **Material receipt** (`0349fbe9…`), **On new parcel to send** (`6e7eb045…`) y, si hace falta, **Parcels to send** (`8bad5a38…`) y **Report incident** (`1b190ed8…`).
   - Process send photo y Mark Parcel as received (DT-6) se pueden dejar en la versión nueva aunque se restaure el main viejo: son compatibles y más seguros.
4. **BD**: la migración `20261022100000` no hace falta deshacerla. Es aditiva y la web la aprovecha si está. Si hubiera que retirarla, haría falta una migración nueva forward-only (no tocar el baseline).
5. Los contextos `pending_incident_reply` y `pending_material_*` que queden caducan solos (48 h y 1 h) y el main viejo los ignora.
6. Anotar qué falló, con el id de la ejecución, antes de reintentar.

---

## 7. Referencias
- Ledgers e informes:
  - `.superpowers/sdd/2026-10-20-incidencias-reportadas-v2-3-n8n/`
  - `.superpowers/sdd/2026-10-21-incidencias-v2-6-n8n-materiales-conversacion/`
- Notas de cambios: `C:\Users\fernandezi\projects\ONE n8n\panelist_n8n\workflows\patches\incidencias-reportadas-v2.md`
- Exports sin secretos: `C:\Users\fernandezi\projects\ONE n8n\panelist_n8n\workflows\*.json` (sin commit).
- Migración: `supabase/migrations/20261022100000_incident_conversation_unread.sql` (sin aplicar).
