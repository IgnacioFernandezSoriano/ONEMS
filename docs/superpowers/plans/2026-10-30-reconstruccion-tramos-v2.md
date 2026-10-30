# Reconstrucción de tramos v2 — plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** que el cron produzca tramos con tránsito desde la última lectura, tiempos natural/laborable y enriquecimiento completo, reconstruyendo cada etiqueta de forma idempotente.

**Architecture:** una migración forward-only redefine `reconstruct_journeys` (misma firma) y hace el rebuild de KENYA; un test SQL en el harness local cubre los casos del spec.

**Tech Stack:** PL/pgSQL, harness `supabase/tests/run_tests.sh` (Postgres portable 5433).

**Spec:** `docs/superpowers/specs/2026-10-30-reconstruccion-tramos-v2-design.md`

## Global Constraints

- CHECKs de `journey_segments` (ver spec). `exit_timestamp`, `actual_time_minutes`, `adjusted_time_minutes` NOT NULL.
- Firma intacta: `reconstruct_journeys(p_account_id uuid DEFAULT NULL, p_tag_id text DEFAULT NULL) RETURNS TABLE(segments_created bigint, events_processed bigint, execution_time_ms bigint)`, SECURITY DEFINER.
- Ninguna escritura en onems-dev sin OK explícito.

## Review Focus

1. Lectura suelta en A y luego entrada+salida en B → 1 tránsito A→B + 1 operativo B. (test caso 1)
2. Dos pasadas seguidas sin eventos nuevos → mismo número de tramos, mismos ids de evento. (test caso 2)
3. Llega una lectura tardía de salida en A → el tramo operativo de A aparece y el tránsito pasa a empezar en esa salida. (test caso 3)
4. Visita con solo salida (entrada perdida) → sin operativo; tránsito desde la visita anterior hasta esa salida. (test caso 4)
5. Etiqueta vista en un solo centro con entrada+salida → 1 operativo y ningún tránsito; sin SLA → `no_sla`. (test caso 5)

---

### Task 1: test de reconstrucción v2 (falla antes, pasa después)

**Files:**
- Create: `supabase/tests/reconstruct_journeys_v2.test.sql`

- [ ] Escribir el test con fixture `incident_city.sql` + 2 centros (City1/City2, PC2 en `working_days` con horario 08:00–17:00) + lectores, y los 5 casos del Review Focus, cada uno con asserts sobre `segment_type`, `from/to_postal_center_id`, `entry/exit_event_id`, `natural_transit_time_minutes`, `natural_time_in_center_minutes`, `working_time_in_center_minutes`, `origin_city_name`, `carrier_id`, `product_id`, `sla_compliance`, y que todos los eventos quedan `is_consolidated=true`.
- [ ] `bash supabase/tests/run_tests.sh reconstruct_journeys_v2` → FAIL (caso 1: no hay tránsito).

### Task 2: migración `reconstruct_journeys` v2

**Files:**
- Create: `supabase/migrations/20261030145555_reconstruct_journeys_v2.sql`

- [ ] `CREATE OR REPLACE FUNCTION public.reconstruct_journeys(...)` según spec §Qué se construye (visitas = runs consecutivos por centro; operativo si hay entrada y salida posterior; tránsito desde última lectura; SLAs; tiempos duales; snapshots; borrar+reconstruir por etiqueta; marcar todos consolidados).
- [ ] Rebuild KENYA al final (DO block: `UPDATE processed_events SET is_consolidated=false, processed_at=NULL`; `DELETE journey_segments`; `DELETE journeys`; `PERFORM process_rfid_pipeline(kenya)`), sin tocar DEMO2.
- [ ] `bash supabase/tests/run_tests.sh reconstruct_journeys_v2 journeys_origin_destination pipeline_assembly_phase` → 3 PASS.

### Task 3: aplicar y verificar

- [ ] Pedir OK (onems-dev `sehbnpgzqljrsqimwyuz`), `apply_migration`, renombrar el fichero a la versión registrada.
- [ ] Verificar: tramos de tránsito de las etiquetas 00011082 y 00011350; `processed_events` de KENYA sin `is_consolidated=false`; `process_rfid_pipeline(kenya)` todas las fases `success`.
- [ ] Commit en develop.
