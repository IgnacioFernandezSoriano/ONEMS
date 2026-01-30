import { useState, useMemo, Fragment } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useReportingFilters } from '@/contexts/ReportingFiltersContext';
import { useJKPerformance } from '@/hooks/reporting/useJKPerformance';
import { KPICard } from '@/components/reporting/KPICard';
import { ReportFilters } from '@/components/reporting/ReportFilters';
import { Package, Clock, CheckCircle, AlertTriangle, Info, FileDown } from 'lucide-react';
import { WeeklySamplesChart } from '@/components/reporting/WeeklySamplesChart';
import { PerformanceDistributionChart } from '@/components/reporting/PerformanceDistributionChart';
import { CumulativeDistributionTable } from '@/components/reporting/CumulativeDistributionTable';
import { CumulativeDistributionChart } from '@/components/reporting/CumulativeDistributionChart';
import { exportRouteCSV, exportCityCSV, exportRegionCSV, exportCarrierProductCSV, exportCumulativeCSV } from '@/utils/jkExportCSV';
import { ColumnTooltip } from '@/components/reporting/ColumnTooltip';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import { useTranslation } from '@/hooks/useTranslation';

export default function JKPerformance() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;
  const { filters, setFilters, resetFilters } = useReportingFilters();
  const [activeTab, setActiveTab] = useState<'route' | 'city' | 'region' | 'carrier' | 'cumulative'>('route');
  const [cumulativeView, setCumulativeView] = useState<'table' | 'chart'>('chart');
  const [showProblematicOnly, setShowProblematicOnly] = useState(false);

  const {
    routeData: rawRouteData,
    cityData: rawCityData,
    regionData: rawRegionData,
    carrierData: rawCarrierData,
    productData: rawProductData,
    weeklySamples: rawWeeklySamples,
    metrics: rawMetrics,
    maxDays,
    globalWarningThreshold,
    globalCriticalThreshold,
    loading,
    error,
  } = useJKPerformance(accountId, {
    startDate: filters.startDate,
    endDate: filters.endDate,
    originCity: filters.originCity,
    destinationCity: filters.destinationCity,
    carrier: filters.carrier,
    product: filters.product,

  });

  // Apply problematic routes filter globally
  const filteredRouteData = useMemo(() => {
    if (!showProblematicOnly) return rawRouteData;
    return rawRouteData.filter(route => route.onTimePercentage <= route.criticalThreshold);
  }, [rawRouteData, showProblematicOnly]);

  // Recalculate all derived data based on filtered routes
  const { routeData, cityData, regionData, carrierData, productData, weeklySamples, metrics } = useMemo(() => {
    // Apply compliance status filter first
    let baseRouteData = rawRouteData;
    let baseCityData = rawCityData;
    let baseRegionData = rawRegionData;
    let baseCarrierData = rawCarrierData;
    let baseProductData = rawProductData;

    // Filter by compliance status if selected
    if (filters.complianceStatus) {
      const selectedStatuses = filters.complianceStatus.split(',').filter(s => s);
      if (selectedStatuses.length > 0 && selectedStatuses.length < 3) {
        baseRouteData = baseRouteData.filter(r => selectedStatuses.includes(r.status));
        baseCityData = baseCityData.filter(c => selectedStatuses.includes(c.status));
        baseRegionData = baseRegionData.filter(r => selectedStatuses.includes(r.status));
        baseCarrierData = baseCarrierData.filter(c => selectedStatuses.includes(c.status));
        baseProductData = baseProductData.filter(p => selectedStatuses.includes(p.status));
      }
    }

    if (!showProblematicOnly) {
      // Sort weekly samples chronologically even when no filter is active
      const sortedWeeklySamples = [...rawWeeklySamples].sort((a, b) => 
        new Date(a.weekStart).getTime() - new Date(b.weekStart).getTime()
      );
      
      // Recalculate metrics from filtered data
      const totalSamples = baseRouteData.reduce((sum, r) => sum + r.totalSamples, 0);
      const totalWeightedJKActual = baseRouteData.reduce((sum, r) => sum + r.jkActual * r.totalSamples, 0);
      const totalWeightedJKStandard = baseRouteData.reduce((sum, r) => sum + r.jkStandard * r.totalSamples, 0);
      const onTimeSamples = baseRouteData.reduce((sum, r) => sum + r.onTimeSamples, 0);
      const avgJKActual = totalSamples > 0 ? totalWeightedJKActual / totalSamples : 0;
      const avgJKStandard = totalSamples > 0 ? totalWeightedJKStandard / totalSamples : 0;
      const onTimePercentage = totalSamples > 0 ? (onTimeSamples / totalSamples) * 100 : 0;
      const problematicRoutes = baseRouteData.filter(r => r.onTimePercentage <= r.criticalThreshold).length;

      const filteredMetrics = {
        totalSamples,
        avgJKActual,
        avgJKStandard,
        onTimePercentage,
        onTimeSamples,
        problematicRoutes,
      };
      
      // Sort cityData by city name, then by direction (inbound first, outbound second)
      const sortedBaseCityData = [...baseCityData].sort((a, b) => {
        const cityCompare = a.cityName.localeCompare(b.cityName);
        if (cityCompare !== 0) return cityCompare;
        return a.direction === 'inbound' ? -1 : 1;
      });
      
      return {
        routeData: baseRouteData,
        cityData: sortedBaseCityData,
        regionData: baseRegionData,
        carrierData: baseCarrierData,
        productData: baseProductData,
        weeklySamples: sortedWeeklySamples,
        metrics: filteredMetrics,
      };
    }

    // Use filtered route data and apply compliance status filter
    let routeData = filteredRouteData;
    if (filters.complianceStatus) {
      const selectedStatuses = filters.complianceStatus.split(',').filter(s => s);
      if (selectedStatuses.length > 0 && selectedStatuses.length < 3) {
        routeData = routeData.filter(r => selectedStatuses.includes(r.status));
      }
    }

    // Recalculate metrics from filtered routes
    const totalSamples = routeData.reduce((sum, r) => sum + r.totalSamples, 0);
    const totalWeightedJKActual = routeData.reduce((sum, r) => sum + r.jkActual * r.totalSamples, 0);
    const totalWeightedJKStandard = routeData.reduce((sum, r) => sum + r.jkStandard * r.totalSamples, 0);
    const onTimeSamples = routeData.reduce((sum, r) => sum + r.onTimeSamples, 0);
    const avgJKActual = totalSamples > 0 ? totalWeightedJKActual / totalSamples : 0;
    const avgJKStandard = totalSamples > 0 ? totalWeightedJKStandard / totalSamples : 0;
    const onTimePercentage = totalSamples > 0 ? (onTimeSamples / totalSamples) * 100 : 0;
    const problematicRoutes = routeData.filter(r => r.onTimePercentage <= r.criticalThreshold).length;

    const metrics = {
      totalSamples,
      avgJKActual,
      avgJKStandard,
      onTimePercentage,
      onTimeSamples,
      problematicRoutes,
    };

    // Recalculate city data from filtered routes
    const cityMap = new Map<string, any>();
    routeData.forEach(route => {
      // Outbound (origin city)
      const outboundKey = `${route.originCity}-outbound`;
      if (!cityMap.has(outboundKey)) {
        cityMap.set(outboundKey, {
          cityName: route.originCity,
          direction: 'outbound',
          regionName: '', // Would need to be fetched from original data
          routes: 0,
          totalSamples: 0,
          totalWeightedJKStandard: 0,
          totalWeightedJKActual: 0,
          onTimeSamples: 0,
        });
      }
      const outbound = cityMap.get(outboundKey);
      outbound.routes++;
      outbound.totalSamples += route.totalSamples;
      outbound.totalWeightedJKStandard += route.jkStandard * route.totalSamples;
      outbound.totalWeightedJKActual += route.jkActual * route.totalSamples;
      outbound.onTimeSamples += route.onTimeSamples;

      // Inbound (destination city)
      const inboundKey = `${route.destinationCity}-inbound`;
      if (!cityMap.has(inboundKey)) {
        cityMap.set(inboundKey, {
          cityName: route.destinationCity,
          direction: 'inbound',
          regionName: '', // Would need to be fetched from original data
          routes: 0,
          totalSamples: 0,
          totalWeightedJKStandard: 0,
          totalWeightedJKActual: 0,
          onTimeSamples: 0,
        });
      }
      const inbound = cityMap.get(inboundKey);
      inbound.routes++;
      inbound.totalSamples += route.totalSamples;
      inbound.totalWeightedJKStandard += route.jkStandard * route.totalSamples;
      inbound.totalWeightedJKActual += route.jkActual * route.totalSamples;
      inbound.onTimeSamples += route.onTimeSamples;
    });

    const cityData = Array.from(cityMap.values()).map(city => {
      const jkStandard = city.totalSamples > 0 ? city.totalWeightedJKStandard / city.totalSamples : 0;
      const jkActual = city.totalSamples > 0 ? city.totalWeightedJKActual / city.totalSamples : 0;
      const deviation = jkActual - jkStandard;
      const onTimePercentage = city.totalSamples > 0 ? (city.onTimeSamples / city.totalSamples) * 100 : 0;
      const status: 'compliant' | 'warning' | 'critical' = onTimePercentage >= globalWarningThreshold ? 'compliant' : onTimePercentage > globalCriticalThreshold ? 'warning' : 'critical';
      
      // Find region name from original data
      const originalCity = rawCityData.find(c => c.cityName === city.cityName && c.direction === city.direction);
      
      return {
        ...city,
        regionName: originalCity?.regionName || '',
        jkStandard,
        jkActual,
        deviation,
        onTimePercentage,
        status,
      };
    });

    // Recalculate region data from city data
    const regionMap = new Map<string, any>();
    cityData.forEach(city => {
      const key = `${city.regionName}-${city.direction}`;
      if (!regionMap.has(key)) {
        regionMap.set(key, {
          regionName: city.regionName,
          direction: city.direction,
          cities: new Set(),
          routes: 0,
          totalSamples: 0,
          totalWeightedJKStandard: 0,
          totalWeightedJKActual: 0,
          onTimeSamples: 0,
        });
      }
      const region = regionMap.get(key);
      region.cities.add(city.cityName);
      region.routes += city.routes;
      region.totalSamples += city.totalSamples;
      region.totalWeightedJKStandard += city.jkStandard * city.totalSamples;
      region.totalWeightedJKActual += city.jkActual * city.totalSamples;
      region.onTimeSamples += city.onTimeSamples;
    });

    const regionData = Array.from(regionMap.values()).map(region => {
      const jkStandard = region.totalSamples > 0 ? region.totalWeightedJKStandard / region.totalSamples : 0;
      const jkActual = region.totalSamples > 0 ? region.totalWeightedJKActual / region.totalSamples : 0;
      const deviation = jkActual - jkStandard;
      const onTimePercentage = region.totalSamples > 0 ? (region.onTimeSamples / region.totalSamples) * 100 : 0;
      const status: 'compliant' | 'warning' | 'critical' = onTimePercentage >= globalWarningThreshold ? 'compliant' : onTimePercentage > globalCriticalThreshold ? 'warning' : 'critical';
      
      return {
        regionName: region.regionName,
        direction: region.direction,
        cities: region.cities.size,
        routes: region.routes,
        totalSamples: region.totalSamples,
        jkStandard,
        jkActual,
        deviation,
        onTimePercentage,
        status,
      };
    });

    // Recalculate carrier/product data from filtered routes
    const carrierMap = new Map<string, any>();
    routeData.forEach(route => {
      if (!carrierMap.has(route.carrier)) {
        carrierMap.set(route.carrier, {
          carrier: route.carrier,
          routes: 0,
          totalSamples: 0,
          totalWeightedJKStandard: 0,
          totalWeightedJKActual: 0,
          onTimeSamples: 0,
          problematicRoutes: 0,
          products: new Map(),
        });
      }
      const carrier = carrierMap.get(route.carrier);
      carrier.routes++;
      carrier.totalSamples += route.totalSamples;
      carrier.totalWeightedJKStandard += route.jkStandard * route.totalSamples;
      carrier.totalWeightedJKActual += route.jkActual * route.totalSamples;
      carrier.onTimeSamples += route.onTimeSamples;
      if (route.onTimePercentage <= route.criticalThreshold) {
        carrier.problematicRoutes++;
      }

      // Track products within carrier
      if (!carrier.products.has(route.product)) {
        carrier.products.set(route.product, {
          product: route.product,
          routes: 0,
          totalSamples: 0,
          totalWeightedJKStandard: 0,
          totalWeightedJKActual: 0,
          onTimeSamples: 0,
        });
      }
      const product = carrier.products.get(route.product);
      product.routes++;
      product.totalSamples += route.totalSamples;
      product.totalWeightedJKStandard += route.jkStandard * route.totalSamples;
      product.totalWeightedJKActual += route.jkActual * route.totalSamples;
      product.onTimeSamples += route.onTimeSamples;
    });

    const carrierData = Array.from(carrierMap.values()).map(carrier => {
      const jkStandard = carrier.totalSamples > 0 ? carrier.totalWeightedJKStandard / carrier.totalSamples : 0;
      const jkActual = carrier.totalSamples > 0 ? carrier.totalWeightedJKActual / carrier.totalSamples : 0;
      const deviation = jkActual - jkStandard;
      const onTimePercentage = carrier.totalSamples > 0 ? (carrier.onTimeSamples / carrier.totalSamples) * 100 : 0;
      const status: 'compliant' | 'warning' | 'critical' = onTimePercentage >= globalWarningThreshold ? 'compliant' : onTimePercentage > globalCriticalThreshold ? 'warning' : 'critical';
      
      const products = Array.from(carrier.products.values()).map((p: any) => {
        const pJkStandard = p.totalSamples > 0 ? p.totalWeightedJKStandard / p.totalSamples : 0;
        const pJkActual = p.totalSamples > 0 ? p.totalWeightedJKActual / p.totalSamples : 0;
        const pDeviation = pJkActual - pJkStandard;
        const pOnTimePercentage = p.totalSamples > 0 ? (p.onTimeSamples / p.totalSamples) * 100 : 0;
        const pStatus: 'compliant' | 'warning' | 'critical' = pOnTimePercentage >= globalWarningThreshold ? 'compliant' : pOnTimePercentage > globalCriticalThreshold ? 'warning' : 'critical';
        
        return {
          product: p.product,
          routes: p.routes,
          totalSamples: p.totalSamples,
          jkStandard: pJkStandard,
          jkActual: pJkActual,
          deviation: pDeviation,
          onTimePercentage: pOnTimePercentage,
          status: pStatus,
        };
      });

      return {
        carrier: carrier.carrier,
        routes: carrier.routes,
        totalSamples: carrier.totalSamples,
        jkStandard,
        jkActual,
        deviation,
        onTimePercentage,
        problematicRoutes: carrier.problematicRoutes,
        status,
        products,
      };
    });

    // Recalculate product data
    const productMap = new Map<string, any>();
    routeData.forEach(route => {
      if (!productMap.has(route.product)) {
        productMap.set(route.product, {
          product: route.product,
          routes: 0,
          totalSamples: 0,
          totalWeightedJKStandard: 0,
          totalWeightedJKActual: 0,
          onTimeSamples: 0,
          problematicRoutes: 0,
          carriers: new Map(),
        });
      }
      const product = productMap.get(route.product);
      product.routes++;
      product.totalSamples += route.totalSamples;
      product.totalWeightedJKStandard += route.jkStandard * route.totalSamples;
      product.totalWeightedJKActual += route.jkActual * route.totalSamples;
      product.onTimeSamples += route.onTimeSamples;
      if (route.onTimePercentage <= route.criticalThreshold) {
        product.problematicRoutes++;
      }

      // Track carriers within product
      if (!product.carriers.has(route.carrier)) {
        product.carriers.set(route.carrier, {
          carrier: route.carrier,
          routes: 0,
          totalSamples: 0,
          totalWeightedJKStandard: 0,
          totalWeightedJKActual: 0,
          onTimeSamples: 0,
        });
      }
      const carrierInProduct = product.carriers.get(route.carrier);
      carrierInProduct.routes++;
      carrierInProduct.totalSamples += route.totalSamples;
      carrierInProduct.totalWeightedJKStandard += route.jkStandard * route.totalSamples;
      carrierInProduct.totalWeightedJKActual += route.jkActual * route.totalSamples;
      carrierInProduct.onTimeSamples += route.onTimeSamples;
    });

    const productData = Array.from(productMap.values()).map(product => {
      const jkStandard = product.totalSamples > 0 ? product.totalWeightedJKStandard / product.totalSamples : 0;
      const jkActual = product.totalSamples > 0 ? product.totalWeightedJKActual / product.totalSamples : 0;
      const deviation = jkActual - jkStandard;
      const onTimePercentage = product.totalSamples > 0 ? (product.onTimeSamples / product.totalSamples) * 100 : 0;
      const status: 'compliant' | 'warning' | 'critical' = onTimePercentage >= globalWarningThreshold ? 'compliant' : onTimePercentage > globalCriticalThreshold ? 'warning' : 'critical';
      
      const carriers = Array.from(product.carriers.values()).map((c: any) => {
        const cJkStandard = c.totalSamples > 0 ? c.totalWeightedJKStandard / c.totalSamples : 0;
        const cJkActual = c.totalSamples > 0 ? c.totalWeightedJKActual / c.totalSamples : 0;
        const cDeviation = cJkActual - cJkStandard;
        const cOnTimePercentage = c.totalSamples > 0 ? (c.onTimeSamples / c.totalSamples) * 100 : 0;
        const cStatus: 'compliant' | 'warning' | 'critical' = cOnTimePercentage >= globalWarningThreshold ? 'compliant' : cOnTimePercentage > globalCriticalThreshold ? 'warning' : 'critical';
        
        return {
          carrier: c.carrier,
          routes: c.routes,
          totalSamples: c.totalSamples,
          jkStandard: cJkStandard,
          jkActual: cJkActual,
          deviation: cDeviation,
          onTimePercentage: cOnTimePercentage,
          status: cStatus,
        };
      });

      return {
        product: product.product,
        routes: product.routes,
        totalSamples: product.totalSamples,
        jkStandard,
        jkActual,
        deviation,
        onTimePercentage,
        problematicRoutes: product.problematicRoutes,
        status,
        carriers,
      };
    });

    // Recalculate weekly samples from filtered routes
    // Aggregate total samples per week from filtered routes
    const weeklyMap = new Map<string, { weekStart: string; samples: number }>();
    
    // Since we don't have shipment-level weekly data, we'll distribute route samples proportionally
    // This is an approximation - in production you'd query shipments grouped by week
    rawWeeklySamples.forEach(week => {
      weeklyMap.set(week.weekStart, {
        weekStart: week.weekStart,
        samples: 0,
      });
    });

    // Distribute filtered route samples proportionally across weeks
    const totalFilteredSamples = routeData.reduce((sum, r) => sum + r.totalSamples, 0);
    const totalOriginalSamples = rawRouteData.reduce((sum, r) => sum + r.totalSamples, 0);
    const filterRatio = totalOriginalSamples > 0 ? totalFilteredSamples / totalOriginalSamples : 0;

    rawWeeklySamples.forEach(week => {
      const adjustedSamples = Math.round(week.samples * filterRatio);
      weeklyMap.set(week.weekStart, {
        weekStart: week.weekStart,
        samples: adjustedSamples,
      });
    });

    // Convert to array and sort chronologically (oldest to newest)
    const weeklySamples = Array.from(weeklyMap.values())
      .sort((a, b) => new Date(a.weekStart).getTime() - new Date(b.weekStart).getTime());

    // Sort cityData by city name, then by direction (inbound first, outbound second)
    const sortedCityData = [...cityData].sort((a, b) => {
      const cityCompare = a.cityName.localeCompare(b.cityName);
      if (cityCompare !== 0) return cityCompare;
      // inbound (0) before outbound (1)
      return a.direction === 'inbound' ? -1 : 1;
    });

    return {
      routeData,
      cityData: sortedCityData,
      regionData,
      carrierData,
      productData,
      weeklySamples,
      metrics,
    };
  }, [rawRouteData, rawCityData, rawRegionData, rawCarrierData, rawProductData, rawWeeklySamples, rawMetrics, filteredRouteData, showProblematicOnly, globalWarningThreshold, globalCriticalThreshold, filters.complianceStatus]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading J+K performance data...</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">Error loading data: {error.message}</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">{t('reporting.jk_performance_report')}</h1>
          <p className="text-gray-600 mt-1">{t('reporting.transit_time_analysis_and_delivery_performance_tracking')}</p>
        </div>
        <SmartTooltip content="J+K Performance Report: Analyzes actual transit times (J+K Actual) against delivery standards (J+K Std) to identify routes, cities, carriers, or products with systematic delays. Multi-level analysis showing Route, City, Region, Carrier, and Product performance. J+K Standard is the expected delivery time in days from delivery_standards table. J+K Actual is the average actual transit time in business days. Deviation is the difference between Actual and Standard (positive values indicate delays). On-Time % is the percentage of shipments delivered within or before the standard time. Color coding: Green (≥95%), Yellow (90-95%), Red (<90%)." />
      </div>

      {/* Filters */}
      <ReportFilters filters={filters} onChange={setFilters} onReset={resetFilters} />

      {/* KPIs - Minimalist Design */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
        <KPICard
          title={t('reporting.total_samples')}
          value={metrics.totalSamples.toLocaleString()}
          icon={Package}
          trend="neutral"
          trendValue={t('reporting.statistical_significance')}
          color="blue"
          tooltip={{
            description: "Total number of shipments analyzed in the current filter selection.",
            interpretation: "Higher sample sizes provide more reliable statistical insights. Minimum 30 samples recommended per route for significance.",
            utility: "Validates the reliability of performance metrics. Low sample sizes may indicate incomplete data or narrow filters."
          }}
        />
        <KPICard
          title={t('reporting.avg_jk_actual')}
          value={`${metrics.avgJKActual.toFixed(1)} ${t('reporting.days')}`}
          icon={Clock}
          trend={metrics.avgJKActual <= metrics.avgJKStandard ? 'up' : 'down'}
          trendValue={`${t('reporting.vs_std')}: ${metrics.avgJKStandard.toFixed(1)} ${t('reporting.days')}`}
          color={metrics.avgJKActual <= metrics.avgJKStandard ? 'green' : metrics.avgJKActual <= metrics.avgJKStandard + 1 ? 'amber' : 'red'}
          tooltip={{
            description: "Weighted average of actual transit times across all routes in the selection.",
            interpretation: "Compare against J+K Standard. Values below standard indicate early delivery, above standard indicate delays.",
            utility: "Primary metric for overall network performance. Use to track improvement over time."
          }}
        />
        <KPICard
          title={t('reporting.on_time_percent')}
          value={`${metrics.onTimePercentage.toFixed(1)}%`}
          icon={CheckCircle}
          trend={metrics.onTimePercentage >= 95 ? 'up' : metrics.onTimePercentage >= 90 ? 'neutral' : 'down'}
          trendValue={t('reporting.on_time_count', { count: metrics.onTimeSamples.toLocaleString() })}
          color={metrics.onTimePercentage >= 95 ? 'green' : metrics.onTimePercentage >= 90 ? 'amber' : 'red'}
          tooltip={{
            description: "Percentage of shipments delivered within or before the standard delivery time (J+K Std).",
            interpretation: "Thresholds are dynamic and defined in delivery_standards table per route. Green (≥95%), Yellow (90-95%), Red (<90%) are visual guides only.",
            utility: "Key performance indicator for service quality. Compare against route-specific standard percentage (Std %) from delivery_standards."
          }}
        />
        <KPICard
          title={t('reporting.problem_routes')}
          value={metrics.problematicRoutes.toString()}
          icon={AlertTriangle}
          trend={metrics.problematicRoutes === 0 ? 'up' : 'down'}
          trendValue={t('reporting.require_intervention')}
          color={metrics.problematicRoutes === 0 ? 'green' : metrics.problematicRoutes <= 3 ? 'amber' : 'red'}
          tooltip={{
            description: "Number of routes with on-time performance at or below their critical SLA threshold.",
            interpretation: "Routes failing to meet their critical delivery standards. Each route has its own critical threshold defined in delivery_standards table.",
            utility: "Click to filter and show only problematic routes. Prioritization tool for operational improvements."
          }}
          onClick={() => {
            setShowProblematicOnly(!showProblematicOnly);
            setActiveTab('route');
          }}
        />
      </div>

      {/* Charts Section */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Weekly Samples Chart */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center gap-2 mb-4">
            <h3 className="text-lg font-semibold text-gray-900">{t('reporting.weekly_sample_volume')}</h3>
            <SmartTooltip content="Weekly Sample Volume: Shows the number of shipments analyzed per week in the selected date range. Color coding: Green (20% above average), Blue (above average), Yellow (80-100% of average), Red (below 80% of average). Use to identify weeks with low sample sizes that may affect statistical reliability. Minimum 30 samples/week recommended for statistical significance." />
          </div>
          <WeeklySamplesChart data={weeklySamples} />
        </div>

        {/* Performance Distribution */}
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center gap-2 mb-4">
            <h3 className="text-lg font-semibold text-gray-900">{t('reporting.performance_distribution')}</h3>
            <SmartTooltip content="Performance Distribution: Shows how shipments are distributed by actual transit time vs. delivery standard (J+K Std). Categories: After Standard (red, delivered AFTER J+K Std = late), Before/On-Time (green, delivered WITHIN J+K Std = on-time), On Standard (blue, delivered EXACTLY on J+K Std day). Use to visualize overall network performance. Large red bars indicate systematic delays requiring investigation." />
          </div>
          <PerformanceDistributionChart 
            routeData={routeData} 
            maxDays={maxDays} 
            carrierFilter={filters.carrier}
            productFilter={filters.product}
          />
        </div>
      </div>

      {/* Tabs */}
      <div className="bg-white rounded-lg shadow">
        <div className="border-b border-gray-200">
          <nav className="flex -mb-px">
            {[
              { id: 'route', label: t('reporting.route_analysis') },
              { id: 'city', label: t('reporting.city_analysis') },
              { id: 'region', label: t('reporting.region_analysis') },
              { id: 'carrier', label: t('reporting.carrier_product_tab') },
              { id: 'cumulative', label: t('reporting.cumulative_distribution_analysis') },
            ].map((tab) => (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id as any)}
                className={`px-6 py-3 text-sm font-medium border-b-2 transition-colors ${
                  activeTab === tab.id
                    ? 'border-blue-500 text-blue-600'
                    : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                }`}
              >
                {tab.label}
              </button>
            ))}
          </nav>
        </div>

        <div className="p-6">
          {activeTab === 'route' && (
            <div>
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-3">
                  <h3 className="text-lg font-semibold text-gray-900">
                    Route performance ({routeData.length} routes)
                  </h3>
                  {showProblematicOnly && (
                    <span className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium bg-red-100 text-red-800 rounded">
                      <AlertTriangle className="w-3 h-3" />
                      Problematic only
                    </span>
                  )}
                </div>
                <button
                  onClick={() => exportRouteCSV(routeData)}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                >
                  <FileDown className="w-4 h-4" />
                  {t('common.export_csv')}
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          Route
                          <ColumnTooltip content="Origin city → Destination city. Each route is unique by carrier, product, and city pair." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          Samples
                          <ColumnTooltip content="Total number of shipments for this route in the selected date range. Minimum 30 samples recommended for statistical significance." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          J+K Std
                          <ColumnTooltip content="Expected delivery time in days from delivery_standards table. Automatically converted from hours if needed (hours/24)." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          J+K Actual
                          <ColumnTooltip content="Average actual transit time in business days for all shipments on this route. Calculated from shipments.business_transit_days field." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          Deviation
                          <ColumnTooltip content="Difference between J+K Actual and J+K Std (Actual - Standard). Positive values indicate delays, negative values indicate early delivery." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          STD %
                          <ColumnTooltip content="Target on-time percentage defined in delivery_standards for this route. This is the required performance threshold (e.g., 85%) that must be achieved. Compare with On-Time % column to assess compliance." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          On-Time %
                          <ColumnTooltip content="Percentage of shipments delivered within or before J+K Std. Compare against route-specific Std % from delivery_standards (not shown in this table)." />
                        </div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">
                          Status
                          <ColumnTooltip content="Visual indicator: Green (compliant, ≥95%), Yellow (warning, 90-95%), Red (critical, <90%). These are general guides; actual standards are route-specific." />
                        </div>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {[...routeData]
                      .sort((a, b) => {
                        // Sort problematic routes first (On-Time % <= Critical SLA)
                        const aProblematic = a.onTimePercentage <= a.criticalThreshold;
                        const bProblematic = b.onTimePercentage <= b.criticalThreshold;
                        if (aProblematic && !bProblematic) return -1;
                        if (!aProblematic && bProblematic) return 1;
                        // Then sort by On-Time % ascending (worst first)
                        return a.onTimePercentage - b.onTimePercentage;
                      })
                      .map((route, idx) => {
                      const deviationColor = route.deviation <= 0 ? 'text-green-600' : route.deviation < 1 ? 'text-yellow-600' : 'text-red-600';
                      const onTimeColor = route.onTimePercentage >= route.warningThreshold ? 'text-green-600 font-semibold' : route.onTimePercentage > route.criticalThreshold ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const statusColor = route.status === 'compliant' ? 'bg-green-500' : route.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      
                      return (
                        <tr key={idx} className="hover:bg-gray-50">
                          <td className="px-3 py-2 text-sm text-gray-900">
                            {route.originCity} → {route.destinationCity}
                            <div className="text-xs text-gray-500">{route.carrier} · {route.product}</div>
                          </td>
                          <td className="px-3 py-2 text-sm text-gray-900">{route.totalSamples}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{route.jkStandard.toFixed(1)}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{route.jkActual.toFixed(1)}</td>
                          <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                            {route.deviation > 0 ? '+' : ''}{route.deviation.toFixed(1)}
                          </td>
                          <td className="px-3 py-2 text-sm text-gray-900 font-medium">
                            {route.standardPercentage.toFixed(0)}%
                          </td>
                          <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                            {route.onTimePercentage.toFixed(1)}%
                          </td>
                          <td className="px-3 py-2">
                            <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'city' && (
            <div>
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-3">
                  <h3 className="text-lg font-semibold text-gray-900">
                    City performance ({cityData.length} cities)
                  </h3>
                  {showProblematicOnly && (
                    <span className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium bg-red-100 text-red-800 rounded">
                      <AlertTriangle className="w-3 h-3" />
                      Problematic only
                    </span>
                  )}
                </div>
                <button
                  onClick={() => exportCityCSV(cityData)}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                >
                  <FileDown className="w-4 h-4" />
                  {t('common.export_csv')}
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">City <ColumnTooltip content="City name aggregating all routes where this city is origin or destination." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Direction <ColumnTooltip content="Inbound (city is destination) or Outbound (city is origin). Shows traffic flow direction." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Region <ColumnTooltip content="Geographic region to which this city belongs (from topology.regions table)." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Samples <ColumnTooltip content="Total shipments aggregated across all routes involving this city in the specified direction." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Std <ColumnTooltip content="Weighted average of J+K standards across all routes involving this city. Routes with more shipments have higher weight." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Actual <ColumnTooltip content="Weighted average of actual transit times across all routes involving this city." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Deviation <ColumnTooltip content="Weighted average deviation (Actual - Standard) across all routes involving this city." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">STD % <ColumnTooltip content="Weighted average target on-time percentage from delivery_standards for all routes involving this city." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">On-Time % <ColumnTooltip content="Percentage of all shipments (across all routes) delivered on-time for this city." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Status <ColumnTooltip content="Visual indicator based on on-time percentage: Green (≥95%), Yellow (90-95%), Red (<90%)." /></div>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {cityData.map((city, idx) => {
                      const deviationColor = city.deviation <= 0 ? 'text-green-600' : city.deviation < 1 ? 'text-yellow-600' : 'text-red-600';
                      const onTimeColor = city.onTimePercentage >= city.warningThreshold ? 'text-green-600 font-semibold' : city.onTimePercentage > city.criticalThreshold ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const statusColor = city.status === 'compliant' ? 'bg-green-500' : city.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      const directionIcon = city.direction === 'inbound' ? '🔵 ↓' : '🟢 ↑';
                      
                      return (
                        <tr key={idx} className="hover:bg-gray-50">
                          <td className="px-3 py-2 text-sm text-gray-900">{city.cityName}</td>
                          <td className="px-3 py-2 text-sm">{directionIcon} {city.direction}</td>
                          <td className="px-3 py-2 text-sm text-gray-600">{city.regionName}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{city.totalSamples}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{city.jkStandard.toFixed(1)}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{city.jkActual.toFixed(1)}</td>
                          <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                            {city.deviation > 0 ? '+' : ''}{city.deviation.toFixed(1)}
                          </td>
                          <td className="px-3 py-2 text-sm text-gray-900">
                            {city.standardPercentage.toFixed(0)}%
                          </td>
                          <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                            {city.onTimePercentage.toFixed(1)}%
                          </td>
                          <td className="px-3 py-2">
                            <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'region' && (
            <div>
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-3">
                  <h3 className="text-lg font-semibold text-gray-900">
                    Region performance ({regionData.length} regions)
                  </h3>
                  {showProblematicOnly && (
                    <span className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium bg-red-100 text-red-800 rounded">
                      <AlertTriangle className="w-3 h-3" />
                      Problematic only
                    </span>
                  )}
                </div>
                <button
                  onClick={() => exportRegionCSV(regionData)}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                >
                  <FileDown className="w-4 h-4" />
                  {t('common.export_csv')}
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Region <ColumnTooltip content="Geographic region aggregating all cities and routes within it (from topology.regions table)." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Direction <ColumnTooltip content="Inbound (region is destination) or Outbound (region is origin). Shows regional traffic flow." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Cities <ColumnTooltip content="Number of unique cities in this region with shipment data in the specified direction." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Samples <ColumnTooltip content="Total shipments aggregated across all routes involving cities in this region." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Std <ColumnTooltip content="Weighted average of J+K standards across all routes in this region. Routes with more shipments have higher weight." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Actual <ColumnTooltip content="Weighted average of actual transit times across all routes in this region." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Deviation <ColumnTooltip content="Weighted average deviation (Actual - Standard) across all routes in this region." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">On-Time % <ColumnTooltip content="Percentage of all shipments (across all routes) delivered on-time in this region." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Status <ColumnTooltip content="Visual indicator based on on-time percentage: Green (≥95%), Yellow (90-95%), Red (<90%)." /></div>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {[...regionData]
                      .sort((a, b) => {
                        // Sort by status: critical first, then warning, then compliant
                        const statusOrder: Record<string, number> = { critical: 0, warning: 1, compliant: 2 };
                        if (a.status !== b.status) {
                          return statusOrder[a.status] - statusOrder[b.status];
                        }
                        // Then sort by On-Time % ascending (worst first)
                        return a.onTimePercentage - b.onTimePercentage;
                      })
                      .map((region, idx) => {
                      const deviationColor = region.deviation <= 0 ? 'text-green-600' : region.deviation < 1 ? 'text-yellow-600' : 'text-red-600';
                      const onTimeColor = region.onTimePercentage >= globalWarningThreshold ? 'text-green-600 font-semibold' : region.onTimePercentage > globalCriticalThreshold ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const statusColor = region.status === 'compliant' ? 'bg-green-500' : region.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      const directionIcon = region.direction === 'inbound' ? '🔵 ↓' : '🟢 ↑';
                      
                      return (
                        <tr key={idx} className="hover:bg-gray-50">
                          <td className="px-3 py-2 text-sm text-gray-900">{region.regionName}</td>
                          <td className="px-3 py-2 text-sm">{directionIcon} {region.direction}</td>
                          <td className="px-3 py-2 text-sm text-gray-600">{region.cities}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{region.totalSamples}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{region.jkStandard.toFixed(1)}</td>
                          <td className="px-3 py-2 text-sm text-gray-900">{region.jkActual.toFixed(1)}</td>
                          <td className={`px-3 py-2 text-sm ${deviationColor}`}>
                            {region.deviation > 0 ? '+' : ''}{region.deviation.toFixed(1)}
                          </td>
                          <td className={`px-3 py-2 text-sm ${onTimeColor}`}>
                            {region.onTimePercentage.toFixed(1)}%
                          </td>
                          <td className="px-3 py-2">
                            <div className={`w-3 h-3 rounded-full ${statusColor}`} />
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'carrier' && (
            <div>
              <div className="flex items-center justify-between mb-4">
                <div className="flex items-center gap-3">
                  <h3 className="text-lg font-semibold text-gray-900">
                    Carrier / Product performance ({carrierData.length} carriers)
                  </h3>
                  {showProblematicOnly && (
                    <span className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium bg-red-100 text-red-800 rounded">
                      <AlertTriangle className="w-3 h-3" />
                      Problematic only
                    </span>
                  )}
                </div>
                <button
                  onClick={() => exportCarrierProductCSV(carrierData)}
                  className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                >
                  <FileDown className="w-4 h-4" />
                  {t('common.export_csv')}
                </button>
              </div>
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Carrier / Product <ColumnTooltip content="Hierarchical view: Carrier rows (blue background) show aggregated metrics. Product rows (indented with ↳) show metrics for each product under that carrier." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Routes <ColumnTooltip content="Number of unique routes (city pairs) served by this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Samples <ColumnTooltip content="Total shipments for this carrier or product across all routes." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Std <ColumnTooltip content="Weighted average of J+K standards across all routes for this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">J+K Actual <ColumnTooltip content="Weighted average of actual transit times across all routes for this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Deviation <ColumnTooltip content="Weighted average deviation (Actual - Standard) across all routes for this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">On-Time % <ColumnTooltip content="Percentage of all shipments delivered on-time for this carrier or product." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Problem Routes <ColumnTooltip content="Number of routes with on-time performance <90%. Only shown at carrier level (products show '-')." /></div>
                      </th>
                      <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                        <div className="flex items-center gap-1">Status <ColumnTooltip content="Visual indicator: Green (≥95%), Yellow (90-95%), Red (<90%). Shown for both carriers and products." /></div>
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {[...carrierData]
                      .sort((a, b) => {
                        // Sort by status: critical first, then warning, then compliant
                        const statusOrder: Record<string, number> = { critical: 0, warning: 1, compliant: 2 };
                        if (a.status !== b.status) {
                          return statusOrder[a.status] - statusOrder[b.status];
                        }
                        // Then sort by On-Time % ascending (worst first)
                        return a.onTimePercentage - b.onTimePercentage;
                      })
                      .map((carrier, carrierIdx) => {
                      const carrierDeviationColor = carrier.deviation <= 0 ? 'text-green-600' : carrier.deviation < 1 ? 'text-yellow-600' : 'text-red-600';
                      const carrierOnTimeColor = carrier.onTimePercentage >= globalWarningThreshold ? 'text-green-600 font-semibold' : carrier.onTimePercentage > globalCriticalThreshold ? 'text-yellow-600' : 'text-red-600 font-semibold';
                      const carrierStatusColor = carrier.status === 'compliant' ? 'bg-green-500' : carrier.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                      
                      return (
                        <Fragment key={carrierIdx}>
                          {/* Carrier Row */}
                          <tr className="bg-blue-50 hover:bg-blue-100">
                            <td className="px-3 py-2 text-sm font-bold text-gray-900">{carrier.carrier}</td>
                            <td className="px-3 py-2 text-sm font-semibold text-gray-700">{carrier.routes}</td>
                            <td className="px-3 py-2 text-sm font-semibold text-gray-900">{carrier.totalSamples}</td>
                            <td className="px-3 py-2 text-sm font-semibold text-gray-900">{carrier.jkStandard.toFixed(1)}</td>
                            <td className="px-3 py-2 text-sm font-semibold text-gray-900">{carrier.jkActual.toFixed(1)}</td>
                            <td className={`px-3 py-2 text-sm font-semibold ${carrierDeviationColor}`}>
                              {carrier.deviation > 0 ? '+' : ''}{carrier.deviation.toFixed(1)}
                            </td>
                            <td className={`px-3 py-2 text-sm ${carrierOnTimeColor}`}>
                              {carrier.onTimePercentage.toFixed(1)}%
                            </td>
                            <td className="px-3 py-2 text-sm text-red-600 font-semibold">
                              {carrier.problematicRoutes}
                            </td>
                            <td className="px-3 py-2">
                              <div className={`w-3 h-3 rounded-full ${carrierStatusColor}`} />
                            </td>
                          </tr>
                          {/* Product Rows */}
                          {carrier.products.map((product, productIdx) => {
                            const productDeviationColor = product.deviation <= 0 ? 'text-green-600' : product.deviation < 1 ? 'text-yellow-600' : 'text-red-600';
                            const productOnTimeColor = product.onTimePercentage >= globalWarningThreshold ? 'text-green-600 font-semibold' : product.onTimePercentage > globalCriticalThreshold ? 'text-yellow-600' : 'text-red-600 font-semibold';
                            const productStatusColor = product.status === 'compliant' ? 'bg-green-500' : product.status === 'warning' ? 'bg-yellow-500' : 'bg-red-500';
                            
                            return (
                              <tr key={`${carrierIdx}-${productIdx}`} className="hover:bg-gray-50">
                                <td className="px-3 py-2 pl-8 text-sm text-gray-700">↳ {product.product}</td>
                                <td className="px-3 py-2 text-sm text-gray-600">{product.routes}</td>
                                <td className="px-3 py-2 text-sm text-gray-900">{product.totalSamples}</td>
                                <td className="px-3 py-2 text-sm text-gray-900">{product.jkStandard.toFixed(1)}</td>
                                <td className="px-3 py-2 text-sm text-gray-900">{product.jkActual.toFixed(1)}</td>
                                <td className={`px-3 py-2 text-sm ${productDeviationColor}`}>
                                  {product.deviation > 0 ? '+' : ''}{product.deviation.toFixed(1)}
                                </td>
                                <td className={`px-3 py-2 text-sm ${productOnTimeColor}`}>
                                  {product.onTimePercentage.toFixed(1)}%
                                </td>
                                <td className="px-3 py-2 text-sm text-gray-400">-</td>
                                <td className="px-3 py-2">
                                  <div className={`w-3 h-3 rounded-full ${productStatusColor}`} />
                                </td>
                              </tr>
                            );
                          })}
                        </Fragment>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {activeTab === 'cumulative' && (
            <div>
              <div className="flex items-center justify-between mb-4">
                <h3 className="text-lg font-semibold text-gray-900">{t('reporting.cumulative_distribution_analysis')}</h3>
                <div className="flex gap-2">
                  {cumulativeView === 'table' && (
                    <button
                      onClick={() => exportCumulativeCSV(routeData.map(route => ({
                        routeKey: route.routeKey,
                        originCity: route.originCity,
                        destinationCity: route.destinationCity,
                        carrier: route.carrier,
                        product: route.product,
                        jkStandard: route.jkStandard,
                        standardPercentage: route.standardPercentage,
                        distribution: route.distribution,
                        totalSamples: route.totalSamples,
                      })), maxDays)}
                      className="flex items-center gap-2 px-3 py-1.5 text-sm bg-blue-600 hover:bg-blue-700 text-white rounded-lg transition-colors"
                    >
                      <FileDown className="w-4 h-4" />
                      {t('common.export_csv')}
                    </button>
                  )}
                  <button
                    onClick={() => setCumulativeView('chart')}
                    className={`px-4 py-2 text-sm font-medium rounded-lg transition-colors ${
                      cumulativeView === 'chart'
                        ? 'bg-blue-600 text-white'
                        : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                  >
                    {t('reporting.chart_view')}
                  </button>
                  <button
                    onClick={() => setCumulativeView('table')}
                    className={`px-4 py-2 text-sm font-medium rounded-lg transition-colors ${
                      cumulativeView === 'table'
                        ? 'bg-blue-600 text-white'
                        : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                    }`}
                  >
                    {t('reporting.table_view')}
                  </button>
                </div>
              </div>

              {cumulativeView === 'chart' ? (
                <CumulativeDistributionChart
                  routes={routeData.map(route => ({
                    routeKey: route.routeKey,
                    originCity: route.originCity,
                    destinationCity: route.destinationCity,
                    carrier: route.carrier,
                    product: route.product,
                    jkStandard: route.jkStandard,
                    standardPercentage: route.standardPercentage,
                    distribution: route.distribution,
                    totalSamples: route.totalSamples,
                  }))}
                  maxDays={maxDays}
                />
              ) : (
                <CumulativeDistributionTable
                  routes={routeData.map(route => ({
                    routeKey: route.routeKey,
                    originCity: route.originCity,
                    destinationCity: route.destinationCity,
                    carrier: route.carrier,
                    product: route.product,
                    jkStandard: route.jkStandard,
                    standardPercentage: route.standardPercentage,
                    distribution: route.distribution,
                    totalSamples: route.totalSamples,
                  }))}
                  maxDays={maxDays}
                />
              )}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
