# Plan de pruebas en DEMO2 — incidencias v2, conversación y material

Antes de llevar la pantalla a `main` (producción web). Base de datos y bot ya están en producción; lo único que falta por validar es **la pantalla** y el **recorrido completo** entre pantalla, base de datos y Telegram.

- **Cuenta:** DEMO2 (`f4d823d2-93e6-4755-9a89-9da87e7fa86e`). Es la única cuenta de pruebas. No probar en cuentas reales.
- **Dónde:** pantalla en local (`npm run dev`, rama `develop`) apuntando a la BD de onems-dev; bot real **@OneMSBot** con el panelista de pruebas **PAN-DEM-003** (telegram `8349275418`).
- **Quién:** el responsable, con el móvil con Telegram al lado. Claude puede hacer las comprobaciones de solo lectura de la BD y de n8n cuando se le pida.
- **Regla:** todo lo que se cree debe llevar la marca `[TEST-V2]` en la descripción para poder limpiarlo después.
- **Antes de empezar, anotar** (Claude lo puede sacar con un SELECT): `mobile`, `email`, `language` y `address_line1` de PAN-DEM-003, para restaurarlos al terminar.

Marcar cada caso: ✅ OK · ❌ falla (anotar qué se ve) · ⏭ no aplicable.

---

## 0. Preparación (5 min)

| # | Qué hacer | Esperado |
|---|---|---|
| 0.1 | Arrancar `npm run dev` e iniciar sesión como manager de DEMO2 (y, en otra ventana, como superadmin para las pruebas de cuenta). | Entra sin errores en la consola. |
| 0.2 | Comprobar que existen datos `[TEST-V2]` (incidencias A, D, E… del script `docs/database/2026-10-21-datos-prueba-incidencias-v2.sql`). Si no existen, pedir a Claude que los cree (requiere su confirmación: proyecto `onems-dev`, ref `sehbnpgzqljrsqimwyuz`). | Al menos una incidencia de cada categoría que se quiera probar. |
| 0.3 | Idioma de la interfaz en **español**. | Menú "Incidencias" visible. |
| 0.4 | En n8n (PROD): activos Deliver incident messages, Material questions, Notify unread incident replies y el principal. | Todos activos. |

---

## A. Pantalla del manager (sin Telegram)

### A1. Lista y menú
| # | Caso | Esperado |
|---|---|---|
| A1.1 | Abrir Incidencias reportadas. | Lista con las incidencias de DEMO2 y su categoría (A–I), estado y panelista. |
| A1.2 | Filtrar por estado y por categoría. | La lista cambia y vuelve al quitar el filtro. |
| A1.3 | Abrir una incidencia de **otra** cuenta pegando su URL (solo si se conoce un id). | No muestra datos (aislamiento por cuenta). |
| A1.4 | Con un mensaje del panelista sin leer (hacer antes B3), mirar el menú lateral. | Indicador de "sin leer" en el menú y en la fila. Al abrir la incidencia desaparece. |

### A2. Falta de material (categoría A)
| # | Caso | Esperado |
|---|---|---|
| A2.1 | Abrir la incidencia `[TEST-V2] Me faltan sobres…` (PAN-NY-03). | Sección de suministro: necesidad del **periodo** (no 90 días), stock que consta del panelista, y reparto vecinos → central → compra. |
| A2.2 | Revisar los números a mano con una calculadora para un material. | Necesidad − stock del panelista = lo que hay que repartir. Coincide. |
| A2.3 | Confirmar el reparto y generar la **hoja de envíos**. | Se crean los envíos ligados a la incidencia. La hoja se puede ver, descargar en PDF y en Excel/CSV. |
| A2.4 | Abrir el CSV en Excel. | Abre bien, con tildes, sin celdas raras. |
| A2.5 | Donante: mirar los datos que se le muestran del receptor. | Solo **nombre y dirección** (nada de teléfono ni email). |
| A2.6 | Ir a Stock → "Generar envíos". | Los envíos de la incidencia **no** se borran ni se pisan. |
| A2.7 | Pulsar dos veces rápido "Confirmar". | Se crea un solo conjunto de envíos. |

### A3. Resto de categorías
| # | Caso | Esperado |
|---|---|---|
| A3.1 | **B** etiqueta ilegible | Opciones de tratamiento; al resolver, estado `resolved`. |
| A3.2 | **C** dañado | Sin pasos de más; se puede resolver. |
| A3.3 | **D** devuelto | Acciones sobre la muestra devuelta (ReturnedSampleActions); no rompe stock. |
| A3.4 | **E** cómo enviar | Va al manager (no hay vídeos): el manager puede escribir al panelista. |
| A3.5 | **F** petición de baja | Cancelar la baja o dejarla; coherente con el módulo de bajas. |
| A3.6 | **G** problema con foto del tag | Se puede regularizar la muestra. |
| A3.7 | **H** cambio de datos de contacto | Aplica el dato nuevo y deja constancia. |
| A3.8 | **I** otra | Solo conversación y resolver/descartar. |

### A4. Conversación (web → Telegram)
| # | Caso | Esperado |
|---|---|---|
| A4.1 | En una incidencia de PAN-DEM-003, escribir un mensaje al panelista. | Aparece en la conversación como "pendiente de envío" y pasa a "enviado" en ≤ 5 min. |
| A4.2 | Escribir texto con símbolos Markdown rotos (`_ * [`). | Llega al panelista como texto plano, sin error. |
| A4.3 | Idiomas: cambiar la interfaz a EN, FR y **AR**. | Sin textos en blanco ni claves tipo `incidents.xxx`. En árabe, maquetación RTL correcta. |

---

## B. Bot de Telegram (PAN-DEM-003)

Son los pasos 1–18 del apartado 5 del [checklist de promoción](2026-10-22-promocion-n8n-incidencias-v2.md). Resumen:

| # | Acción en Telegram | Esperado |
|---|---|---|
| B1 | `/start`, "Hola", "mis envíos" | Menú; "Hola" no la contesta ninguna IA; lista de envíos. |
| B2 | "El paquete está roto" → Sí | "Registrado, gracias por avisar." Fila `parcel_damaged` en estado `auto_resolved`. |
| B2b | "Me han devuelto el envío" → «No, es otra cosa» | Menú y **ninguna** fila nueva. |
| B2c | Igual → Sí | Fila `open` y **email al responsable de DEMO2**. |
| B2d | "Mi nuevo teléfono es 600 123 456" → Sí → Teléfono → valor → Sí | `mobile` cambiado; **restaurarlo después**. |
| B2e | "No consigo hacer la foto del tag" → Sí → `TEST-G-001` | Envío declarado; sin incidencia. **Restaurar la muestra.** |
| B2f | "Me falta material" → Sí | Fila categoría A abierta y el sistema pide los materiales/cantidades. |
| B2g | "Cómo envío esto" | Categoría E, pasa al manager. |
| B2h | Texto suelto sin sentido ("asdf") | Menú, no se registra incidencia sin pulsar Sí. |
| B3 | Contestar al mensaje del manager (A4.1): «Responder» → "gracias, recibido" → una foto | Un solo acuse; 2 mensajes en la conversación; la foto se ve en la web. |
| B3b | «Volver al menú» → "Hola" | Sale el menú; ese "Hola" no va a la incidencia. |
| B3c | Pasar 48 h sin responder (o simular) | La conversación se cierra sola; un texto nuevo ya no va a la incidencia. |
| B4 | `/myid` | Muestra el id real, sin `{{ }}`. |

---

## C. Recorrido completo de material (A → Telegram → A)

Necesita **donante** y **receptor** con Telegram distintos. Hoy solo PAN-DEM-003 está vinculado (suposición: hay un solo Telegram de pruebas). Opciones: usar un segundo Telegram propio vinculándolo a otro panelista de DEMO2, o probar un lado cada vez.

| # | Paso | Esperado |
|---|---|---|
| C1 | Incidencia A abierta con reparto confirmado (A2.3), donante con Telegram. | Llega al donante (≤ 1 h, 08–20 h) un mensaje con material, cantidades, **nombre y dirección** del receptor y fecha, con botón «Ya lo he enviado». |
| C2 | Pulsar «Ya lo he enviado» **dos veces**. | Un solo "Gracias, anotado". El envío figura como enviado una sola vez. |
| C3 | Receptor con Telegram: llega "¿Has recibido el material de …?" Sí / No. | Con «No»: "te preguntaremos más adelante". |
| C4 | Con «Sí»: cantidades por material → «Todo» en uno y «Otra cantidad» en otro. | Pide cantidad por material. |
| C5 | En «Otra cantidad», escribir `abc`. | Vuelve a pedirla; **no** se registra nada. |
| C6 | Escribir una cantidad menor a la pendiente. | "Anotado; te preguntaremos por el resto". Envío en `partially_received`. |
| C7 | Completar el resto. | "Recibido todo"; envío completo. |
| C8 | Si al recibir se liberan envíos retenidos del panelista. | Mensaje "Ya puedes enviar estos: …" con fecha y destino. |
| C9 | Panelista con material retenido y recordatorio de las 09:00. | **No** le recuerda los envíos retenidos; si todos están retenidos, no recibe el resumen. |
| C10 | Receptor **sin** Telegram. | La fila se salta y se avisa al manager por email, una sola vez. |
| C11 | Donante sin responder 2 preguntas / receptor sin responder 3. | Email al manager, una vez. |
| C12 | Todo recibido. | La incidencia se cierra sola; toda la comunicación queda en la conversación (bot, panelista, manager). |

---

## D. Avisos por email
| # | Caso | Esperado |
|---|---|---|
| D1 | El panelista escribe y nadie lee la incidencia durante > 1 h. | Un email al manager (≤ 15 min después). Un solo email por tanda. |
| D2 | El panelista solo pulsa botones. | No hay email. |
| D3 | El manager abre la incidencia antes de la hora. | No hay email. |

---

## E. Regresión (que no se haya roto lo anterior)
| # | Caso | Esperado |
|---|---|---|
| E1 | Bajas (indisponibilidad) de punta a punta con el bot. | Igual que antes: resolución automática. |
| E2 | Recepción normal de un paquete con foto de etiqueta. | Flujo de siempre. |
| E3 | Stock → "Enviar seleccionados" y "Generar envíos". | Funcionan; no tocan envíos de incidencia. |
| E4 | Envíos solo lunes–viernes. | Ningún envío cae en fin de semana. |
| E5 | Entrar como manager de **otra** cuenta. | No ve nada de DEMO2. |
| E6 | `npm run lint` y `npm run build`. | Lint sin avisos nuevos (línea base 48); build OK. |

---

## F. Comprobaciones de solo lectura al terminar (las hace Claude)
```sql
SELECT category, status, count(*) FROM panelist_incident
 WHERE account_id = 'f4d823d2-93e6-4755-9a89-9da87e7fa86e' GROUP BY 1,2;
SELECT direction, author, status, count(*) FROM incident_message GROUP BY 1,2,3;
SELECT count(*) FROM incident_message WHERE status = 'pending_send' AND author = 'bot'; -- debe ser 0
SELECT mobile, email, language, address_line1 FROM panelists WHERE panelist_code = 'PAN-DEM-003';
```
Y en n8n: ninguna ejecución con error en el principal, Material receipt, Deliver incident messages, Material questions ni Notify unread incident replies.

## G. Limpieza al terminar
1. Restaurar `mobile`, `language` y la muestra tocada de PAN-DEM-003 (valores anotados en el paso 0).
2. Borrar los datos `[TEST-V2]` / `[TEST-V2-N8N]` con el bloque de limpieza de `docs/database/2026-10-21-datos-prueba-incidencias-v2.sql` (Claude lo ejecuta tras su confirmación explícita, proyecto `onems-dev`).
3. Anotar los fallos encontrados en una lista (caso, qué se vio, captura).

## Criterio para pasar a `main`
- **Imprescindible:** A1–A4, B2–B3 y E1–E6 sin ❌.
- **Debería pasar:** C y D. Si no se pueden probar por falta de segundo Telegram, queda anotado como riesgo aceptado y se vigila los primeros días en producción.
- **Se para y se arregla antes de subir:** cualquier dato visible entre cuentas, un mensaje enviado a un usuario real por error, un botón que no responde, o un texto corriente registrado como incidencia sin pulsar Sí.
