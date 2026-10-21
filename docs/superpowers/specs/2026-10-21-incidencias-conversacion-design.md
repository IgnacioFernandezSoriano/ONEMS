# Conversación registrada en las incidencias — Diseño

**Fecha:** 2026-10-21
**Autor:** Ignacio Fernández (con Claude)
**Aplica a:** todas las incidencias — reportadas por el panelista (`panelist_incident`) y de indisponibilidad (`panelist_unavailability`) — y a las que se añadan.
**Estado:** acordado en conversación (2026-10-21).

## 1. Qué y por qué

El manager debe poder ver, dentro de cada incidencia, **toda la conversación con el panelista por Telegram**: lo que envió el bot, lo que respondió el panelista (texto y botones) y lo que escribió el manager desde el cuadro de la incidencia. Y el sistema debe **automatizar** al máximo esos mensajes para que el manager escriba lo mínimo.

Regla de diseño permanente: en cada flujo de incidencia, primero buscar qué puede preguntar o avisar el sistema solo; y todo mensaje entrante o saliente relacionado con una incidencia se registra en ella.

## 2. Modelo

Tabla nueva **`incident_message`** (RLS por `account_id`, lectura `authenticated` de su cuenta y superadmin; escritura solo por RPC):

| columna | |
|---|---|
| `id`, `account_id`, `panelist_id`, `created_at` | |
| `incident_kind` | `reported` \| `unavailability` |
| `incident_id` | id de `panelist_incident` o de `panelist_unavailability` |
| `direction` | `outbound` (al panelista) \| `inbound` (del panelista) \| `internal` (nota del sistema, no se envía) |
| `author` | `bot` \| `panelist` \| `manager` \| `system` |
| `body` | texto tal como lo vio el panelista (en su idioma) o tal como lo escribió |
| `meta` | jsonb: botones ofrecidos, botón pulsado (`callback`), `shipment_id`, `notification_id`, `manager_user_id`, etc. |
| `status` | `pending_send` \| `sent` \| `failed` \| `received` |
| `sent_at`, `error`, `telegram_message_id` | |

RPCs:
- `log_incident_message(p_incident_kind, p_incident_id, p_direction, p_author, p_body, p_meta, p_status)` → la usan n8n (service-role) y los disparadores. Deriva `account_id`/`panelist_id` de la incidencia.
- `send_manager_message(p_incident_kind, p_incident_id, p_body)` → la usa la web: inserta `outbound/manager/pending_send` con `meta.manager_user_id`. Guarda de cuenta.
- `mark_incident_message_sent(p_id, p_ok, p_error, p_telegram_message_id)` → la usa n8n tras enviar.

## 3. Quién escribe en el registro

- **Mensajes del manager**: el cuadro "Respuesta al panelista" de ambas pantallas pasa a escribir en `incident_message` (`send_manager_message`). El campo antiguo `reply_to_panelist` se mantiene solo por compatibilidad (el resolver puede seguir guardándolo, pero el envío sale de `incident_message`).
- **Avisos automáticos** que ya existen (`panelist_notification` de bajas; respuesta "Deliver incident replies"): al enviarse, n8n registra el mensaje con `log_incident_message` (o un disparador al pasar `panelist_notification.status` a `sent` copia el texto si la notificación lleva `incident_id` en el `payload`).
- **Conversaciones del bot** ligadas a una incidencia (alta de incidencia, confirmación de categoría, preguntas de material, respuestas del panelista, botones pulsados): n8n llama a `log_incident_message` en cada paso, con el texto exacto enviado o recibido.
- **Notas del sistema** (`internal`): cambios de estado relevantes que conviene ver en la línea de tiempo ("Material recibido: 300 sobres", "Incidencia resuelta automáticamente").

## 4. Envío

Un único workflow de n8n ("Deliver incident messages", sustituye a "Deliver incident replies" `zpCm5uOEeDTXUIco`) entrega los `outbound` en `pending_send` (cada 5 min y por push desde la web como hoy), marca `sent`/`failed` y guarda `telegram_message_id`. Las respuestas del panelista a un mensaje del manager entran como `inbound` si el panelista tiene una incidencia con conversación abierta (contexto `pending_incident_reply` en `panelist_context`, caduca a las 48 h).

## 5. Pantalla

Bloque **"Conversación"** en el detalle de ambas incidencias (reportadas y bajas): lista cronológica tipo chat (bot/manager a un lado, panelista al otro, notas del sistema centradas en gris), con hora, estado de entrega (enviado / pendiente / fallido) y botones pulsados. Debajo, el cuadro para escribir al panelista (sustituye al actual "Respuesta al panelista"). Textos de la interfaz por `t()` en los 4 idiomas; el contenido de los mensajes se muestra tal cual.

## 6. Fuera de alcance

- Traducir automáticamente los mensajes del manager al idioma del panelista.
- Registro retroactivo de conversaciones anteriores a esta versión (no se guardaron).
