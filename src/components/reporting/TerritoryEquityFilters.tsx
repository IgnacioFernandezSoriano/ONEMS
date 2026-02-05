import { useState, useEffect, useRef, useCallback } from 'react';
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
  const [originCities, setOriginCities] = useState<string[]>([]);
  const [destinationCities, setDestinationCities] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [isCollapsed, setIsCollapsed] = useState(false);
  const [filteredProducts, setFilteredProducts] = useState<string[]>([]);
  const prevCarrierRef = useRef<string>();

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

        // Get unique origin cities
        const { data: originCityData } = await supabase
          .from('one_db')
          .select('origin_city_name')
          .eq('account_id', profile.account_id)
          .not('origin_city_name', 'is', null);

        // Get unique destination cities
        const { data: destCityData } = await supabase
          .from('one_db')
          .select('destination_city_name')
          .eq('account_id', profile.account_id)
          .not('destination_city_name', 'is', null);

        const uniqueCarriers = [...new Set(carrierData?.map(d => d.carrier_name) || [])];
        const uniqueProducts = [...new Set(productData?.map(d => d.product_name) || [])];
        const uniqueRegions = regionData?.map(r => r.name) || [];
        const uniqueOriginCities = [...new Set(originCityData?.map(d => d.origin_city_name) || [])];
        const uniqueDestCities = [...new Set(destCityData?.map(d => d.destination_city_name) || [])];

        setCarriers(uniqueCarriers.sort());
        setProducts(uniqueProducts.sort());
        setRegions(uniqueRegions.sort());
        setOriginCities(uniqueOriginCities.sort());
        setDestinationCities(uniqueDestCities.sort());
      } catch (error) {
        console.error('Error loading filter options:', error);
      } finally {
        setLoading(false);
      }
    }

    loadFilterOptions();
  }, [profile?.account_id]);

  // Filter products by selected carrier
  useEffect(() => {
    async function filterProductsByCarrier() {
      if (!profile?.account_id) return;
      
      if (!filters.carrier) {
        setFilteredProducts(products);
        return;
      }

      try {
        const { data } = await supabase
          .from('one_db')
          .select('product_name')
          .eq('account_id', profile.account_id)
          .eq('carrier_name', filters.carrier)
          .not('product_name', 'is', null);

        const uniqueProducts = [...new Set(data?.map(d => d.product_name) || [])];
        setFilteredProducts(uniqueProducts.sort());

        // Reset product if it's not in the filtered list and carrier changed
        if (prevCarrierRef.current !== undefined && 
            prevCarrierRef.current !== filters.carrier && 
            filters.product && 
            !uniqueProducts.includes(filters.product)) {
          handleChange('product', '');
        }
      } catch (error) {
        console.error('Error filtering products:', error);
        setFilteredProducts(products);
      }

      prevCarrierRef.current = filters.carrier;
    }

    filterProductsByCarrier();
  }, [filters.carrier, products, profile?.account_id]);

  const handleChange = useCallback((field: keyof Filters, value: string | string[] | undefined) => {
    onChange({
      ...filters,
      [field]: value
    } as Filters);
  }, [filters, onChange]);

  const handleReset = () => {
    if (onReset) {
      onReset();
    } else {
      onChange({
        startDate: '',
        endDate: '',
        carrier: '',
        product: '',
        originCity: '',
        destinationCity: '',
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
      <div className="grid grid-cols-1 md:grid-cols-3 lg:grid-cols-9 gap-4">
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
            {filteredProducts.map(product => (
              <option key={product} value={product}>{product}</option>
            ))}
          </select>
        </div>

        {/* Origin City */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <MapPin className="w-4 h-4 inline mr-1" />
            Origin City
            <SmartTooltip content="Filter by origin city (where shipments depart from). Shows only shipments originating from the selected city." />
          </label>
          <select
            value={filters.originCity || ''}
            onChange={(e) => handleChange('originCity', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={loading}
          >
            <option value="">All Origins</option>
            {originCities.map(city => (
              <option key={city} value={city}>{city}</option>
            ))}
          </select>
        </div>

        {/* Destination City */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <MapPin className="w-4 h-4 inline mr-1" />
            Destination City
            <SmartTooltip content="Filter by destination city (where shipments arrive). Shows only shipments delivered to the selected city." />
          </label>
          <select
            value={filters.destinationCity || ''}
            onChange={(e) => handleChange('destinationCity', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            disabled={loading}
          >
            <option value="">All Destinations</option>
            {destinationCities.map(city => (
              <option key={city} value={city}>{city}</option>
            ))}
          </select>
        </div>

        {/* Region and Direction filters removed - now in Regional Analysis tab */}

        {/* Equity Status moved to Product Analysis tab */}
      </div>
      </>
      )}
    </div>
  );
}
