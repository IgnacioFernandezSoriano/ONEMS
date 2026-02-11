import { useState, useMemo } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { useAuth } from '@/contexts/AuthContext';
import { useJourneySegments } from '@/hooks/useJourneySegments';
import { JourneySegmentsFilters } from '@/components/diagnosis/JourneySegmentsFilters';
import { JourneySegmentsTable } from '@/components/diagnosis/JourneySegmentsTable';
import { Map, CheckCircle, AlertTriangle, XCircle, Clock } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';

export default function JourneySegments() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const {
    segments,
    filteredSegments,
    loading,
    error,
    refetch,
    applyFilters,
    exportToCSV,
    runReconstruction,
    isReconstructing,
  } = useJourneySegments(profile?.account_id || undefined);

  const [selectedSegments, setSelectedSegments] = useState<string[]>([]);

  const handleSelectSegment = (id: string) => {
    setSelectedSegments((prev) =>
      prev.includes(id) ? prev.filter((segmentId) => segmentId !== id) : [...prev, id]
    );
  };

  const handleSelectAll = () => {
    if (selectedSegments.length === filteredSegments.length) {
      setSelectedSegments([]);
    } else {
      setSelectedSegments(filteredSegments.map((s) => s.id));
    }
  };

  const handleExport = () => {
    const segmentsToExport = filteredSegments.filter((s) => selectedSegments.includes(s.id));
    exportToCSV(segmentsToExport);
  };

  const handleClearSelection = () => {
    setSelectedSegments([]);
  };

  const handleFilterChange = (filters: any) => {
    applyFilters(filters);
    setSelectedSegments([]); // Clear selection when filters change
  };

  const handleRunReconstruction = async () => {
    await runReconstruction();
    setSelectedSegments([]);
  };

  // Calculate KPIs
  const kpis = useMemo(() => {
    const total = filteredSegments.length;
    const onTime = filteredSegments.filter((s) => s.sla_compliance === 'on_time').length;
    const warning = filteredSegments.filter((s) => s.sla_compliance === 'warning').length;
    const critical = filteredSegments.filter((s) => s.sla_compliance === 'critical').length;
    const violated = filteredSegments.filter((s) => s.sla_compliance === 'violated').length;
    const noSla = filteredSegments.filter((s) => s.sla_compliance === 'no_sla').length;

    const avgTime =
      total > 0
        ? (
            filteredSegments.reduce((sum, s) => sum + (s.adjusted_time_minutes || 0), 0) / total
          ).toFixed(1)
        : '0.0';

    const onTimePercentage = total > 0 ? ((onTime / total) * 100).toFixed(1) : '0.0';

    return { total, onTime, warning, critical, violated, noSla, avgTime, onTimePercentage };
  }, [filteredSegments]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex items-center gap-3 text-gray-600">
          <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-gray-600"></div>
          <span>{t('journey_segments.loading')}</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-4">
        <p className="text-red-700">{t('journey_segments.error')}: {error}</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-purple-50 rounded-lg">
            <Map className="w-8 h-8 text-purple-600" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-2xl font-bold text-gray-900">{t('journey_segments.title')}</h1>
              <SmartTooltip content="Journey Segments reconstructs complete tag journeys from RFID events, calculating transit times and SLA compliance for both operational (within center) and distribution (between centers) segments." />
            </div>
            <p className="text-sm text-gray-600 mt-1">{t('journey_segments.description')}</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <button
            onClick={handleRunReconstruction}
            disabled={isReconstructing}
            className="flex items-center gap-2 px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 transition-colors disabled:bg-gray-300 disabled:cursor-not-allowed"
            title={t('journey_segments.run_reconstruction_tooltip')}
          >
            <Map className={`w-4 h-4 ${isReconstructing ? 'animate-spin' : ''}`} />
            {t('journey_segments.run_reconstruction')}
          </button>
          <button
            onClick={handleExport}
            disabled={selectedSegments.length === 0}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors disabled:bg-gray-300 disabled:cursor-not-allowed"
            title={t('journey_segments.export_tooltip')}
          >
            <Map className="w-4 h-4" />
            {t('journey_segments.export_csv')} ({selectedSegments.length})
          </button>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-4">
        {/* Total Segments */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('journey_segments.kpi.total')}</p>
              <p className="text-3xl font-bold text-gray-900">{kpis.total}</p>
              <p className="text-xs text-gray-500 mt-1">{t('journey_segments.kpi.segments')}</p>
            </div>
            <div className="p-3 bg-gray-50 rounded-lg">
              <Map className="w-6 h-6 text-gray-600" />
            </div>
          </div>
        </div>

        {/* On Time */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('journey_segments.kpi.on_time')}</p>
              <p className="text-3xl font-bold text-green-600">{kpis.onTime}</p>
              <p className="text-xs text-gray-500 mt-1">{kpis.onTimePercentage}%</p>
            </div>
            <div className="p-3 bg-green-50 rounded-lg">
              <CheckCircle className="w-6 h-6 text-green-600" />
            </div>
          </div>
        </div>

        {/* Warning */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('journey_segments.kpi.warning')}</p>
              <p className="text-3xl font-bold text-yellow-600">{kpis.warning}</p>
              <p className="text-xs text-gray-500 mt-1">
                {kpis.total > 0 ? ((kpis.warning / kpis.total) * 100).toFixed(1) : '0.0'}%
              </p>
            </div>
            <div className="p-3 bg-yellow-50 rounded-lg">
              <AlertTriangle className="w-6 h-6 text-yellow-600" />
            </div>
          </div>
        </div>

        {/* Critical */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('journey_segments.kpi.critical')}</p>
              <p className="text-3xl font-bold text-red-600">{kpis.critical + kpis.violated}</p>
              <p className="text-xs text-gray-500 mt-1">
                {kpis.total > 0
                  ? (((kpis.critical + kpis.violated) / kpis.total) * 100).toFixed(1)
                  : '0.0'}
                %
              </p>
            </div>
            <div className="p-3 bg-red-50 rounded-lg">
              <XCircle className="w-6 h-6 text-red-600" />
            </div>
          </div>
        </div>

        {/* Average Time */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('journey_segments.kpi.avg_time')}</p>
              <p className="text-3xl font-bold text-blue-600">{kpis.avgTime}</p>
              <p className="text-xs text-gray-500 mt-1">{t('journey_segments.kpi.minutes')}</p>
            </div>
            <div className="p-3 bg-blue-50 rounded-lg">
              <Clock className="w-6 h-6 text-blue-600" />
            </div>
          </div>
        </div>
      </div>

      {/* Filters */}
      <JourneySegmentsFilters onFilterChange={handleFilterChange} />

      {/* Bulk Actions Panel */}
      {selectedSegments.length > 0 && (
        <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              <CheckCircle className="w-5 h-5 text-blue-600" />
              <span className="text-sm font-medium text-blue-900">
                {t('journey_segments.selected_count', { count: selectedSegments.length })}
              </span>
            </div>
            <div className="flex items-center gap-3">
              <button
                onClick={handleExport}
                className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors text-sm"
              >
                {t('journey_segments.export_selected')}
              </button>
              <button
                onClick={handleClearSelection}
                className="px-4 py-2 bg-white text-gray-700 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors text-sm"
              >
                {t('journey_segments.clear_selection')}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Table */}
      <JourneySegmentsTable
        segments={filteredSegments}
        selectedSegments={selectedSegments}
        onSelectSegment={handleSelectSegment}
        onSelectAll={handleSelectAll}
      />
    </div>
  );
}
