import { useState, useEffect } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/lib/supabase';
import { Filter, X, RotateCcw } from 'lucide-react';

interface JourneySegmentsFiltersProps {
  onFilterChange: (filters: any) => void;
}

export function JourneySegmentsFilters({ onFilterChange }: JourneySegmentsFiltersProps) {
  const { t } = useTranslation();
  const { profile } = useAuth();

  const [search, setSearch] = useState('');
  const [segmentType, setSegmentType] = useState<string>('');
  const [postalCenterId, setPostalCenterId] = useState('');
  const [fromPostalCenterId, setFromPostalCenterId] = useState('');
  const [toPostalCenterId, setToPostalCenterId] = useState('');
  const [slaCompliance, setSlaCompliance] = useState('');
  const [dateFrom, setDateFrom] = useState('');
  const [dateTo, setDateTo] = useState('');

  const [postalCenters, setPostalCenters] = useState<any[]>([]);

  useEffect(() => {
    loadPostalCenters();
  }, [profile?.account_id]);

  const loadPostalCenters = async () => {
    if (!profile?.account_id) return;

    try {
      const { data, error } = await supabase
        .from('postal_centers')
        .select('id, code, name')
        .eq('account_id', profile.account_id)
        .order('name');

      if (error) throw error;
      setPostalCenters(data || []);
    } catch (error) {
      console.error('Error loading postal centers:', error);
    }
  };

  const handleApplyFilters = () => {
    onFilterChange({
      search: search || undefined,
      segment_type: segmentType || null,
      postal_center_id: postalCenterId || undefined,
      from_postal_center_id: fromPostalCenterId || undefined,
      to_postal_center_id: toPostalCenterId || undefined,
      sla_compliance: slaCompliance || undefined,
      date_from: dateFrom || undefined,
      date_to: dateTo || undefined,
    });
  };

  const handleClearFilters = () => {
    setSearch('');
    setSegmentType('');
    setPostalCenterId('');
    setFromPostalCenterId('');
    setToPostalCenterId('');
    setSlaCompliance('');
    setDateFrom('');
    setDateTo('');
    onFilterChange({});
  };

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
      <div className="flex items-center justify-between mb-4">
        <div className="flex items-center gap-2">
          <Filter className="w-5 h-5 text-gray-600" />
          <h3 className="text-lg font-semibold text-gray-900">{t('journey_segments.filters.title')}</h3>
        </div>
        <button
          onClick={handleClearFilters}
          className="flex items-center gap-2 px-3 py-1.5 text-sm text-gray-700 bg-gray-100 hover:bg-gray-200 rounded-lg transition-colors"
          title="Reset all filters"
        >
          <RotateCcw className="w-4 h-4" />
          Reset
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Search */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('journey_segments.filters.search')}
          </label>
          <input
            type="text"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t('journey_segments.filters.search_placeholder')}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
        </div>

        {/* Segment Type */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('journey_segments.filters.segment_type')}
          </label>
          <select
            value={segmentType}
            onChange={(e) => setSegmentType(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          >
            <option value="">{t('journey_segments.filters.all_types')}</option>
            <option value="operational">{t('journey_segments.filters.operational')}</option>
            <option value="distribution">{t('journey_segments.filters.distribution')}</option>
          </select>
        </div>

        {/* Postal Center (for operational) */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('journey_segments.filters.postal_center')}
          </label>
          <select
            value={postalCenterId}
            onChange={(e) => setPostalCenterId(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          >
            <option value="">{t('journey_segments.filters.all_centers')}</option>
            {postalCenters.map((center) => (
              <option key={center.id} value={center.id}>
                {center.code} - {center.name}
              </option>
            ))}
          </select>
        </div>

        {/* SLA Compliance */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('journey_segments.filters.sla_compliance')}
          </label>
          <select
            value={slaCompliance}
            onChange={(e) => setSlaCompliance(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          >
            <option value="">{t('journey_segments.filters.all_compliance')}</option>
            <option value="on_time">{t('journey_segments.filters.on_time')}</option>
            <option value="warning">{t('journey_segments.filters.warning')}</option>
            <option value="critical">{t('journey_segments.filters.critical')}</option>
            <option value="violated">{t('journey_segments.filters.violated')}</option>
            <option value="no_sla">{t('journey_segments.filters.no_sla')}</option>
          </select>
        </div>

        {/* From Postal Center (for distribution) */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('journey_segments.filters.from_center')}
          </label>
          <select
            value={fromPostalCenterId}
            onChange={(e) => setFromPostalCenterId(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          >
            <option value="">{t('journey_segments.filters.all_centers')}</option>
            {postalCenters.map((center) => (
              <option key={center.id} value={center.id}>
                {center.code} - {center.name}
              </option>
            ))}
          </select>
        </div>

        {/* To Postal Center (for distribution) */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('journey_segments.filters.to_center')}
          </label>
          <select
            value={toPostalCenterId}
            onChange={(e) => setToPostalCenterId(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          >
            <option value="">{t('journey_segments.filters.all_centers')}</option>
            {postalCenters.map((center) => (
              <option key={center.id} value={center.id}>
                {center.code} - {center.name}
              </option>
            ))}
          </select>
        </div>

        {/* Date From */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('journey_segments.filters.date_from')}
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
            {t('journey_segments.filters.date_to')}
          </label>
          <input
            type="date"
            value={dateTo}
            onChange={(e) => setDateTo(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-purple-500 focus:border-transparent"
          />
        </div>
      </div>

      {/* Action Buttons */}
      <div className="flex items-center gap-3 mt-4">
        <button
          onClick={handleApplyFilters}
          className="flex items-center gap-2 px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors"
        >
          <Filter className="w-4 h-4" />
          {t('journey_segments.filters.apply')}
        </button>
        <button
          onClick={handleClearFilters}
          className="flex items-center gap-2 px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors"
        >
          <X className="w-4 h-4" />
          {t('journey_segments.filters.clear')}
        </button>
      </div>
    </div>
  );
}
