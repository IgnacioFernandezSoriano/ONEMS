# Carrier Link: descargas CSV + incidencias en el menú Incidencias — plan

> Ejecución inline (superpowers:executing-plans). Diseño aprobado por Ignacio en el chat del 25/11 (ver abajo).

**Goal:** botón "Descargar CSV" en las listas de Carrier Link y la opción "Carrier Link incidents" movida del menú
Database al menú Incidencias.

**Diseño aprobado (25/11):** menú: el ítem `/carrier-link/incidents` sale del grupo Database y va al grupo
INCIDENTS como cuarto ítem; misma ruta, mismo permiso `cl_incidents`, mismo interruptor Carrier Link (solo DEMO2).
CSV: descarga todo lo que cumple los filtros puestos (no solo la página); columnas = las de la pantalla con los mismos
textos; fechas `YYYY-MM-DD HH:MM` en hora local; BOM UTF-8; protección contra fórmulas (`=`, `+`, `-`, `@`, tab, CR
al inicio de un texto → prefijo `'`); tope 50.000 filas con aviso de recortado; textos en en/es/fr/ar/pt. Sin cambios
de base de datos.

## Global Constraints
- Worktree `ONEMS_wt_cl_query`, rama `feat/cl-csv-incidencias` desde `origin/develop`. Commit por tarea; sin push.
- Ninguna escritura en Supabase.
- Textos nuevos en los 5 CSV de `public/locales/` (en, es, fr, ar, pt).
- `npm run lint` y `npm run build` limpios; `npm test` (vitest) verde.

## Tasks
1. **Helper** `src/lib/carrierLink/clCsv.ts` + `src/lib/__tests__/clCsv.test.ts`:
   `CSV_MAX_ROWS = 50000`; `csvCell(v)`; `toCsv(headers, rows)` (CRLF); `csvDate(iso)`; `csvFileName(base, now)`
   → `<base>_YYYYMMDD-HHMM.csv`; `fetchCapped(fetchPage, max)` → `{rows, truncated}`; `downloadCsv(name, text)` (BOM).
   Componente `src/components/carrier-link/ClCsvButton.tsx` (estado ocupado, error, aviso de recortado).
2. **Menú**: mover el ítem en `Sidebar.tsx`.
3. **Samples**: "Descargar muestras", "Descargar lecturas" (lecturas de las muestras filtradas) y botón en el detalle.
4. **Monitor**: entregas (con sus filtros, columna de alertas) y alertas (filtro abiertas/todas).
5. **Incidents**: lista con sus filtros (rpc `cl_incidents_list` por páginas de 1.000).
6. **Reading points**: puntos y lugares sin dar de alta (ya están en memoria).
7. Textos, lint, build, test; revisión final.
