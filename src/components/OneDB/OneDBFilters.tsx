import React, { useState } from 'react';
import { Filter, RotateCcw } from 'lucide-react';
import { OneDBFilters as Filters, OneDBRecord } from '../../hooks/useOneDB';
import { SmartTooltip } from '../common/SmartTooltip';

import { useTranslation } from '@/hooks/useTranslation';
interface OneDBFiltersProps {
  records: OneDBRecord[];
  onFilterChange: (filters: Filters) => void;
}

export const OneDBFilters: React.FC<OneDBFiltersProps> = ({ records, onFilterChange }) => {
  const [isExpanded, setIsExpanded] = useState(false);
  const [filters, setFilters] = useState<Filters>({});

  // Extract unique values for dropdowns
  const carriers = Array.from(new Set(records.map((r) => r.carrier_name))).sort();
  const products = Array.from(new Set(records.map((r) => r.product_name))).sort();
  const originCities = Array.from(new Set(records.map((r) => r.origin_city_name))).sort();
  const destinationCities = Array.from(new Set(records.map((r) => r.destination_city_name))).sort();

  const handleFilterChange = (key: keyof Filters, value: any) => {
    const newFilters = { ...filters, [key]: value };
    setFilters(newFilters);
    onFilterChange(newFilters);
  };

  const clearFilters = () => {
    setFilters({});
    onFilterChange({});
  };

  const activeFilterCount = Object.values(filters).filter(
    (v) => v !== undefined && v !== null && v !== ''
  ).length;

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200">
      {/* Header */}
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className="w-full px-6 py-4 flex items-center justify-between hover:bg-gray-50 transition-colors"
      >
        <div className="flex items-center gap-3">
          <Filter className="w-5 h-5 text-gray-400" />
          <span className="font-medium text-gray-900">{t('stock.filters')}</span>
          <SmartTooltip content="Filter ONE DB records by search term, carrier, product, route, delivery status, or date range to narrow down your analysis." />
          {activeFilterCount > 0 && (
            <span className="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-medium rounded-full">
              {activeFilterCount} Active
            </span>
          )}
        </div>
        <div className="flex items-center gap-3">
          {activeFilterCount > 0 && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                clearFilters();
              }}
              className="flex items-center gap-2 px-3 py-1.5 text-sm text-gray-700 hover:text-gray-900 transition-colors"
              title="Reset filters"
            >
              <RotateCcw className="w-4 h-4" />
              Reset
            </button>
          )}
          <span className="text-gray-400">{isExpanded ? '▲' : '▼'}</span>
        </div>
      </button>

      {/* Filter Content */}
      {isExpanded && (
        <div className="px-6 pb-6 border-t border-gray-200">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
            {/* Search */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🔍</span>
                Search
                <SmartTooltip content="Search by Tag ID or Plan name. Use partial matches to find related records." />
              </label>
              <input
                type="text"
                value={filters.search || ''}
                onChange={(e) => handleFilterChange('search', e.target.value)}
                placeholder="Tag ID or Plan..."
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {/* Carrier */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🚚</span>
                Carrier
                <SmartTooltip content="Filter by specific carrier. Shows only shipments handled by the selected carrier." />
              </label>
              <select
                value={filters.carrier_name || ''}
                onChange={(e) => handleFilterChange('carrier_name', e.target.value || undefined)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">All Carriers</option>
                {carriers.map((carrier) => (
                  <option key={carrier} value={carrier}>
                    {carrier}
                  </option>
                ))}
              </select>
            </div>

            {/* Product */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📦</span>
                Product
                <SmartTooltip content="Filter by product/service type. Shows only shipments using the selected product." />
              </label>
              <select
                value={filters.product_name || ''}
                onChange={(e) => handleFilterChange('product_name', e.target.value || undefined)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">All Products</option>
                {products.map((product) => (
                  <option key={product} value={product}>
                    {product}
                  </option>
                ))}
              </select>
            </div>

            {/* Origin City */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📍</span>
                Origin City
                <SmartTooltip content="Filter by origin city. Shows only shipments that started from the selected city." />
              </label>
              <select
                value={filters.origin_city_name || ''}
                onChange={(e) =>
                  handleFilterChange('origin_city_name', e.target.value || undefined)
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">All Cities</option>
                {originCities.map((city) => (
                  <option key={city} value={city}>
                    {city}
                  </option>
                ))}
              </select>
            </div>

            {/* Destination City */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🎯</span>
                Destination City
                <SmartTooltip content="Filter by destination city. Shows only shipments delivered to the selected city." />
              </label>
              <select
                value={filters.destination_city_name || ''}
                onChange={(e) =>
                  handleFilterChange('destination_city_name', e.target.value || undefined)
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">All Cities</option>
                {destinationCities.map((city) => (
                  <option key={city} value={city}>
                    {city}
                  </option>
                ))}
              </select>
            </div>

            {/* On Time Delivery */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>⏱️</span>
                On-Time Delivery
                <SmartTooltip content="Filter by delivery performance. 'Yes' shows shipments delivered within standard, 'No' shows delayed shipments." />
              </label>
              <select
                value={
                  filters.on_time_delivery === undefined || filters.on_time_delivery === null
                    ? ''
                    : filters.on_time_delivery.toString()
                }
                onChange={(e) => {
                  const value = e.target.value;
                  handleFilterChange(
                    'on_time_delivery',
                    value === '' ? undefined : value === 'true'
                  );
                }}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">All Records</option>
                <option value="true">✓ On Time</option>
                <option value="false">✕ Delayed</option>
              </select>
            </div>

            {/* Date From */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📅</span>
                From Date
                <SmartTooltip content="Filter records sent on or after this date. Leave empty to include all records from the beginning." />
              </label>
              <input
                type="date"
                value={filters.date_from || ''}
                onChange={(e) => handleFilterChange('date_from', e.target.value || undefined)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {/* Date To */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📅</span>
                To Date
                <SmartTooltip content="Filter records sent on or before this date. Leave empty to include all records up to the present." />
              </label>
              <input
                type="date"
                value={filters.date_to || ''}
                onChange={(e) => handleFilterChange('date_to', e.target.value || undefined)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
