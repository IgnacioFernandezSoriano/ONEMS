import { useState } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { useAuth } from '@/contexts/AuthContext';
import { useCompleteJourneys } from '@/hooks/useCompleteJourneys';
import { CompleteJourneysFilters } from '@/components/diagnosis/CompleteJourneysFilters';
import { CompleteJourneysTable } from '@/components/diagnosis/CompleteJourneysTable';
import { Route, CheckCircle, AlertTriangle, XCircle, Clock, TrendingUp } from 'lucide-react';
import { SmartTooltip } from '@/components/common/SmartTooltip';

export default function CompleteJourneys() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const {
    journeys,
    filteredJourneys,
    loading,
    error,
    refetch,
    applyFilters,
    exportToCSV,
    runAssembly,
    isAssembling,
  } = useCompleteJourneys(profile?.account_id || undefined);

  const [selectedJourneys, setSelectedJourneys] = useState<string[]>([]);

  const handleSelectJourney = (id: string) => {
    setSelectedJourneys((prev) =>
      prev.includes(id) ? prev.filter((journeyId) => journeyId !== id) : [...prev, id]
    );
  };

  const handleSelectAll = () => {
    if (selectedJourneys.length === filteredJourneys.length) {
      setSelectedJourneys([]);
    } else {
      setSelectedJourneys(filteredJourneys.map((j) => j.id));
    }
  };

  const handleExport = () => {
    const journeysToExport = filteredJourneys.filter((j) => selectedJourneys.includes(j.id));
    exportToCSV(journeysToExport);
  };

  const handleClearSelection = () => {
    setSelectedJourneys([]);
  };

  const handleFilterChange = (filters: any) => {
    applyFilters(filters);
    setSelectedJourneys([]);
  };

  // Calculate KPIs
  const totalJourneys = journeys.length;
  const journeysOnTime = journeys.filter((j) => j.overall_sla_compliance === 'on_time').length;
  const journeysWarning = journeys.filter((j) => j.overall_sla_compliance === 'warning').length;
  const journeysCritical = journeys.filter((j) => j.overall_sla_compliance === 'critical').length;
  const avgTotalTime =
    journeys.length > 0
      ? journeys.reduce((sum, j) => sum + j.total_adjusted_time_minutes, 0) / journeys.length
      : 0;

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
        <div>
          <div className="flex items-center gap-2">
            <Route className="h-6 w-6 text-purple-600" />
            <h1 className="text-2xl font-bold text-gray-900">
              {t('complete_journeys.title')}
            </h1>
            <SmartTooltip content={t('complete_journeys.description')} />
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={runAssembly}
            disabled={isAssembling}
            className="px-4 py-2 bg-purple-600 text-white rounded-lg hover:bg-purple-700 disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
          >
            <TrendingUp className="h-4 w-4" />
            {isAssembling ? t('complete_journeys.assembling') : t('complete_journeys.run_assembly')}
          </button>
          {selectedJourneys.length > 0 && (
            <button
              onClick={handleExport}
              className="px-4 py-2 bg-white border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 flex items-center gap-2"
            >
              {t('complete_journeys.export_csv', { count: selectedJourneys.length })}
            </button>
          )}
        </div>
      </div>

      {/* KPIs */}
      <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
        <div className="bg-white p-4 rounded-lg shadow border border-gray-200">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">{t('complete_journeys.kpi.total')}</p>
              <p className="text-2xl font-bold text-gray-900">{totalJourneys}</p>
              <p className="text-xs text-gray-500">{t('complete_journeys.kpi.journeys')}</p>
            </div>
            <Route className="h-8 w-8 text-gray-400" />
          </div>
        </div>

        <div className="bg-white p-4 rounded-lg shadow border border-gray-200">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">{t('complete_journeys.kpi.on_time')}</p>
              <p className="text-2xl font-bold text-green-600">{journeysOnTime}</p>
              <p className="text-xs text-gray-500">
                {totalJourneys > 0 ? ((journeysOnTime / totalJourneys) * 100).toFixed(1) : 0}%
              </p>
            </div>
            <CheckCircle className="h-8 w-8 text-green-500" />
          </div>
        </div>

        <div className="bg-white p-4 rounded-lg shadow border border-gray-200">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">{t('complete_journeys.kpi.warning')}</p>
              <p className="text-2xl font-bold text-yellow-600">{journeysWarning}</p>
              <p className="text-xs text-gray-500">
                {totalJourneys > 0 ? ((journeysWarning / totalJourneys) * 100).toFixed(1) : 0}%
              </p>
            </div>
            <AlertTriangle className="h-8 w-8 text-yellow-500" />
          </div>
        </div>

        <div className="bg-white p-4 rounded-lg shadow border border-gray-200">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">{t('complete_journeys.kpi.critical')}</p>
              <p className="text-2xl font-bold text-red-600">{journeysCritical}</p>
              <p className="text-xs text-gray-500">
                {totalJourneys > 0 ? ((journeysCritical / totalJourneys) * 100).toFixed(1) : 0}%
              </p>
            </div>
            <XCircle className="h-8 w-8 text-red-500" />
          </div>
        </div>

        <div className="bg-white p-4 rounded-lg shadow border border-gray-200">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600">{t('complete_journeys.kpi.avg_time')}</p>
              <p className="text-2xl font-bold text-blue-600">{avgTotalTime.toFixed(1)}</p>
              <p className="text-xs text-gray-500">{t('complete_journeys.kpi.minutes')}</p>
            </div>
            <Clock className="h-8 w-8 text-blue-500" />
          </div>
        </div>
      </div>

      {/* Filters */}
      <CompleteJourneysFilters onFilterChange={handleFilterChange} />

      {/* Table */}
      <CompleteJourneysTable
        journeys={filteredJourneys}
        selectedJourneys={selectedJourneys}
        onSelectJourney={handleSelectJourney}
        onSelectAll={handleSelectAll}
        onClearSelection={handleClearSelection}
      />
    </div>
  );
}
