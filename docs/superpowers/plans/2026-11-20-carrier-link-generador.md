# Carrier Link — generador de planes igual al del allocation plan

> For agentic workers: REQUIRED SUB-SKILL: superpowers:subagent-driven-development.

**Goal:** Que "Planes de muestreo" genere las cuotas con el MISMO generador del allocation plan (mismo formulario y mismo cálculo: total, periodo, matriz de perfiles de ciudad A/B/C, distribución estacional, días laborables/festivos), sin panelistas, y permita cargar las cuotas desde un CSV.

**Owner decision (20/11, verbatim):** "lo único que cambia es que aquí no hay panelistas pero es lo mismo en cuanto a la generación". Missing today: "no puedo definir el plan entre perfiles de ciudades ni estacional ni cargarlo directamente".

**Architecture:** `generateAllocationPlan` (src/lib/allocationPlanCalculator.ts) is reused as-is with synthetic nodes: one node per city that has ACTIVE carrier points of the plan's carrier (node id = city id). Origins restricted to cities with role origin|both, destinations to destination|both, never same city (R23). Its per-shipment entries are aggregated into `ClQuota {origin_city_id, destination_city_id, iso_year, iso_week, samples}` (ISO week of fechaProgramada). The generator form's shared parts (matrix A/B/C with autofill, seasonal with autofill, total, dates) are the SAME UI as AllocationPlanGeneratorForm (extract shared subcomponents if needed; allocation plan behaviour must stay byte-for-byte identical in output). The previous equal-weights `generateClQuotas` stays only as a fallback/unused or is removed if nothing uses it.

## Global Constraints
- Same as plan 2026-11-20-carrier-link-fase2.md Global Constraints (i18n 5 CSVs, permissions, SelectAccountNotice, filtered writes, no window.confirm/alert in new code, lint baseline 47, npm test + build pass).
- No DB changes. cl_plan_set_quotas receives only quotas with samples > 0.
- Allocation plan generator output must not change for the same inputs (existing tests + a new regression test).
- Scale: 15,000 samples/year per product, up to 30 cities/870 routes: generation < 2 s in the browser.

## Task 1: Generation engine parity (lib)
Files: src/lib/allocationPlanCalculator.ts (only if an optional origin/destination restriction is needed — default behaviour unchanged), src/lib/carrierLink/clGenerator.ts, test src/lib/__tests__/clGenerator.test.ts.
Produces: `buildClGeneratorNodes(points: {city_id: string; e2e_role: string; is_active?: boolean}[], cities: {id: string; classification?: string|null}[])` → nodes/cities input for generateAllocationPlan + origin/destination sets; `generateClQuotasLikeAllocation(params: { totalSamples, startDate, endDate, cityDistributionMatrix, useSeasonalDistribution, seasonalDistribution?, nonWorkingDays?, workingDows?, points, cities }): ClQuota[]`.
Tests: same totals as generateAllocationPlan for the same matrix/seasonal/total; sum exact; no same-city route; destination-only city never origin and origin-only never destination; seasonal 0% month gets 0; ISO year boundary (W53/W01); 15,000 samples / 30 cities < 2000 ms; allocation plan regression test (generateAllocationPlan output unchanged for a fixed seed/rng).
## Task 2: Same generator form in Planes de muestreo
Files: src/pages/carrier-link/ClPlans.tsx, src/components/allocation-plans/AllocationPlanGeneratorForm.tsx (extract shared MatrixEditor/SeasonalEditor only if needed, no visual/behaviour change in allocation), locales.
The draft plan's "Generar cuotas" opens the same generator controls (matrix A/B/C with autofill/clear, seasonal toggle with 12 months + autofill, total and dates prefilled from the plan, editable) → preview (existing grouped table) → Guardar cuotas. Show which cities are origin/destination and their classification. If cities lack classification, same handling as allocation.
## Task 3: Direct load from CSV
Files: src/lib/carrierLink/quotaCsv.ts (+ test), ClPlans.tsx, locales.
Template download (header: origin_city,destination_city,week,samples; week as YYYY-Www; also accept a date YYYY-MM-DD → its ISO week); parse (comma or semicolon), city by name (case/accents-insensitive) or id within the account; validation per row (unknown city, same city, week outside plan period, duplicates, samples not integer ≥ 0, route without origin/destination point) with row-numbered translated errors; valid file → same preview → Guardar cuotas. Max 50,000 rows.

---
# v2 (20/11, owner): "todo ha de ser prácticamente una copia para no despistar al usuario que al final necesita lo mismo que es hacer un allocation plan"
Owner decisions (verbatim essence): same names as the E2E Allocation section ("se tiene que llamar todo igual pero sin que lo pueda confundir"); Load Balancing also needed "pero sin el máximo por panelista porque aquí no hay". Controller rulings: button "Aplicar" = activate the plan (demands start); balancing works on generated (draft) and applied (active) plans with the same fence rule as E2E (only weeks not yet requested from the carrier can change on an active plan).

## Target structure of the Carrier Link tab (mirror of E2E)
| E2E | Carrier Link | Route | Option |
|---|---|---|---|
| Configuración → Panelistas | Configuración → Puntos de lectura, Conectores | /carrier-link/reading-points, /carrier-link/connectors | cl_reading_points, cl_connectors |
| Asignación → Generador de Asignaciones (tabs Generador / Planes generados / Planes aplicados; CSV import + template; download CSV; Aplicar; Eliminar) | Asignación → Generador de Asignaciones (same tabs/actions; "Aplicar" = cl_plan_activate) | /carrier-link/allocation-generator | cl_plans |
| Asignación → Balanceo de Carga | Asignación → Balanceo de Carga (no per-panelist max; nodes = origin cities / routes) | /carrier-link/load-balancing | cl_plans |
| Asignación → Planes de Asignación (records) | Asignación → Planes de Asignación (records = quotas route×week: planned, carried, obtained, status; link to their samples) | /carrier-link/allocation-plans | cl_plans |
| — | Muestras, Monitor (unchanged) | existing | cl_samples, cl_monitor |
Same i18n texts as E2E (reuse the same keys where the text is identical); every Carrier Link page shows a "Carrier Link" badge in its header and the tab has its own accent colour so pages cannot be confused. Old routes /carrier-link/plans redirect to the generator. Help page sections updated to the new names.

## Task 2: Menu/routes mirror (frontend)
Sidebar Carrier Link group restructured as above (sub-groups Configuración / Asignación + Muestras + Monitor), routes + ROUTE_OPTION/OPTION_ROUTE, redirect from /carrier-link/plans, header badge component used by all Carrier Link pages; access tests updated.
## Task 3: Generador de Asignaciones (copy)
Copy of src/pages/AllocationPlanGenerator.tsx + its form (Task 1 engine; matrix A/B/C, seasonal, totals/dates, carrier/product/connector instead of panelist-specific fields) with the same tabs and actions: generate → "Planes generados" (draft plans with quotas saved), download CSV, CSV import with template (quota rows origin_city,destination_city,week,samples, validated per row), "Aplicar" (cl_plan_activate with missing-points/standards notices), "Eliminar" (draft only). Replaces ClPlans.tsx.
## Task 4: Planes de Asignación (copy)
Copy of src/pages/AllocationPlans.tsx layout/filters for quotas (plan, origin, destination, week, status), paginated server-side, totals, link to Muestras filtered by quota.
## Task 5: DB support for balancing (migration, applied with owner confirmation)
`cl_plan_rebalance_quotas(p_plan_id uuid, p_changes jsonb)` SECURITY DEFINER, cl_plan_authorize edit; changes = [{origin_city_id, destination_city_id, iso_year, iso_week, samples}] absolute values; plan total must be preserved; draft plans: any week; active plans: only quotas with status 'pending' and period_start > fence (same fence semantics as E2E balancing: read how E2E computes it); validated set-based; safeupdate; tests incl. 15k scale < 2 s. Also check/ensure draft plan deletion is possible for the generator's "Eliminar" (RPC if RLS forbids).
## Task 6: Balanceo de Carga (copy)
Copy of src/pages/NodeLoadBalancing.tsx + useNodeLoadBalancing (read its algorithm/UX: expected average, acceptable deviation, fence, compensation) applied to quotas: nodes = origin cities (and per-week view), no capacity limit; proposals saved through cl_plan_rebalance_quotas.
## Task 7: Help + cleanup
Help page carrier-link.* updated to the new structure/names (5 languages); remove dead code (old ClPlans pieces, generateClQuotas if unused).

---
# v3 menus (20/11, owner): "los menús deben ser con la misma lógica"
Carrier Link tab = same groups as E2E:
- **Setup**: Topología del país (same cities, NO nodes — panelist nodes hidden in this tab), Carriers y Productos, E2E: SLA (all shared pages/data with E2E), Puntos de lectura, Conectores.
- **Asignación**: Generador de Asignaciones, Balanceo de Carga, Planes de Asignación (copies, see v2).
- **Base de datos**: the SAME E2E database page (one_db) opened pre-filtered to origin "carrier"; Muestras; Monitor de capturas. (Data is ONE store: one_db.source panelist|carrier; reports read both.)
- **Reporting** (proposed to owner): same report pages as E2E (they already have the origin filter).
- **Incidencias**: only in the E2E tab (pending owner answer: also remove from Diagnosis?).
Task 2 (menu) implements this; shared pages must be reachable from both tabs without duplicating code (same route or a carrier-link route rendering the same page with a "carrier" context prop: topology hides nodes, E2E DB pre-filters source=carrier). Permissions: shared pages keep their existing options (country_topology, carriers, e2e_sla, e2e_db…).

---
# v4 (20/11, owner): NO third tab
Owner: "lo que cambia es la forma de obtener el dato y se adapta a cada forma (panelista o link) que irá determinado por cada carrier. Incluso dentro de un carrier podemos tener los dos sistemas de captura". → Capture method is per carrier (possibly both). Tabs stay E2E and Diagnosis only; Carrier Link items become submenus inside E2E:
- E2E ▸ Setup: Topología del país, Carriers y Productos, E2E: SLA, Panelistas (panelists) | Puntos de lectura, Conectores (Carrier Link sub-heading).
- E2E ▸ Asignación: sub-heading "Panelistas": Generador de Asignaciones, Balanceo de Carga, Planes de Asignación (existing) | sub-heading "Carrier Link": Generador de Asignaciones, Balanceo de Carga, Planes de Asignación (copies).
- E2E ▸ Materiales (panelists only, unchanged); E2E ▸ Incidencias (panelists only) — moved inside E2E if today it is a separate group; Reporting unchanged; Base de datos: Base de datos E2E, API (both origins) | "Carrier Link": Muestras, Monitor de capturas.
- Diagnosis unchanged. The Carrier Link tab and its tab button are removed; /carrier-link/* routes stay.
Pending owner answer: per-carrier capture-method setting (Panelistas / Carrier Link / Ambos) in Carriers y Productos to filter carriers in each generator.
Task 2 is redefined accordingly (menu inside E2E; badge "Carrier Link" on its pages; accent colour on the Carrier Link sub-headings).

## Task 8: Capture method per carrier (owner approved 20/11: "me parece bien")
DB (new migration 20261121100300_carrier_capture_method.sql, applied later with owner confirmation): `carriers.capture_method text NOT NULL DEFAULT 'panelists' CHECK (capture_method IN ('panelists','carrier_link','both'))`; backfill: carriers that already have Carrier Link data (cl_plans/cl_feeds/carrier_scan readers) → 'both' if they also have panelist allocation data, else 'carrier_link'; everything else stays 'panelists' (Kenya/Senegal unchanged). No change to existing RLS (column covered by current carriers policies). Test SQL: default, CHECK, backfill logic.
Frontend: src/pages/Carriers.tsx (+ useCarriers) shows and edits "Forma de captura" (Panelistas / Carrier Link / Ambos) per carrier, translated in 5 CSVs; E2E allocation generator (src/components/allocation-plans/AllocationPlanGeneratorForm.tsx or its carrier list source) offers only carriers with panelists|both; Carrier Link generator, connectors and reading points offer only carrier_link|both. Behaviour for Kenya/Senegal identical (all their carriers are 'panelists'). Tests for the pure filter helper.
