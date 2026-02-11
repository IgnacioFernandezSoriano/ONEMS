import { useState } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { useCompleteJourneys } from '@/hooks/useCompleteJourneys';
import { CompleteJourneysFilters } from '@/components/diagnosis/CompleteJourneysFilters';
import { CompleteJourneysTable } from '@/components/diagnosis/CompleteJourneysTable';
import { Route, CheckCircle, AlertTriangle, XCircle, Clock, Play, Download } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';

export default function CompleteJourneys() {
  const { t } = useTranslation();
  const {
    journeys,
    loading,
    error,
    setFilters,
    kpis,
    runAssembly,
    isAssembling,
  } = useCompleteJourneys();

  const [selectedJourneys, setSelectedJourneys] = useState<string[]>([]);

  const handleSelectJourney = (id: string) => {
    setSelectedJourneys((prev) =>
      prev.includes(id) ? prev.filter((journeyId) => journeyId !== id) : [...prev, id]
    );
  };

  const handleSelectAll = () => {
    if (selectedJourneys.length === journeys.length) {
      setSelectedJourneys([]);
    } else {
      setSelectedJourneys(journeys.map((j) => j.tag_id));
    }
  };

  const handleClearSelection = () => {
    setSelectedJourneys([]);
  };

  const handleFilterChange = (filters: any) => {
    setFilters(filters);
    setSelectedJourneys([]);
  };

  const handleRunAssembly = async () => {
    const result = await runAssembly();
    if (result?.success) {
      alert(result.message);
    }
  };

  const handleExport = () => {
    const journeysToExport = journeys.filter((j) => selectedJourneys.includes(j.tag_id));
    const csv = [
      ['Tag ID', 'Segments', 'Centers', 'Start Time', 'Total Time (min)', 'Status', 'Violations'].join(','),
      ...journeysToExport.map((j) =>
        [
          j.tag_id,
          j.total_segments,
          j.total_centers_visited,
          j.first_event_timestamp || '',
          j.total_adjusted_time_minutes || 0,
          j.journey_status,
          j.total_sla_violations,
        ].join(',')
      ),
    ].join('\n');

    const blob = new Blob([csv], { type: 'text/csv' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `complete-journeys-${new Date().toISOString().split('T')[0]}.csv`;
    a.click();
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">{t('common.loading')}</div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">{error}</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-purple-100 rounded-lg">
            <Route className="w-6 h-6 text-purple-600" />
          </div>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{t('complete_journeys.title')}</h1>
            <p className="text-sm text-gray-600">{t('complete_journeys.description')}</p>
          </div>
        </div>
        <div className="flex gap-2">
          <SmartTooltip content={t('complete_journeys.run_assembly')}>
            <button
              onClick={handleRunAssembly}
              disabled={isAssembling}
              className="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 disabled:opacity-50 flex items-center gap-2"
            >
              <Play className="w-4 h-4" />
              {isAssembling ? t('complete_journeys.assembling') : t('complete_journeys.run_assembly')}
            </button>
          </SmartTooltip>
          {selectedJourneys.length > 0 && (
            <SmartTooltip content={t('complete_journeys.export_csv', { count: selectedJourneys.length })}>
              <button
                onClick={handleExport}
                className="px-4 py-2 bg-gray-600 text-white rounded-lg hover:bg-gray-700 flex items-center gap-2"
              >
                <Download className="w-4 h-4" />
                CSV ({selectedJourneys.length})
              </button>
            </SmartTooltip>
          )}
        </div>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-gray-600">{t('complete_journeys.kpi.total')}</p>
              <p className="text-2xl font-bold text-gray-900">{kpis.total}</p>
              <p className="text-xs text-gray-500">{t('complete_journeys.kpi.journeys')}</p>
            </div>
            <Route className="w-8 h-8 text-gray-400" />
          </div>
        </div>

        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-gray-600">{t('complete_journeys.kpi.on_time')}</p>
              <p className="text-2xl font-bold text-green-600">{kpis.on_time}</p>
              <p className="text-xs text-gray-500">
                {kpis.total > 0 ? ((kpis.on_time / kpis.total) * 100).toFixed(1) : 0}%
              </p>
            </div>
            <CheckCircle className="w-8 h-8 text-green-500" />
          </div>
        </div>

        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-gray-600">{t('complete_journeys.kpi.warning')}</p>
              <p className="text-2xl font-bold text-yellow-600">{kpis.warning}</p>
              <p className="text-xs text-gray-500">
                {kpis.total > 0 ? ((kpis.warning / kpis.total) * 100).toFixed(1) : 0}%
              </p>
            </div>
            <AlertTriangle className="w-8 h-8 text-yellow-500" />
          </div>
        </div>

        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-gray-600">{t('complete_journeys.kpi.critical')}</p>
              <p className="text-2xl font-bold text-red-600">{kpis.critical}</p>
              <p className="text-xs text-gray-500">
                {kpis.total > 0 ? ((kpis.critical / kpis.total) * 100).toFixed(1) : 0}%
              </p>
            </div>
            <XCircle className="w-8 h-8 text-red-500" />
          </div>
        </div>

        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm font-medium text-gray-600">{t('complete_journeys.kpi.avg_time')}</p>
              <p className="text-2xl font-bold text-blue-600">{kpis.avg_time.toFixed(1)}</p>
              <p className="text-xs text-gray-500">{t('complete_journeys.kpi.minutes')}</p>
            </div>
            <Clock className="w-8 h-8 text-blue-500" />
          </div>
        </div>
      </div>

      {/* Filters */}
      <CompleteJourneysFilters onFilterChange={handleFilterChange} />

      {/* Table */}
      <CompleteJourneysTable
        journeys={journeys}
        selectedJourneys={selectedJourneys}
        onSelectJourney={handleSelectJourney}
        onSelectAll={handleSelectAll}
        onClearSelection={handleClearSelection}
      />
    </div>
  );
}
