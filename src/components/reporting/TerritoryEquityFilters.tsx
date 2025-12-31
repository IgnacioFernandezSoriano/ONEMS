import { useState, useEffect } from 'react';
import { Calendar, Filter, RotateCcw, MapPin, Navigation, AlertCircle } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';
import type { TerritoryEquityFilters as Filters } from '@/types/reporting';

import { useTranslation } from '@/hooks/useTranslation';
interface TerritoryEquityFiltersProps {
  filters: Filters;
  onChange: (filters: Filters) => void;
  onReset?: () => void;
}

export function TerritoryEquityFilters({ filters, onChange, onReset }: TerritoryEquityFiltersProps) {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const [carriers, setCarriers] = useState<string[]>([]);
  const [products, setProducts] = useState<string[]>([]);
  const [regions, setRegions] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [isCollapsed, setIsCollapsed] = useState(false);

  useEffect(() => {
    async function loadFilterOptions() {
      if (!profile?.account_id) return;

      try {
        setLoading(true);

        // Get unique carriers
        const { data: carrierData } = await supabase
          .from('one_db')
          .select('carrier_name')
          .eq('account_id', profile.account_id)
          .not('carrier_name', 'is', null);

        // Get unique products
        const { data: productData } = await supabase
          .from('one_db')
          .select('product_name')
          .eq('account_id', profile.account_id)
          .not('product_name', 'is', null);

        // Get regions
        const { data: regionData } = await supabase
          .from('regions')
          .select('name')
          .eq('account_id', profile.account_id);

        const uniqueCarriers = [...new Set(carrierData?.map(d => d.carrier_name) || [])];
        const uniqueProducts = [...new Set(productData?.map(d => d.product_name) || [])];
        const uniqueRegions = regionData?.map(r => r.name) || [];

        setCarriers(uniqueCarriers.sort());
        setProducts(uniqueProducts.sort());
        setRegions(uniqueRegions.sort());
      } catch (error) {
        console.error('Error loading filter options:', error);
      } finally {
        setLoading(false);
      }
    }

    loadFilterOptions();
  }, [profile?.account_id]);

  const handleChange = (field: keyof Filters, value: string | string[] | undefined) => {
    onChange({
      ...filters,
      [field]: value
    } as Filters);
  };

  const handleReset = () => {
    if (onReset) {
      onReset();
    } else {
      onChange({
        startDate: '',
        endDate: '',
        carrier: '',
        product: '',
        region: '',
        direction: undefined,
        equityStatus: [],
      });
    }
  };



  return (
    <div className="bg-white rounded-lg shadow p-4">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <button
            onClick={() => setIsCollapsed(!isCollapsed)}
            className="p-1 hover:bg-gray-100 rounded transition-colors"
            title={isCollapsed ? "Expand filters" : "Collapse filters"}
          >
            {isCollapsed ? (
              <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 9l-7 7-7-7" />
              </svg>
            ) : (
              <svg className="w-5 h-5 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 15l7-7 7 7" />
              </svg>
            )}
          </button>
          <Filter className="w-5 h-5 text-gray-600" />
          <h3 className="text-lg font-semibold text-gray-900">{t('stock.filters')}</h3>
          <SmartTooltip content="Filter the Territory Equity Report by date range, carrier, product, region, direction (inbound/outbound), or equity status. All filters are optional." />
        </div>
        <button
          onClick={handleReset}
          className="flex items-center gap-2 px-3 py-1.5 text-sm text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
          title="Reset all filters"
        >
          <RotateCcw className="w-4 h-4" />
          Reset
        </button>
      </div>
      
      {!isCollapsed && (
      <>
      <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-7 gap-4">
        {/* Start Date */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <Calendar className="w-4 h-4 inline mr-1" />
            Start Date
            <SmartTooltip content="Filter shipments sent on or after this date. Leave empty to include all historical data." />
          </label>
          <input
            type="date"
            value={filters.startDate || ''}
            onChange={(e) => handleChange('startDate', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
        </div>

        {/* End Date */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <Calendar className="w-4 h-4 inline mr-1" />
            End Date
            <SmartTooltip content="Filter shipments sent on or before this date. Leave empty to include data up to today." />
          </label>
          <input
            type="date"
            value={filters.endDate || ''}
            onChange={(e) => handleChange('endDate', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
        </div>

        {/* Carrier */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Carrier
            <SmartTooltip content="Filter by specific carrier (e.g., DHL). Shows only shipments handled by the selected carrier." />
          </label>
          <select
            value={filters.carrier || ''}
            onChange={(e) => handleChange('carrier', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={loading}
          >
            <option value="">All Carriers</option>
            {carriers.map(carrier => (
              <option key={carrier} value={carrier}>{carrier}</option>
            ))}
          </select>
        </div>

        {/* Product */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Product
            <SmartTooltip content="Filter by service type (e.g., Express 24h). Shows only shipments using the selected product." />
          </label>
          <select
            value={filters.product || ''}
            onChange={(e) => handleChange('product', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={loading}
          >
            <option value="">All Products</option>
            {products.map(product => (
              <option key={product} value={product}>{product}</option>
            ))}
          </select>
        </div>

        {/* Region */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <MapPin className="w-4 h-4 inline mr-1" />
            Region
            <SmartTooltip content="Filter by geographic region. Shows only cities within the selected region. Regions are defined by the regulator." />
          </label>
          <select
            value={filters.region || ''}
            onChange={(e) => handleChange('region', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={loading}
          >
            <option value="">All Regions</option>
            {regions.map(region => (
              <option key={region} value={region}>{region}</option>
            ))}
          </select>
        </div>

        {/* Direction */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <Navigation className="w-4 h-4 inline mr-1" />
            Direction
            <SmartTooltip content="Filter by shipment direction. Inbound: packages arriving TO cities. Outbound: packages leaving FROM cities. Both: combined analysis." />
          </label>
          <select
            value={filters.direction || ''}
            onChange={(e) => handleChange('direction', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          >
            <option value="">Both Directions</option>
            <option value="inbound">📥 Inbound Only</option>
            <option value="outbound">📤 Outbound Only</option>
          </select>
        </div>

        {/* Equity Status */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <AlertCircle className="w-4 h-4 inline mr-1" />
            Equity Status
            <SmartTooltip content="Filter by equity compliance status. Compliant: meeting standards. Warning: below standard. Critical: significantly below standard requiring action." />
          </label>
          <select
            value={(filters.equityStatus && filters.equityStatus.length > 0) ? filters.equityStatus[0] : ''}
            onChange={(e) => handleChange('equityStatus', e.target.value ? [e.target.value] : [])}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          >
            <option value="">All Statuses</option>
            <option value="compliant">✅ Compliant</option>
            <option value="warning">⚠️ Warning</option>
            <option value="critical">🔴 Critical</option>
          </select>
        </div>
      </div>

      {/* Filter Guidance */}
      <div className="mt-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
        <h4 className="text-sm font-semibold text-blue-900 mb-1">Territory Equity Filter Guide</h4>
        <ul className="text-xs text-blue-800 space-y-1">
          <li>• <strong>No filters:</strong> View overall service equity across all cities and regions</li>
          <li>• <strong>Region:</strong> Focus analysis on specific geographic areas</li>
          <li>• <strong>Direction:</strong> Analyze inbound vs outbound service quality separately</li>
          <li>• <strong>Equity Status:</strong> Identify cities with specific compliance levels</li>
          <li>• <strong>Carrier/Product:</strong> Narrow analysis to specific service providers or types</li>
          <li>• <strong>Date Range:</strong> Analyze trends over specific time periods</li>
        </ul>
      </div>
      </>
      )}
    </div>
  );
}
