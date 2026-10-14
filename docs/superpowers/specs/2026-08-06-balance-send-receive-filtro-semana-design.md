# Balance de la ciudad: send/receive por semana + filtro por semana

**Fecha:** 2026-08-06
**Módulo:** Incidencias (subsistema C) — panel "Balance de la ciudad" del manager.

## Problema

La matriz nodo×semana del panel de Balance muestra un único número por celda que en
realidad son **solo envíos (send)**: la RPC `rpc_get_node_load_by_period` devuelve
`received_count` fijado a `0`. El manager no distingue send de receive, y no puede
tratar la incidencia semana a semana.

## Objetivo

1. Cada semana muestra **dos subcolumnas: S (send) y R (receive)**.
2. Pulsar la cabecera de una semana **filtra la lista de propuestas** a las muestras de
   esa semana (la tabla sigue mostrando todas las semanas). Toggle: volver a pulsar quita
   el filtro.

## Diseño

### Base de datos (1 migración forward-only)
- `CREATE OR REPLACE FUNCTION public.rpc_get_node_load_by_period(...)` con **la misma
  firma**. Único cambio: sustituir `0 AS received_count` por una subconsulta correlacionada
  que cuenta envíos donde el nodo es **destino** en la misma ventana de la semana:
  `COUNT(DISTINCT apd2.id) WHERE apd2.destination_node_id = n.id AND ...`.
- `sent_count`, `shipment_count`, la saturación y las stats de ciudad **no cambian** (siguen
  basadas en origen). El módulo Load Balancing lee `shipment_count` y no pinta
  `received_count` → **sin impacto**.
- Proyecto: `onems-dev` / `sehbnpgzqljrsqimwyuz`. Se aplica por el dashboard con confirmación.

### Tipos (`src/lib/types.ts`)
- `CityNodeLoadRow.counts: Record<number, { sent: number; received: number }>`.
- `CityNodeLoadRow.total: { sent: number; received: number }`.

### Hook (`src/lib/hooks/useCityNodeLoad.ts`)
- Acumular por semana `sent = row.sent_count` y `received = row.received_count`.
- `total` acumula ambos.

### Componente (`src/components/incidents/ProposalReviewPanel.tsx`)
- Cabecera a dos filas: fila 1 con "Sem N" (colSpan=2, clicable), fila 2 con "S | R".
  Columnas Nodo/Estado usan rowSpan=2; Total desdoblado en S/R.
- Celdas de cuerpo: dos `<td>` por semana (sent, received). Total del nodo en S/R.
- Estado nuevo `selectedWeek: number | null`. Click en cabecera de semana → toggle.
  Semana seleccionada resaltada (además del ámbar de semana afectada).
- Lista de propuestas: filtrar `pendingProposals` por `detail.fecha_programada` dentro de
  `[week_start_date, week_end_date]` de la semana seleccionada. Sin selección → todas.
- Aviso corto bajo la tabla: "pulsa una semana para filtrar" / al filtrar, indica qué semana
  y cómo quitarlo.

### i18n (4 idiomas: en/es/fr/ar)
Claves nuevas bajo `incidents.balance.`: `send` (S), `receive` (R), `send_full`,
`receive_full`, `week_filter_hint`, `week_filter_active`.

## Fuera de alcance
Motor de propuestas, módulo Load Balancing, lógica de resolución de incidencias.
