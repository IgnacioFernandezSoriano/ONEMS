import { useTranslation } from '@/hooks/useTranslation';
import { CompleteJourney } from '@/hooks/useCompleteJourneys';
import { CheckCircle, AlertTriangle, XCircle, Circle, Layers } from 'lucide-react';

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

  const getComplianceIcon = (compliance: string) => {
    switch (compliance) {
      case 'on_time':
        return <CheckCircle className="w-5 h-5 text-green-500" />;
      case 'warning':
        return <AlertTriangle className="w-5 h-5 text-yellow-500" />;
      case 'critical':
      case 'violated':
        return <XCircle className="w-5 h-5 text-red-500" />;
      case 'mixed':
        return <Layers className="w-5 h-5 text-blue-500" />;
      default:
        return <Circle className="w-5 h-5 text-gray-400" />;
    }
  };

  const getComplianceClass = (compliance: string) => {
    switch (compliance) {
      case 'on_time':
        return 'bg-green-100 text-green-800';
      case 'warning':
        return 'bg-yellow-100 text-yellow-800';
      case 'critical':
      case 'violated':
        return 'bg-red-100 text-red-800';
      case 'mixed':
        return 'bg-blue-100 text-blue-800';
      default:
        return 'bg-gray-100 text-gray-800';
    }
  };

  if (journeys.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-8 text-center">
        <p className="text-gray-500">{t('complete_journeys.table.no_journeys')}</p>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
      {/* Selection header */}
      {selectedJourneys.length > 0 && (
        <div className="bg-purple-50 border-b border-purple-200 px-4 py-2 flex items-center justify-between">
          <span className="text-sm text-purple-700">
            {t('complete_journeys.table.selected', { count: selectedJourneys.length })}
          </span>
          <button
            onClick={onClearSelection}
            className="text-sm text-purple-600 hover:text-purple-800"
          >
            {t('complete_journeys.table.clear_selection')}
          </button>
        </div>
      )}

      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-4 py-3 text-left">
                <input
                  type="checkbox"
                  checked={selectedJourneys.length === journeys.length && journeys.length > 0}
                  onChange={onSelectAll}
                  className="rounded border-gray-300 text-purple-600 focus:ring-purple-500"
                />
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.tag_id')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.segments')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.centers')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.start_time')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.total_time')}
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('complete_journeys.table.compliance')}
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {journeys.map((journey) => (
              <tr
                key={journey.id}
                className={`hover:bg-gray-50 ${
                  selectedJourneys.includes(journey.id) ? 'bg-purple-50' : ''
                }`}
              >
                <td className="px-4 py-3">
                  <input
                    type="checkbox"
                    checked={selectedJourneys.includes(journey.id)}
                    onChange={() => onSelectJourney(journey.id)}
                    className="rounded border-gray-300 text-purple-600 focus:ring-purple-500"
                  />
                </td>
                <td className="px-4 py-3 text-sm font-medium text-gray-900">
                  {journey.tag_id}
                </td>
                <td className="px-4 py-3 text-sm text-gray-600">
                  <div className="flex flex-col">
                    <span className="font-medium">{journey.total_segments} total</span>
                    <span className="text-xs text-gray-500">
                      {journey.operational_segments} op / {journey.distribution_segments} dist
                    </span>
                  </div>
                </td>
                <td className="px-4 py-3 text-sm text-gray-600">
                  <div className="max-w-xs truncate" title={journey.centers_visited.join(' → ')}>
                    {journey.centers_visited.slice(0, 3).join(' → ')}
                    {journey.centers_visited.length > 3 && ' ...'}
                  </div>
                </td>
                <td className="px-4 py-3 text-sm text-gray-600">
                  {new Date(journey.journey_start_timestamp).toLocaleString()}
                </td>
                <td className="px-4 py-3 text-sm text-gray-600">
                  <div className="flex flex-col">
                    <span className="font-medium">{journey.total_adjusted_time_minutes} min</span>
                    <span className="text-xs text-gray-500">
                      Op: {journey.total_operational_time_minutes} / Dist: {journey.total_distribution_time_minutes}
                    </span>
                  </div>
                </td>
                <td className="px-4 py-3">
                  <div className="flex items-center gap-2">
                    {getComplianceIcon(journey.overall_sla_compliance)}
                    <span
                      className={`px-2 py-1 text-xs font-medium rounded-full ${getComplianceClass(
                        journey.overall_sla_compliance
                      )}`}
                    >
                      {t(`complete_journeys.compliance.${journey.overall_sla_compliance}`)}
                    </span>
                  </div>
                  <div className="text-xs text-gray-500 mt-1">
                    {journey.segments_on_time} OK / {journey.segments_warning} ⚠ / {journey.segments_critical + journey.segments_violated} ✗
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
