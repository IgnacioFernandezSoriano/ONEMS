# Diseño de Estructura de Datos Basada en Rutas

## Problema Actual

El sistema agrega datos por **ciudad**, perdiendo la relación origen-destino:
- Inbound de una ciudad = TODOS los envíos que llegan (desde cualquier origen)
- Outbound de una ciudad = TODOS los envíos que salen (hacia cualquier destino)

Cuando se aplica un filtro `Origin=Sacramento`, el Inbound de New York muestra envíos desde TODOS los orígenes, no solo Sacramento.

## Solución: Datos por Ruta

Mantener los datos agregados por **ruta** (par origen-destino) y solo agrupar para visualización.

### Nueva Estructura de Datos

```typescript
interface RouteEquityData {
  // Route identification
  originCityId: string;
  originCityName: string;
  originRegionId: string;
  originRegionName: string | null;
  
  destinationCityId: string;
  destinationCityName: string;
  destinationRegionId: string;
  destinationRegionName: string | null;
  
  // Route-level metrics
  totalShipments: number;
  compliantShipments: number;
  actualPercentage: number;
  standardPercentage: number;
  standardDays: number;  // J+K Standard
  actualDays: number;    // J+K Actual
  deviation: number;
  status: 'compliant' | 'warning' | 'critical';
  
  // Carrier/Product breakdown for this route
  carrierProductBreakdown: Array<{
    carrier: string;
    product: string;
    totalShipments: number;
    compliantShipments: number;
    actualPercentage: number;
    standardPercentage: number;
    standardDays: number;
    actualDays: number;
    deviation: number;
  }>;
  
  accountId: string;
}
```

### Lógica de Agrupación para Visualización

**Escenario: Origin Filter (ej. Sacramento)**

Para cada ciudad destino única en las rutas filtradas:
1. **Grupo de Ciudad Destino** (ej. "New York")
   - **Inbound Row**: Métricas de la ruta Sacramento → New York
   - **Outbound Row**: Métricas de la ruta Sacramento → New York (misma ruta, vista desde origen)

**Escenario: Destination Filter (ej. New York)**

Para cada ciudad origen única en las rutas filtradas:
1. **Grupo de Ciudad Origen** (ej. "Sacramento")
   - **Inbound Row**: Métricas de la ruta Sacramento → New York (vista desde destino)
   - **Outbound Row**: Métricas de la ruta Sacramento → New York (vista desde origen)

**Escenario: Route Filter (Origin + Destination)**

Una sola ruta específica:
1. **Grupo de la Ruta**
   - **Inbound Row**: Métricas de esa ruta específica
   - **Outbound Row**: Métricas de esa ruta específica (misma ruta)

**Escenario: General (sin filtros)**

Todas las rutas, agrupadas por ciudad:
- Para cada ciudad que aparece como origen O destino:
  - **Inbound Row**: Suma de TODAS las rutas donde la ciudad es destino
  - **Outbound Row**: Suma de TODAS las rutas donde la ciudad es origen

### Transformación de Datos

```typescript
// 1. Mantener datos por ruta
const routeDataMap = new Map<string, RouteEquityData>();
// Key: "originCityId|destinationCityId"

// 2. Procesar cada shipment
shipments.forEach(shipment => {
  const routeKey = `${shipment.origin_city_id}|${shipment.destination_city_id}`;
  
  if (!routeDataMap.has(routeKey)) {
    routeDataMap.set(routeKey, {
      originCityId: shipment.origin_city_id,
      originCityName: shipment.origin_city_name,
      // ... inicializar estructura
    });
  }
  
  const routeData = routeDataMap.get(routeKey)!;
  routeData.totalShipments++;
  // ... agregar métricas
});

// 3. Convertir a array y filtrar
const routeDataArray = Array.from(routeDataMap.values());

// 4. Agrupar para visualización según escenario
function groupRoutesForDisplay(
  routes: RouteEquityData[],
  scenario: FilterScenario
): CityEquityData[] {
  // Implementar lógica de agrupación según escenario
}
```

### Ventajas

1. **Precisión**: Los filtros muestran exactamente las rutas seleccionadas
2. **Flexibilidad**: Podemos agregar de diferentes formas según el escenario
3. **Escalabilidad**: Fácil agregar análisis de rutas específicas
4. **Consistencia**: Misma lógica para todos los reportes

### Cambios Necesarios

#### Hooks
- `useTerritoryEquityData.ts`: Refactorizar para mantener `routeDataMap`
- `useComplianceData.ts`: Aplicar misma lógica
- `useJKPerformance.ts`: Aplicar misma lógica
- `useCarrierProductOverview.ts`: Aplicar misma lógica

#### Componentes
- `TerritoryEquityTable.tsx`: Recibir datos agrupados correctamente
- `InboundOutboundChart.tsx`: Usar datos filtrados por ruta
- `RegionalAnalysis.tsx`: Agregar rutas por región

#### Tipos
- Agregar `RouteEquityData` interface
- Mantener `CityEquityData` para compatibilidad de visualización
- Agregar funciones de agrupación

### Plan de Implementación

1. **Fase 1**: Crear nueva estructura `RouteEquityData`
2. **Fase 2**: Refactorizar `useTerritoryEquityData` para mantener datos por ruta
3. **Fase 3**: Implementar función de agrupación según escenario
4. **Fase 4**: Actualizar componentes de visualización
5. **Fase 5**: Replicar a otros hooks
6. **Fase 6**: Testing exhaustivo de todos los escenarios
7. **Fase 7**: Deploy y documentación
