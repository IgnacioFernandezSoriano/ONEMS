import React, { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '../../lib/supabase';
import { Package, Clock, CheckCircle, AlertTriangle } from 'lucide-react';

interface SegmentRoute {
  route_key: string;
  origin_city: string;
  destination_city: string;
  carrier: string;
  segment_type: string;
  total_segments: number;
  jk_standard_days: number;
  jk_actual_days: number;
  deviation_days: number;
  on_time_percentage: number;
  on_time_segments: number;
  status: string;
}

interface CityPerformance {
  city_name: string;
  direction: string;
  routes: number;
  total_segments: number;
  jk_standard_days: number;
  jk_actual_days: number;
  deviation_days: number;
  on_time_percentage: number;
  status: string;
}

interface CarrierPerformance {
  carrier: string;
  routes: number;
  total_segments: number;
  jk_standard_days: number;
  jk_actual_days: number;
  deviation_days: number;
  on_time_percentage: number;
  problematic_routes: number;
  status: string;
}

const JKPerformanceSegments: React.FC = () => {
  const { profile } = useAuth();
  const [searchParams] = useSearchParams();
  const [activeTab, setActiveTab] = useState<'segments' | 'centers' | 'carriers'>('segments');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Filters
  const [originCity, setOriginCity] = useState<string>('');
  const [destinationCity, setDestinationCity] = useState<string>('');
  const [carrier, setCarrier] = useState<string>('');
  const [product, setProduct] = useState<string>('');
  const [segmentType, setSegmentType] = useState<string>('');
  const [threshold, setThreshold] = useState<string>('');
  const [carrierId, setCarrierId] = useState<string>('');
  const [productId, setProductId] = useState<string>('');
  const [fromCenterId, setFromCenterId] = useState<string>('');
  const [toCenterId, setToCenterId] = useState<string>('');

  // Dropdown options
  const [carriers, setCarriers] = useState<{id: string, name: string}[]>([]);
  const [products, setProducts] = useState<{id: string, name: string, carrier_id: string}[]>([]);
  const [filteredProducts, setFilteredProducts] = useState<{id: string, name: string}[]>([]);

  // Data
  const [segmentRoutes, setSegmentRoutes] = useState<SegmentRoute[]>([]);
  const [cityPerformance, setCityPerformance] = useState<CityPerformance[]>([]);
  const [carrierPerformance, setCarrierPerformance] = useState<CarrierPerformance[]>([]);

  // Metrics
  const [metrics, setMetrics] = useState({
    totalSegments: 0,
    avgJKActual: 0,
    avgJKStandard: 0,
    onTimePercentage: 0,
    problematicRoutes: 0
  });

  // Load carriers and products
  useEffect(() => {
    const loadOptions = async () => {
      if (!profile?.account_id) return;

      try {
        // Load carriers
        const { data: carriersData } = await supabase
          .from('carriers')
          .select('id, name')
          .eq('account_id', profile.account_id)
          .order('name');
        if (carriersData) setCarriers(carriersData);

        // Load products
        const { data: productsData } = await supabase
          .from('products')
          .select('id, name, carrier_id')
          .eq('account_id', profile.account_id)
          .order('name');
        if (productsData) setProducts(productsData);
      } catch (err) {
        console.error('Error loading options:', err);
      }
    };

    loadOptions();
  }, [profile?.account_id]);

  // Filter products by selected carrier
  useEffect(() => {
    if (carrierId) {
      setFilteredProducts(products.filter(p => p.carrier_id === carrierId));
    } else {
      setFilteredProducts(products);
    }
  }, [carrierId, products]);

  // Read URL params on mount and resolve IDs to names
  useEffect(() => {
    const urlCarrierId = searchParams.get('carrier_id');
    const urlProductId = searchParams.get('product_id');
    const urlFromCenterId = searchParams.get('from_center_id');
    const urlToCenterId = searchParams.get('to_center_id');
    const urlSegmentType = searchParams.get('segment_type');

    if (urlCarrierId) setCarrierId(urlCarrierId);
    if (urlProductId) setProductId(urlProductId);
    if (urlFromCenterId) setFromCenterId(urlFromCenterId);
    if (urlToCenterId) setToCenterId(urlToCenterId);
    if (urlSegmentType) setSegmentType(urlSegmentType);

    // Resolve IDs to names
    const resolveIds = async () => {
      if (!profile?.account_id) return;

      try {
        // Resolve carrier
        if (urlCarrierId) {
          const { data: carrierData } = await supabase
            .from('carriers')
            .select('name')
            .eq('id', urlCarrierId)
            .single();
          if (carrierData) setCarrier(carrierData.name);
        }

        // Resolve product
        if (urlProductId) {
          const { data: productData } = await supabase
            .from('products')
            .select('name')
            .eq('id', urlProductId)
            .single();
          if (productData) setProduct(productData.name);
        }

        // Resolve from center to city
        if (urlFromCenterId) {
          const { data: centerData } = await supabase
            .from('postal_centers')
            .select('city')
            .eq('id', urlFromCenterId)
            .single();
          if (centerData) setOriginCity(centerData.city);
        }

        // Resolve to center to city
        if (urlToCenterId) {
          const { data: centerData } = await supabase
            .from('postal_centers')
            .select('city')
            .eq('id', urlToCenterId)
            .single();
          if (centerData) setDestinationCity(centerData.city);
        }
      } catch (err) {
        console.error('Error resolving IDs:', err);
      }
    };

    resolveIds();
  }, [searchParams, profile?.account_id]);

  useEffect(() => {
    if (activeTab === 'segments') {
      loadSegmentRoutes();
    } else if (activeTab === 'centers') {
      loadCityPerformance();
    } else if (activeTab === 'carriers') {
      loadCarrierPerformance();
    }
  }, [activeTab, profile?.account_id, originCity, destinationCity, carrier, segmentType, carrierId, productId, fromCenterId, toCenterId]);

  const loadSegmentRoutes = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_jk_performance_segments', {
        p_account_id: profile.account_id,
        p_origin_city: originCity || null,
        p_destination_city: destinationCity || null,
        p_carrier: carrier || null,
        p_product: product || null,
        p_segment_type: segmentType || null,
        p_threshold: threshold || null
      });

      if (rpcError) throw rpcError;

      setSegmentRoutes(data || []);

      // Calculate metrics
      const totalSegments = data?.reduce((sum: number, r: SegmentRoute) => sum + r.total_segments, 0) || 0;
      const totalWeightedJKActual = data?.reduce((sum: number, r: SegmentRoute) => sum + r.jk_actual_days * r.total_segments, 0) || 0;
      const totalWeightedJKStandard = data?.reduce((sum: number, r: SegmentRoute) => sum + r.jk_standard_days * r.total_segments, 0) || 0;
      const onTimeSegments = data?.reduce((sum: number, r: SegmentRoute) => sum + r.on_time_segments, 0) || 0;
      const problematicRoutes = data?.filter((r: SegmentRoute) => r.status === 'critical').length || 0;

      setMetrics({
        totalSegments,
        avgJKActual: totalSegments > 0 ? totalWeightedJKActual / totalSegments : 0,
        avgJKStandard: totalSegments > 0 ? totalWeightedJKStandard / totalSegments : 0,
        onTimePercentage: totalSegments > 0 ? (onTimeSegments / totalSegments) * 100 : 0,
        problematicRoutes
      });
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const loadCityPerformance = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_jk_city_performance_segments', {
        p_account_id: profile.account_id
      });

      if (rpcError) throw rpcError;
      setCityPerformance(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const loadCarrierPerformance = async () => {
    if (!profile?.account_id) return;

    try {
      setLoading(true);
      setError(null);

      const { data, error: rpcError } = await supabase.rpc('get_jk_carrier_performance_segments', {
        p_account_id: profile.account_id
      });

      if (rpcError) throw rpcError;
      setCarrierPerformance(data || []);
    } catch (err: any) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  };

  const getStatusBadge = (status: string) => {
    const colors = {
      compliant: 'bg-green-100 text-green-800',
      warning: 'bg-yellow-100 text-yellow-800',
      critical: 'bg-red-100 text-red-800'
    };
    return colors[status as keyof typeof colors] || 'bg-gray-100 text-gray-800';
  };

  const renderFilters = () => (
    <div className="bg-white border border-gray-200 rounded-lg p-4 mb-6">
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Carrier</label>
          <select
            value={carrierId}
            onChange={(e) => {
              const selectedId = e.target.value;
              setCarrierId(selectedId);
              const selectedCarrier = carriers.find(c => c.id === selectedId);
              setCarrier(selectedCarrier?.name || '');
              // Reset product when carrier changes
              setProductId('');
              setProduct('');
            }}
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
          >
            <option value="">All Carriers</option>
            {carriers.map(c => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Product</label>
          <select
            value={productId}
            onChange={(e) => {
              const selectedId = e.target.value;
              setProductId(selectedId);
              const selectedProduct = filteredProducts.find(p => p.id === selectedId);
              setProduct(selectedProduct?.name || '');
            }}
            disabled={!carrierId}
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm disabled:bg-gray-100"
          >
            <option value="">All Products</option>
            {filteredProducts.map(p => (
              <option key={p.id} value={p.id}>{p.name}</option>
            ))}
          </select>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Threshold</label>
          <select
            value={threshold}
            onChange={(e) => setThreshold(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
          >
            <option value="">All</option>
            <option value="compliant">Compliant</option>
            <option value="warning">Warning</option>
            <option value="critical">Critical</option>
          </select>
        </div>
      </div>
      <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Origin City</label>
          <input
            type="text"
            value={originCity}
            onChange={(e) => setOriginCity(e.target.value)}
            placeholder="All"
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Destination City</label>
          <input
            type="text"
            value={destinationCity}
            onChange={(e) => setDestinationCity(e.target.value)}
            placeholder="All"
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Segment Type</label>
          <select
            value={segmentType}
            onChange={(e) => setSegmentType(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
          >
            <option value="">All</option>
            <option value="operational">Operational</option>
            <option value="distribution">Distribution</option>
          </select>
        </div>
      </div>
    </div>
  );

  const renderKPIs = () => (
    <div className="grid grid-cols-1 md:grid-cols-5 gap-4 mb-6">
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm text-gray-600">Total Segments</span>
          <Package className="h-5 w-5 text-blue-600" />
        </div>
        <div className="text-2xl font-bold text-gray-900">{metrics.totalSegments}</div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm text-gray-600">Avg J+K Actual</span>
          <Clock className="h-5 w-5 text-orange-600" />
        </div>
        <div className="text-2xl font-bold text-gray-900">{metrics.avgJKActual.toFixed(2)}d</div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm text-gray-600">Avg J+K Standard</span>
          <Clock className="h-5 w-5 text-blue-600" />
        </div>
        <div className="text-2xl font-bold text-gray-900">{metrics.avgJKStandard.toFixed(2)}d</div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm text-gray-600">On-Time %</span>
          <CheckCircle className="h-5 w-5 text-green-600" />
        </div>
        <div className={`text-2xl font-bold ${
          metrics.onTimePercentage >= 80 ? 'text-green-600' :
          metrics.onTimePercentage >= 75 ? 'text-yellow-600' :
          'text-red-600'
        }`}>
          {metrics.onTimePercentage.toFixed(1)}%
        </div>
      </div>
      <div className="bg-white border border-gray-200 rounded-lg p-4">
        <div className="flex items-center justify-between mb-2">
          <span className="text-sm text-gray-600">Problematic Routes</span>
          <AlertTriangle className="h-5 w-5 text-red-600" />
        </div>
        <div className="text-2xl font-bold text-red-600">{metrics.problematicRoutes}</div>
      </div>
    </div>
  );

  const renderSegmentsTab = () => (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ROUTE</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">CARRIER</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">TYPE</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">SEGMENTS</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">J+K STD</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">J+K ACT</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">DEVIATION</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ON-TIME %</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">STATUS</th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {segmentRoutes.map((route, idx) => (
            <tr key={idx}>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                <div>{route.origin_city} → {route.destination_city}</div>
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{route.carrier}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 capitalize">{route.segment_type}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{route.total_segments}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{route.jk_standard_days}d</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{route.jk_actual_days}d</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm">
                <span className={route.deviation_days > 0 ? 'text-red-600 font-semibold' : 'text-green-600 font-semibold'}>
                  {route.deviation_days > 0 ? '+' : ''}{route.deviation_days}d
                </span>
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm">
                <span className={`font-semibold ${
                  route.on_time_percentage >= 80 ? 'text-green-600' :
                  route.on_time_percentage >= 75 ? 'text-yellow-600' :
                  'text-red-600'
                }`}>
                  {route.on_time_percentage}%
                </span>
              </td>
              <td className="px-6 py-4 whitespace-nowrap">
                <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${getStatusBadge(route.status)}`}>
                  {route.status}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );

  const renderCentersTab = () => (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">CENTER</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">DIRECTION</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ROUTES</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">SEGMENTS</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">J+K STD</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">J+K ACT</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">DEVIATION</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ON-TIME %</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">STATUS</th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {cityPerformance.map((city, idx) => (
            <tr key={idx}>
              <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{city.city_name}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 capitalize">{city.direction}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{city.routes}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{city.total_segments}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{city.jk_standard_days}d</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{city.jk_actual_days}d</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm">
                <span className={city.deviation_days > 0 ? 'text-red-600 font-semibold' : 'text-green-600 font-semibold'}>
                  {city.deviation_days > 0 ? '+' : ''}{city.deviation_days}d
                </span>
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm">
                <span className={`font-semibold ${
                  city.on_time_percentage >= 80 ? 'text-green-600' :
                  city.on_time_percentage >= 75 ? 'text-yellow-600' :
                  'text-red-600'
                }`}>
                  {city.on_time_percentage}%
                </span>
              </td>
              <td className="px-6 py-4 whitespace-nowrap">
                <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${getStatusBadge(city.status)}`}>
                  {city.status}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );

  const renderCarriersTab = () => (
    <div className="overflow-x-auto">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">CARRIER</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ROUTES</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">SEGMENTS</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">J+K STD</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">J+K ACT</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">DEVIATION</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ON-TIME %</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">PROBLEMATIC</th>
            <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">STATUS</th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {carrierPerformance.map((carr, idx) => (
            <tr key={idx}>
              <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">{carr.carrier}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{carr.routes}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{carr.total_segments}</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{carr.jk_standard_days}d</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{carr.jk_actual_days}d</td>
              <td className="px-6 py-4 whitespace-nowrap text-sm">
                <span className={carr.deviation_days > 0 ? 'text-red-600 font-semibold' : 'text-green-600 font-semibold'}>
                  {carr.deviation_days > 0 ? '+' : ''}{carr.deviation_days}d
                </span>
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm">
                <span className={`font-semibold ${
                  carr.on_time_percentage >= 80 ? 'text-green-600' :
                  carr.on_time_percentage >= 75 ? 'text-yellow-600' :
                  'text-red-600'
                }`}>
                  {carr.on_time_percentage}%
                </span>
              </td>
              <td className="px-6 py-4 whitespace-nowrap text-sm text-red-600 font-semibold">{carr.problematic_routes}</td>
              <td className="px-6 py-4 whitespace-nowrap">
                <span className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${getStatusBadge(carr.status)}`}>
                  {carr.status}
                </span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );

  return (
    <div className="p-6 max-w-7xl mx-auto">
      <div className="mb-6">
        <div className="flex items-center gap-2 mb-2">
          <Package className="h-6 w-6 text-blue-600" />
          <h1 className="text-2xl font-bold text-gray-900">J+K Performance (Segments)</h1>
        </div>
        <p className="text-gray-600">Segment-level performance analysis with J+K metrics (days)</p>
      </div>

      {renderFilters()}
      {activeTab === 'segments' && renderKPIs()}

      {/* Tabs */}
      <div className="border-b border-gray-200 mb-6">
        <nav className="-mb-px flex space-x-8">
          <button
            onClick={() => setActiveTab('segments')}
            className={`py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'segments'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            Segments
          </button>
          <button
            onClick={() => setActiveTab('centers')}
            className={`py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'centers'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            Centers
          </button>
          <button
            onClick={() => setActiveTab('carriers')}
            className={`py-4 px-1 border-b-2 font-medium text-sm ${
              activeTab === 'carriers'
                ? 'border-blue-500 text-blue-600'
                : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
            }`}
          >
            Carriers
          </button>
        </nav>
      </div>

      {/* Content */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        {loading ? (
          <div className="text-center py-8 text-gray-500">Loading...</div>
        ) : error ? (
          <div className="text-center py-8 text-red-500">Error: {error}</div>
        ) : (
          <>
            {activeTab === 'segments' && renderSegmentsTab()}
            {activeTab === 'centers' && renderCentersTab()}
            {activeTab === 'carriers' && renderCarriersTab()}
          </>
        )}
      </div>
    </div>
  );
};

export default JKPerformanceSegments;
