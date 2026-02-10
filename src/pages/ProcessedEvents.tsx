import { useState, useMemo } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { useProcessedEvents, ProcessedEventsFilters as Filters } from '../hooks/useProcessedEvents';
import { ProcessedEventsFilters } from '../components/ProcessedEvents/ProcessedEventsFilters';
import { ProcessedEventsTable } from '../components/ProcessedEvents/ProcessedEventsTable';
import { ProcessedEventsBulkPanel } from '../components/ProcessedEvents/ProcessedEventsBulkPanel';
import { Database, CheckCircle, Activity, Package, Download } from 'lucide-react';
import { SmartTooltip } from '../components/common/SmartTooltip';
import { useTranslation } from '@/hooks/useTranslation';

export default function ProcessedEvents() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const { records, filteredRecords, loading, error, refetch, applyFilters, exportToCSV } =
    useProcessedEvents(profile?.account_id || undefined);

  const [selectedRecords, setSelectedRecords] = useState<string[]>([]);

  const handleSelectRecord = (id: string) => {
    setSelectedRecords((prev) =>
      prev.includes(id) ? prev.filter((recordId) => recordId !== id) : [...prev, id]
    );
  };

  const handleSelectAll = () => {
    if (selectedRecords.length === filteredRecords.length) {
      setSelectedRecords([]);
    } else {
      setSelectedRecords(filteredRecords.map((r) => r.id.toString()));
    }
  };

  const handleExport = () => {
    const recordsToExport = filteredRecords.filter((r) =>
      selectedRecords.includes(r.id.toString())
    );
    exportToCSV(recordsToExport);
  };

  const handleClearSelection = () => {
    setSelectedRecords([]);
  };

  const handleFilterChange = (filters: Filters) => {
    applyFilters(filters);
    setSelectedRecords([]); // Clear selection when filters change
  };

  // Calculate KPIs
  const kpis = useMemo(() => {
    const total = filteredRecords.length;
    const entryEvents = filteredRecords.filter((r) => r.event_type === 'entry').length;
    const exitEvents = filteredRecords.filter((r) => r.event_type === 'exit').length;
    const consolidated = filteredRecords.filter((r) => r.is_consolidated).length;
    const pending = total - consolidated;
    const avgRawCount =
      total > 0
        ? (
            filteredRecords.reduce((sum, r) => sum + r.raw_event_count, 0) / total
          ).toFixed(1)
        : '0';

    return {
      total,
      entryEvents,
      exitEvents,
      consolidated,
      pending,
      avgRawCount,
    };
  }, [filteredRecords]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex items-center gap-3 text-gray-600">
          <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-gray-600"></div>
          <span>{t('processed_events.loading')}</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-4">
        <p className="text-red-700">
          {t('processed_events.error')}: {error}
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-green-50 rounded-lg">
            <Database className="w-8 h-8 text-green-600" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-2xl font-bold text-gray-900">
                {t('processed_events.title')}
              </h1>
              <SmartTooltip content={t('processed_events.tooltip')} />
            </div>
            <p className="text-sm text-gray-600 mt-1">{t('processed_events.description')}</p>
          </div>
        </div>
        <button
          onClick={handleExport}
          disabled={selectedRecords.length === 0}
          className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors disabled:bg-gray-300 disabled:cursor-not-allowed"
          title={t('processed_events.export_selected')}
        >
          <Download className="w-4 h-4" />
          {t('processed_events.export_csv')} ({selectedRecords.length})
        </button>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Total Records */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('processed_events.total_events')}</p>
              <p className="text-3xl font-bold text-gray-900">{kpis.total}</p>
              <p className="text-xs text-gray-500 mt-1">
                {t('processed_events.processed_events')}
              </p>
            </div>
            <div className="p-3 bg-green-50 rounded-lg">
              <Database className="w-6 h-6 text-green-600" />
            </div>
          </div>
        </div>

        {/* Entry/Exit Distribution */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('processed_events.by_type')}</p>
              <div className="flex items-center gap-2 mt-2">
                <span className="text-sm font-medium text-blue-600">
                  {kpis.entryEvents} {t('processed_events.entry_short')}
                </span>
                <span className="text-gray-400">|</span>
                <span className="text-sm font-medium text-green-600">
                  {kpis.exitEvents} {t('processed_events.exit_short')}
                </span>
              </div>
              <p className="text-xs text-gray-500 mt-1">{t('processed_events.event_types')}</p>
            </div>
            <div className="p-3 bg-blue-50 rounded-lg">
              <Activity className="w-6 h-6 text-blue-600" />
            </div>
          </div>
        </div>

        {/* Consolidated Status */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('processed_events.consolidated_status')}</p>
              <div className="flex items-center gap-2 mt-2">
                <span className="text-sm font-medium text-green-600">
                  {kpis.consolidated} {t('processed_events.done')}
                </span>
                <span className="text-gray-400">|</span>
                <span className="text-sm font-medium text-yellow-600">
                  {kpis.pending} {t('processed_events.pending')}
                </span>
              </div>
              <p className="text-xs text-gray-500 mt-1">
                {t('processed_events.consolidation_progress')}
              </p>
            </div>
            <div className="p-3 bg-green-50 rounded-lg">
              <CheckCircle className="w-6 h-6 text-green-600" />
            </div>
          </div>
        </div>

        {/* Average Raw Count */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('processed_events.avg_raw_count')}</p>
              <p className="text-3xl font-bold text-blue-900">{kpis.avgRawCount}</p>
              <p className="text-xs text-gray-500 mt-1">
                {t('processed_events.raw_events_per_processed')}
              </p>
            </div>
            <div className="p-3 bg-orange-50 rounded-lg">
              <Package className="w-6 h-6 text-orange-600" />
            </div>
          </div>
        </div>
      </div>

      {/* Filters */}
      <ProcessedEventsFilters records={records} onFilterChange={handleFilterChange} />

      {/* Table */}
      <ProcessedEventsTable
        records={filteredRecords}
        selectedRecords={selectedRecords}
        onSelectRecord={handleSelectRecord}
        onSelectAll={handleSelectAll}
      />

      {/* Bulk Operations Panel */}
      <ProcessedEventsBulkPanel
        selectedCount={selectedRecords.length}
        totalCount={filteredRecords.length}
        onExport={handleExport}
        onClearSelection={handleClearSelection}
      />

      {/* Footer Info */}
      {records.length > 0 && (
        <div className="text-center text-sm text-gray-500">
          {t('processed_events.showing_records', {
            filtered: filteredRecords.length,
            total: records.length,
          })}
        </div>
      )}
    </div>
  );
}
