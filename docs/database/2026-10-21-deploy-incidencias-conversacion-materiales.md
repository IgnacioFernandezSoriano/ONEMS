# Despliegue — Conversación en incidencias + falta de material v2 (base de datos)

**Migración:** `supabase/migrations/20261021120000_incidents_conversation_materials.sql` · **Proyecto:** onems-dev `sehbnpgzqljrsqimwyuz`
**Test local:** `bash supabase/tests/run_tests.sh incidents_conversation_materials` → PASS (2026-10-21).

## Qué cambia
1. `incident_message`: conversación de todas las incidencias. Solo lectura para la web; escritura por RPC (`send_manager_message` para el manager; el resto solo n8n/servidor).
2. Envíos de material enlazados a su incidencia y agenda de preguntas por Telegram (`due_material_questions`, `record_material_question`).
3. Recepción parcial (`receive_material_shipment_items`); `receive_material_shipment` recibe lo pendiente y **ya no cancela la baja** por materiales; la incidencia se resuelve cuando llegan todos sus envíos.
4. Envíos retenidos por falta de stock (`material_hold`, `refresh_material_hold`, `panelist_held_detail_ids`).
5. Avisos enviados y respuestas del manager (vía antigua) quedan registrados en la conversación; `resolve_panelist_incident` registra los cambios de estado y libera los retenidos al cerrar una de material.
6. Reglas nuevas: el panelista de una incidencia debe ser de su cuenta; una incidencia enlazada a un envío debe ser de la misma cuenta; un material no puede repetirse en un mismo envío.

## Pre-checks (hechos 2026-10-21, solo lectura) — todo OK
- Ningún objeto nuevo existe; constraints `material_shipments_status_check` y `panelist_notification_kind_check` existen con esos nombres.
- Cuerpos vivos de `send_material_shipment`, `receive_material_shipment`, `resolve_panelist_incident` = repositorio.
- `material_shipments`: 33 filas, todas `pending`; `material_shipment_items`: 150, sin material repetido por envío.
- 0 incidencias con panelista de otra cuenta; panelistas todos `active`; `panelist_notification.kind` solo `plan_change_this_week`.

## Post-checks
- `to_regclass` de `incident_message` y `material_hold` no nulos; RLS activa; `authenticated` sin INSERT en ambas.
- `anon` sin EXECUTE en ninguna función nueva; `authenticated` solo en `send_manager_message`, `receive_material_shipment_items`, `send_material_shipment`, `receive_material_shipment`.
- 4 triggers nuevos presentes. Vigilar las siguientes ejecuciones de n8n "Deliver incident replies" y "Material receipt".

## Vuelta atrás
Migración forward-only: deshacer con otra migración (DROP de tablas/funciones/triggers nuevos; recrear las tres funciones con su cuerpo de 20260806160000 / 20260807100100 / 20260807100200; quitar las columnas nuevas de `material_shipments`; restaurar los CHECK). No devolver EXECUTE a `anon`.
