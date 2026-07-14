# ONEMS — Guía del proyecto para Claude

ONEMS (ONE for Regulators MS) es una app web multi-tenant para reguladores postales:
planificación de envíos, panelistas, lectores RFID, diagnóstico de red, SLAs, equidad
territorial y reporting. Frontend React + Supabase (Postgres) como backend.

> El responsable del repo **no es programador**. Explica los cambios en lenguaje claro,
> prioriza la seguridad (no romper prod) y confirma antes de acciones irreversibles.

---

## 🔴 Supabase — reglas anti-confusión (OBLIGATORIAS)

- Hay **UNA sola base Supabase** para este proyecto: **`onems-dev`**, project-ref
  **`sehbnpgzqljrsqimwyuz`** (org "ONE for Regulators MS"). "prod" y "dev" son solo la
  **rama git** y el frontend desplegado — **apuntan a la misma BD**. No existe una base
  separada de staging.
- **Antes de CUALQUIER escritura en Supabase** (migración, `execute_sql`, `apply_migration`,
  deploy de edge function) debo **nombrar el proyecto + su ref y pedir confirmación
  explícita**. Nunca inferir la base.
- **NUNCA** ejecutar `supabase db reset` ni `supabase db push` contra el proyecto remoto sin
  confirmación explícita: reescriben la BD de producción real.
- La BD viva puede ir **por delante de la rama `main`**. Auditar el estado real (no fiarse
  solo de las migraciones del repo) antes de proponer un cambio de esquema.

## Base de datos — flujo de trabajo

- **Baseline squasheado (2026-07-14):** el esquema real de prod está capturado en
  `supabase/migrations/00000000000000_baseline_prod_schema.sql`. Las 130 migraciones
  históricas están archivadas en `supabase/migrations_archive_pre_baseline/` (la CLI ya no
  las aplica; **no editarlas ni devolverlas** a `migrations/`).
- **Forward-only:** cada cambio nuevo es UNA migración con timestamp posterior al baseline
  (`YYYYMMDDHHMMSS_descripcion.sql`). No tocar el baseline.
- **Validar sin tocar prod:** hay un Postgres 17.6 portable local en
  `C:\Users\fernandezi\pgportable\` (`127.0.0.1:5433`). Los scripts de `supabase/tests/`
  (`replay_baseline.ps1`, `00_bootstrap_supabase_shim.sql`) permiten aplicar el baseline +
  migraciones nuevas en local y verificar antes de ir a prod. El puerto 5432 remoto está
  **bloqueado por firewall**: para la BD en vivo se usa la Management API (HTTPS) o el CLI,
  no conexión directa.
- **Multi-tenant / RLS:** el aislamiento entre cuentas es por **`account_id`** vía Row Level
  Security. Toda tabla de datos de cuenta debe llevar RLS por `account_id`. Nunca proponer
  una consulta o política que exponga datos entre cuentas.
- **Edge Functions** en `supabase/functions/` (Deno): incluyen `create-user`/`delete-user`
  (alta/baja server-side), `rfid-provider-poll` + `consolidate-rfid-events` (ETL RFID),
  `onedb-api`, `weekly-aggregation`, `admin-reset-password`.

## Stack y estructura

- **Frontend:** React 18 + TypeScript + Vite + Tailwind + react-router-dom. Gráficas con
  `recharts`, mapas con `react-leaflet`, iconos `lucide-react`, fechas `date-fns`.
- **Datos:** `@supabase/supabase-js`; cliente único en `src/lib/supabase.ts`.
- **Estructura `src/`:**
  - `pages/` — una página por módulo (Dashboard, Panelists, PostalCenters, NodeLoadBalancing,
    AllocationPlans, SLAs, Carriers, Diagnosis, Reporting, Admin…).
  - `hooks/` (~29) — lógica de datos por módulo (`useAuth`, `useAccount`, `usePanelists`,
    `useStockManagement`, `useNodeLoadBalancing`…). El patrón es **página → hook → supabase**.
  - `contexts/` — `AuthContext`, `AccountContext`, `LocaleContext`, `ReportingFiltersContext`,
    `SidebarContext`.
  - `lib/` — cliente supabase, cálculos (`allocationPlanCalculator`, `e2eCalculations`,
    `jkCalculations`), utilidades de export/formato, tipos (`types_*.ts`).
  - `locales/` — traducciones `en/ es/ fr/ ar/`.

## i18n — 4 idiomas (EN / ES / FR / AR)

- **Todo texto visible pasa por `useTranslation()`** (god node del graph, ~200 conexiones:
  es transversal por diseño, no un acoplamiento accidental). **Nunca** hardcodear cadenas de
  UI: añadir la clave a los **4** ficheros de `src/locales/` (incluido árabe, RTL).
- Un componente `.tsx` con texto fijo que no pase por el hook queda fuera de los 4 idiomas:
  es un bug de traducción.

## Comandos

```bash
npm run dev      # servidor de desarrollo (Vite)
npm run build    # tsc + build de producción
npm run lint     # ESLint (0 warnings permitidos: --max-warnings 0)
```

- No hay suite de tests automatizados de frontend. `npm run lint` y `npm run build` son la
  puerta de calidad: deben pasar antes de dar algo por terminado.

## Convenciones

- Componentes y páginas en **PascalCase** (`.tsx`); hooks en **camelCase** con prefijo `use`.
- Ficheros `*.backup`, `*.bak`, `_old`: son restos; **no** tomarlos como referencia y no crear
  nuevos (usar git para el historial).
- Git: rama por defecto **`develop`**; `main` es release. No commitear ni pushear salvo que el
  usuario lo pida. Secretos (`*key*.txt`, `.env*`) están gitignored — nunca commitearlos.

---

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
