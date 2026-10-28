# Guía n8n — Confirmación de recepción de material (ONEMS)

**Fecha:** 2026-08-07
**Para:** quien monta los workflows en el proyecto de n8n.
**Objetivo:** que el panelista confirme por Telegram que recibió el material de reposición, y
que esa confirmación cierre el ciclo en ONEMS (acredita stock, cierra la baja, resuelve la
incidencia) con **una sola llamada**.

Este documento es autónomo: puedes copiarlo al proyecto de n8n. No necesita nada del código de
ONEMS salvo lo que aquí se indica.

---

## 0. Resumen en una frase

El panelista pulsa "he recibido el material" en Telegram → n8n averigua de qué envío se trata →
llama a la función `receive_material_shipment(p_shipment_id)` de la BD de ONEMS → esa función
acredita el stock del panelista, marca el envío como recibido, cierra la baja asociada y
resuelve la incidencia. La llamada es **idempotente** (repetirla es seguro).

---

## 1. Datos de conexión

- **Base de datos:** Supabase, proyecto **`onems-dev`**, project-ref **`sehbnpgzqljrsqimwyuz`**.
- Hay **UNA sola base** ("prod" y "dev" son la misma BD; solo cambia el frontend desplegado).
- **Credencial:** usa la **service-role key** de ese proyecto, guardada como **credencial de
  n8n** (nodo Postgres/Supabase o variable de la llamada HTTP). **Nunca** la escribas dentro
  del workflow ni en ningún documento.

### ⚠️ Regla multi-tenant

ONEMS es multi-cuenta, aislado por `account_id`. La service-role **salta el RLS**, así que en
tus lecturas manuales (pasos 2 y 3) **filtra tú por `account_id`**. La función del paso 4 ya
valida la cuenta internamente, no hace falta que la pases.

---

## 2. El reto central: ¿qué envío confirma el panelista?

El panelista solo dice "ya lo recibí". n8n debe deducir el **`shipment_id`**. La vía robusta:
**Telegram del remitente → su panelista → sus envíos en estado `sent`**.

---

## 3. Pasos del workflow

### Paso 1 — Disparador (Telegram Trigger)
Recibe la confirmación del panelista: un botón "✅ He recibido el material" o una palabra clave.
De aquí obtienes el **`telegram_id`** del remitente.

### Paso 2 — Buscar el panelista (nodo Postgres / Supabase, SELECT)
```sql
SELECT id AS panelist_id, account_id, language
FROM panelists
WHERE telegram_id = '{{telegram_id_del_remitente}}';
```
Sin fila → responde "no te reconozco, contacta al coordinador" y termina.

### Paso 3 — Buscar el envío a confirmar (SELECT)
```sql
SELECT id AS shipment_id, shipment_date
FROM material_shipments
WHERE panelist_id = '{{panelist_id}}'
  AND account_id  = '{{account_id}}'
  AND status = 'sent'
ORDER BY shipment_date ASC;
```
- **1 resultado** → ese es el `shipment_id`; ve al paso 4.
- **0 resultados** → responde "no tienes envíos pendientes de confirmar".
- **Varios** → lístalos y que el panelista elija, o confirma el más antiguo. Empieza simple
  (confirmar el más antiguo) si normalmente hay solo uno.

### Paso 4 — Confirmar la recepción (la ÚNICA escritura)

**Opción A — nodo HTTP Request:**
- **Método:** POST
- **URL:** `https://sehbnpgzqljrsqimwyuz.supabase.co/rest/v1/rpc/receive_material_shipment`
- **Headers:**
  - `apikey`: `<service-role key>` (desde la credencial de n8n)
  - `Authorization`: `Bearer <service-role key>`
  - `Content-Type`: `application/json`
- **Body (JSON):**
```json
{ "p_shipment_id": "{{shipment_id}}" }
```

**Opción B — nodo Postgres:**
```sql
SELECT public.receive_material_shipment('{{shipment_id}}');
```

Esa única llamada hace TODO en la BD. No toques `material_shipments`,
`panelist_material_stocks`, `panelist_unavailability` ni `panelist_incident` a mano.

### Paso 5 — Responder al panelista (Telegram)
"✅ Recepción registrada, gracias. Ya puedes retomar tus envíos."
(usa `language` del paso 2 para el idioma correcto: es/en/fr/ar).

---

## 4. Qué hace `receive_material_shipment` por dentro (para saber qué esperar)

1. Bloquea la fila del envío y valida que pertenece a la cuenta correcta.
2. **Idempotente:** si el envío ya está `received`, no hace nada y retorna sin error
   (reintentos seguros). Si está en un estado no válido (p. ej. `cancelled`), lanza excepción.
3. Por cada ítem: suma la cantidad a `panelist_material_stocks`, marca `quantity_received` y
   registra un movimiento `receipt`.
4. Marca el envío `status = 'received'`, `received_date = now()`.
5. Si el envío está enlazado a una incidencia:
   - si tiene baja asociada activa, la pasa a `cancelled` (esto revierte automáticamente los
     desplazamientos de muestras);
   - resuelve la incidencia como `resolved`.
   Si el envío no está enlazado a ninguna incidencia (reposición proactiva), solo hace 1-4.

Permiso: la función tiene `grant execute ... to service_role`, así que n8n puede llamarla.

---

## 5. Errores a contemplar

- **Envío `cancelled` u otro estado no válido:** la RPC lanza error → responde "ese envío ya no
  está activo, avisa al coordinador".
- **Envío ya `received`:** la RPC NO falla (no-op) → responde igual "ya estaba confirmado".
- **Reintentos:** ante la duda de si una llamada llegó, vuelve a llamarla; es seguro.

---

## 6. Consulta de stock (opcional, para reconciliación)

Si en algún flujo necesitas comparar el stock que dice el panelista con el que registra ONEMS:
```sql
SELECT panelist_id, material_id, quantity, last_updated
FROM panelist_material_stocks
WHERE account_id  = '{{account_id}}'   -- obligatorio: filtra tú por cuenta
  AND panelist_id = '{{panelist_id}}';
```
Es una lectura directa; el valor ya vive en Supabase. No lo recalcules ni lo escribas a mano
(para cambiarlo, usa el flujo de recepción).

---

## 7. Cómo probarlo sin Telegram

1. En ONEMS, en una incidencia `missing_materials`, ejecuta el asistente hasta "Crear baja y
   desplazar" (deja un envío en `sent` enlazado a la incidencia).
2. Copia ese `shipment_id` y llama la RPC a mano (paso 4, opción A o B).
3. Verifica: el stock del panelista sube, el envío pasa a `received`, la baja queda `cancelled`
   y la incidencia `resolved`.

---

## 8. Notas

- **Aviso "material en camino" (sentido inverso, ONEMS → panelista):** es un flujo aparte que
  todavía **no está cableado** en ONEMS (falta que ONEMS marque el aviso al enviar). Cuando esté
  listo, se documentará como un segundo workflow. Esta guía cubre solo la **confirmación de
  recepción**, que ya funciona de punta a punta.
- **Seguridad:** la service-role key va siempre en una credencial gestionada por n8n, nunca en
  texto plano. Antes de cualquier escritura, ten claro que la base es `onems-dev`
  (`sehbnpgzqljrsqimwyuz`) — no hay otra.
