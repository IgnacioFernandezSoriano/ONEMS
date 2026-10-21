# Deuda técnica

Lista de cosas que funcionan hoy pero conviene arreglar. Cada entrada: qué pasa, desde cuándo, cuándo muerde y cómo se arregla.

---

## DT-1 — Las pruebas de incidencias de baja usan fechas fijas (caducan ~marzo 2027)

- **Apuntado:** 2026-10-20.
- **Fecha límite:** antes de **febrero de 2027**.
- **Afecta a:** solo a las pruebas `supabase/tests/incident_*.test.sql` (6 ficheros). La web, n8n y los datos reales NO se ven afectados.

**Qué pasa.** Las funciones de incidencias comparan con el día de hoy (`current_date`): rechazan bajas en el pasado (`in_past`), solo mueven envíos de hoy en adelante y solo avisan por Telegram de la semana actual. Las pruebas usan fechas fijas entre `2027-03-01` y `2027-06-21`. Cuando esas fechas pasen a ser pasado, el sistema se comportará correctamente pero distinto de lo que las pruebas esperan, y fallarán.

Migraciones con funciones que miran la fecha de hoy: `20261020130100_incident_helpers`, `130200_resolve_unavailability_incident`, `130400_incident_triggers`, `130500_declare_panelist_unavailability` (validación `in_past`), `130600_incident_backfill` y `20261020150000_incident_move_to_cell`.

**Solución recomendada: un reloj controlable.**
1. Migración nueva (forward-only) con `incident_today()`: devuelve `coalesce(nullif(current_setting('app.incident_today', true), '')::date, current_date)`.
2. Sustituir `current_date` por `incident_today()` en las funciones de incidencias (las semanas actuales se derivan de ahí).
3. En cada prueba, al empezar: `set local app.incident_today = '2027-03-01';`.
4. En producción nadie fija el ajuste → se usa la fecha real; el comportamiento no cambia.
5. Validar primero en el Postgres local (`127.0.0.1:5433`, `supabase/tests/replay_baseline.ps1`) y aplicar en onems-dev (`sehbnpgzqljrsqimwyuz`) con confirmación explícita.

**Alternativa descartada:** reescribir las pruebas con fechas relativas (`current_date + 30`). Son más de 150 fechas, y algunas comprobaciones dependen de que una fecha caiga en lunes o dentro del mismo mes; las pruebas podrían fallar unos días sí y otros no.

---

## DT-2 — Clave `service_role` de Supabase escrita en un workflow de n8n

- **Apuntado:** 2026-10-20 (ya figuraba en `panelist_n8n/docs/integrations.md`).
- **Afecta a:** el nodo "Lookup email" de `Telegram - User initiated message` (PROD `IkVtek2csP5AbWxB`). La clave está en el historial git del repo `panelist_n8n` desde el commit `851357d`.
- **Riesgo:** esa clave da acceso total a la base de datos.
- **Solución:** rotar la clave en Supabase y pasar el nodo a la credencial Postgres de n8n (`735a8hxfuUEDPIYD`).

---

## DT-3 — Textos fijos en inglés en pantallas antiguas

- **Apuntado:** 2026-10-20.
- **Afecta a:** algunas pantallas antiguas que no pasan por `useTranslation()`, por ejemplo `StockAlertsTab.tsx`, `MaterialCatalog.tsx`, `AllocationPlans.tsx` ("No records found") y `AllocationPlanGeneratorForm.tsx`. Esos textos salen en inglés en cualquier idioma.
- **Solución:** pasarlos por `t()` y añadir las claves a `public/locales/{en,es,fr,ar}.csv`.

---

## DT-4 — Las RPCs de incidencias comprueban la cuenta pero no el rol

- **Apuntado:** 2026-10-21 (señalado por la revisión automática de seguridad al ampliar `update_panelist_contact`).
- **Afecta a:** las RPCs `SECURITY DEFINER` de incidencias (`resolve_panelist_incident`, `update_panelist_contact(_v2)`, `cancel_detail`, `reroute_returned_sample`, `apply_sample_move`, etc.). La guarda es `assert_same_account` / `profiles.account_id`: cualquier usuario **autenticado de la misma cuenta** puede llamarlas, aunque la pantalla solo la vean `admin`/`superadmin`.
- **Riesgo:** bajo mientras todos los usuarios de una cuenta sean gestores; sube si se crean usuarios con rol de solo lectura.
- **Solución:** un helper `assert_manager_role()` (rol en `profiles` ∈ `admin`,`superadmin`, o `is_superadmin()`) llamado tras `assert_same_account` en todas las RPCs de escritura, permitiendo `auth.uid() IS NULL` (service-role / n8n). Una migración forward-only con test de permisos.
