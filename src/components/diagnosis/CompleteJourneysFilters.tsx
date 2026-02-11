import { useState } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { Filter, X } from 'lucide-react';

interface CompleteJourneysFiltersProps {
  onFilterChange: (filters: any) => void;
}

export function CompleteJourneysFilters({ onFilterChange }: CompleteJourneysFiltersProps) {
  const { t } = useTranslation();

  const [search, setSearch] = useState('');
  const [slaCompliance, setSlaCompliance] = useState('');
  const [minSegments, setMinSegments] = useState('');
  const [maxSegments, setMaxSegments] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');

  const handleApplyFilters = () => {
    onFilterChange({
      search: search || undefined,
      sla_compliance: slaCompliance || undefined,
      min_segments: minSegments ? parseInt(minSegments) : undefined,
      max_segments: maxSegments ? parseInt(maxSegments) : undefined,
      date_from: dateFrom || undefined,
      date_to: dateTo || undefined,
    });
  };

  const handleClearFilters = () => {
    setSearch('');
    setSlaCompliance('');
    setMinSegments('');
    setMaxSegments('');
    setDateFrom('');
    setDateTo('');
    onFilterChange({});
  };

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
      <div className="flex items-center gap-2 mb-4">
        <Filter className="w-5 h-5 text-gray-600" />
        <h3 className="text-lg font-semibold text-gray-900">{t('complete_journeys.filters.title')}</h3>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {/* Search */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('complete_journeys.filters.search')}
          </label>
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t('complete_journeys.filters.search_placeholder')}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
        </div>

        {/* SLA Compliance */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('complete_journeys.filters.sla_compliance')}
          </label>
          <select
            value={slaCompliance}
            onChange={(e) => setSlaCompliance(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          >
            <option value="">{t('complete_journeys.filters.all_status')}</option>
            <option value="on_time">{t('complete_journeys.compliance.on_time')}</option>
            <option value="warning">{t('complete_journeys.compliance.warning')}</option>
            <option value="critical">{t('complete_journeys.compliance.critical')}</option>
            <option value="violated">{t('complete_journeys.compliance.violated')}</option>
            <option value="no_sla">{t('complete_journeys.compliance.no_sla')}</option>
            <option value="mixed">{t('complete_journeys.compliance.mixed')}</option>
          </select>
        </div>

        {/* Min Segments */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('complete_journeys.filters.min_segments')}
          </label>
          <input
            type="number"
            value={minSegments}
            onChange={(e) => setMinSegments(e.target.value)}
            min="0"
            placeholder="0"
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
        </div>

        {/* Max Segments */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('complete_journeys.filters.max_segments')}
          </label>
          <input
            type="number"
            value={maxSegments}
            onChange={(e) => setMaxSegments(e.target.value)}
            min="0"
            placeholder="∞"
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
        </div>

        {/* Date From */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('complete_journeys.filters.date_from')}
          </label>
          <input
            type="date"
            value={dateFrom}
            onChange={(e) => setDateFrom(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
        </div>

        {/* Date To */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('complete_journeys.filters.date_to')}
          </label>
          <input
            type="date"
            value={dateTo}
            onChange={(e) => setDateTo(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
        </div>
      </div>

      <div className="flex gap-2 mt-4">
        <button
          onClick={handleApplyFilters}
          className="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 flex items-center gap-2"
        >
          <Filter className="w-4 h-4" />
          {t('complete_journeys.filters.apply')}
        </button>
        <button
          onClick={handleClearFilters}
          className="px-4 py-2 bg-white border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 flex items-center gap-2"
        >
          <X className="w-4 h-4" />
          {t('complete_journeys.filters.clear')}
        </button>
      </div>
    </div>
  );
}
