import { useState, useEffect } from 'react';
import { Search, Filter, X } from 'lucide-react';
import { supabase } from '@/lib/supabase';
import { useAuth } from '@/contexts/AuthContext';
import { useTranslation } from '@/hooks/useTranslation';

export interface ReadersFiltersState {
  search: string;
  carrier_id: string;
  postal_center_id: string;
  reader_type: string;
  assignment_status: string;
  mobility_status: string;
}

interface ReadersFiltersProps {
  onFilterChange: (filters: ReadersFiltersState) => void;
}

interface PostalCenter {
  id: string;
  name: string;
  code: string;
}

interface Carrier {
  id: string;
  name: string;
}

export function ReadersFilters({ onFilterChange }: ReadersFiltersProps) {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const [isExpanded, setIsExpanded] = useState(false);
  const [postalCenters, setPostalCenters] = useState<PostalCenter[]>([]);
  const [carriers, setCarriers] = useState<Carrier[]>([]);

  const [filters, setFilters] = useState<ReadersFiltersState>({
    search: '',
    carrier_id: '',
    postal_center_id: '',
    reader_type: '',
    assignment_status: '',
    mobility_status: '',
  });

  // Fetch postal centers
  useEffect(() => {
    const fetchPostalCenters = async () => {
      if (!profile?.account_id) return;

      const { data, error } = await supabase
        .from('postal_centers')
        .select('id, name, code')
        .eq('account_id', profile.account_id)
        .order('name');

      if (data && !error) {
        setPostalCenters(data);
      }
    };

    fetchPostalCenters();
  }, [profile?.account_id]);

  // Fetch carriers
  useEffect(() => {
    const fetchCarriers = async () => {
      if (!profile?.account_id) return;

      const { data, error } = await supabase
        .from('carriers')
        .select('id, name')
        .eq('account_id', profile.account_id)
        .order('name');

      if (data && !error) {
        setCarriers(data);
      }
    };

    fetchCarriers();
  }, [profile?.account_id]);

  const handleFilterChange = (key: keyof ReadersFiltersState, value: string) => {
    const newFilters = { ...filters, [key]: value };
    setFilters(newFilters);
    onFilterChange(newFilters);
  };

  const handleReset = () => {
    const resetFilters: ReadersFiltersState = {
      search: '',
      carrier_id: '',
      postal_center_id: '',
      reader_type: '',
      assignment_status: '',
      mobility_status: '',
    };
    setFilters(resetFilters);
    onFilterChange(resetFilters);
  };

  const activeFiltersCount = [
    filters.search,
    filters.carrier_id,
    filters.postal_center_id,
    filters.reader_type,
    filters.assignment_status,
    filters.mobility_status,
  ].filter(Boolean).length;

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200">
      {/* Header */}
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className="w-full px-6 py-4 flex items-center justify-between hover:bg-gray-50 transition-colors"
      >
        <div className="flex items-center gap-3">
          <Filter className="w-5 h-5 text-gray-600" />
          <span className="font-medium text-gray-900">{t('readers_management.filters')}</span>
          {activeFiltersCount > 0 && (
            <span className="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-medium rounded-full">
              {activeFiltersCount} {t('readers_management.active')}
            </span>
          )}
        </div>
        <div className="flex items-center gap-2">
          {activeFiltersCount > 0 && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                handleReset();
              }}
              className="px-3 py-1 text-sm text-gray-600 hover:text-gray-900 hover:bg-gray-100 rounded transition-colors"
            >
              {t('readers_management.reset')}
            </button>
          )}
          <span className="text-gray-400">
            {isExpanded ? '−' : '+'}
          </span>
        </div>
      </button>

      {/* Filters Content */}
      {isExpanded && (
        <div className="px-6 pb-6 border-t border-gray-200">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4 mt-4">
            {/* Search */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('readers_management.search')}
              </label>
              <div className="relative">
                <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
                <input
                  type="text"
                  value={filters.search}
                  onChange={(e) => handleFilterChange('search', e.target.value)}
                  placeholder={t('readers_management.search_placeholder')}
                  className="w-full pl-10 pr-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
                {filters.search && (
                  <button
                    onClick={() => handleFilterChange('search', '')}
                    className="absolute right-3 top-1/2 transform -translate-y-1/2"
                  >
                    <X className="w-4 h-4 text-gray-400 hover:text-gray-600" />
                  </button>
                )}
              </div>
            </div>

            {/* Carrier */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('readers_management.carrier')}
              </label>
              <select
                value={filters.carrier_id}
                onChange={(e) => handleFilterChange('carrier_id', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('readers_management.all_carriers')}</option>
                {carriers.map((carrier) => (
                  <option key={carrier.id} value={carrier.id}>
                    {carrier.name}
                  </option>
                ))}
              </select>
            </div>

            {/* Postal Center */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('readers_management.postal_center')}
              </label>
              <select
                value={filters.postal_center_id}
                onChange={(e) => handleFilterChange('postal_center_id', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('readers_management.all_centers')}</option>
                <option value="unassigned">{t('readers_management.unassigned')}</option>
                {postalCenters.map((center) => (
                  <option key={center.id} value={center.id}>
                    {center.name}
                  </option>
                ))}
              </select>
            </div>

            {/* Reader Type */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('readers_management.reader_type')}
              </label>
              <select
                value={filters.reader_type}
                onChange={(e) => handleFilterChange('reader_type', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('readers_management.all_types')}</option>
                <option value="Entry">{t('readers_management.entry')}</option>
                <option value="Exit">{t('readers_management.exit')}</option>
                <option value="Mixed">{t('readers_management.mixed')}</option>
              </select>
            </div>

            {/* Assignment Status */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('readers_management.assignment_status')}
              </label>
              <select
                value={filters.assignment_status}
                onChange={(e) => handleFilterChange('assignment_status', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('readers_management.all_statuses')}</option>
                <option value="assigned">{t('readers_management.assigned')}</option>
                <option value="unassigned">{t('readers_management.unassigned')}</option>
              </select>
            </div>

            {/* Mobility Status */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('readers_management.mobility_status')}
              </label>
              <select
                value={filters.mobility_status}
                onChange={(e) => handleFilterChange('mobility_status', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('readers_management.all_mobility')}</option>
                <option value="mobile">{t('readers_management.has_history')}</option>
                <option value="fixed">{t('readers_management.no_history')}</option>
              </select>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
