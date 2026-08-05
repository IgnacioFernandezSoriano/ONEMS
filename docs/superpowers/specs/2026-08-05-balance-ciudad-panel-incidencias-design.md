# Panel "Balance de la ciudad" en el detalle de incidencias (solo lectura)

**Fecha:** 2026-08-05
**Contexto:** amplía la pantalla del subsistema C (ver [[incidencias-subsistema-c]]). Da al manager
visibilidad del load balancing de la ciudad al decidir cómo resolver los reroute de una baja.

## 1. Objetivo

Cuando el manager revisa las propuestas de reasignación de una baja, la mayoría son **reroute**
(mover una muestra a otro nodo de la misma ciudad). Para decidir bien —confirmar la sugerencia
del motor o elegir otro nodo en el override— necesita ver **cómo está de cargada cada estación
de la ciudad**. Este panel, de **solo lectura**, muestra ese balance en la propia pantalla.

### Fuera de alcance

- **No** ejecuta rebalanceo (nada de `previewBalance`/`applyBalance`): solo informa. Los
  movimientos se siguen haciendo confirmando/override en las filas de propuestas.
- No aplica a `shift_date`, `cancel` ni `none` (no hay nodo destino); el panel es contexto
  general de la ciudad, no cambia según la fila.
- Sin backend nuevo: reutiliza el RPC ya desplegado del módulo de load balancing.

## 2. Ubicación y comportamiento

- **Cabecera de la baja (ampliación):** al bloque existente de panelista / fechas / causa se le
  añade el **nodo del panelista** (código `auto_id` + ciudad). Reutiliza la clave i18n
  `incidents.inbox.node` ("Node / city"). Es el mismo dato que necesita el panel, así que se
  trae una sola vez.
- Vive en `ProposalReviewPanel` (el detalle nivel 2), **en la cabecera, debajo** del bloque de
  panelista / fechas / causa (ya con el nodo).
- Panel **plegable**, abierto por defecto. Título "Balance de la ciudad · {ciudad}".
- **Solo lectura.** No tiene acciones propias.
- **Reactivo a las decisiones:** confirmar u override de un `reroute` (y de `shift_date`/`cancel`)
  **muta el plan** y cambia la carga de los nodos. El panel debe **recargar sus datos tras cada
  decisión** (individual y en bloque) para mostrar los números reales actualizados. En la
  práctica: cada handler que hoy llama a `loadProposals()` (confirm, override, dismiss, confirm
  seleccionadas, dismiss seleccionadas) debe **también** re-consultar la carga (`refetch` del
  hook `useCityNodeLoad`). Así, al reasignar una muestra a un nodo, ese nodo sube su conteo en el
  panel al instante.

## 3. Contenido — matriz nodo × semana

**Vista de matriz** (revisado tras feedback): filas = nodos de la ciudad, columnas = **semanas**.
La **ventana** va desde el inicio de la baja hasta **fin del mes de la baja + 14 días** (las dos
primeras semanas del mes siguiente), para ver la semana afectada y cómo evoluciona la carga.

Cada fila (nodo de la ciudad del panelista de baja) tiene:

- **Código del nodo** (`nodes.auto_id`).
- **Semáforo de saturación** del periodo: `normal` (verde) / `high` (ámbar) / `saturated` (rojo),
  a partir de `saturation_level` del RPC.
- **Una celda por semana** con el conteo de muestras de ese nodo esa semana (`shipment_count`).
  Las **columnas de las semanas que solapan con la baja** (semanas afectadas) van **resaltadas**.
- **Total** de la fila en la ventana.
- **Marcadores**:
  - 🚫 el **nodo que se libera** — el nodo del panelista de baja (queda sin panelista disponible).
  - ⭐ el/los **nodo(s) sugeridos** por las propuestas pendientes de esta baja (los
    `suggested_target_node_id` de las filas `reroute`).
- **Orden**: de menos a más cargado (los mejores destinos primero); el nodo liberado puede ir
  al final o resaltado aparte.

Si la ciudad tiene un solo nodo o no hay datos de carga en el rango, mostrar un aviso corto
("sin datos de balance para este periodo") en vez de una tabla vacía.

## 4. Datos

- Fuente: RPC **ya desplegado** `rpc_get_node_load_by_period(p_account_id, p_start_date,
  p_end_date, p_reference_load, p_deviation_percent)` (el mismo que usa la página
  NodeLoadBalancing). Devuelve, por nodo (y semana dentro del periodo), `node_id, node_code,
  city_id, city_name, shipment_count, saturation_level, load_percentage`, y agregados de ciudad.
- **Parámetros:** `p_start_date`/`p_end_date` = fechas de la baja; `p_reference_load` = 6 y
  `p_deviation_percent` = 20 (los valores por defecto del módulo) en v1.
- **Agregación:** el RPC devuelve filas por nodo (posiblemente por semana). El hook agrega por
  `node_id`: suma `shipment_count` en el rango y deriva el semáforo del nodo. **A verificar en
  implementación:** si `saturation_level`/`load_percentage` ya vienen a nivel de periodo (una
  cifra por nodo, repetida por semana) se toma tal cual; si vienen por semana, tomar el nivel
  más alto (peor caso) del nodo en el rango. Filtrar a la ciudad del panelista.
- Nuevo hook **`useCityNodeLoad(cityId, startDate, endDate)`** en `src/hooks/` (o
  `src/lib/hooks/`), que envuelve el RPC con `effectiveAccountId`, filtra a la ciudad y devuelve
  `{ nodes: CityNodeLoad[], loading, error, refetch }` con
  `CityNodeLoad = { node_id, node_code, saturation_level, load_count }`. `refetch` (estable, vía
  `useCallback`) re-consulta el RPC; lo llaman los handlers de decisión del panel de propuestas.
- Multi-tenant: el RPC ya filtra por `account_id`; usar `effectiveAccountId`. Solo lectura.

## 5. Integración con lo existente

- `ProposalReviewPanel` ya carga la cabecera de la baja (`fetchUnavailabilityHeader`) con
  panelista y fechas. Necesitará además: la **ciudad** del panelista (para el RPC) y el **node_id**
  del panelista (para el marcador 🚫). Ampliar `UnavailabilityHeader`/`fetchUnavailabilityHeader`
  para devolver `city_id`, `city_name` y el `node_id`/`node_code` del panelista.
- Los nodos sugeridos ⭐ salen de las propuestas ya cargadas (`proposals`, campos
  `suggested_target_node_id` con `reroute`).

## 6. i18n

Claves nuevas `incidents.balance.*` en los **4** CSV (`public/locales/*.csv`): título del panel,
cabeceras de columna (nodo, carga, estado), etiquetas de los tres niveles de saturación,
marcadores (liberado / sugerido), y el aviso de "sin datos". Todo por `useTranslation()`.

## 7. Puerta de calidad

`npm run lint` (0 errores) y `npm run build`. Sin tests de frontend. El RPC ya está desplegado y
probado por el módulo NodeLoadBalancing; no se toca la BD.

## 8. Entregables

| # | Entregable | Tipo |
|---|---|---|
| 1 | Hook `useCityNodeLoad` (envuelve `rpc_get_node_load_by_period`) | Frontend |
| 2 | Ampliar `fetchUnavailabilityHeader`/`UnavailabilityHeader` con ciudad + nodo del panelista, y **mostrar el nodo del panelista en la cabecera** | Frontend |
| 3 | Panel plegable "Balance de la ciudad" en `ProposalReviewPanel` (semáforo + conteo + marcadores) | Frontend |
| 4 | Claves i18n `incidents.balance.*` en 4 idiomas | Frontend |
