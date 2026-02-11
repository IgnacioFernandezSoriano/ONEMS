import { useTranslation } from '@/hooks/useTranslation';
import { CompleteJourney } from '@/hooks/useCompleteJourneys';
import { CheckCircle, AlertTriangle, XCircle, Circle, MapPin } from 'lucide-react';
import { format } from 'date-fns';

interface CompleteJourneysTableProps {
  journeys: CompleteJourney[];
  selectedJourneys: string[];
  onSelectJourney: (id: string) => void;
  onSelectAll: () => void;
  onClearSelection: () => void;
}

export function CompleteJourneysTable({
  journeys,
  selectedJourneys,
  onSelectJourney,
  onSelectAll,
  onClearSelection,
}: CompleteJourneysTableProps) {
  const { t } = useTranslation();

  const getStatusIcon = (status: string, violations: number) => {
    if (violations === 0) {
      return <CheckCircle className="w-5 h-5 text-green-500" />;
    } else if (violations <= 2) {
      return <AlertTriangle className="w-5 h-5 text-yellow-500" />;
    } else {
      return <XCircle className="w-5 h-5 text-red-500" />;
    }
  };

  const getStatusClass = (status: string, violations: number) => {
    if (violations === 0) {
      return 'bg-green-100 text-green-800';
    } else if (violations <= 2) {
      return 'bg-yellow-100 text-yellow-800';
    } else {
      return 'bg-red-100 text-red-800';
    }
  };

  const getStatusLabel = (status: string, violations: number) => {
    if (violations === 0) return t('complete_journeys.compliance.on_time');
    if (violations <= 2) return t('complete_journeys.compliance.warning');
    return t('complete_journeys.compliance.critical');
  };

  const formatDuration = (minutes: number | null) => {
    if (!minutes) return '-';
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    return hours > 0 ? `${hours}h ${mins}m` : `${mins}m`;
  };

  if (journeys.length === 0) {
    return (
      <div className="text-center py-12 bg-white rounded-lg shadow">
        <MapPin className="w-12 h-12 text-gray-400 mx-auto mb-4" />
        <p className="text-gray-500">{t('complete_journeys.table.no_journeys')}</p>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow overflow-hidden">
      {selectedJourneys.length > 0 && (
        <div className="bg-blue-50 px-4 py-3 border-b border-blue-200 flex items-center justify-between">
          <span className="text-sm text-blue-700">
            {t('complete_journeys.table.selected', { count: selectedJourneys.length })}
          </span>
          <button
            onClick={onClearSelection}
            className="text-sm text-blue-600 hover:text-blue-800 font-medium"
          >
            {t('complete_journeys.table.clear_selection')}
          </button>
        </div>
      )}

      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left">
                <input
                  type="checkbox"
                  checked={selectedJourneys.length === journeys.length}
                  onChange={onSelectAll}
                  className="rounded border-gray-300"
                />
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.tag_id')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.segments')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.centers')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.start_time')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.total_time')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.compliance')}
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {journeys.map((journey) => (
              <tr key={journey.id} className="hover:bg-gray-50">
                <td className="px-6 py-4">
                  <input
                    type="checkbox"
                    checked={selectedJourneys.includes(journey.tag_id)}
                    onChange={() => onSelectJourney(journey.tag_id)}
                    className="rounded border-gray-300"
                  />
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="text-sm font-medium text-gray-900">{journey.tag_id}</div>
                  {journey.is_missroute && (
                    <div className="text-xs text-red-600">Missroute</div>
                  )}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="text-sm text-gray-900">{journey.total_segments}</div>
                  <div className="text-xs text-gray-500">
                    {journey.on_time_segments} on time
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="text-sm text-gray-900">{journey.total_centers_visited}</div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="text-sm text-gray-900">
                    {journey.first_event_timestamp
                      ? format(new Date(journey.first_event_timestamp), 'dd/MM/yyyy HH:mm')
                      : '-'}
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="text-sm text-gray-900">
                    {formatDuration(journey.total_adjusted_time_minutes)}
                  </div>
                  <div className="text-xs text-gray-500">
                    Op: {formatDuration(journey.total_operational_time_minutes)} | 
                    Dist: {formatDuration(journey.total_distribution_time_minutes)}
                  </div>
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <div className="flex items-center gap-2">
                    {getStatusIcon(journey.journey_status, journey.total_sla_violations)}
                    <span
                      className={`inline-flex px-2 py-1 text-xs font-semibold rounded-full ${getStatusClass(
                        journey.journey_status,
                        journey.total_sla_violations
                      )}`}
                    >
                      {getStatusLabel(journey.journey_status, journey.total_sla_violations)}
                    </span>
                  </div>
                  {journey.total_sla_violations > 0 && (
                    <div className="text-xs text-red-600 mt-1">
                      {journey.total_sla_violations} violations
                    </div>
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
