import React, { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useAccount } from '@/contexts/AccountContext';
import { supabase } from '@/lib/supabase';
import { useTranslation } from '@/hooks/useTranslation';
import { PerformanceDistributionChart } from '@/components/reporting/PerformanceDistributionChart';
import { CumulativeDistributionChart } from '@/components/reporting/CumulativeDistributionChart';
import { RoutePerformanceTable } from '@/components/reporting/RoutePerformanceTable';
import { Info } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';

interface SegmentData {
  segmentKey: string;
  fromCenter: string;
  toCenter: string;
  carrier: string;
  product: string;
  segmentType: 'operational' | 'distribution';
  totalSamples: number;
  jkStandard: number;
  jkActual: number;
  onTimeSamples: number;
  beforeStandardSamples: number;
  afterStandardSamples: number;
  onTimePercentage: number;
  deviation: number;
  standardPercentage: number;
  status: 'compliant' | 'warning' | 'critical';
  distribution: Map<number, number>;
  warningThreshold: number;
  criticalThreshold: number;
}

export default function JKPerformanceSegments() {
  const { profile } = useAuth();
  const { effectiveAccountId } = useAccount();
  const [searchParams] = useSearchParams();
  const { t } = useTranslation();
  
  const [carrier, setCarrier] = useState('');
  const [product, setProduct] = useState('');
  const [originCity, setOriginCity] = useState('');
  const [destinationCity, setDestinationCity] = useState('');
  const [segmentType, setSegmentType] = useState<'all' | 'operational' | 'distribution'>('all');
  const [threshold, setThreshold] = useState<'all' | 'compliant' | 'warning' | 'critical'>('all');
  
  const [carriers, setCarriers] = useState<Array<{id: string, name: string}>>([]);
  const [products, setProducts] = useState<Array<{id: string, name: string, carrier_id: string}>>([]);
  const [cities, setCities] = useState<string[]>([]);
  const [postalCenters, setPostalCenters] = useState<Array<{id: string, name: string, city: string}>>([]);
  
  const [segmentData, setSegmentData] = useState<SegmentData[]>([]);
  const [loading, setLoading] = useState(false);
  const [viewMode, setViewMode] = useState<'chart' | 'table'>('chart');

  // Load carriers, products, cities
  useEffect(() => {
    if (!effectiveAccountId) return;

    const loadFilters = async () => {
      // Load carriers
      const { data: carriersData } = await supabase
        .from('carriers')
        .select('id, name')
        .eq('account_id', effectiveAccountId)
        .order('name');
      if (carriersData) setCarriers(carriersData);

      // Load products
      const { data: productsData } = await supabase
        .from('products')
        .select('id, name, carrier_id')
        .eq('account_id', effectiveAccountId)
        .order('name');
      if (productsData) setProducts(productsData);

      // Load postal centers
      const { data: centersData } = await supabase
        .from('postal_centers')
        .select('id, name, city')
        .eq('account_id', effectiveAccountId)
        .order('name');
      if (centersData) {
        setPostalCenters(centersData);
        const uniqueCities = [...new Set(centersData.map(c => c.city))].sort();
        setCities(uniqueCities);
      }
    };

    loadFilters();
  }, [effectiveAccountId]);

  // Read URL params and set filters
  useEffect(() => {
    const carrierIdParam = searchParams.get('carrier_id');
    const productIdParam = searchParams.get('product_id');
    const fromCenterIdParam = searchParams.get('from_center_id');
    const toCenterIdParam = searchParams.get('to_center_id');
    const segmentTypeParam = searchParams.get('segment_type');

    if (carrierIdParam && carriers.length > 0) {
      const carrierObj = carriers.find(c => c.id === carrierIdParam);
      if (carrierObj) setCarrier(carrierObj.name);
    }

    if (productIdParam && products.length > 0) {
      const productObj = products.find(p => p.id === productIdParam);
      if (productObj) setProduct(productObj.name);
    }

    if (fromCenterIdParam && effectiveAccountId) {
      supabase
        .from('postal_centers')
        .select('city')
        .eq('id', fromCenterIdParam)
        .eq('account_id', effectiveAccountId)
        .single()
        .then(({ data }) => {
          if (data) setOriginCity(data.city);
        });
    }

    if (toCenterIdParam && effectiveAccountId) {
      supabase
        .from('postal_centers')
        .select('city')
        .eq('id', toCenterIdParam)
        .eq('account_id', effectiveAccountId)
        .single()
        .then(({ data }) => {
          if (data) setDestinationCity(data.city);
        });
    }

    if (segmentTypeParam === 'operational' || segmentTypeParam === 'distribution') {
      setSegmentType(segmentTypeParam);
    }
  }, [searchParams, carriers, products, effectiveAccountId]);

  // Load segment data
  useEffect(() => {
    if (!effectiveAccountId) return;

    const loadSegments = async () => {
      setLoading(true);

      try {
        // Query journey_paths to get segment_details
        let query = supabase
          .from('journey_paths')
          .select(`
            id,
            carrier_id,
            product_id,
            origin_city_name,
            destination_city_name,
            segment_details,
            carriers(name),
            products(code, description)
          `)
          .eq('account_id', effectiveAccountId);

        if (carrier) {
          const carrierObj = carriers.find(c => c.name === carrier);
          if (carrierObj) query = query.eq('carrier_id', carrierObj.id);
        }

        if (product) {
          const productObj = products.find(p => p.name === product);
          if (productObj) query = query.eq('product_id', productObj.id);
        }

        if (originCity) {
          query = query.eq('origin_city_name', originCity);
        }

        if (destinationCity) {
          query = query.eq('destination_city_name', destinationCity);
        }

        const { data: journeyPaths, error } = await query;

        if (error) throw error;
        if (!journeyPaths || journeyPaths.length === 0) {
          setSegmentData([]);
          setLoading(false);
          return;
        }

        console.log('📊 JKPerformanceSegments - Data Source: journey_paths.segment_details');
        console.log('📦 Total journey paths loaded:', journeyPaths.length);

        // Extract all segments from all journey paths
        const allSegments: any[] = [];
        journeyPaths.forEach((path: any) => {
          if (path.segment_details && Array.isArray(path.segment_details)) {
            path.segment_details.forEach((seg: any) => {
              allSegments.push({
                ...seg,
                carrier_name: path.carriers?.name || 'Unknown',
                product_name: path.products ? `${path.products.code} - ${path.products.description}` : 'Unknown',
                carrier_id: path.carrier_id,
                product_id: path.product_id
              });
            });
          }
        });

        console.log('📦 Total segments extracted:', allSegments.length);

        // Get SLAs
        const { data: slas } = await supabase
          .from('slas')
          .select('*')
          .eq('account_id', effectiveAccountId)
          .eq('is_active', true);

        if (!slas) {
          setSegmentData([]);
          setLoading(false);
          return;
        }

        // Group segments by unique key
        const segmentMap = new Map<string, any>();
        console.log('🔍 Processing segment_details...');

        allSegments.forEach((seg: any) => {
          // Create unique key based on segment type and centers
          const segmentKey = seg.segment_type === 'operational'
            ? `${seg.from_center_name}_center_${seg.carrier_name}_${seg.product_name}`
            : `${seg.from_center_name}_${seg.to_center_name}_transit_${seg.carrier_name}_${seg.product_name}`;

          if (!segmentMap.has(segmentKey)) {
            segmentMap.set(segmentKey, {
              segmentKey,
              fromCenter: seg.from_center_name,
              toCenter: seg.to_center_name || seg.from_center_name,
              carrier: seg.carrier_name,
              product: seg.product_name,
              segmentType: seg.segment_type,
              samples: [],
              sla_minutes: seg.sla_minutes,
              on_time_threshold: seg.on_time_threshold,
              warning_threshold: seg.warning_threshold,
              critical_threshold: seg.critical_threshold,
            });
          }

          // Add sample times from the segment
          if (seg.sample_times && Array.isArray(seg.sample_times)) {
            seg.sample_times.forEach((time: number) => {
              segmentMap.get(segmentKey).samples.push({ time });
            });
          }
        });

        // Calculate metrics for each segment
        const processedSegments: SegmentData[] = [];

        segmentMap.forEach((segGroup) => {
          // Use SLA values from segment_details (already pre-calculated)
          const jkStandardMinutes = segGroup.sla_minutes || 1440; // Default 1 day
          const jkStandardDays = jkStandardMinutes / 1440;
          const standardPercentage = segGroup.on_time_threshold || 95;
          const warningThreshold = segGroup.warning_threshold || 90;
          const criticalThreshold = segGroup.critical_threshold || 80;

          // Calculate distribution
          const distribution = new Map<number, number>();
          let onTimeSamples = 0;
          let beforeStandardSamples = 0;
          let afterStandardSamples = 0;

          segGroup.samples.forEach((sample: any) => {
            const days = Math.round(sample.time / 1440);
            distribution.set(days, (distribution.get(days) || 0) + 1);

            if (sample.time <= jkStandardMinutes) {
              onTimeSamples++;
              if (sample.time < jkStandardMinutes) beforeStandardSamples++;
            } else {
              afterStandardSamples++;
            }
          });

          const totalSamples = segGroup.samples.length;
          const onTimePercentage = totalSamples > 0 ? (onTimeSamples / totalSamples) * 100 : 0;

          // Calculate J+K Actual (day where standardPercentage is reached)
          let cumulativeCount = 0;
          let jkActualDays = jkStandardDays;
          const sortedDays = Array.from(distribution.keys()).sort((a, b) => a - b);
          for (const day of sortedDays) {
            cumulativeCount += distribution.get(day) || 0;
            const cumulativePercentage = (cumulativeCount / totalSamples) * 100;
            if (cumulativePercentage >= standardPercentage) {
              jkActualDays = day;
              break;
            }
          }

          const deviation = jkActualDays - jkStandardDays;

          let status: 'compliant' | 'warning' | 'critical' = 'compliant';
          if (onTimePercentage < criticalThreshold) {
            status = 'critical';
          } else if (onTimePercentage < warningThreshold) {
            status = 'warning';
          }

          // Filter by threshold
          if (threshold !== 'all' && status !== threshold) return;

          // Filter by segment type
          if (segmentType !== 'all' && segGroup.segmentType !== segmentType) return;

          processedSegments.push({
            segmentKey: segGroup.segmentKey,
            fromCenter: segGroup.fromCenter,
            toCenter: segGroup.toCenter,
            carrier: segGroup.carrier,
            product: segGroup.product,
            segmentType: segGroup.segmentType,
            totalSamples,
            jkStandard: jkStandardDays,
            jkActual: jkActualDays,
            onTimeSamples,
            beforeStandardSamples,
            afterStandardSamples,
            onTimePercentage,
            deviation,
            standardPercentage,
            status,
            distribution,
            warningThreshold,
            criticalThreshold,
          });
        });

        const operationalCount = processedSegments.filter(s => s.segmentType === 'operational').length;
        const distributionCount = processedSegments.filter(s => s.segmentType === 'distribution').length;
        console.log('✅ Processed segments:');
        console.log('  - Operational (center):', operationalCount);
        console.log('  - Distribution (transit):', distributionCount);
        console.log('  - Total:', processedSegments.length);

        setSegmentData(processedSegments);
      } catch (error) {
        console.error('Error loading segments:', error);
        setSegmentData([]);
      } finally {
        setLoading(false);
      }
    };

    loadSegments();
  }, [effectiveAccountId, carrier, product, originCity, destinationCity, segmentType, threshold, carriers, products]);

  // Convert SegmentData to JKRouteData format for charts
  const routeDataForCharts = segmentData.map(seg => ({
    originCity: seg.fromCenter,
    destinationCity: seg.toCenter,
    carrier: seg.carrier,
    product: seg.product,
    totalSamples: seg.totalSamples,
    jkStandard: seg.jkStandard,
    jkActual: seg.jkActual,
    onTimeSamples: seg.onTimeSamples,
    beforeStandardSamples: seg.beforeStandardSamples,
    afterStandardSamples: seg.afterStandardSamples,
    onTimePercentage: seg.onTimePercentage,
    deviation: seg.deviation,
    standardPercentage: seg.standardPercentage,
    status: seg.status,
    routeKey: seg.segmentKey,
    distribution: seg.distribution,
    warningThreshold: seg.warningThreshold,
    criticalThreshold: seg.criticalThreshold,
  }));

  const maxDays = Math.max(...Array.from(segmentData.flatMap(s => Array.from(s.distribution.keys()))), 0);

  // Calculate metrics
  const totalSegments = segmentData.length;
  const totalSamples = segmentData.reduce((sum, s) => sum + s.totalSamples, 0);
  const avgJKActual = totalSamples > 0 
    ? segmentData.reduce((sum, s) => sum + s.jkActual * s.totalSamples, 0) / totalSamples 
    : 0;
  const avgJKStandard = totalSamples > 0
    ? segmentData.reduce((sum, s) => sum + s.jkStandard * s.totalSamples, 0) / totalSamples
    : 0;
  const onTimePercentage = totalSamples > 0
    ? (segmentData.reduce((sum, s) => sum + s.onTimeSamples, 0) / totalSamples) * 100
    : 0;
  const problematicSegments = segmentData.filter(s => s.status === 'warning' || s.status === 'critical').length;

  // Filter products by selected carrier
  const filteredProducts = carrier 
    ? products.filter(p => {
        const carrierObj = carriers.find(c => c.name === carrier);
        return carrierObj && p.carrier_id === carrierObj.id;
      })
    : products;

  return (
    <div className="min-h-screen bg-gray-50">
      <div className="max-w-7xl mx-auto px-4 py-6">
        {/* Header */}
        <div className="mb-6">
          <div className="flex items-center gap-2 mb-2">
            <Info className="w-5 h-5 text-blue-600" />
            <h1 className="text-2xl font-bold text-gray-900">{t('diagnosis.jk_performance_segments.title', undefined, 'J+K Performance (Segments)')}</h1>
          </div>
          <p className="text-sm text-gray-600">
            {t('diagnosis.jk_performance_segments.description', undefined, 'Segment-level performance analysis with J+K metrics (days)')}
          </p>
        </div>

        {/* Filters */}
        <div className="bg-white rounded-lg shadow-sm p-4 mb-6">
          <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-4">
            {/* Carrier */}
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">{t('common.carrier', undefined, 'Carrier')}</label>
              <select
                value={carrier}
                onChange={(e) => {
                  setCarrier(e.target.value);
                  setProduct('');
                }}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >
                <option value="">{t('common.all', undefined, 'All')}</option>
                {carriers.map(c => (
                  <option key={c.id} value={c.name}>{c.name}</option>
                ))}
              </select>
            </div>

            {/* Product */}
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">{t('common.product', undefined, 'Product')}</label>
              <select
                value={product}
                onChange={(e) => setProduct(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                disabled={!carrier}
              >
                <option value="">{t('common.all', undefined, 'All')}</option>
                {filteredProducts.map(p => (
                  <option key={p.id} value={p.name}>{p.name}</option>
                ))}
              </select>
            </div>

            {/* Segment Type */}
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">{t('diagnosis.segment_type', undefined, 'Segment Type')}</label>
              <select
                value={segmentType}
                onChange={(e) => {
                  setSegmentType(e.target.value as any);
                  // Reset location filters when changing segment type
                  setOriginCity('');
                  setDestinationCity('');
                }}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >
                <option value="all">{t('common.all', undefined, 'All')}</option>
                <option value="operational">{t('diagnosis.operational', undefined, 'Operational')}</option>
                <option value="distribution">{t('diagnosis.distribution', undefined, 'Distribution')}</option>
              </select>
            </div>

            {/* Dynamic location filters based on segment type */}
            {segmentType === 'operational' && (
              <div>
                <label className="block text-xs font-medium text-gray-700 mb-1">{t('common.center', undefined, 'Center')}</label>
                <select
                  value={originCity}
                  onChange={(e) => setOriginCity(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                >
                  <option value="">{t('common.all', undefined, 'All')}</option>
                  {cities.map(city => (
                    <option key={city} value={city}>{city}</option>
                  ))}
                </select>
              </div>
            )}

            {(segmentType === 'distribution' || segmentType === 'all') && (
              <>
                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">{t('common.origin_city', undefined, 'Origin City')}</label>
                  <select
                    value={originCity}
                    onChange={(e) => setOriginCity(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                  >
                    <option value="">{t('common.all', undefined, 'All')}</option>
                    {cities.map(city => (
                      <option key={city} value={city}>{city}</option>
                    ))}
                  </select>
                </div>

                <div>
                  <label className="block text-xs font-medium text-gray-700 mb-1">{t('common.destination_city', undefined, 'Destination City')}</label>
                  <select
                    value={destinationCity}
                    onChange={(e) => setDestinationCity(e.target.value)}
                    className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
                  >
                    <option value="">{t('common.all', undefined, 'All')}</option>
                    {cities.map(city => (
                      <option key={city} value={city}>{city}</option>
                    ))}
                  </select>
                </div>
              </>
            )}

            {/* Threshold */}
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">{t('common.threshold', undefined, 'Threshold')}</label>
              <select
                value={threshold}
                onChange={(e) => setThreshold(e.target.value as any)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >
                <option value="all">{t('common.all', undefined, 'All')}</option>
                <option value="compliant">{t('common.compliant', undefined, 'Compliant')}</option>
                <option value="warning">{t('common.warning', undefined, 'Warning')}</option>
                <option value="critical">{t('common.critical', undefined, 'Critical')}</option>
              </select>
            </div>
          </div>
        </div>

        {/* Metrics Cards */}
        <div className="grid grid-cols-2 md:grid-cols-5 gap-4 mb-6">
          <div className="bg-white rounded-lg shadow-sm p-4">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-gray-500">{t('diagnosis.total_segments', undefined, 'Total Segments')}</span>
              <Info className="w-3 h-3 text-gray-400" />
            </div>
            <div className="text-2xl font-bold text-gray-900">{totalSegments}</div>
          </div>

          <div className="bg-white rounded-lg shadow-sm p-4">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-gray-500">{t('diagnosis.avg_jk_actual', undefined, 'Avg J+K Actual')}</span>
              <Info className="w-3 h-3 text-gray-400" />
            </div>
            <div className="text-2xl font-bold text-gray-900">{avgJKActual.toFixed(2)}d</div>
          </div>

          <div className="bg-white rounded-lg shadow-sm p-4">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-gray-500">{t('diagnosis.avg_jk_standard', undefined, 'Avg J+K Standard')}</span>
              <Info className="w-3 h-3 text-gray-400" />
            </div>
            <div className="text-2xl font-bold text-gray-900">{avgJKStandard.toFixed(2)}d</div>
          </div>

          <div className="bg-white rounded-lg shadow-sm p-4">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-gray-500">{t('diagnosis.on_time_percentage', undefined, '% On Time')}</span>
              <Info className="w-3 h-3 text-gray-400" />
            </div>
            <div className={`text-2xl font-bold ${
              onTimePercentage >= 90 ? 'text-green-600' : 
              onTimePercentage >= 80 ? 'text-yellow-600' : 
              'text-red-600'
            }`}>
              {onTimePercentage.toFixed(1)}%
            </div>
          </div>

          <div className="bg-white rounded-lg shadow-sm p-4">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-gray-500">{t('diagnosis.problematic_routes', undefined, 'Problematic Routes')}</span>
              <Info className="w-3 h-3 text-gray-400" />
            </div>
            <div className="text-2xl font-bold text-red-600">{problematicSegments}</div>
          </div>
        </div>

        {loading ? (
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
            <p className="mt-2 text-sm text-gray-600">{t('common.loading', undefined, 'Loading')}...</p>
          </div>
        ) : (
          <>
            {/* Charts */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
              <div className="bg-white rounded-lg shadow-sm p-6">
                <h3 className="text-lg font-semibold text-gray-900 mb-4">{t('diagnosis.performance_distribution', undefined, 'Performance Distribution')}</h3>
                <PerformanceDistributionChart
                  routeData={routeDataForCharts}
                  maxDays={maxDays}
                  carrierFilter={carrier}
                  productFilter={product}
                />
              </div>

              <div className="bg-white rounded-lg shadow-sm p-6">
                <div className="flex items-center justify-between mb-4">
                  <h3 className="text-lg font-semibold text-gray-900">Distribución Acumulada</h3>
                  <div className="flex gap-2">
                    <button
                      onClick={() => setViewMode('chart')}
                      className={`px-3 py-1 text-sm rounded ${
                        viewMode === 'chart'
                          ? 'bg-blue-600 text-white'
                          : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                      }`}
                    >
                      Gráfico
                    </button>
                    <button
                      onClick={() => setViewMode('table')}
                      className={`px-3 py-1 text-sm rounded ${
                        viewMode === 'table'
                          ? 'bg-blue-600 text-white'
                          : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                      }`}
                    >
                      Tabla
                    </button>
                  </div>
                </div>
                <CumulativeDistributionChart
                  routes={routeDataForCharts.map(r => ({
                    routeKey: r.routeKey,
                    originCity: r.originCity,
                    destinationCity: r.destinationCity,
                    carrier: r.carrier,
                    product: r.product,
                    jkStandard: r.jkStandard,
                    standardPercentage: r.standardPercentage,
                    distribution: r.distribution,
                    totalSamples: r.totalSamples,
                  }))}
                  maxDays={maxDays}
                />
              </div>
            </div>

            {/* Table */}
            <div className="bg-white rounded-lg shadow-sm p-6">
              <RoutePerformanceTable routeData={routeDataForCharts} />
            </div>
          </>
        )}
      </div>
    </div>
  );
}
