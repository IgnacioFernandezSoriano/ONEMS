import React, { useEffect, useState } from 'react';
import { Calendar, Filter, RotateCcw, MapPin } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';

import { useTranslation } from '@/hooks/useTranslation';
interface ReportFiltersProps {
  filters: {
    startDate: string;
    endDate: string;
    carrier: string;
    product: string;
    originCity: string;
    destinationCity: string;
    complianceStatus?: string;
  };
  onChange: (filters: any) => void;
  onReset?: () => void;
}

export function ReportFilters({ filters, onChange, onReset }: ReportFiltersProps) {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const [carriers, setCarriers] = useState<string[]>([]);
  const [products, setProducts] = useState<string[]>([]);
  const [originCities, setOriginCities] = useState<string[]>([]);
  const [destinationCities, setDestinationCities] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [isCollapsed, setIsCollapsed] = useState(false);

  useEffect(() => {
    async function loadFilterOptions() {
      if (!profile?.account_id) return;

      try {
        setLoading(true);

        // Get unique carriers from one_db for this account
        const { data: carrierData } = await supabase
          .from('one_db')
          .select('carrier_name')
          .eq('account_id', profile.account_id)
          .not('carrier_name', 'is', null);

        // Get unique products from one_db for this account
        const { data: productData } = await supabase
          .from('one_db')
          .select('product_name')
          .eq('account_id', profile.account_id)
          .not('product_name', 'is', null);

        // Get unique origin cities
        const { data: originData } = await supabase
          .from('one_db')
          .select('origin_city_name')
          .eq('account_id', profile.account_id)
          .not('origin_city_name', 'is', null);

        // Get unique destination cities
        const { data: destinationData } = await supabase
          .from('one_db')
          .select('destination_city_name')
          .eq('account_id', profile.account_id)
          .not('destination_city_name', 'is', null);

        // Extract unique values
        const uniqueCarriers = [...new Set(carrierData?.map(d => d.carrier_name) || [])];
        const uniqueProducts = [...new Set(productData?.map(d => d.product_name) || [])];
        const uniqueOrigins = [...new Set(originData?.map(d => d.origin_city_name) || [])];
        const uniqueDestinations = [...new Set(destinationData?.map(d => d.destination_city_name) || [])];

        setCarriers(uniqueCarriers.sort());
        setProducts(uniqueProducts.sort());
        setOriginCities(uniqueOrigins.sort());
        setDestinationCities(uniqueDestinations.sort());
      } catch (error) {
        console.error('Error loading filter options:', error);
      } finally {
        setLoading(false);
      }
    }

    loadFilterOptions();
  }, [profile?.account_id]);

  const handleChange = (field: string, value: string) => {
    onChange({
      ...filters,
      [field]: value
    });
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
        originCity: '',
        destinationCity: ''
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
          <SmartTooltip content="Filters apply to all reporting views. Use them to narrow your analysis to specific time periods, carriers, products, or routes. Empty filters show all available data." />
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
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <Calendar className="w-4 h-4 inline mr-1" />
            Start Date
            <SmartTooltip content="Filter shipments sent on or after this date. Leave empty to include all historical data. Useful for analyzing specific time periods or recent performance." />
          </label>
          <input
            type="date"
            value={filters.startDate}
            onChange={(e) => handleChange('startDate', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <Calendar className="w-4 h-4 inline mr-1" />
            End Date
            <SmartTooltip content="Filter shipments sent on or before this date. Leave empty to include data up to today. Combine with Start Date to analyze a specific date range." />
          </label>
          <input
            type="date"
            value={filters.endDate}
            onChange={(e) => handleChange('endDate', e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Carrier
            <SmartTooltip content="Filter by specific carrier (e.g., DHL, FedEx). Shows only shipments handled by the selected carrier. Use to compare carrier performance or investigate specific carrier issues." />
          </label>
          <select
            value={filters.carrier}
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

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Product
            <SmartTooltip content="Filter by service type (e.g., Express 24h, Standard). Shows only shipments using the selected product. Use to analyze performance by service level or compare product offerings." />
          </label>
          <select
            value={filters.product}
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

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <MapPin className="w-4 h-4 inline mr-1" />
            Origin City
            <SmartTooltip content="Filter by departure city. When selected, shows performance FROM this city TO all destinations (or to specific destination if also filtered). Use to analyze outbound performance from a specific location." />
          </label>
          <select
            value={filters.originCity}
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

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <MapPin className="w-4 h-4 inline mr-1" />
            Destination City
            <SmartTooltip content="Filter by arrival city. When selected, shows performance TO this city FROM all origins (or from specific origin if also filtered). Use to analyze inbound performance to a specific location." />
          </label>
          <select
            value={filters.destinationCity}
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

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Compliance Status
            <SmartTooltip content="Select multiple compliance statuses to filter routes. Compliant (✅ meeting standard), Warning (⚠️ below standard but above critical), or Critical (🔴 below critical threshold with penalty)." />
          </label>
          <div className="border border-gray-300 rounded-lg p-2 bg-white">
            <label className="flex items-center gap-2 py-1 cursor-pointer hover:bg-gray-50 px-2 rounded">
              <input
                type="checkbox"
                checked={(filters.complianceStatus || '').includes('compliant')}
                onChange={(e) => {
                  const current = (filters.complianceStatus || '').split(',').filter(Boolean);
                  const updated = e.target.checked
                    ? [...current, 'compliant']
                    : current.filter(s => s !== 'compliant');
                  handleChange('complianceStatus', updated.join(','));
                }}
                className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
              />
              <span className="text-sm">✅ Compliant</span>
            </label>
            <label className="flex items-center gap-2 py-1 cursor-pointer hover:bg-gray-50 px-2 rounded">
              <input
                type="checkbox"
                checked={(filters.complianceStatus || '').includes('warning')}
                onChange={(e) => {
                  const current = (filters.complianceStatus || '').split(',').filter(Boolean);
                  const updated = e.target.checked
                    ? [...current, 'warning']
                    : current.filter(s => s !== 'warning');
                  handleChange('complianceStatus', updated.join(','));
                }}
                className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
              />
              <span className="text-sm">⚠️ Warning</span>
            </label>
            <label className="flex items-center gap-2 py-1 cursor-pointer hover:bg-gray-50 px-2 rounded">
              <input
                type="checkbox"
                checked={(filters.complianceStatus || '').includes('critical')}
                onChange={(e) => {
                  const current = (filters.complianceStatus || '').split(',').filter(Boolean);
                  const updated = e.target.checked
                    ? [...current, 'critical']
                    : current.filter(s => s !== 'critical');
                  handleChange('complianceStatus', updated.join(','));
                }}
                className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
              />
              <span className="text-sm">🔴 Critical</span>
            </label>
          </div>
        </div>
      </div>

      {/* Filter Guidance */}
      <div className="mt-4 p-3 bg-blue-50 border border-blue-200 rounded-lg">
        <h4 className="text-sm font-semibold text-blue-900 mb-1">Filter Analysis Guide</h4>
        <ul className="text-xs text-blue-800 space-y-1">
          <li>• <strong>No filters:</strong> View overall ecosystem performance across all routes and carriers</li>
          <li>• <strong>Origin only:</strong> Analyze outbound quality from one city to all destinations</li>
          <li>• <strong>Destination only:</strong> Analyze inbound quality to one city from all origins</li>
          <li>• <strong>Both cities:</strong> Analyze specific route performance (origin → destination)</li>
          <li>• <strong>Carrier/Product:</strong> Further narrow analysis to specific service providers or types</li>
        </ul>
      </div>
      </>
      )}
    </div>
  );
}
