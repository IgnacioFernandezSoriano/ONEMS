# n8n ↔ ONEMS — Incidencias de indisponibilidad (bajas de panelista)

Estado a 2026-10-20: **en producción** (bot "One For Panelist"). Repo n8n: `panelist_n8n` (commits `5201f17`, `74cf89b`).
Diseño: `docs/superpowers/specs/2026-10-20-incidencias-indisponibilidad-resolucion-automatica-design.md`.

## 1. Workflows

| Workflow | Id | Qué hace |
|---|---|---|
| Telegram - User initiated message (PROD) | `IkVtek2csP5AbWxB` | El ayudante de texto libre (`time_off_subagent`) llama a la herramienta `declare_time_off` → guarda la baja, avisa al manager por email y responde "Recibido. Gracias por informar." |
| Telegram - User initiated message (DEV) | `eeM4E4RS1UDThvUF` | Igual, con el bot DEV. Se probó primero aquí. |
| Panelist unavailability (compartido DEV/PROD) | `TWeVlUeFF0WzGH86` | Menú de botones. "✅ Confirmar" llama a `declare_panelist_unavailability`; IF `Declared ok?` → "Recibido. Gracias por informar." / `Send range error` con el `error_code`. |
| Deliver panelist notifications | `592sTnywfgiIGKI7` | Cada 15 min vacía la cola `panelist_notification` por Telegram (bot PROD). |

Credenciales: Postgres `735a8hxfuUEDPIYD` ("OneMS dev - Postgres account"), Telegram PROD `rp79mLnvGH8hxiaL`.

## 2. `declare_panelist_unavailability(p_panelist_id uuid, p_start_date date, p_end_date date, p_reason text default 'other', p_notes text default null) → jsonb`

Solo `service_role`/`postgres` (la credencial de n8n). La cuenta se deriva del panelista; crea la baja y dispara la incidencia.

- Éxito: `{ok: true, unavailability_id, start_date, end_date, days, affected_samples, pending_samples, incident_status}`.
- Error: `{ok: false, error_code, ov_start?, ov_end?}` con `error_code` ∈
  `panelist_not_found | no_date | bad_reason | end_before_start | in_past | too_long (>90 días) | overlap` (en `overlap`, `ov_start/ov_end` = baja existente).
- `p_reason` ∈ `vacation | sick_leave | personal | other`.

## 3. Cola `panelist_notification`

Columnas: `id, account_id, panelist_id, kind, payload jsonb, status ('pending_send'|'sent'|'failed'), error, created_at, sent_at`.

- `kind = 'unavailability_received'` (bajas dadas de alta desde la web): `payload = {unavailability_id, start_date, end_date}`.
- `kind = 'plan_change_this_week'` (solo si la fecha antigua o nueva cae en la semana actual, lunes–domingo):
  - Comunes: `detail_id, change, old_date, new_date, scheduled_date, product_description, carrier_name, recipient_role`.
  - `change` ∈ `shift_date | reroute_origin | reroute_destination | cancel | revert`.
  - `recipient_role` ∈ `sender | receiver | former_sender | former_receiver`.
  - `sender` añade `origin_node_code, destination_node_code, destination_panelist_name, destination_address{address_line1, address_line2, postal_code, city}`.
  - `receiver` añade `origin_node_code, destination_node_code, origin_panelist_name` (nunca una dirección).
  - `former_*`: solo los comunes (minimización de datos). **Las plantillas deben tolerar campos ausentes.**

Entrega (workflow `Deliver panelist notifications`):
- Lee `pending_send` de los últimos 7 días (máx. 50 por pasada), solo panelistas con `telegram_id` numérico (el resto queda en cola).
- Texto plano (sin Markdown) en ES/EN/FR/AR según `panelists.language`.
- OK → `status='sent', sent_at=now()`. Telegram rechaza → `status='failed', error=<motivo>`.

## 4. Pendiente / notas

- Revisión nativa de los textos FR/AR.
- **Seguridad (preexistente):** el nodo de búsqueda de panelista por email de `Telegram - User initiated message` lleva una clave `service_role` de Supabase escrita en el código (está en el historial del repo `panelist_n8n` desde `851357d`). Recomendado: rotar la clave y pasar ese nodo a la credencial Postgres.
