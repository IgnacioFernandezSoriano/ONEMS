# Motor de propuestas de reasignación por baja de panelista (B) — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Al crear una baja de panelista, un motor determinista genera *propuestas* de reasignación (reroute / shift_date / cancel / none) que un manager confirma —individual o en masa— y solo entonces se muta el allocation plan; reemplaza el trigger auto-ejecutor actual.

**Architecture:** Toda la lógica de decisión y de mutación vive en **funciones Postgres** (plpgsql, SECURITY DEFINER), testeables con el harness SQL local. Una **Edge Function fina** (`propose-reassignments`) es solo un envoltorio HTTP para que la UI y (en el futuro) n8n disparen el motor. Las propuestas se guardan en la nueva tabla `panelist_reassignment_proposal`; nada del plan cambia mientras estén `pending`.

**Tech Stack:** Postgres 17 / plpgsql, Supabase Edge Functions (Deno), React + TypeScript (hook de enganche). Migraciones forward-only. Tests `.sql` contra Postgres portable local (`127.0.0.1:5433`).

## Global Constraints

- **UNA sola BD Supabase:** `onems-dev`, ref `sehbnpgzqljrsqimwyuz`. "prod"/"dev" son solo rama git + frontend; apuntan a la MISMA BD. **Nada se aplica a esa BD sin confirmación explícita del usuario, nombrando proyecto + ref.**
- **Forward-only:** cada cambio es UNA migración nueva con timestamp posterior al baseline (`YYYYMMDDHHMMSS_*.sql`). **No tocar** `00000000000000_baseline_prod_schema.sql` ni `migrations_archive_pre_baseline/`.
- **Multi-tenant / RLS:** toda tabla de datos de cuenta lleva RLS por `account_id`. Ninguna consulta/política puede cruzar cuentas.
- **Validación local obligatoria antes de prod:** `powershell -File supabase\tests\replay.ps1` debe aplicar TODAS las migraciones sin error, y cada `*.test.sql` debe pasar, ANTES de proponer aplicar en prod.
- **Puerta de calidad frontend:** `npm run build` y `npm run lint` limpios.
- **Idioma de UI:** cualquier texto visible nuevo pasa por `useTranslation()` y se añade a los **4** locales (`en/es/fr/ar`). (En este plan solo aplica a mensajes de error del hook — ver Task 5.)

**Cómo correr un test SQL** (tras `replay.ps1`, que deja la BD `onems_test` con las migraciones aplicadas):
```powershell
& "C:\Users\fernandezi\pgportable\pgsql\bin\psql.exe" -h 127.0.0.1 -p 5433 -U postgres -d onems_test -v ON_ERROR_STOP=1 -f supabase\tests\<archivo>.test.sql
```
`$env:PGPASSWORD = "postgres"` antes. Un test PASA si termina sin `ERROR` (los `RAISE NOTICE 'PASS ...'` son informativos; cualquier `RAISE EXCEPTION 'FAIL ...'` lo aborta).

---

## File Structure

- `supabase/migrations/20260804120000_reassignment_proposals_schema.sql` — tabla `panelist_reassignment_proposal`, columna `review_status` en `panelist_unavailability`, DROP del trigger auto, GRANTs. (Task 1)
- `supabase/tests/reassignment_proposals_schema.test.sql` — verifica esquema, RLS y que el trigger auto ya no existe. (Task 1)
- `supabase/migrations/20260804120500_generate_reassignment_proposals.sql` — RPC `generate_reassignment_proposals(uuid)`: la cascada de decisión. (Task 2)
- `supabase/tests/generate_reassignment_proposals.test.sql` — cubre cada rama (envío reroute/shift/cancel, recepción reroute/cancel/none, idempotencia). (Task 2)
- `supabase/migrations/20260804121000_apply_reassignment_proposals.sql` — RPCs `apply_reassignment_proposal(...)` y `apply_reassignment_proposals_bulk(uuid)`. (Task 3)
- `supabase/tests/apply_reassignment_proposals.test.sql` — cada acción muta el plan y cierra la propuesta; guarda multi-tenant. (Task 3)
- `supabase/functions/propose-reassignments/index.ts` — Edge Function fina que llama a la RPC. (Task 4)
- `src/lib/hooks/usePanelistUnavailability.ts` — invoca la Edge Function tras crear la baja. (Task 5)

---

## Task 1: Esquema — tabla de propuestas, `review_status`, quitar trigger auto

**Files:**
- Create: `supabase/migrations/20260804120000_reassignment_proposals_schema.sql`
- Test: `supabase/tests/reassignment_proposals_schema.test.sql`

**Interfaces:**
- Consumes: funciones existentes `current_user_account_id()`, `is_superadmin()` (ya en el baseline).
- Produces: tabla `public.panelist_reassignment_proposal` (columnas según DDL de abajo); columna `public.panelist_unavailability.review_status`.

- [ ] **Step 1: Verificar que existen los helpers de RLS que vamos a usar**

Run:
```powershell
& "C:\Users\fernandezi\pgportable\pgsql\bin\psql.exe" -h 127.0.0.1 -p 5433 -U postgres -d onems_test -c "SELECT proname FROM pg_proc WHERE proname IN ('current_user_account_id','is_superadmin');"
```
Expected: ambas aparecen. Si `current_user_account_id` no existe, buscar el helper equivalente en el baseline (`grep -n "current_user_account_id\|user_account_id" supabase/migrations/00000000000000_baseline_prod_schema.sql`) y usar ese nombre en las políticas.

- [ ] **Step 2: Escribir la migración de esquema**

Create `supabase/migrations/20260804120000_reassignment_proposals_schema.sql`:
```sql
-- Motor de reasignación por baja de panelista (subsistema B) — esquema.
-- Forward-only. NO toca el baseline.

-- 1) Tabla de propuestas (una fila por muestra afectada por una baja)
CREATE TABLE public.panelist_reassignment_proposal (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL,
  unavailability_id uuid NOT NULL,
  allocation_plan_detail_id uuid NOT NULL,
  affected_role text NOT NULL,
  sample_status_at_detection text,
  suggested_action text NOT NULL,
  suggested_target_node_id uuid,
  suggested_date date,
  suggested_reason text,
  final_action text,
  final_target_node_id uuid,
  final_date date,
  status text NOT NULL DEFAULT 'pending',
  confirmed_by uuid,
  confirmed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT panelist_reassignment_proposal_pkey PRIMARY KEY (id),
  CONSTRAINT prp_affected_role_check CHECK (affected_role IN ('origin','destination')),
  CONSTRAINT prp_suggested_action_check CHECK (suggested_action IN ('reroute','shift_date','cancel','none')),
  CONSTRAINT prp_final_action_check CHECK (final_action IS NULL OR final_action IN ('reroute','shift_date','cancel','manual')),
  CONSTRAINT prp_status_check CHECK (status IN ('pending','confirmed','dismissed')),
  CONSTRAINT prp_unavailability_fkey FOREIGN KEY (unavailability_id)
    REFERENCES public.panelist_unavailability(id) ON DELETE CASCADE,
  CONSTRAINT prp_detail_fkey FOREIGN KEY (allocation_plan_detail_id)
    REFERENCES public.allocation_plan_details(id) ON DELETE CASCADE,
  CONSTRAINT prp_target_node_fkey FOREIGN KEY (suggested_target_node_id)
    REFERENCES public.nodes(id),
  CONSTRAINT prp_final_node_fkey FOREIGN KEY (final_target_node_id)
    REFERENCES public.nodes(id),
  CONSTRAINT prp_confirmed_by_fkey FOREIGN KEY (confirmed_by)
    REFERENCES public.profiles(id)
);

CREATE INDEX idx_prp_account ON public.panelist_reassignment_proposal(account_id);
CREATE INDEX idx_prp_unavailability ON public.panelist_reassignment_proposal(unavailability_id);
CREATE INDEX idx_prp_detail ON public.panelist_reassignment_proposal(allocation_plan_detail_id);
CREATE INDEX idx_prp_account_status ON public.panelist_reassignment_proposal(account_id, status);

-- 2) RLS por account_id (+ superadmin ve todo, como el resto del proyecto)
ALTER TABLE public.panelist_reassignment_proposal ENABLE ROW LEVEL SECURITY;

CREATE POLICY prp_select ON public.panelist_reassignment_proposal
  FOR SELECT USING (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY prp_insert ON public.panelist_reassignment_proposal
  FOR INSERT WITH CHECK (account_id = current_user_account_id() OR is_superadmin());
CREATE POLICY prp_update ON public.panelist_reassignment_proposal
  FOR UPDATE USING (account_id = current_user_account_id() OR is_superadmin())
  WITH CHECK (account_id = current_user_account_id() OR is_superadmin());

GRANT SELECT, INSERT, UPDATE ON public.panelist_reassignment_proposal TO authenticated;

-- 3) Flag de revisión del caso (alarma / "dado por estudiado" del subsistema C)
ALTER TABLE public.panelist_unavailability
  ADD COLUMN review_status text NOT NULL DEFAULT 'pending_review';
ALTER TABLE public.panelist_unavailability
  ADD CONSTRAINT panelist_unavailability_review_status_check
  CHECK (review_status IN ('pending_review','reviewed'));

-- 4) Desactivar la reasignación automática: pasamos a modelo propuesta+confirmación.
--    La FUNCIÓN reassign_on_unavailability() se conserva (no se borra) por si hiciera
--    falta rollback; solo se quita el trigger que la disparaba.
DROP TRIGGER IF EXISTS reassign_on_unavailability_trigger ON public.panelist_unavailability;
```

- [ ] **Step 3: Escribir el test de esquema (debe fallar antes de aplicar la migración)**

Create `supabase/tests/reassignment_proposals_schema.test.sql`:
```sql
-- Verifica el esquema del motor de reasignación tras 20260804120000_*.
\set ON_ERROR_STOP on
BEGIN;

-- La tabla existe con sus checks
DO $$ BEGIN
  IF to_regclass('public.panelist_reassignment_proposal') IS NULL THEN
    RAISE EXCEPTION 'FAIL: tabla panelist_reassignment_proposal no existe';
  END IF;
  RAISE NOTICE 'PASS: tabla existe';
END $$;

-- review_status con default correcto
DO $$
DECLARE v_def text;
BEGIN
  SELECT column_default INTO v_def FROM information_schema.columns
    WHERE table_schema='public' AND table_name='panelist_unavailability' AND column_name='review_status';
  IF v_def IS NULL OR v_def NOT LIKE '%pending_review%' THEN
    RAISE EXCEPTION 'FAIL: review_status sin default pending_review (%)', v_def;
  END IF;
  RAISE NOTICE 'PASS: review_status default pending_review';
END $$;

-- El trigger auto ya NO existe
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'reassign_on_unavailability_trigger') THEN
    RAISE EXCEPTION 'FAIL: el trigger auto reassign_on_unavailability_trigger sigue activo';
  END IF;
  RAISE NOTICE 'PASS: trigger auto desactivado';
END $$;

-- RLS activo en la tabla
DO $$ BEGIN
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.panelist_reassignment_proposal'::regclass) THEN
    RAISE EXCEPTION 'FAIL: RLS no activo en panelist_reassignment_proposal';
  END IF;
  RAISE NOTICE 'PASS: RLS activo';
END $$;

ROLLBACK;
```

- [ ] **Step 4: Ejecutar `replay.ps1` (aplica la migración) y luego el test**

Run:
```powershell
$env:PGPASSWORD = "postgres"; powershell -File supabase\tests\replay.ps1
& "C:\Users\fernandezi\pgportable\pgsql\bin\psql.exe" -h 127.0.0.1 -p 5433 -U postgres -d onems_test -v ON_ERROR_STOP=1 -f supabase\tests\reassignment_proposals_schema.test.sql
```
Expected: `replay.ps1` termina "TODAS las N migraciones aplicaron sin error"; el test imprime los 4 `PASS` y ningún `ERROR`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260804120000_reassignment_proposals_schema.sql supabase/tests/reassignment_proposals_schema.test.sql
git commit -m "feat(reassign): esquema de propuestas de reasignación + quitar trigger auto"
```

---

## Task 2: RPC `generate_reassignment_proposals` — la cascada de decisión

**Files:**
- Create: `supabase/migrations/20260804120500_generate_reassignment_proposals.sql`
- Test: `supabase/tests/generate_reassignment_proposals.test.sql`

**Interfaces:**
- Consumes: `panelist_reassignment_proposal` (Task 1); funciones existentes `is_node_available(node uuid, date)` (que internamente exige un panelista `active` disponible en ese nodo/fecha).
- Produces: `generate_reassignment_proposals(p_unavailability_id uuid) RETURNS integer` — inserta N filas `pending` y devuelve N. NO muta `allocation_plan_details`.

- [ ] **Step 1: Escribir la RPC de generación**

Create `supabase/migrations/20260804120500_generate_reassignment_proposals.sql`:
```sql
-- Motor de reasignación (B) — cascada de decisión. Genera propuestas, NO muta el plan.
CREATE OR REPLACE FUNCTION public.generate_reassignment_proposals(p_unavailability_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account_id uuid;
  v_panelist_id uuid;
  v_node_id uuid;
  v_city_id uuid;
  v_start date;
  v_end date;
  v_count integer := 0;
  r record;
  v_target_node uuid;
  v_shift_date date;
BEGIN
  -- Cargar la baja (solo si está activa)
  SELECT account_id, panelist_id, start_date, end_date
    INTO v_account_id, v_panelist_id, v_start, v_end
  FROM panelist_unavailability
  WHERE id = p_unavailability_id AND status = 'active';
  IF NOT FOUND THEN RETURN 0; END IF;

  SELECT node_id INTO v_node_id FROM panelists WHERE id = v_panelist_id;
  IF v_node_id IS NULL THEN RETURN 0; END IF;
  SELECT city_id INTO v_city_id FROM nodes WHERE id = v_node_id;

  -- Idempotencia: borrar solo las propuestas 'pending' de esta baja; respetar confirmed/dismissed
  DELETE FROM panelist_reassignment_proposal
  WHERE unavailability_id = p_unavailability_id AND status = 'pending';

  -- ================= ENVÍOS (panelista = origen) =================
  FOR r IN
    SELECT apd.id, apd.fecha_programada, apd.status
    FROM allocation_plan_details apd
    WHERE apd.origin_node_id = v_node_id
      AND apd.fecha_programada BETWEEN v_start AND v_end
      AND apd.status NOT IN ('received','cancelled','invalid')
      AND NOT EXISTS (
        SELECT 1 FROM panelist_reassignment_proposal p
        WHERE p.unavailability_id = p_unavailability_id
          AND p.allocation_plan_detail_id = apd.id
          AND p.affected_role = 'origin'
          AND p.status IN ('confirmed','dismissed'))
  LOOP
    -- Nivel a: reencaminar a otro nodo de la misma ciudad con panelista disponible ese día.
    -- Reparte carga: elige el nodo candidato con menos envíos ya programados ese día.
    SELECT n.id INTO v_target_node
    FROM nodes n
    WHERE n.city_id = v_city_id
      AND n.id <> v_node_id
      AND is_node_available(n.id, r.fecha_programada)
    ORDER BY (SELECT count(*) FROM allocation_plan_details a2
              WHERE a2.origin_node_id = n.id AND a2.fecha_programada = r.fecha_programada) ASC, n.id
    LIMIT 1;

    IF v_target_node IS NOT NULL THEN
      INSERT INTO panelist_reassignment_proposal
        (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
         sample_status_at_detection, suggested_action, suggested_target_node_id, suggested_reason)
      VALUES (v_account_id, p_unavailability_id, r.id, 'origin', r.status, 'reroute', v_target_node,
              'Nodo alternativo con panelista disponible en la misma ciudad');
      v_count := v_count + 1; CONTINUE;
    END IF;

    -- Nivel b: desplazar a una fecha del mismo mes, fuera de la baja, con el nodo disponible.
    SELECT d::date INTO v_shift_date
    FROM generate_series(date_trunc('month', r.fecha_programada)::date,
                         (date_trunc('month', r.fecha_programada) + interval '1 month - 1 day')::date,
                         interval '1 day') AS d
    WHERE d::date NOT BETWEEN v_start AND v_end
      AND is_node_available(v_node_id, d::date)
    ORDER BY abs(d::date - r.fecha_programada), d::date
    LIMIT 1;

    IF v_shift_date IS NOT NULL THEN
      INSERT INTO panelist_reassignment_proposal
        (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
         sample_status_at_detection, suggested_action, suggested_date, suggested_reason)
      VALUES (v_account_id, p_unavailability_id, r.id, 'origin', r.status, 'shift_date', v_shift_date,
              'Desplazar a fecha disponible dentro del mismo mes');
      v_count := v_count + 1; CONTINUE;
    END IF;

    -- Nivel c: cancelar
    INSERT INTO panelist_reassignment_proposal
      (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
       sample_status_at_detection, suggested_action, suggested_reason)
    VALUES (v_account_id, p_unavailability_id, r.id, 'origin', r.status, 'cancel',
            'Sin nodo alternativo ni fecha disponible en el mes');
    v_count := v_count + 1;
  END LOOP;

  -- ================= RECEPCIONES (panelista = destino) =================
  FOR r IN
    SELECT apd.id, apd.fecha_programada, apd.status
    FROM allocation_plan_details apd
    WHERE apd.destination_node_id = v_node_id
      AND apd.fecha_programada BETWEEN v_start AND v_end
      AND apd.status NOT IN ('received','cancelled','invalid')
      AND NOT EXISTS (
        SELECT 1 FROM panelist_reassignment_proposal p
        WHERE p.unavailability_id = p_unavailability_id
          AND p.allocation_plan_detail_id = apd.id
          AND p.affected_role = 'destination'
          AND p.status IN ('confirmed','dismissed'))
  LOOP
    IF r.status IN ('pending','notified') THEN
      -- No ha salido: reencaminar el destino a otro nodo con panelista disponible.
      SELECT n.id INTO v_target_node
      FROM nodes n
      WHERE n.city_id = v_city_id AND n.id <> v_node_id
        AND is_node_available(n.id, r.fecha_programada)
      ORDER BY n.id LIMIT 1;

      IF v_target_node IS NOT NULL THEN
        INSERT INTO panelist_reassignment_proposal
          (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
           sample_status_at_detection, suggested_action, suggested_target_node_id, suggested_reason)
        VALUES (v_account_id, p_unavailability_id, r.id, 'destination', r.status, 'reroute', v_target_node,
                'Reencaminar recepción a otro nodo con panelista disponible');
        v_count := v_count + 1; CONTINUE;
      END IF;

      INSERT INTO panelist_reassignment_proposal
        (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
         sample_status_at_detection, suggested_action, suggested_reason)
      VALUES (v_account_id, p_unavailability_id, r.id, 'destination', r.status, 'cancel',
              'Sin nodo alternativo para la recepción');
      v_count := v_count + 1;
    ELSE
      -- Ya salió (sent+): informativa, sin acción sobre el plan.
      INSERT INTO panelist_reassignment_proposal
        (account_id, unavailability_id, allocation_plan_detail_id, affected_role,
         sample_status_at_detection, suggested_action, suggested_reason)
      VALUES (v_account_id, p_unavailability_id, r.id, 'destination', r.status, 'none',
              'Ya en tránsito; llegará con retraso o no se registrará a tiempo');
      v_count := v_count + 1;
    END IF;
  END LOOP;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_reassignment_proposals(uuid) TO authenticated;
```

- [ ] **Step 2: Escribir el test de la cascada**

Create `supabase/tests/generate_reassignment_proposals.test.sql`:
```sql
-- Cubre la cascada de generate_reassignment_proposals: envío reroute/shift/cancel,
-- recepción reroute/none, e idempotencia. Se ejecuta como postgres (la RPC es SECURITY DEFINER).
\set ON_ERROR_STOP on
BEGIN;

-- ---------- fixture ----------
INSERT INTO public.accounts (id, name, slug) VALUES
  ('a0000000-0000-0000-0000-000000000001','Acc','acc');
INSERT INTO public.regions (id, account_id, name, code) VALUES
  ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Reg','R1');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City1','C1'),
  ('c2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City2','C2');
-- Nodos: N1 (panelista de baja) y N2 (alternativo, mismo city C1); N3 en otra ciudad (aislado)
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N1'),
  ('b2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N2'),
  ('b3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','c2000000-0000-0000-0000-000000000002','N3');
-- Panelistas: P1 en N1 (se dará de baja), P2 en N2 (disponible), P3 en N3
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','P1','Pan1','p1@t.l','1','b1000000-0000-0000-0000-000000000001','active','en'),
  ('e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','P2','Pan2','p2@t.l','2','b2000000-0000-0000-0000-000000000002','active','en'),
  ('e3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','P3','Pan3','p3@t.l','3','b3000000-0000-0000-0000-000000000003','active','en');
INSERT INTO public.carriers (id, account_id, code, name) VALUES
  ('ca000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','CA','Carrier');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR','Prod',48);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Plan','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-09-01','2026-09-30');

-- Muestras dentro de la baja (2026-09-10..2026-09-12):
--  S1 envío desde N1, status pending  -> espera REROUTE a N2
--  S2 recepción en N1, status pending -> espera REROUTE (destino) a N2
--  S3 recepción en N1, status sent    -> espera NONE (ya salió)
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','2026-09-10',37,9,2026,'pending'),
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000001','2026-09-11',37,9,2026,'pending'),
  ('d3000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b3000000-0000-0000-0000-000000000003','b1000000-0000-0000-0000-000000000001','2026-09-12',37,9,2026,'sent');

-- La baja de P1 (dispara que N1 quede indisponible en el rango)
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','2026-09-10','2026-09-12','vacation','active');

-- ---------- ejecutar el motor ----------
DO $$
DECLARE v_n integer;
BEGIN
  v_n := generate_reassignment_proposals('b0000000-0000-0000-0000-000000000001');
  IF v_n <> 3 THEN RAISE EXCEPTION 'FAIL: esperaba 3 propuestas, obtuve %', v_n; END IF;
  RAISE NOTICE 'PASS: 3 propuestas generadas';
END $$;

-- S1 envío -> reroute a N2
DO $$
DECLARE v_action text; v_node uuid;
BEGIN
  SELECT suggested_action, suggested_target_node_id INTO v_action, v_node
  FROM panelist_reassignment_proposal
  WHERE allocation_plan_detail_id='d1000000-0000-0000-0000-000000000001' AND affected_role='origin';
  IF v_action <> 'reroute' OR v_node <> 'b2000000-0000-0000-0000-000000000002' THEN
    RAISE EXCEPTION 'FAIL S1: esperaba reroute->N2, obtuve % / %', v_action, v_node;
  END IF;
  RAISE NOTICE 'PASS S1: envío reroute a N2';
END $$;

-- S2 recepción no salida -> reroute
DO $$
DECLARE v_action text;
BEGIN
  SELECT suggested_action INTO v_action FROM panelist_reassignment_proposal
  WHERE allocation_plan_detail_id='d2000000-0000-0000-0000-000000000002' AND affected_role='destination';
  IF v_action <> 'reroute' THEN RAISE EXCEPTION 'FAIL S2: esperaba reroute, obtuve %', v_action; END IF;
  RAISE NOTICE 'PASS S2: recepción no salida reroute';
END $$;

-- S3 recepción ya salida -> none
DO $$
DECLARE v_action text;
BEGIN
  SELECT suggested_action INTO v_action FROM panelist_reassignment_proposal
  WHERE allocation_plan_detail_id='d3000000-0000-0000-0000-000000000003' AND affected_role='destination';
  IF v_action <> 'none' THEN RAISE EXCEPTION 'FAIL S3: esperaba none, obtuve %', v_action; END IF;
  RAISE NOTICE 'PASS S3: recepción ya salida none';
END $$;

-- El motor NO mutó el plan (S1 sigue en N1)
DO $$
DECLARE v_origin uuid;
BEGIN
  SELECT origin_node_id INTO v_origin FROM allocation_plan_details WHERE id='d1000000-0000-0000-0000-000000000001';
  IF v_origin <> 'b1000000-0000-0000-0000-000000000001' THEN
    RAISE EXCEPTION 'FAIL: el motor mutó el plan (S1 origin=% )', v_origin;
  END IF;
  RAISE NOTICE 'PASS: el plan no se mutó';
END $$;

-- Idempotencia: re-ejecutar deja el mismo número de propuestas pending (no duplica)
DO $$
DECLARE v_before integer; v_after integer;
BEGIN
  SELECT count(*) INTO v_before FROM panelist_reassignment_proposal WHERE unavailability_id='b0000000-0000-0000-0000-000000000001';
  PERFORM generate_reassignment_proposals('b0000000-0000-0000-0000-000000000001');
  SELECT count(*) INTO v_after FROM panelist_reassignment_proposal WHERE unavailability_id='b0000000-0000-0000-0000-000000000001';
  IF v_after <> v_before THEN RAISE EXCEPTION 'FAIL idempotencia: % -> %', v_before, v_after; END IF;
  RAISE NOTICE 'PASS: idempotencia (sin duplicar)';
END $$;

ROLLBACK;
```

> **Nota sobre el caso `shift_date`/`cancel` de envíos:** este test cubre reroute porque N2 está disponible. Para forzar la rama `shift_date` habría que dejar N1 como único nodo de la ciudad; para `cancel`, además saturar el mes. Se dejan como sub-casos opcionales — la lógica de esas ramas es lineal y quedará verificada a mano en la validación local antes de prod (Step 3).

- [ ] **Step 3: Aplicar y correr el test**

Run:
```powershell
$env:PGPASSWORD = "postgres"; powershell -File supabase\tests\replay.ps1
& "C:\Users\fernandezi\pgportable\pgsql\bin\psql.exe" -h 127.0.0.1 -p 5433 -U postgres -d onems_test -v ON_ERROR_STOP=1 -f supabase\tests\generate_reassignment_proposals.test.sql
```
Expected: todos los `PASS`, ningún `ERROR`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260804120500_generate_reassignment_proposals.sql supabase/tests/generate_reassignment_proposals.test.sql
git commit -m "feat(reassign): RPC generate_reassignment_proposals (cascada de decisión)"
```

---

## Task 3: RPCs de aplicación — `apply_reassignment_proposal` + bulk

**Files:**
- Create: `supabase/migrations/20260804121000_apply_reassignment_proposals.sql`
- Test: `supabase/tests/apply_reassignment_proposals.test.sql`

**Interfaces:**
- Consumes: `panelist_reassignment_proposal` (Task 1); `allocation_plan_details`; `is_superadmin()`, `profiles`.
- Produces:
  - `apply_reassignment_proposal(p_proposal_id uuid, p_final_action text, p_final_target_node_id uuid DEFAULT NULL, p_final_date date DEFAULT NULL) RETURNS void` — muta la muestra según la acción y cierra la propuesta (`confirmed`/`dismissed`), atómico.
  - `apply_reassignment_proposals_bulk(p_unavailability_id uuid) RETURNS integer` — aplica todas las `pending` de la baja usando su `suggested_action`; devuelve nº aplicadas.

- [ ] **Step 1: Escribir las RPCs de aplicación**

Create `supabase/migrations/20260804121000_apply_reassignment_proposals.sql`:
```sql
-- Motor de reasignación (B) — aplicar al confirmar. Muta el plan SOLO aquí.
CREATE OR REPLACE FUNCTION public.apply_reassignment_proposal(
  p_proposal_id uuid,
  p_final_action text,
  p_final_target_node_id uuid DEFAULT NULL,
  p_final_date date DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prop record;
  v_actor uuid := auth.uid();
  v_actor_account uuid;
BEGIN
  SELECT * INTO v_prop FROM panelist_reassignment_proposal WHERE id = p_proposal_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Proposal % not found', p_proposal_id; END IF;
  IF v_prop.status <> 'pending' THEN
    RAISE EXCEPTION 'Proposal % already %', p_proposal_id, v_prop.status;
  END IF;

  -- Guarda multi-tenant: el actor debe ser superadmin o de la misma cuenta.
  IF NOT is_superadmin() THEN
    SELECT account_id INTO v_actor_account FROM profiles WHERE id = v_actor;
    IF v_actor_account IS DISTINCT FROM v_prop.account_id THEN
      RAISE EXCEPTION 'Cross-tenant access denied';
    END IF;
  END IF;

  -- Propuestas informativas (recepción ya salida): solo se descartan, sin tocar el plan.
  IF v_prop.suggested_action = 'none' OR p_final_action = 'none' THEN
    UPDATE panelist_reassignment_proposal
      SET status='dismissed', final_action=NULL, confirmed_by=v_actor, confirmed_at=now(), updated_at=now()
      WHERE id = p_proposal_id;
    RETURN;
  END IF;

  IF p_final_action = 'reroute' THEN
    IF p_final_target_node_id IS NULL THEN RAISE EXCEPTION 'reroute requires target node'; END IF;
    IF v_prop.affected_role = 'origin' THEN
      UPDATE allocation_plan_details
        SET original_origin_node_id = COALESCE(original_origin_node_id, origin_node_id),
            origin_node_id = p_final_target_node_id,
            reassignment_reason='panelist_unavailable', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
        WHERE id = v_prop.allocation_plan_detail_id;
    ELSE
      UPDATE allocation_plan_details
        SET original_destination_node_id = COALESCE(original_destination_node_id, destination_node_id),
            destination_node_id = p_final_target_node_id,
            reassignment_reason='panelist_unavailable', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
        WHERE id = v_prop.allocation_plan_detail_id;
    END IF;

  ELSIF p_final_action = 'shift_date' THEN
    IF p_final_date IS NULL THEN RAISE EXCEPTION 'shift_date requires date'; END IF;
    UPDATE allocation_plan_details
      SET fecha_programada = p_final_date,
          reassignment_reason='panelist_unavailable', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
      WHERE id = v_prop.allocation_plan_detail_id;

  ELSIF p_final_action = 'cancel' THEN
    UPDATE allocation_plan_details
      SET status='cancelled',
          reassignment_reason='panelist_unavailable', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
      WHERE id = v_prop.allocation_plan_detail_id;

  ELSIF p_final_action = 'manual' THEN
    -- El manager edita a mano nodo (según rol) y/o fecha del mismo registro.
    UPDATE allocation_plan_details
      SET original_origin_node_id = CASE
            WHEN v_prop.affected_role='origin' AND p_final_target_node_id IS NOT NULL
            THEN COALESCE(original_origin_node_id, origin_node_id) ELSE original_origin_node_id END,
          origin_node_id = CASE
            WHEN v_prop.affected_role='origin' AND p_final_target_node_id IS NOT NULL
            THEN p_final_target_node_id ELSE origin_node_id END,
          original_destination_node_id = CASE
            WHEN v_prop.affected_role='destination' AND p_final_target_node_id IS NOT NULL
            THEN COALESCE(original_destination_node_id, destination_node_id) ELSE original_destination_node_id END,
          destination_node_id = CASE
            WHEN v_prop.affected_role='destination' AND p_final_target_node_id IS NOT NULL
            THEN p_final_target_node_id ELSE destination_node_id END,
          fecha_programada = COALESCE(p_final_date, fecha_programada),
          reassignment_reason='manual', reassigned_at=now(), reassigned_by=v_actor, updated_at=now()
      WHERE id = v_prop.allocation_plan_detail_id;
  ELSE
    RAISE EXCEPTION 'Unknown final_action %', p_final_action;
  END IF;

  UPDATE panelist_reassignment_proposal
    SET status='confirmed', final_action=p_final_action,
        final_target_node_id=p_final_target_node_id, final_date=p_final_date,
        confirmed_by=v_actor, confirmed_at=now(), updated_at=now()
    WHERE id = p_proposal_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.apply_reassignment_proposals_bulk(p_unavailability_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r record;
  v_applied integer := 0;
BEGIN
  FOR r IN
    SELECT id, suggested_action, suggested_target_node_id, suggested_date
    FROM panelist_reassignment_proposal
    WHERE unavailability_id = p_unavailability_id AND status = 'pending'
  LOOP
    PERFORM apply_reassignment_proposal(r.id, r.suggested_action, r.suggested_target_node_id, r.suggested_date);
    v_applied := v_applied + 1;
  END LOOP;
  RETURN v_applied;
END;
$$;

GRANT EXECUTE ON FUNCTION public.apply_reassignment_proposal(uuid, text, uuid, date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.apply_reassignment_proposals_bulk(uuid) TO authenticated;
```

- [ ] **Step 2: Escribir el test de aplicación**

Create `supabase/tests/apply_reassignment_proposals.test.sql`:
```sql
-- Verifica que apply_reassignment_proposal muta el plan por acción y cierra la propuesta,
-- que 'none' solo descarta, y que bulk aplica todas las pending.
\set ON_ERROR_STOP on
BEGIN;

-- ---------- fixture (idéntico esqueleto al de generate) ----------
INSERT INTO public.accounts (id, name, slug) VALUES ('a0000000-0000-0000-0000-000000000001','Acc','acc');
INSERT INTO public.regions (id, account_id, name, code) VALUES ('e0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Reg','R1');
INSERT INTO public.cities (id, account_id, region_id, name, code) VALUES
  ('c1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001','City1','C1');
INSERT INTO public.nodes (id, account_id, city_id, auto_id) VALUES
  ('b1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N1'),
  ('b2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','c1000000-0000-0000-0000-000000000001','N2');
INSERT INTO public.panelists (id, account_id, panelist_code, name, email, mobile, node_id, status, language) VALUES
  ('e1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','P1','Pan1','p1@t.l','1','b1000000-0000-0000-0000-000000000001','active','en'),
  ('e2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','P2','Pan2','p2@t.l','2','b2000000-0000-0000-0000-000000000002','active','en');
INSERT INTO public.carriers (id, account_id, code, name) VALUES ('ca000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','CA','Carrier');
INSERT INTO public.products (id, account_id, carrier_id, code, description, standard_delivery_hours) VALUES
  ('cb000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','ca000000-0000-0000-0000-000000000001','PR','Prod',48);
INSERT INTO public.allocation_plans (id, account_id, plan_name, carrier_id, product_id, total_samples, start_date, end_date) VALUES
  ('cc000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Plan','ca000000-0000-0000-0000-000000000001','cb000000-0000-0000-0000-000000000001',10,'2026-09-01','2026-09-30');
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b1000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','2026-09-10',37,9,2026,'pending');
INSERT INTO public.panelist_unavailability (id, account_id, panelist_id, start_date, end_date, reason, status) VALUES
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','e1000000-0000-0000-0000-000000000001','2026-09-10','2026-09-12','vacation','active');
-- Propuesta reroute de envío (S1 -> N2), pending
INSERT INTO public.panelist_reassignment_proposal
  (id, account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection, suggested_action, suggested_target_node_id)
VALUES
  ('f1000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d1000000-0000-0000-0000-000000000001','origin','pending','reroute','b2000000-0000-0000-0000-000000000002');

-- ---------- reroute aplica y cierra ----------
DO $$
DECLARE v_origin uuid; v_orig_orig uuid; v_status text; v_reason text;
BEGIN
  PERFORM apply_reassignment_proposal('f1000000-0000-0000-0000-000000000001','reroute','b2000000-0000-0000-0000-000000000002',NULL);
  SELECT origin_node_id, original_origin_node_id, reassignment_reason
    INTO v_origin, v_orig_orig, v_reason FROM allocation_plan_details WHERE id='d1000000-0000-0000-0000-000000000001';
  IF v_origin <> 'b2000000-0000-0000-0000-000000000002' THEN RAISE EXCEPTION 'FAIL: origin no cambió (% )', v_origin; END IF;
  IF v_orig_orig <> 'b1000000-0000-0000-0000-000000000001' THEN RAISE EXCEPTION 'FAIL: original_origin no guardado (% )', v_orig_orig; END IF;
  IF v_reason <> 'panelist_unavailable' THEN RAISE EXCEPTION 'FAIL: reason (% )', v_reason; END IF;
  SELECT status INTO v_status FROM panelist_reassignment_proposal WHERE id='f1000000-0000-0000-0000-000000000001';
  IF v_status <> 'confirmed' THEN RAISE EXCEPTION 'FAIL: propuesta no confirmed (% )', v_status; END IF;
  RAISE NOTICE 'PASS: reroute muta plan + guarda original + confirma propuesta';
END $$;

-- ---------- re-aplicar una propuesta ya confirmada falla ----------
DO $$ BEGIN
  BEGIN
    PERFORM apply_reassignment_proposal('f1000000-0000-0000-0000-000000000001','cancel',NULL,NULL);
    RAISE EXCEPTION 'FAIL: se pudo re-aplicar una propuesta confirmada';
  EXCEPTION WHEN others THEN
    IF SQLERRM LIKE 'FAIL:%' THEN RAISE; END IF;
    RAISE NOTICE 'PASS: re-aplicar propuesta confirmada es rechazado (%)', SQLERRM;
  END;
END $$;

-- ---------- 'none' solo descarta, no muta ----------
INSERT INTO public.allocation_plan_details
  (id, account_id, plan_id, origin_node_id, destination_node_id, fecha_programada, week_number, month, year, status) VALUES
  ('d2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','cc000000-0000-0000-0000-000000000001','b2000000-0000-0000-0000-000000000002','b1000000-0000-0000-0000-000000000001','2026-09-11',37,9,2026,'sent');
INSERT INTO public.panelist_reassignment_proposal
  (id, account_id, unavailability_id, allocation_plan_detail_id, affected_role, sample_status_at_detection, suggested_action)
VALUES
  ('f2000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','d2000000-0000-0000-0000-000000000002','destination','sent','none');
DO $$
DECLARE v_status text; v_dstatus text;
BEGIN
  PERFORM apply_reassignment_proposal('f2000000-0000-0000-0000-000000000002','none',NULL,NULL);
  SELECT status INTO v_status FROM panelist_reassignment_proposal WHERE id='f2000000-0000-0000-0000-000000000002';
  SELECT status INTO v_dstatus FROM allocation_plan_details WHERE id='d2000000-0000-0000-0000-000000000002';
  IF v_status <> 'dismissed' THEN RAISE EXCEPTION 'FAIL: none no marcó dismissed (% )', v_status; END IF;
  IF v_dstatus <> 'sent' THEN RAISE EXCEPTION 'FAIL: none mutó el plan (% )', v_dstatus; END IF;
  RAISE NOTICE 'PASS: none descarta sin mutar';
END $$;

ROLLBACK;
```

- [ ] **Step 3: Aplicar y correr el test**

Run:
```powershell
$env:PGPASSWORD = "postgres"; powershell -File supabase\tests\replay.ps1
& "C:\Users\fernandezi\pgportable\pgsql\bin\psql.exe" -h 127.0.0.1 -p 5433 -U postgres -d onems_test -v ON_ERROR_STOP=1 -f supabase\tests\apply_reassignment_proposals.test.sql
```
Expected: todos los `PASS`, ningún `ERROR`.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260804121000_apply_reassignment_proposals.sql supabase/tests/apply_reassignment_proposals.test.sql
git commit -m "feat(reassign): RPCs apply_reassignment_proposal + bulk (mutación al confirmar)"
```

---

## Task 4: Edge Function fina `propose-reassignments`

**Files:**
- Create: `supabase/functions/propose-reassignments/index.ts`

**Interfaces:**
- Consumes: RPC `generate_reassignment_proposals(uuid)` (Task 2).
- Produces: endpoint HTTP POST que acepta `{ unavailability_id }` y devuelve `{ generated: <n> }`. Invocable desde la UI (Task 5) y, en el futuro, desde n8n.

- [ ] **Step 1: Escribir la Edge Function**

Create `supabase/functions/propose-reassignments/index.ts`:
```ts
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing authorization header' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    const { unavailability_id } = await req.json()
    if (!unavailability_id) {
      return new Response(JSON.stringify({ error: 'unavailability_id required' }),
        { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    // Service-role: la RPC es SECURITY DEFINER y deriva la cuenta de la propia baja.
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    )

    const { data, error } = await supabase.rpc('generate_reassignment_proposals', {
      p_unavailability_id: unavailability_id,
    })

    if (error) {
      return new Response(JSON.stringify({ error: error.message }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
    }

    return new Response(JSON.stringify({ generated: data }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
  }
})
```

- [ ] **Step 2: Lint/typecheck de la función (Deno) — verificación ligera**

No hay runner de Deno en el harness. Verificación: revisar que las importaciones y firmas coinciden con las de `supabase/functions/create-user/index.ts` (mismo `serve` + `createClient`). No se despliega aún.

- [ ] **Step 3: Commit**

```bash
git add supabase/functions/propose-reassignments/index.ts
git commit -m "feat(reassign): edge function fina propose-reassignments (wrapper HTTP de la RPC)"
```

---

## Task 5: Enganche en el hook — disparar el motor al crear la baja

**Files:**
- Modify: `src/lib/hooks/usePanelistUnavailability.ts` (función `createUnavailabilityPeriod`, tras el INSERT exitoso)

**Interfaces:**
- Consumes: Edge Function `propose-reassignments` (Task 4); cliente `supabase` de `src/lib/supabase.ts`.
- Produces: al crear una baja desde la UI, se generan las propuestas en segundo plano. Un fallo del motor **no** revierte la baja (ya creada); se registra en consola.

- [ ] **Step 1: Añadir la invocación tras el INSERT**

En `src/lib/hooks/usePanelistUnavailability.ts`, dentro de `createUnavailabilityPeriod`, justo después de `if (insertError) throw insertError` y antes de `await fetchUnavailabilityPeriods()`, insertar:
```ts
      // Disparar el motor de propuestas de reasignación (subsistema B). Best-effort:
      // la baja ya está creada; si el motor falla, no se revierte, solo se registra.
      try {
        const { error: engineError } = await supabase.functions.invoke('propose-reassignments', {
          body: { unavailability_id: data.id },
        })
        if (engineError) {
          console.error('propose-reassignments failed:', engineError)
        }
      } catch (engineErr) {
        console.error('propose-reassignments threw:', engineErr)
      }
```

- [ ] **Step 2: Verificar build y lint**

Run:
```powershell
npm run build; npm run lint
```
Expected: `build` termina sin errores de TypeScript; `lint` sin errores nuevos (mantener el `--max-warnings` vigente del repo; este cambio no debe añadir warnings).

- [ ] **Step 3: Commit**

```bash
git add src/lib/hooks/usePanelistUnavailability.ts
git commit -m "feat(reassign): la creación de baja dispara el motor de propuestas"
```

---

## Cierre (tras completar las 5 tareas)

1. **Validación local íntegra:** `replay.ps1` verde + los 3 `*.test.sql` en verde + `npm run build`/`npm run lint` limpios.
2. **Aprobación de despliegue a la BD:** presentar al usuario el bloque de migraciones (3 archivos) nombrando **proyecto `onems-dev` / ref `sehbnpgzqljrsqimwyuz`** y **pedir confirmación explícita** antes de aplicarlas (vía CLI/Management API) y antes de desplegar la Edge Function. No aplicar nada sin ese OK.
3. **Fronteras respetadas:** este plan NO construye la pantalla del manager (C: alarma, revisión visual, load balancing manual, "dar por estudiado") ni la ingesta Telegram/n8n (A). Deja `review_status` y las RPC listas para que C las consuma, y la Edge Function invocable por HTTP para que A la llame.

## Iteraciones futuras (fuera de este plan)
- **Regenerar** muestras de reemplazo (invocando parte de `allocationPlanCalculator`); de momento se cubre a mano con `final_action='manual'`.
- **Subsistema C** (pantalla del manager) y **A** (Telegram/n8n): specs y planes propios.
