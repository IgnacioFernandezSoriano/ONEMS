# Arquitectura Frontend - Módulo de Reporting E2E

## 1. Estructura de Componentes

```
src/
├── pages/
│   ├── Reporting/
│   │   ├── Dashboard.tsx              # Vista 1: Dashboard General
│   │   ├── ComplianceReport.tsx       # Vista 2: Cumplimiento Normativo
│   │   ├── LocalityBreakdown.tsx      # Vista 3: Desglose por Localidad
│   │   └── ShipmentTracking.tsx       # Vista 4: Trazabilidad Individual
│   └── ReportingConfig.tsx            # Configuración (superadmin)
│
├── components/
│   ├── reporting/
│   │   ├── KPICard.tsx                # Card de métrica individual
│   │   ├── DualLineChart.tsx          # Gráfico de líneas dual
│   │   ├── ComplianceTable.tsx        # Tabla de cumplimiento
│   │   ├── LocalityTable.tsx          # Tabla de localidades
│   │   ├── TreemapVisualization.tsx   # Treemap alternativo a mapa
│   │   ├── HeatmapTable.tsx           # Heatmap alternativo a mapa
│   │   ├── TimelineChart.tsx          # Línea de tiempo horizontal
│   │   ├── EventsTable.tsx            # Tabla de eventos
│   │   ├── ReportFilters.tsx          # Filtros globales
│   │   └── TrendIndicator.tsx         # Indicador de tendencia (↑↓)
│   └── ...
│
├── hooks/
│   ├── reporting/
│   │   ├── useReportingGeneral.ts     # Hook para Vista 1
│   │   ├── useComplianceData.ts       # Hook para Vista 2
│   │   ├── useLocalityData.ts         # Hook para Vista 3
│   │   ├── useShipmentTracking.ts     # Hook para Vista 4
│   │   └── useReportingConfig.ts      # Hook para configuración
│   └── ...
│
├── types/
│   └── reporting.ts                   # TypeScript interfaces
│
└── utils/
    └── reportingHelpers.ts            # Funciones auxiliares
```

---

## 2. TypeScript Interfaces

```typescript
// src/types/reporting.ts

export interface ReportingFilters {
  dateFrom: Date;
  dateTo: Date;
  carrier?: string;
  product?: string;
  routeClassification?: string;
  locality?: string;
}

export interface KPIMetric {
  label: string;
  value: number | string;
  unit?: string;
  trend?: 'up' | 'down' | 'stable';
  trendValue?: number;
  color?: 'green' | 'yellow' | 'red';
}

export interface GeneralPerformanceData {
  period: Date;
  compliancePercentage: number;
  avgBusinessDays: number;
  totalShipments: number;
}

export interface ComplianceByClassification {
  routeClassification: string;
  totalShipments: number;
  compliantShipments: number;
  compliancePercentage: number;
  avgBusinessDays: number;
  maxTransitDays: number;
  trend?: 'up' | 'down' | 'stable';
}

export interface LocalityData {
  localityName: string;
  localityClassification: 'capital' | 'major' | 'minor';
  regionName?: string;
  totalShipments: number;
  compliancePercentage: number;
  avgBusinessDays: number;
  maxTransitDays: number;
  primaryCarrier: string;
}

export interface ShipmentEvent {
  timestamp: Date;
  event: string;
  location: string;
  durationFromPrevious?: number;
  additionalInfo?: Record<string, any>;
}

export interface ShipmentTrackingData {
  tagId: string;
  planName: string;
  carrierName: string;
  productName: string;
  originCity: string;
  destinationCity: string;
  sentAt: Date;
  receivedAt: Date;
  expectedDeliveryAt: Date;
  totalTransitDays: number;
  businessTransitDays: number;
  onTimeDelivery: boolean;
  delayHours: number;
  standardDeliveryHours: number;
  timeUnit: string;
  events: ShipmentEvent[];
}

export interface ReportingConfig {
  accountId: string;
  complianceThresholdWarning: number;
  complianceThresholdCritical: number;
  defaultReportPeriod: 'week' | 'month' | 'quarter';
  useRegionalGrouping: boolean;
  preferredMapAlternative: 'treemap' | 'heatmap';
}
```

---

## 3. Hooks de Datos

### Hook 1: useReportingGeneral

```typescript
// src/hooks/reporting/useReportingGeneral.ts

import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import type { GeneralPerformanceData, ReportingFilters, KPIMetric } from '@/types/reporting';

export function useReportingGeneral(filters: ReportingFilters) {
  const { profile } = useAuth();
  const [data, setData] = useState<GeneralPerformanceData[]>([]);
  const [kpis, setKpis] = useState<KPIMetric[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!profile?.account_id) return;

    async function fetchData() {
      try {
        setLoading(true);

        // Fetch time series data
        let query = supabase
          .from('v_reporting_general_performance')
          .select('*')
          .eq('account_id', profile.account_id)
          .gte('period_week', filters.dateFrom.toISOString())
          .lte('period_week', filters.dateTo.toISOString());

        if (filters.carrier) {
          query = query.eq('carrier_name', filters.carrier);
        }
        if (filters.product) {
          query = query.eq('product_name', filters.product);
        }

        const { data: timeSeriesData, error: timeSeriesError } = await query
          .order('period_week', { ascending: true });

        if (timeSeriesError) throw timeSeriesError;

        // Calculate KPIs
        const totalShipments = timeSeriesData.reduce((sum, row) => sum + row.total_shipments, 0);
        const avgCompliance = timeSeriesData.reduce((sum, row) => 
          sum + (row.compliance_percentage * row.total_shipments), 0) / totalShipments;
        const avgBusinessDays = timeSeriesData.reduce((sum, row) => 
          sum + (row.avg_business_days * row.total_shipments), 0) / totalShipments;

        // Calculate trend (compare with previous period)
        // TODO: Implement trend calculation

        setKpis([
          {
            label: 'Cumplimiento General',
            value: avgCompliance.toFixed(2),
            unit: '%',
            trend: 'stable',
            color: avgCompliance >= 95 ? 'green' : avgCompliance >= 85 ? 'yellow' : 'red'
          },
          {
            label: 'Promedio Días Hábiles',
            value: avgBusinessDays.toFixed(2),
            unit: 'días',
            trend: 'stable'
          },
          {
            label: 'Total Envíos Medidos',
            value: totalShipments.toLocaleString(),
            unit: 'envíos'
          }
        ]);

        setData(timeSeriesData.map(row => ({
          period: new Date(row.period_week),
          compliancePercentage: row.compliance_percentage,
          avgBusinessDays: row.avg_business_days,
          totalShipments: row.total_shipments
        })));

        setError(null);
      } catch (err) {
        console.error('Error fetching reporting data:', err);
        setError(err instanceof Error ? err.message : 'Error desconocido');
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [profile?.account_id, filters]);

  return { data, kpis, loading, error };
}
```

### Hook 2: useComplianceData

```typescript
// src/hooks/reporting/useComplianceData.ts

import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import type { ComplianceByClassification, ReportingFilters } from '@/types/reporting';

export function useComplianceData(filters: ReportingFilters) {
  const { profile } = useAuth();
  const [data, setData] = useState<ComplianceByClassification[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!profile?.account_id) return;

    async function fetchData() {
      try {
        setLoading(true);

        const { data: complianceData, error: complianceError } = await supabase
          .from('v_reporting_compliance_by_classification')
          .select('*')
          .eq('account_id', profile.account_id);

        if (complianceError) throw complianceError;

        setData(complianceData.map(row => ({
          routeClassification: row.route_classification,
          totalShipments: row.total_shipments,
          compliantShipments: row.compliant_shipments,
          compliancePercentage: row.compliance_percentage,
          avgBusinessDays: row.avg_business_days,
          maxTransitDays: row.max_transit_days,
          trend: 'stable' // TODO: Calculate trend
        })));

        setError(null);
      } catch (err) {
        console.error('Error fetching compliance data:', err);
        setError(err instanceof Error ? err.message : 'Error desconocido');
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [profile?.account_id, filters]);

  return { data, loading, error };
}
```

### Hook 3: useLocalityData

```typescript
// src/hooks/reporting/useLocalityData.ts

import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import type { LocalityData, ReportingFilters } from '@/types/reporting';

export function useLocalityData(filters: ReportingFilters) {
  const { profile } = useAuth();
  const [data, setData] = useState<LocalityData[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!profile?.account_id) return;

    async function fetchData() {
      try {
        setLoading(true);

        const { data: localityData, error: localityError } = await supabase
          .from('v_reporting_by_locality')
          .select('*')
          .eq('account_id', profile.account_id)
          .order('total_shipments', { ascending: false });

        if (localityError) throw localityError;

        setData(localityData.map(row => ({
          localityName: row.locality_name,
          localityClassification: row.locality_classification,
          regionName: row.region_name,
          totalShipments: row.total_shipments,
          compliancePercentage: row.compliance_percentage,
          avgBusinessDays: row.avg_business_days,
          maxTransitDays: row.max_transit_days,
          primaryCarrier: row.primary_carrier
        })));

        setError(null);
      } catch (err) {
        console.error('Error fetching locality data:', err);
        setError(err instanceof Error ? err.message : 'Error desconocido');
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [profile?.account_id, filters]);

  return { data, loading, error };
}
```

### Hook 4: useShipmentTracking

```typescript
// src/hooks/reporting/useShipmentTracking.ts

import { useState, useEffect } from 'react';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import type { ShipmentTrackingData } from '@/types/reporting';

export function useShipmentTracking(tagId: string) {
  const { profile } = useAuth();
  const [data, setData] = useState<ShipmentTrackingData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (!profile?.account_id || !tagId) return;

    async function fetchData() {
      try {
        setLoading(true);

        const { data: trackingData, error: trackingError } = await supabase
          .from('v_reporting_individual_tracking')
          .select('*')
          .eq('account_id', profile.account_id)
          .eq('tag_id', tagId)
          .single();

        if (trackingError) throw trackingError;

        // Parse events from source_data_snapshot
        const events = parseEventsFromSnapshot(trackingData.source_data_snapshot);

        setData({
          tagId: trackingData.tag_id,
          planName: trackingData.plan_name,
          carrierName: trackingData.carrier_name,
          productName: trackingData.product_name,
          originCity: trackingData.origin_city_name,
          destinationCity: trackingData.destination_city_name,
          sentAt: new Date(trackingData.sent_at),
          receivedAt: new Date(trackingData.received_at),
          expectedDeliveryAt: new Date(trackingData.expected_delivery_at),
          totalTransitDays: trackingData.total_transit_days,
          businessTransitDays: trackingData.business_transit_days,
          onTimeDelivery: trackingData.on_time_delivery,
          delayHours: trackingData.delay_hours,
          standardDeliveryHours: trackingData.standard_delivery_hours,
          timeUnit: trackingData.time_unit,
          events
        });

        setError(null);
      } catch (err) {
        console.error('Error fetching shipment tracking:', err);
        setError(err instanceof Error ? err.message : 'Error desconocido');
      } finally {
        setLoading(false);
      }
    }

    fetchData();
  }, [profile?.account_id, tagId]);

  return { data, loading, error };
}

function parseEventsFromSnapshot(snapshot: any): ShipmentEvent[] {
  // TODO: Implement event parsing logic
  return [];
}
```

---

## 4. Componentes Principales

### Vista 1: Dashboard General

```typescript
// src/pages/Reporting/Dashboard.tsx

import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useReportingGeneral } from '@/hooks/reporting/useReportingGeneral';
import KPICard from '@/components/reporting/KPICard';
import DualLineChart from '@/components/reporting/DualLineChart';
import ReportFilters from '@/components/reporting/ReportFilters';
import type { ReportingFilters } from '@/types/reporting';

export default function ReportingDashboard() {
  const navigate = useNavigate();
  const [filters, setFilters] = useState<ReportingFilters>({
    dateFrom: new Date(new Date().setMonth(new Date().getMonth() - 3)),
    dateTo: new Date()
  });

  const { data, kpis, loading, error } = useReportingGeneral(filters);

  if (loading) return <div>Cargando...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div className="p-6">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold">Dashboard de Desempeño General</h1>
        <button
          onClick={() => navigate('/reporting/compliance')}
          className="btn btn-primary"
        >
          Ver Informe de Cumplimiento →
        </button>
      </div>

      <ReportFilters filters={filters} onChange={setFilters} />

      {/* KPIs */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        {kpis.map((kpi, index) => (
          <KPICard key={index} {...kpi} />
        ))}
      </div>

      {/* Gráfico de líneas dual */}
      <div className="bg-white rounded-lg shadow p-6 mb-6">
        <h2 className="text-lg font-semibold mb-4">Evolución Temporal</h2>
        <DualLineChart data={data} />
      </div>

      {/* Distribución por Carrier */}
      <div className="bg-white rounded-lg shadow p-6">
        <h2 className="text-lg font-semibold mb-4">Distribución por Carrier</h2>
        {/* TODO: Implement carrier distribution chart */}
      </div>
    </div>
  );
}
```

### Vista 2: Cumplimiento Normativo

```typescript
// src/pages/Reporting/ComplianceReport.tsx

import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useComplianceData } from '@/hooks/reporting/useComplianceData';
import ComplianceTable from '@/components/reporting/ComplianceTable';
import ReportFilters from '@/components/reporting/ReportFilters';
import type { ReportingFilters } from '@/types/reporting';

export default function ComplianceReport() {
  const navigate = useNavigate();
  const [filters, setFilters] = useState<ReportingFilters>({
    dateFrom: new Date(new Date().setMonth(new Date().getMonth() - 1)),
    dateTo: new Date()
  });

  const { data, loading, error } = useComplianceData(filters);

  const handleRowClick = (classification: string) => {
    navigate(`/reporting/locality?classification=${classification}`);
  };

  if (loading) return <div>Cargando...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div className="p-6">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold">Informe de Cumplimiento Normativo</h1>
        <button
          onClick={() => navigate('/reporting/dashboard')}
          className="btn btn-secondary"
        >
          ← Volver al Dashboard
        </button>
      </div>

      <ReportFilters filters={filters} onChange={setFilters} />

      <ComplianceTable 
        data={data} 
        onRowClick={handleRowClick}
      />
    </div>
  );
}
```

### Vista 3: Desglose por Localidad

```typescript
// src/pages/Reporting/LocalityBreakdown.tsx

import React, { useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useLocalityData } from '@/hooks/reporting/useLocalityData';
import LocalityTable from '@/components/reporting/LocalityTable';
import TreemapVisualization from '@/components/reporting/TreemapVisualization';
import ReportFilters from '@/components/reporting/ReportFilters';
import type { ReportingFilters } from '@/types/reporting';

export default function LocalityBreakdown() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const classification = searchParams.get('classification');

  const [filters, setFilters] = useState<ReportingFilters>({
    dateFrom: new Date(new Date().setMonth(new Date().getMonth() - 1)),
    dateTo: new Date(),
    routeClassification: classification || undefined
  });

  const { data, loading, error } = useLocalityData(filters);

  const handleRowClick = (localityName: string) => {
    // Navigate to individual tracking filtered by locality
    navigate(`/reporting/tracking?locality=${localityName}`);
  };

  if (loading) return <div>Cargando...</div>;
  if (error) return <div>Error: {error}</div>;

  return (
    <div className="p-6">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold">Desglose por Localidad</h1>
        <button
          onClick={() => navigate('/reporting/compliance')}
          className="btn btn-secondary"
        >
          ← Volver a Cumplimiento
        </button>
      </div>

      <ReportFilters filters={filters} onChange={setFilters} />

      {/* Treemap visualization */}
      <div className="bg-white rounded-lg shadow p-6 mb-6">
        <h2 className="text-lg font-semibold mb-4">Visualización Geográfica</h2>
        <TreemapVisualization data={data} />
      </div>

      {/* Locality table */}
      <LocalityTable 
        data={data} 
        onRowClick={handleRowClick}
      />
    </div>
  );
}
```

### Vista 4: Trazabilidad Individual

```typescript
// src/pages/Reporting/ShipmentTracking.tsx

import React from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useShipmentTracking } from '@/hooks/reporting/useShipmentTracking';
import TimelineChart from '@/components/reporting/TimelineChart';
import EventsTable from '@/components/reporting/EventsTable';

export default function ShipmentTracking() {
  const { tagId } = useParams<{ tagId: string }>();
  const navigate = useNavigate();
  const { data, loading, error } = useShipmentTracking(tagId || '');

  if (loading) return <div>Cargando...</div>;
  if (error) return <div>Error: {error}</div>;
  if (!data) return <div>No se encontró el envío</div>;

  return (
    <div className="p-6">
      <div className="flex justify-between items-center mb-6">
        <h1 className="text-2xl font-bold">Trazabilidad: {data.tagId}</h1>
        <button
          onClick={() => navigate(-1)}
          className="btn btn-secondary"
        >
          ← Volver
        </button>
      </div>

      {/* Shipment info cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <div className="bg-white rounded-lg shadow p-4">
          <h3 className="text-sm text-gray-500">Ruta</h3>
          <p className="text-lg font-semibold">
            {data.originCity} → {data.destinationCity}
          </p>
        </div>
        <div className="bg-white rounded-lg shadow p-4">
          <h3 className="text-sm text-gray-500">Tiempo de Tránsito</h3>
          <p className="text-lg font-semibold">
            {data.businessTransitDays} días hábiles
          </p>
        </div>
        <div className="bg-white rounded-lg shadow p-4">
          <h3 className="text-sm text-gray-500">Cumplimiento</h3>
          <p className={`text-lg font-semibold ${data.onTimeDelivery ? 'text-green-600' : 'text-red-600'}`}>
            {data.onTimeDelivery ? 'A tiempo' : `Retraso: ${data.delayHours.toFixed(1)}h`}
          </p>
        </div>
      </div>

      {/* Timeline */}
      <div className="bg-white rounded-lg shadow p-6 mb-6">
        <h2 className="text-lg font-semibold mb-4">Línea de Tiempo</h2>
        <TimelineChart data={data} />
      </div>

      {/* Events table */}
      <div className="bg-white rounded-lg shadow p-6">
        <h2 className="text-lg font-semibold mb-4">Eventos</h2>
        <EventsTable events={data.events} />
      </div>
    </div>
  );
}
```

---

## 5. Rutas y Navegación

```typescript
// src/App.tsx (agregar rutas)

import ReportingDashboard from '@/pages/Reporting/Dashboard';
import ComplianceReport from '@/pages/Reporting/ComplianceReport';
import LocalityBreakdown from '@/pages/Reporting/LocalityBreakdown';
import ShipmentTracking from '@/pages/Reporting/ShipmentTracking';
import ReportingConfig from '@/pages/ReportingConfig';

// En el router:
{
  path: '/reporting',
  children: [
    { path: 'dashboard', element: <ReportingDashboard /> },
    { path: 'compliance', element: <ComplianceReport /> },
    { path: 'locality', element: <LocalityBreakdown /> },
    { path: 'tracking/:tagId', element: <ShipmentTracking /> }
  ]
},
{
  path: '/settings/reporting-config',
  element: <ReportingConfig /> // Solo superadmin
}
```

---

## 6. Librerías de Visualización Recomendadas

### Opción 1: Recharts (Recomendada)
- **Pros:** React-native, fácil de usar, buena documentación
- **Uso:** Gráficos de líneas, barras, treemap
- **Instalación:** `npm install recharts`

### Opción 2: Chart.js con react-chartjs-2
- **Pros:** Muy popular, muchos ejemplos
- **Uso:** Gráficos de líneas, barras
- **Instalación:** `npm install chart.js react-chartjs-2`

### Opción 3: D3.js (Para visualizaciones avanzadas)
- **Pros:** Máxima flexibilidad
- **Contras:** Curva de aprendizaje más alta
- **Uso:** Treemap, heatmap personalizados

---

## 7. Checklist de Implementación

### Fase 1: Setup
- [ ] Crear estructura de carpetas
- [ ] Definir interfaces TypeScript
- [ ] Instalar librerías de visualización

### Fase 2: Hooks
- [ ] Implementar useReportingGeneral
- [ ] Implementar useComplianceData
- [ ] Implementar useLocalityData
- [ ] Implementar useShipmentTracking
- [ ] Implementar useReportingConfig

### Fase 3: Componentes Básicos
- [ ] KPICard
- [ ] TrendIndicator
- [ ] ReportFilters
- [ ] EventsTable

### Fase 4: Componentes de Visualización
- [ ] DualLineChart
- [ ] TreemapVisualization o HeatmapTable
- [ ] TimelineChart
- [ ] ComplianceTable
- [ ] LocalityTable

### Fase 5: Páginas
- [ ] ReportingDashboard
- [ ] ComplianceReport
- [ ] LocalityBreakdown
- [ ] ShipmentTracking
- [ ] ReportingConfig

### Fase 6: Navegación
- [ ] Configurar rutas
- [ ] Implementar navegación entre vistas
- [ ] Agregar al menú principal

### Fase 7: Testing
- [ ] Test con datos reales
- [ ] Verificar filtros
- [ ] Verificar navegación
- [ ] Optimización de rendimiento

---

## 8. Consideraciones de UX

### Colores de Estado
- **Verde:** Cumplimiento ≥ 95%
- **Amarillo:** Cumplimiento 85-95%
- **Rojo:** Cumplimiento < 85%

### Indicadores de Tendencia
- **↑ Verde:** Mejora
- **↓ Rojo:** Deterioro
- **→ Gris:** Estable

### Interactividad
- Todas las tablas deben ser clicables
- Tooltips en gráficos
- Búsqueda y ordenamiento en tablas
- Exportación a CSV/PDF (fase futura)

---

**Documento preparado por:** Manus AI  
**Para:** ONE MS - Módulo de Reporting E2E  
**Próxima revisión:** Tras inicio de implementación
