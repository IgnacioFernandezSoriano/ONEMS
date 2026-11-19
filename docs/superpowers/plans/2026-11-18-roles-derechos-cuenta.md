# Roles y derechos por cuenta — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lo que cada usuario ve y puede hacer en ONEMS sale de sus roles en la cuenta activa y de la matriz de derechos de esa cuenta, editable en una pestaña "Roles y accesos", y la base de datos rechaza escrituras sin Edit.

**Architecture:** Tablas nuevas (catálogo de opciones, plantilla, matriz por cuenta, roles por usuario, registro) + funciones `my_access`/`has_access` en Postgres. El frontend carga `my_access` en un `PermissionsContext` que gobierna menú, rutas y modo View. Varias cuentas por persona vía "cuenta activa" (`profiles.account_id`), sin tocar las 139 políticas RLS existentes. Fase 3 añade comprobación de Edit a las escrituras con JWT de usuario.

**Tech Stack:** React 18 + TypeScript + Vite + Tailwind; Supabase Postgres 17 (RLS, SECURITY DEFINER); Deno edge functions; tests SQL con psql en Postgres portable local.

**Spec:** `docs/superpowers/specs/2026-11-18-roles-derechos-cuenta-design.md`

## Global Constraints

- Worktree `c:\Users\fernandezi\projects\ONEMS_wt_roles`, rama `feat/roles-derechos`. No commit a develop/main; no push sin que lo pida Ignacio.
- **Nada se aplica a la BD compartida (onems-dev `sehbnpgzqljrsqimwyuz`) ni se despliega una edge function sin confirmación expresa de Ignacio.** Validación solo en local: `$env:ONEMS_REPO='c:\Users\fernandezi\projects\ONEMS_wt_roles'; powershell -File supabase\tests\replay.ps1` y después `psql -h 127.0.0.1 -p 5433 -U postgres -d onems_test -v ON_ERROR_STOP=1 -f supabase\tests\<test>.sql` (psql en `C:\Users\fernandezi\pgportable\pgsql\bin`, PGPASSWORD=postgres).
- Migraciones nuevas: `supabase/migrations/YYYYMMDDHHMMSS_<desc>.sql`, timestamp > 20261118200000. No tocar el baseline.
- Toda función nueva: `SET search_path = public` (o `''`) y nombres cualificados `public.x`. REVOKE de PUBLIC/anon; GRANT a authenticated solo lo que llama la web.
- Roles (texto exacto): `account_manager`, `panelist_manager`, `materials_supplier`, `do_coordinator`, `upu_account_manager`, `allocation_plan_manager`; columna sin rol: `no_role` (solo en plantilla). Niveles: `edit`, `view` (ausencia de fila = sin acceso).
- Las 28 claves de opción y la plantilla son EXACTAMENTE las de la tabla "Plantilla de derechos" del spec.
- Superadmin (`public.is_superadmin()`): todo `edit`, fuera de la matriz.
- Editores de la pestaña de una cuenta: superadmin, o usuario con rol `account_manager` o `upu_account_manager` en esa cuenta. Fijo, no depende de la matriz.
- Textos visibles en los 5 ficheros `public/locales/{en,es,fr,ar,pt}.csv` (CRLF). Nunca cadenas fijas en componentes.
- Puerta de calidad frontend: `npm run lint` (0 warnings) y `npm run build`.
- Nuevas cargas de datos usan `useLatestRequest` (`src/lib/latestRequest.ts`) y `scopeToAccount` (`src/lib/accountScope.ts`).
- `service_role` (bot n8n, crons) nunca queda afectado por las comprobaciones nuevas.

## Review Focus

1. Superadmin con otra cuenta seleccionada: `my_access` y la pestaña deben actuar sobre la cuenta seleccionada, no la suya (fallo real del 18/11 con `is_superadmin`).
2. Usuario con roles en dos cuentas que cambia de cuenta: menú y datos deben ser los de la nueva cuenta tras el cambio, sin restos de la anterior.
3. Account Manager que se quita a sí mismo todos los derechos de la matriz: debe seguir pudiendo abrir y corregir la pestaña.
4. Usuario sin rol que escribe a mano `/dashboard` o `/panelists`: redirigido a su primera página de reporting, nunca pantalla en blanco ni bucle de redirección.
5. Un editor de la cuenta A intentando cambiar matriz o roles de la cuenta B por RPC directa: rechazado.

---

## Fase 1 — datos, pestaña, menú y rutas

### Task 1: Esquema y funciones de acceso

**Files:**
- Create: `supabase/migrations/20261119100000_account_access.sql`
- Test: `supabase/tests/account_access.test.sql`

**Interfaces:**
- Produces (todas en `public`):
  - Tablas: `access_option(key text pk, menu_group text, sort int)`; `access_template(role text, option text fk, level text check in ('edit','view'), pk(role,option))`; `account_access(account_id uuid fk accounts on delete cascade, role text, option text fk, level text, pk(account_id,role,option))`; `account_user_role(account_id uuid fk, user_id uuid fk profiles on delete cascade, role text, provisional boolean default false, pk(account_id,user_id,role))`; `account_access_log(id bigserial, account_id uuid, changed_by uuid, changed_at timestamptz default now(), kind text, detail jsonb)`.
  - `my_access(p_account_id uuid) returns table(option text, level text)` — superadmin: todas las opciones `edit`; con roles en la cuenta: máximo por opción de `account_access` de sus roles; sin roles: filas `no_role` de `access_template`.
  - `has_access(p_account_id uuid, p_option text, p_level text) returns boolean` (`'view'` se cumple con edit o view).
  - `can_manage_account_access(p_account_id uuid) returns boolean`.
  - `account_access_set(p_account_id uuid, p_role text, p_option text, p_level text)` (`p_level` null = quitar), `account_access_reset(p_account_id uuid)`, `account_user_role_set(p_account_id uuid, p_user_id uuid, p_role text, p_enabled boolean)` (al activar, `provisional=false`), `account_user_role_add_by_email(p_account_id uuid, p_email text, p_role text)` (solo superadmin; usuario de otra cuenta), `set_active_account(p_account_id uuid)`, `my_accounts() returns table(account_id uuid, name text)`, `account_contacts_set(p_account_id uuid, p_contacts jsonb)` (actualiza solo las 6 columnas `accounts.email_*` presentes en el jsonb; exige `can_manage_account_access`; deja log).
  - GRANT EXECUTE a `authenticated` de: `my_access`, `has_access`, `can_manage_account_access`, `account_access_set`, `account_access_reset`, `account_user_role_set`, `account_user_role_add_by_email`, `set_active_account`, `my_accounts`, `account_contacts_set` (cada una valida dentro). `service_role` también.
  - Todas las escrituras dejan fila en `account_access_log`. Trigger AFTER INSERT en `accounts` copia la plantilla (sin `no_role`). La migración copia la plantilla a las cuentas existentes.
  - RLS en las tablas nuevas: SELECT para miembros de la cuenta (`account_id = current_user_account_id()` o fila propia en `account_user_role`) y superadmin; sin INSERT/UPDATE/DELETE directos (solo vía funciones).

- [ ] **Step 1: Write the failing test** `account_access.test.sql` (patrón de `pipeline_rpcs_cuenta.test.sql`, con `pg_temp.as_user` y `fail_if`), casos:
  - plantilla tiene 28 opciones; cuenta nueva insertada recibe copia de 6 roles sin `no_role`;
  - usuario con `panelist_manager`+`materials_supplier`: `has_access(A,'stock_management','edit')` true, `has_access(A,'carriers','view')` false;
  - usuario sin rol: `my_access(A)` = 5 filas view (territory_equity, compliance, route_analysis, segment_analysis, help_center), sin `dashboard`;
  - superadmin con cuenta A2: `has_access(A2,'users','edit')` true;
  - `account_manager` de A: `account_access_set(A,...)` ok y deja log; sobre A2 → excepción; usuario `panelist_manager` → excepción;
  - AM se quita todo con `account_access_set` y `can_manage_account_access(A)` sigue true;
  - usuario con roles en A y A2: `set_active_account(A2)` cambia `profiles.account_id`; a una cuenta sin rol → excepción; `my_accounts()` devuelve 2;
  - `account_user_role_add_by_email` por no superadmin → excepción;
  - anon sin EXECUTE en ninguna función nueva.
- [ ] **Step 2: Run** replay + test. Expected: FAIL (`function public.my_access does not exist`).
- [ ] **Step 3: Implement** la migración con la plantilla literal del spec.
- [ ] **Step 4: Run** replay + test. Expected: `account_access: OK`.
- [ ] **Step 5: Commit** `feat(acceso): tablas, plantilla y funciones de roles y derechos por cuenta`.

### Task 2: Migración de activación (asignación inicial de roles)

**Files:**
- Create: `supabase/migrations/20261119100100_account_access_activation.sql`
- Create: `supabase/tests/adhoc/account_access_activation_preview.sql` (consulta de solo lectura: usuario, cuenta, rol resultante, provisional)
- Test: `supabase/tests/account_access_activation.test.sql`

**Interfaces:** Consumes `account_user_role` (Task 1). Inserta, para cada perfil no superadmin con `account_id`: el rol cuyo `accounts.email_<rol>` coincide (lower/trim) con `profiles.email` (puede ser más de uno); si no coincide ninguno y `role='admin'` → `account_manager` con `provisional=true`; `role='user'` → nada. Idempotente (`ON CONFLICT DO NOTHING`).

- [ ] **Step 1: Test** con fixture: admin con correo = `email_panelist_manager` → `panelist_manager` no provisional; admin sin coincidencia → `account_manager` provisional; user → sin filas; segunda ejecución no duplica.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → OK.
- [ ] **Step 5: Commit** `feat(acceso): asignación inicial de roles desde los contactos de la cuenta`.

### Task 3: Catálogo de opciones y PermissionsContext

**Files:**
- Create: `src/lib/access.ts`
- Create: `src/contexts/PermissionsContext.tsx`
- Modify: `src/App.tsx` (proveedor dentro de `AccountProvider`)
- Test: `src/lib/access.test.ts` (vitest ya usado en `planUndo`)

**Interfaces:**
- Produces:
  - `type AccessOption` (unión de las 28 claves); `type AccessLevel = 'edit' | 'view'`; `type AccountRole` (6 roles).
  - `ACCESS_OPTIONS: { key: AccessOption; group: string; labelKey: string }[]` en orden de menú.
  - `ROUTE_OPTION: Record<string, AccessOption | 'superadmin' | 'open'>` — rutas de `App.tsx`. Mapeo de rutas fuera de la matriz (Ruling del plan): `/diagnosis/network-overview`, `/diagnosis/center-analysis`, `/diagnosis/segment-deep-dive`, `/diagnosis/journey-segments`, `/diagnosis/complete-journeys`, `/diagnosis/route-path-analysis` → `route_analysis`; `/diagnosis/pipeline-monitor`, `/diagnosis/event-consolidation` → `epcis_api`; `/reporting/territory-equity-v2` → `territory_equity`; `/reporting/jk-performance`, `/reporting/jk-performance-v2` → `segment_analysis`; `/settings/reporting-config` → `account_working_days`; `/settings/users`, `/users` → `users`; `/settings/accounts`, `/admin/translations` → `superadmin`; `/receive-generator`, `/admin/account-management` → `account_working_days` en DEMO2 (spec: superadmin y AM; usar edit en account_working_days como aproximación aceptada); `/settings`, `/settings/change-password`, `/login` → `open`; `/settings/roles-access` → `open` con guarda propia (Task 5).
  - `firstAllowedPath(levels: Map<AccessOption, AccessLevel>): string | null`.
  - `usePermissions(): { loading: boolean; level(o: AccessOption): AccessLevel | null; canView(o): boolean; canEdit(o): boolean; canManageAccess: boolean; isProvisional: boolean; reload(): void }` — llama `my_access(effectiveAccountId)` y `can_manage_account_access` con `useLatestRequest`.
- [ ] **Step 1: Test** `access.test.ts`: cada ruta de `App.tsx` listada tiene entrada; `firstAllowedPath` con solo reporting → `/reporting/territory-equity`; con nada → null.
- [ ] **Step 2–4:** fallo → implementar → pasa. `npm run lint && npm run build`.
- [ ] **Step 5: Commit** `feat(acceso): catálogo de opciones y contexto de permisos`.

### Task 4: Menú, rutas protegidas y selector de cuenta

**Files:**
- Modify: `src/components/layout/Sidebar.tsx`, `src/components/auth/ProtectedRoute.tsx`, `src/App.tsx`, `src/contexts/AccountContext.tsx`

**Interfaces:** Consumes Task 3. `ProtectedRoute` acepta `option?: AccessOption | 'superadmin'`; sin acceso → `<Navigate to={firstAllowedPath(...) ?? '/settings/change-password'} />` (nunca a sí misma). Sidebar: cada item lleva `option` y se muestra si `canView`; grupos vacíos se ocultan; desaparece el uso de `roles: ['admin','superadmin']`. `/` y la entrada tras login van a `firstAllowedPath`. Usuarios no superadmin con `my_accounts()` > 1 ven selector; al elegir, `set_active_account` y recarga del perfil y de permisos.
- [ ] **Step 1:** Implementar. **Step 2:** `npm run lint && npm run build`. **Step 3:** Prueba manual descrita en el informe (usuario sin rol, AM, superadmin con KENYA) con `npm run dev` contra la BD local si es posible; si no, dejarlo anotado como pendiente de prueba en navegador.
- [ ] **Step 4: Commit** `feat(acceso): menú y rutas según la matriz de la cuenta`.

### Task 5: Pestaña "Roles y accesos"

**Files:**
- Create: `src/components/accounts/RolesAccessTab.tsx`, `src/pages/Settings/RolesAccess.tsx`, `src/hooks/useAccountAccess.ts`
- Modify: `src/components/accounts/AccountForm.tsx` (pestañas General / Roles y accesos; los 6 correos pasan a la pestaña), `src/App.tsx` (ruta `/settings/roles-access`), Sidebar (entrada en ADMINISTRATION si `canManageAccess`), 5 locales.

**Interfaces:** Consumes RPCs de Task 1. Secciones: (1) contactos (mismos campos `accounts.email_*`, se guardan como hoy); (2) matriz opciones × 6 roles con selector Edit/View/— por celda, columna "Sin rol" de solo lectura; (3) usuarios de la cuenta con casillas de rol y etiqueta "provisional"; superadmin además "añadir por correo"; (4) "Volver a la plantilla" con confirmación; (5) últimos 50 cambios del log. Solo editable si `canManageAccess`; si no, la página redirige.
- [ ] **Step 1:** Implementar. **Step 2:** `npm run lint && npm run build`. **Step 3: Commit** `feat(acceso): pestaña Roles y accesos de la cuenta`.

### Task 6: Alta y baja de usuarios según la matriz

**Files:**
- Modify: `supabase/functions/create-user/index.ts`, `supabase/functions/delete-user/index.ts`, `src/pages/Admin/Users.tsx` (+ `src/components/users/UserForm.tsx`)

**Interfaces:** Compatibilidad hacia atrás obligatoria (se despliegan antes que el frontend nuevo): la regla antigua (admin de su cuenta) sigue valiendo. Las funciones permiten la operación si superadmin, o regla antigua, o `has_access(cuenta, 'users', 'edit')` (rpc con el JWT del llamante) y la cuenta es la suya. Los nuevos usuarios de cuenta se crean con `profiles.role='user'` y opcionalmente roles (`account_user_role_set` tras crear). `profiles.role='admin'` deja de asignarse desde la UI. En Users.tsx los botones de alta/baja dependen de `canEdit('users')`.
- [ ] **Step 1:** Implementar. **Step 2:** `deno check` de ambas funciones si está disponible; `npm run lint && npm run build`. **Step 3: Commit** `feat(acceso): alta y baja de usuarios según la matriz`. (Despliegue de las funciones: solo con confirmación, en la release.)

## Fase 2 — modo View en pantallas

### Task 7: Modo View por bloques

**Files (un commit por bloque):** páginas de `src/pages/` y sus componentes por grupo: (a) E2E Setup + Allocation; (b) Materials + E2E Database; (c) Diagnóstico Setup + Database; (d) Incidents + Account Working Days + Reporting config.

**Interfaces:** Consumes `canEdit(option)` de Task 3. En cada pantalla, si `!canEdit(option)`: ocultar crear/editar/borrar/importar/guardar y acciones masivas; tablas y filtros intactos.
- [ ] Por bloque: implementar → `npm run lint && npm run build` → commit `feat(acceso): modo consulta en <bloque>`.

## Fase 3 — la base rechaza escrituras sin Edit

### Task 8: Inventario de escrituras

**Files:** Create `docs/superpowers/specs/2026-11-18-roles-inventario-escrituras.md`
- [ ] Por cada tabla de cuenta escrita desde la web (`.insert/.update/.upsert/.delete` y `.rpc` que escriben, y edge functions llamadas desde la web): tabla/función → opciones que la escriben. Marcar las que también escribe el bot con JWT de usuario (si existe alguna, señalarlo: no debe cerrarse). Commit.

### Task 9: Políticas y funciones con comprobación de Edit

**Files:** Create `supabase/migrations/20261119100200_account_access_writes.sql`; Test `supabase/tests/account_access_writes.test.sql`

**Interfaces:** Para cada tabla del inventario: políticas INSERT/UPDATE/DELETE para `authenticated` añaden `public.has_access(account_id, <opción>, 'edit') OR ...` (OR entre opciones del inventario). Funciones SECURITY DEFINER que escriben y llama la web (p. ej. `plan_action_*`, `plan_undo_*`) comprueban `has_access` al inicio. `service_role` sin cambios.
- [ ] **Step 1: Test:** usuario con View en `panelists` → UPDATE en `panelists` rechazado; con Edit → ok; `plan_action_delete` con View en `allocation_plans` → excepción; service_role → ok.
- [ ] **Step 2–4:** fallo → implementar → OK. **Step 5: Commit** `feat(acceso): la base exige Edit para escribir`.

## Antes de producción (no son tareas de código; orden decidido por Ignacio)

1. Ejecutar `account_access_activation_preview.sql` en solo lectura y enseñar a Ignacio quién queda con qué.
2. Reescribir el artifact "Roles de la cuenta ONEMS" (https://claude.ai/artifact/ErsDQivrzcbwymQGXm9LH1).
3. Comunicación a las cuentas.
4. Aplicar migraciones (Tasks 1, 2, 9) y desplegar `create-user`/`delete-user` — cada una con confirmación expresa (proyecto onems-dev `sehbnpgzqljrsqimwyuz`).
5. PR a develop y release a main (los abre Ignacio).
