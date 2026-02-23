import React, { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useAccount } from '@/contexts/AccountContext';
import { supabase } from '@/lib/supabase';
import { PerformanceDistributionChart } from '@/components/reporting/PerformanceDistributionChart';
import { CumulativeDistributionChart } from '@/components/reporting/CumulativeDistributionChart';
import { RoutePerformanceTable } from '@/components/reporting/RoutePerformanceTable';
import { Info } from 'lucide-react';
import { useSearchParams } from 'react-router-dom';
import { useTranslation } from '@/hooks/useTranslation';

interface SegmentData {
  segmentKey: string;
  fromCenter: string;
  toCenter: string;
  carrier: string;
  product: string;
  segmentType: 'operational' | 'distribution';
  carrier_id?: string;
  product_id?: string;
  from_postal_center_id?: string;
  to_postal_center_id?: string;
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
  const [fromCenter, setFromCenter] = useState('');
  const [toCenter, setToCenter] = useState('');
  const [segmentType, setSegmentType] = useState<'all' | 'operational' | 'distribution'>('all');
  const [threshold, setThreshold] = useState<'all' | 'compliant' | 'warning' | 'critical'>('all');
  
  const [carriers, setCarriers] = useState<Array<{id: string, name: string}>>([]);
  const [products, setProducts] = useState<Array<{id: string, code: string, description: string, carrier_id: string}>>([]);
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
        .select('id, code, description, carrier_id')
        .eq('account_id', effectiveAccountId)
        .order('code');
      if (productsData) setProducts(productsData);

      // Load postal centers (load all centers, not filtered by account)
      const { data: centersData } = await supabase
        .from('postal_centers')
        .select('id, name, city');
      if (centersData) {
        setPostalCenters(centersData);
        console.log(`📍 Loaded ${centersData.length} postal centers (all accounts)`);
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
    const postalCenterIdParam = searchParams.get('postal_center_id');
    const segmentTypeParam = searchParams.get('segment_type');

    if (carrierIdParam && carriers.length > 0) {
      const carrierObj = carriers.find(c => c.id === carrierIdParam);
      if (carrierObj) setCarrier(carrierObj.name);
    }

    if (productIdParam && products.length > 0) {
      const productObj = products.find(p => p.id === productIdParam);
      if (productObj) setProduct(`${productObj.code} - ${productObj.description}`);
    }

    // For operational segments, use postal_center_id
    if (postalCenterIdParam && postalCenters.length > 0) {
      const centerObj = postalCenters.find(c => c.id === postalCenterIdParam);
      if (centerObj) {
        setFromCenter(centerObj.name);
        setOriginCity(centerObj.city);
      }
    } else if (fromCenterIdParam && postalCenters.length > 0) {
      const centerObj = postalCenters.find(c => c.id === fromCenterIdParam);
      if (centerObj) {
        setFromCenter(centerObj.name);
        setOriginCity(centerObj.city);
      }
    }

    if (toCenterIdParam && postalCenters.length > 0) {
      const centerObj = postalCenters.find(c => c.id === toCenterIdParam);
      if (centerObj) {
        setToCenter(centerObj.name);
        setDestinationCity(centerObj.city);
      }
    }

    if (segmentTypeParam === 'operational' || segmentTypeParam === 'distribution') {
      setSegmentType(segmentTypeParam);
    }
  }, [searchParams, carriers, products, postalCenters, effectiveAccountId]);

  // Load segment data
  useEffect(() => {
    if (!effectiveAccountId) return;

    const loadSegments = async () => {
      setLoading(true);

      try {
        // Query journey_segments with simpler select
        let query = supabase
          .from('journey_segments')
          .select('*')
          .eq('account_id', effectiveAccountId)
          .limit(1000);

        if (carrier) {
          const carrierObj = carriers.find(c => c.name === carrier);
          if (carrierObj) query = query.eq('carrier_id', carrierObj.id);
        }

        if (product) {
          const productObj = products.find(p => `${p.code} - ${p.description}` === product);
          if (productObj) query = query.eq('product_id', productObj.id);
        }

        if (originCity) {
          query = query.eq('from_postal_center_city', originCity);
        }

        if (destinationCity) {
          query = query.eq('to_postal_center_city', destinationCity);
        }

        if (fromCenter) {
          const centerObj = postalCenters.find(c => c.name === fromCenter);
          if (centerObj) {
            // For operational segments, filter by postal_center_id
            if (segmentType === 'operational') {
              query = query.eq('postal_center_id', centerObj.id);
            } else {
              query = query.eq('from_postal_center_id', centerObj.id);
            }
          }
        }

        if (toCenter) {
          const centerObj = postalCenters.find(c => c.name === toCenter);
          if (centerObj) query = query.eq('to_postal_center_id', centerObj.id);
        }

        const { data: segments, error } = await query;

        if (error) throw error;
        if (!segments || segments.length === 0) {
          setSegmentData([]);
          setLoading(false);
          return;
        }

        console.log('📊 JKPerformanceSegments - Data Source: journey_segments table');
        console.log('📦 Total segments loaded:', segments.length);

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

        // Group segments and calculate metrics
        const segmentMap = new Map<string, any>();
        console.log('🔍 Grouping segments by type (operational/distribution)...');

        // Create lookup maps
        const carrierMap = new Map(carriers.map(c => [c.id, c.name]));
        const productMap = new Map(products.map(p => [p.id, `${p.code} - ${p.description}`]));
        const centerMap = new Map(postalCenters.map(c => [c.id, c.name]));

        console.log(`📍 Loaded ${postalCenters.length} postal centers for mapping`);
        console.log('Sample center IDs in map:', Array.from(centerMap.keys()).slice(0, 3));

        segments.forEach((seg: any) => {
          const carrierName = carrierMap.get(seg.carrier_id) || 'Unknown';
          const productName = productMap.get(seg.product_id) || 'Unknown';
          const fromCenterName = centerMap.get(seg.from_postal_center_id) || seg.from_postal_center_city || 'Unknown';
          const toCenterName = centerMap.get(seg.to_postal_center_id) || seg.to_postal_center_city || 'Unknown';
          
          // Debug: Log if we're falling back to city names
          if (!centerMap.has(seg.from_postal_center_id)) {
            console.warn(`⚠️  Center ID not found: ${seg.from_postal_center_id}, falling back to city: ${seg.from_postal_center_city}`);
          }
          if (seg.to_postal_center_id && !centerMap.has(seg.to_postal_center_id)) {
            console.warn(`⚠️  Center ID not found: ${seg.to_postal_center_id}, falling back to city: ${seg.to_postal_center_city}`);
          }
          
          // Center segment - only if there's actual time in center
          const timeInCenter = seg.working_time_in_center_minutes || seg.natural_time_in_center_minutes || 0;
          if (timeInCenter > 0) {
            const centerKey = `${fromCenterName}_center_${carrierName}_${productName}`;
            if (!segmentMap.has(centerKey)) {
              segmentMap.set(centerKey, {
                segmentKey: centerKey,
                fromCenter: fromCenterName,
                toCenter: fromCenterName,
                carrier: carrierName,
                product: productName,
                segmentType: 'operational',
                samples: [],
                carrier_id: seg.carrier_id,
                product_id: seg.product_id,
                postal_center_id: seg.postal_center_id,
              });
            }
            segmentMap.get(centerKey).samples.push({ time: timeInCenter, journey_id: seg.id });
          }

          // Transit segment - only if there's actual transit time
          const transitTime = seg.working_transit_time_minutes || seg.natural_transit_time_minutes || 0;
          if (transitTime > 0 && seg.to_postal_center_id) {
            const transitKey = `${fromCenterName}_${toCenterName}_transit_${carrierName}_${productName}`;
            if (!segmentMap.has(transitKey)) {
              segmentMap.set(transitKey, {
                segmentKey: transitKey,
                fromCenter: fromCenterName,
                toCenter: toCenterName,
                carrier: carrierName,
                product: productName,
                segmentType: 'distribution',
                samples: [],
                carrier_id: seg.carrier_id,
                product_id: seg.product_id,
                from_postal_center_id: seg.from_postal_center_id,
                to_postal_center_id: seg.to_postal_center_id,
              });
            }
            segmentMap.get(transitKey).samples.push({ time: transitTime, journey_id: seg.id });
          }
        });

        console.log('✅ Processed segments:');
        console.log('  - Operational (center):', Array.from(segmentMap.values()).filter(s => s.segmentType === 'operational').length);
        console.log('  - Distribution (transit):', Array.from(segmentMap.values()).filter(s => s.segmentType === 'distribution').length);
        console.log('  - Total:', segmentMap.size);

        // Calculate metrics for each segment
        const processedSegments: SegmentData[] = [];

        segmentMap.forEach((segGroup) => {
          // Find SLA
          let sla = null;
          if (segGroup.segmentType === 'operational') {
            // Try to find carrier-specific SLA first, then fallback to generic
            sla = slas.find(s => 
              s.sla_type === 'operational' &&
              s.postal_center_id === segGroup.postal_center_id &&
              s.carrier_id === segGroup.carrier_id
            );
            if (!sla) {
              sla = slas.find(s => 
                s.sla_type === 'operational' &&
                s.postal_center_id === segGroup.postal_center_id &&
                s.carrier_id === null
              );
            }
            console.log(`🔍 SLA lookup for ${segGroup.fromCenter}:`, {
              found: !!sla,
              expected_minutes: sla?.expected_time_minutes || 'using default 1440',
              carrier_id: segGroup.carrier_id,
              postal_center_id: segGroup.postal_center_id
            });
          } else {
            // Try to find carrier-specific SLA first, then fallback to generic
            sla = slas.find(s => 
              s.sla_type === 'distribution' &&
              s.from_postal_center_id === segGroup.from_postal_center_id &&
              s.to_postal_center_id === segGroup.to_postal_center_id &&
              s.carrier_id === segGroup.carrier_id
            );
            if (!sla) {
              sla = slas.find(s => 
                s.sla_type === 'distribution' &&
                s.from_postal_center_id === segGroup.from_postal_center_id &&
                s.to_postal_center_id === segGroup.to_postal_center_id &&
                s.carrier_id === null
              );
            }
          }

          // Use SLA values or defaults if no SLA exists
          const jkStandardMinutes = sla?.expected_time_minutes || 1440; // Default 1 day
          const jkStandardDays = jkStandardMinutes / 1440;
          const standardPercentage = sla?.on_time_percentage || 95;
          const warningThreshold = sla?.warning_threshold || 90;
          const criticalThreshold = sla?.critical_threshold || 80;

          // Calculate distribution and J+K Actual
          const distribution = new Map<number, number>();
          let onTimeSamples = 0;
          let beforeStandardSamples = 0;
          let afterStandardSamples = 0;

          // Store all sample times in days for J+K Actual calculation
          const sampleDays: number[] = [];

          segGroup.samples.forEach((sample: any) => {
            const days = Math.round(sample.time / 1440);
            const exactDays = sample.time / 1440;
            distribution.set(days, (distribution.get(days) || 0) + 1);
            sampleDays.push(exactDays);

            if (sample.time <= jkStandardMinutes) {
              onTimeSamples++;
              if (sample.time < jkStandardMinutes) beforeStandardSamples++;
            } else {
              afterStandardSamples++;
            }
          });

          const totalSamples = segGroup.samples.length;
          const onTimePercentage = totalSamples > 0 ? (onTimeSamples / totalSamples) * 100 : 0;

          // Calculate J+K Actual: sort samples by time and find the day where standardPercentage is reached
          let jkActualDays = jkStandardDays;
          if (sampleDays.length > 0) {
            const sortedSampleDays = [...sampleDays].sort((a, b) => a - b);
            const targetIndex = Math.ceil((standardPercentage / 100) * totalSamples) - 1;
            jkActualDays = sortedSampleDays[Math.min(targetIndex, sortedSampleDays.length - 1)];
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
            carrier_id: segGroup.carrier_id,
            product_id: segGroup.product_id,
            from_postal_center_id: segGroup.from_postal_center_id,
            to_postal_center_id: segGroup.to_postal_center_id,
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
  }, [effectiveAccountId, carrier, product, originCity, destinationCity, fromCenter, toCenter, segmentType, threshold, carriers, products, postalCenters]);

  // Convert SegmentData to JKRouteData format for charts
  const routeDataForCharts = segmentData.map(seg => ({
    originCity: seg.fromCenter,
    destinationCity: seg.toCenter,
    carrier: seg.carrier,
    product: seg.product,
    segmentType: seg.segmentType,
    carrier_id: seg.carrier_id,
    product_id: seg.product_id,
    from_postal_center_id: seg.from_postal_center_id,
    to_postal_center_id: seg.to_postal_center_id,
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
          <div className="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-8 gap-4">
            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">{t('common.carrier', undefined, 'Carrier')}</label>
              <select
                value={carrier}
                onChange={(e) => {
                  setCarrier(e.target.value);
                  setProduct(''); // Reset product when carrier changes
                }}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >
                <option value="">{t('common.all', undefined, 'All')}</option>
                {carriers.map(c => (
                  <option key={c.id} value={c.name}>{c.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">{t('common.product', undefined, 'Product')}</label>
              <select
                value={product}
                onChange={(e) => setProduct(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >
                <option value="">{t('common.all', undefined, 'All')}</option>
                {filteredProducts.map(p => (
                  <option key={p.id} value={`${p.code} - ${p.description}`}>{p.code} - {p.description}</option>
                ))}
              </select>
            </div>

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

            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">From Center</label>
              <select
                value={fromCenter}
                onChange={(e) => setFromCenter(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >
                <option value="">All</option>
                {postalCenters.map(center => (
                  <option key={center.id} value={center.name}>{center.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">To Center</label>
              <select
                value={toCenter}
                onChange={(e) => setToCenter(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >
                <option value="">All</option>
                {postalCenters.map(center => (
                  <option key={center.id} value={center.name}>{center.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-xs font-medium text-gray-700 mb-1">{t('diagnosis.segment_type', undefined, 'Segment Type')}</label>
              <select
                value={segmentType}
                onChange={(e) => setSegmentType(e.target.value as any)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg text-sm"
              >
                <option value="all">{t('common.all', undefined, 'All')}</option>
                <option value="operational">{t('diagnosis.operational', undefined, 'Operational')}</option>
                <option value="distribution">{t('diagnosis.distribution', undefined, 'Distribution')}</option>
              </select>
            </div>

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
              <span className="text-xs text-gray-500">Avg J+K Actual</span>
              <Info className="w-3 h-3 text-gray-400" />
            </div>
            <div className="text-2xl font-bold text-gray-900">{avgJKActual.toFixed(2)}d</div>
          </div>

          <div className="bg-white rounded-lg shadow-sm p-4">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-gray-500">Avg J+K Standard</span>
              <Info className="w-3 h-3 text-gray-400" />
            </div>
            <div className="text-2xl font-bold text-gray-900">{avgJKStandard.toFixed(2)}d</div>
          </div>

          <div className="bg-white rounded-lg shadow-sm p-4">
            <div className="flex items-center gap-2 mb-1">
              <span className="text-xs text-gray-500">% On Time</span>
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
              <span className="text-xs text-gray-500">Problematic Segments</span>
              <Info className="w-3 h-3 text-gray-400" />
            </div>
            <div className="text-2xl font-bold text-red-600">{problematicSegments}</div>
          </div>
        </div>

        {loading ? (
          <div className="text-center py-12">
            <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
            <p className="mt-2 text-sm text-gray-600">Cargando datos de segmentos...</p>
          </div>
        ) : (
          <>
            {/* Charts */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 mb-6">
              <div className="bg-white rounded-lg shadow-sm p-6">
                <h3 className="text-lg font-semibold text-gray-900 mb-4">Distribución de Rendimiento</h3>
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
