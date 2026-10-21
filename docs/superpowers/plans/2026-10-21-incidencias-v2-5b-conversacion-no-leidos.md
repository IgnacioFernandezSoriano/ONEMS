# Incidencias v2 — Plan 5b: Conversación — no leídos, fotos y cierre (BD + pantalla)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El manager ve qué conversaciones tienen respuesta nueva, las fotos del panelista, y las conversaciones se cierran solas al resolver la incidencia.
**Spec:** `docs/superpowers/specs/2026-10-21-incidencias-conversacion-design.md` §7.

## Global Constraints
- Base `onems-dev` `sehbnpgzqljrsqimwyuz`; migración forward-only `20261022100000_incident_conversation_unread.sql`; aplicar SOLO con confirmación explícita. Tests locales `supabase/tests/run_tests.sh`.
- Frontend: `t()` en 4 idiomas; lint sin avisos nuevos (48 base); build limpio.

### Task 0: Migración
- [ ] `incident_message.read_at timestamptz`, `notified_at timestamptz`; índice parcial `(incident_kind, incident_id) WHERE direction='inbound' AND read_at IS NULL`.
- [ ] `mark_incident_conversation_read(p_incident_kind, p_incident_id)` (authenticated de la cuenta; pone `read_at=now()` a los inbound sin leer).
- [ ] `unread_incident_conversations()` → filas `{incident_kind, incident_id, unread, last_at}` de la cuenta del usuario (RLS/guarda de cuenta; superadmin todas).
- [ ] `due_unread_reply_notifications()` (service_role): inbound sin leer y sin `notified_at` con más de 1 h, agrupados por incidencia, con email del manager de la cuenta (`accounts.email_panelist_manager`, si no `admin_email`); `mark_unread_reply_notified(p_incident_kind, p_incident_id)` pone `notified_at`.
- [ ] Al pasar `panelist_incident.status` a resolved/dismissed/auto_resolved, o `panelist_unavailability.incident_status` a resolved: borrar `panelist_context` `pending_incident_reply` de ese panelista que apunte a esa incidencia (trigger).
- [ ] Tests (fechas relativas, `DO … RAISE`), privilegios (anon sin EXECUTE).

### Task 1: Pantalla
- [ ] `useIncidentConversation`: al montar (y tras cada recarga con nuevos inbound) llama a `mark_incident_conversation_read`; muestra fotos de `meta.photo_path` con URL firmada (bucket `incident-photos`, como `signedPhotoUrl`).
- [ ] Bandejas de reportadas y de bajas: marca "Respuesta nueva" (badge) en las filas con `unread > 0`; el menú lateral suma un contador de conversaciones con no leídos (junto a los contadores actuales), refresco cada 60 s.
- [ ] Claves `incident_conversation.unread_badge`, `.new_reply`, `.photo_alt` en 4 CSV.
