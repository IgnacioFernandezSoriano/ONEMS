# GPS fase 3a — informe de operación con la pregunta de lugar — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** El correo L-X-V de cada cuenta muestra quién dice «No» o queda lejos sin contestar, y las referencias de
apartado/casa a revisar.

**Architecture:** La BD calcula (`ops_report._data`, una migración forward-only sobre el cuerpo vivo) y el agente
de Hetzner pinta (`report_build.py` / `report_html.py` / `report_i18n.py`). No se toca el bot.

**Tech Stack:** Postgres 17 (Supabase onems-dev `sehbnpgzqljrsqimwyuz`), Python 3 + pytest (ops-agent, `uv run`).

**Spec:** `docs/superpowers/specs/2026-11-24-gps-informe-design.md`

**Worktrees:** ONEMS → `c:/Users/fernandezi/projects/ONEMS_wt_gps_report` (rama `feat/gps-informe`, desde
`origin/develop`); agente → `c:/Users/fernandezi/projects/ONE n8n/panelist_n8n_wt_gps_report` (rama
`feat/gps-informe`, desde `origin/main`).

## Global Constraints
- Escritura en onems-dev solo con confirmación explícita de Ignacio (proyecto + ref nombrados).
- Forward-only: migración nueva `20261124100000_ops_report_gps_place.sql`; no editar migraciones anteriores.
- Antes de generar la migración, el cuerpo vivo de `ops_report._data` debe coincidir con el del repo (md5 sin
  comentarios ni espacios; vivo hoy = `45379aa528435c416d582cef7a0b37f6`).
- Textos del informe en ES/EN/FR; escuetos, nunca acusan al panelista.
- Umbrales: rojo con «No» ≥ 3 en el periodo; `median_far` sigue en 500 m pero solo en ciudades POBOX.
- Commit/push solo cuando Ignacio lo pida.

## Review Focus
- Panelista sin `gps` (datos antiguos) o `gps` sin las claves nuevas → el informe no falla; cuenta 0.
- Declaración contestada «Sí» (status pasa a `ok`) → no cuenta como lejos ni «No».
- Ciudad sin POBOX con todas las posiciones lejos de la oficina → **no** aparece como oficina dudosa.
- Referencia `declined` (inactiva, sin coordenadas) → no aparece en «a revisar».
- Cuenta sin nada que revisar → anexo con «ninguno», sin titular en «Lo importante».

---

### Task 1: BD — `ops_report._data` con respuestas y revisión de referencias

**Files:**
- Create: `supabase/migrations/20261124100000_ops_report_gps_place.sql` (generada por script desde el cuerpo vivo)
- Modify: `supabase/tests/ops_report_gps.test.sql` (el `gps` de P1 gana claves; casos nuevos)
- Runner local: copia de `scratchpad/gps/gpstest.sh` → `scratchpad/gps/rptest.sh` con
  `ROOT=/c/Users/fernandezi/projects/ONEMS_wt_gps_report` y `DB=onems_test_rpt`.

**Interfaces:**
- Produces (JSON de `ops_report._data`):
  - `panelists[].gps` añade `said_no` (int: declaraciones con `*_self_reported_place = 'other'`),
    `far_unanswered` (int: `*_gps_status = 'far'` y `*_self_reported_place IS NULL`),
    `last_off_day` (texto `YYYY-MM-DD` local o null: último día con «No» o lejos sin respuesta).
  - raíz `gps_review`: `{"references_review": [{"code","name","city","kind","reason","distance_m"}],
    "pobox_without_ref": [{"code","name","city"}]}` (arrays vacíos si no hay nada).
  - `config.gps_reference`: igual, pero `median_far` solo para ciudades con `pp.pobox`.

- [ ] **Step 1: comprobar que repo = vivo.** Extraer el último `CREATE OR REPLACE FUNCTION ops_report._data`
  del repo (`20261120110800_cl_final_fixes.sql`), calcular el md5 normalizado y compararlo con el vivo
  (`execute_sql` de solo lectura). Si no coincide, parar y avisar.
- [ ] **Step 2: tests rojos** en `ops_report_gps.test.sql`:
  - el objeto `gps` esperado de P1 incluye `"said_no":0,"far_unanswered":1,"last_off_day":"2027-03-10"`;
  - fixture nueva D6 (P1 envía 2027-03-11, `sent_gps_status='far'`, `sent_self_reported_place='other'`) →
    `said_no = 1`, `far_unanswered = 1`, `last_off_day = '2027-03-11'`;
  - fixture D7 (`'ok'`, `sent_self_reported_place='pobox'`) → no cambia `said_no` ni `far_unanswered`;
  - `panelist_location_reference` activa con `needs_review = true, review_reason='pobox_far_from_postal_center',
    distance_to_postal_center_m = 1500` para P1 → `gps_review.references_review` = 1 fila con `kind`, `reason`,
    `distance_m = 1500`; una fila `source='declined', active=false` de P2 → no sale;
  - City1 POBOX (`cities.pobox_enabled = true`) y P1 sin referencia `pobox` activa → P1 en `pobox_without_ref`;
    al añadirle una `pobox` activa, desaparece;
  - con City1 **sin** POBOX, la mediana 900 m ya no produce `median_far` para City1; con City1 POBOX sí
    (assert existente se mantiene en ese caso).
- [ ] **Step 3:** `bash rptest.sh build && bash rptest.sh test ops_report_gps` → FAIL en las claves nuevas.
- [ ] **Step 4: generar la migración** con un script Python (`scratchpad/gps/gen_rpt_100000.py`) que toma el cuerpo
  del Step 1 y aplica reemplazos con `assert count == 1`: claves nuevas dentro del `SELECT jsonb_build_object` de
  `gps` (añadir `self_reported_place` y el día local a la subconsulta `g`), filtro `pp.pobox` en `med`/`gc`
  de `gps_reference` para `median_far`, y `'gps_review'` en el `jsonb_build_object` final. Cabecera de comentario
  (qué y por qué, spec 2026-11-24) y mismos REVOKE/GRANT que la definición viva.
- [ ] **Step 5:** `bash rptest.sh mig .../20261124100000_ops_report_gps_place.sql && bash rptest.sh test ops_report_gps cl_final_fixes`
  → PASS ambos.
- [ ] **Step 6: suite completa** `bash rptest.sh test $(ls supabase/tests/*.test.sql | xargs -n1 basename)` →
  solo los 9 fallos previos conocidos (consolidate_*, incident_conversation_unread, landing_tables, monitoring_*,
  poll_cron, readers_reader_id_unique, resolve_provider_reads); `cl_set_quotas_scale` puede ser intermitente.

### Task 2: Agente — columna, tabla «Declaran fuera de su sitio» y anexo de revisión

**Files:**
- Modify: `ops-agent/src/ops_agent/report_build.py` (`gps_cell`, `Report`, `build_report`)
- Modify: `ops-agent/src/ops_agent/report_html.py` (pintar tabla y anexo)
- Modify: `ops-agent/src/ops_agent/report_i18n.py` (ES/EN/FR + glosario)
- Test: `ops-agent/tests/test_op_report.py`

**Interfaces:**
- Consumes: JSON de Task 1.
- Produces: `Report.gps_off: Table` (cabeceras `col_panelist, col_city, col_said_no, col_far_unanswered,
  col_last_day`) y `Report.gps_review: Table` (cabeceras `col_panelist, col_city, col_what, col_reason`; una fila
  por referencia a revisar y por POBOX sin apartado).

- [ ] **Step 1: tests rojos** (helper `_gps` acepta `said_no`, `far_unanswered`, `last_off_day`):
  - `test_gps_cell_shows_no_and_unanswered`: `_gps(10, 7, far=3, said_no=1, far_unanswered=2)` → celda
    `"7/10 · 1 «No» · 2 lejos sin respuesta"`, naranja; `said_no=3` → rojo; `_gps(10,10)` → `"10/10"`, sin color;
    `gps` sin claves nuevas → como hoy, sin error.
  - `test_declaring_off_place_table`: sale quien tiene `said_no` o `far_unanswered` > 0, ordenado por
    `said_no` desc y luego `far_unanswered` desc; columnas con los números y `last_off_day` como `dd/mm`;
    vacía → nota `T["none"]`; en el HTML va tras «7. Quién no registra con GPS» y antes de «Anexo 1.».
  - `test_location_review_annex`: `gps_review` con 1 referencia (`pobox_far_from_postal_center`, 1500) y 1 POBOX
    sin apartado → 2 filas con texto traducido del motivo; HTML: «Anexo 4. Revisión de la ubicación» al final,
    tras «Anexo 3.»; sin `gps_review` → «ninguno».
  - `test_gps_facts_include_new_numbers`: los `said_no` y códigos de la tabla nueva están en `r.facts`.
  - actualizar `test_gps_glossary_and_no_more_no_gps_yet`: la definición GPS ya **no** dice «descontada la
    precisión»; dice 300 m y «su apartado o su casa» (ES), «their PO box or their home» (EN),
    «sa boîte postale ou son domicile» (FR); `anom_far` habla de «lejos de su sitio».
- [ ] **Step 2:** `cd ops-agent && uv run pytest tests/test_op_report.py -q` → FAIL en los nuevos.
- [ ] **Step 3: implementar.** `gps_cell(g, T)` añade los dos sufijos con claves `gps_said_no`,
  `gps_far_unanswered` y el rojo por `said_no >= 3`; tabla y anexo en `build_report` con `f(...)` para facts;
  `report_html.py` pinta `gps_off` bajo `s_gps` con subtítulo `s_gps_off` y el anexo `s_gps_review` tras `s_limits`.
  Claves i18n nuevas (ES): `s_gps_off` «Declaran fuera de su sitio», `s_gps_review` «Anexo 4. Revisión de la
  ubicación», `col_said_no` «Dijo «No»», `col_far_unanswered` «Lejos sin respuesta», `col_last_day` «Último día»,
  `col_what` «Qué», `gps_said_no` ««No»», `gps_far_unanswered` «lejos sin respuesta», `rv_pobox_far_from_postal_center`
  «apartado a {d} m de la oficina», `rv_home_far_from_city` «casa a {d} m del centro de la ciudad»,
  `rv_pobox_without_ref` «ciudad POBOX sin apartado guardado», `rv_kind_pobox` «apartado», `rv_kind_home` «casa»;
  equivalentes EN/FR. Glosario GPS y `lim_gps` reescritos (300 m, su apartado o su casa, «sin referencia»).
- [ ] **Step 4:** `uv run pytest -q` (suite entera del agente) → PASS.

### Task 3: Puesta en marcha

- [ ] **Step 1:** pedir confirmación a Ignacio (onems-dev `sehbnpgzqljrsqimwyuz`) y aplicar la migración con
  `apply_migration`; verificar md5 vivo = archivo.
- [ ] **Step 2:** `ops_report._data` de KENYA (últimos 7 días) en solo lectura: comprobar que sale `gps_review` y
  que las 3 referencias de Kenya (1 a revisar) aparecen como se espera.
- [ ] **Step 3:** desplegar el agente con `ops-agent/deploy/deploy.ps1` (mismo procedimiento que los despliegues
  anteriores); en el servidor, `ops-agent run-report --dry-run --account KENYA --out <dir>` y traer el HTML para
  que Ignacio lo vea antes del siguiente envío real.
- [ ] **Step 4:** actualizar memoria (`gps-declaracion.md`) y preparar textos de PR (ONEMS → develop,
  panelist_n8n → main) para cuando Ignacio pida commit.
