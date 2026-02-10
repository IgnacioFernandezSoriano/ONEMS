import { useState, useEffect } from 'react';
import { Search, Filter, X } from 'lucide-react';
import { ProcessedEvent, ProcessedEventsFilters as Filters } from '../../hooks/useProcessedEvents';
import { supabase } from '../../lib/supabase';
import { useAuth } from '../../contexts/AuthContext';
import { useTranslation } from '@/hooks/useTranslation';

interface ProcessedEventsFiltersProps {
  records: ProcessedEvent[];
  onFilterChange: (filters: Filters) => void;
}

interface PostalCenter {
  id: string;
  name: string;
  code: string;
}

export function ProcessedEventsFilters({ records, onFilterChange }: ProcessedEventsFiltersProps) {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const [isExpanded, setIsExpanded] = useState(false);
  const [postalCenters, setPostalCenters] = useState<PostalCenter[]>([]);

  const [filters, setFilters] = useState<Filters>({
    search: '',
    postal_center_id: '',
    event_type: null,
    date_from: '',
    date_to: '',
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

  const handleFilterChange = (key: keyof Filters, value: any) => {
    const newFilters = { ...filters, [key]: value };
    setFilters(newFilters);
    onFilterChange(newFilters);
  };

  const handleReset = () => {
    const resetFilters: Filters = {
      search: '',
      postal_center_id: '',
      event_type: null,
      date_from: '',
      date_to: '',
    };
    setFilters(resetFilters);
    onFilterChange(resetFilters);
  };

  const activeFiltersCount = [
    filters.search,
    filters.postal_center_id,
    filters.event_type,
    filters.date_from,
    filters.date_to,
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
          <span className="font-medium text-gray-900">{t('processed_events.filters')}</span>
          {activeFiltersCount > 0 && (
            <span className="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-medium rounded-full">
              {activeFiltersCount} {t('processed_events.active')}
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
              {t('processed_events.reset')}
            </button>
          )}
          <span className="text-gray-400">{isExpanded ? '−' : '+'}</span>
        </div>
      </button>

      {/* Filters */}
      {isExpanded && (
        <div className="px-6 pb-6 space-y-4 border-t border-gray-200 pt-4">
          {/* Search */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-2">
              {t('processed_events.search')}
            </label>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 w-4 h-4 text-gray-400" />
              <input
                type="text"
                value={filters.search || ''}
                onChange={(e) => handleFilterChange('search', e.target.value)}
                placeholder={t('processed_events.search_placeholder')}
                className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
              {filters.search && (
                <button
                  onClick={() => handleFilterChange('search', '')}
                  className="absolute right-3 top-1/2 transform -translate-y-1/2 text-gray-400 hover:text-gray-600"
                >
                  <X className="w-4 h-4" />
                </button>
              )}
            </div>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
            {/* Postal Center */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('processed_events.postal_center')}
              </label>
              <select
                value={filters.postal_center_id || ''}
                onChange={(e) => handleFilterChange('postal_center_id', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('processed_events.all_centers')}</option>
                {postalCenters.map((center) => (
                  <option key={center.id} value={center.id}>
                    {center.code} - {center.name}
                  </option>
                ))}
              </select>
            </div>

            {/* Event Type */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('processed_events.event_type')}
              </label>
              <select
                value={filters.event_type || ''}
                onChange={(e) =>
                  handleFilterChange('event_type', e.target.value || null)
                }
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('processed_events.all_types')}</option>
                <option value="entry">{t('processed_events.type_entry')}</option>
                <option value="exit">{t('processed_events.type_exit')}</option>
              </select>
            </div>

            {/* Date From */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('processed_events.date_from')}
              </label>
              <input
                type="date"
                value={filters.date_from || ''}
                onChange={(e) => handleFilterChange('date_from', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {/* Date To */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t('processed_events.date_to')}
              </label>
              <input
                type="date"
                value={filters.date_to || ''}
                onChange={(e) => handleFilterChange('date_to', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
