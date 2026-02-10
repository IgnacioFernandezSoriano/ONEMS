import { ProcessedEvent } from '../../hooks/useProcessedEvents';
import { CheckSquare, Square, Clock, ArrowRight } from 'lucide-react';
import { useTranslation } from '@/hooks/useTranslation';

interface ProcessedEventsTableProps {
  records: ProcessedEvent[];
  selectedRecords: string[];
  onSelectRecord: (id: string) => void;
  onSelectAll: () => void;
}

export function ProcessedEventsTable({
  records,
  selectedRecords,
  onSelectRecord,
  onSelectAll,
}: ProcessedEventsTableProps) {
  const { t } = useTranslation();

  const formatDateTime = (dateString: string) => {
    const date = new Date(dateString);
    return date.toLocaleString('es-ES', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const formatMinutes = (minutes: number | null) => {
    if (minutes === null) return 'N/A';
    const hours = Math.floor(minutes / 60);
    const mins = minutes % 60;
    if (hours > 0) {
      return `${hours}h ${mins}m`;
    }
    return `${mins}m`;
  };

  const getReaderTypeBadge = (type: string) => {
    const badges = {
      entry: 'bg-blue-100 text-blue-700',
      exit: 'bg-green-100 text-green-700',
      mixed: 'bg-purple-100 text-purple-700',
    };
    return badges[type as keyof typeof badges] || 'bg-gray-100 text-gray-700';
  };

  const allSelected = records.length > 0 && selectedRecords.length === records.length;

  if (records.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-12 text-center">
        <div className="text-gray-400 mb-2">
          <Clock className="w-12 h-12 mx-auto" />
        </div>
        <p className="text-gray-600">{t('processed_events.no_records')}</p>
      </div>
    );
  }

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-6 py-3 text-left">
                <button
                  onClick={onSelectAll}
                  className="text-gray-600 hover:text-gray-900"
                  title={allSelected ? t('processed_events.deselect_all') : t('processed_events.select_all')}
                >
                  {allSelected ? (
                    <CheckSquare className="w-5 h-5" />
                  ) : (
                    <Square className="w-5 h-5" />
                  )}
                </button>
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('processed_events.tag_id')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('processed_events.postal_center')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('processed_events.reader_type')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('processed_events.entry_reader')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('processed_events.exit_reader')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('processed_events.entry_time')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('processed_events.exit_time')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('processed_events.transit_time')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('processed_events.adjusted_time')}
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {records.map((record) => {
              const isSelected = selectedRecords.includes(record.id);
              return (
                <tr
                  key={record.id}
                  className={`hover:bg-gray-50 transition-colors ${
                    isSelected ? 'bg-blue-50' : ''
                  }`}
                >
                  <td className="px-6 py-4">
                    <button
                      onClick={() => onSelectRecord(record.id)}
                      className="text-gray-600 hover:text-gray-900"
                    >
                      {isSelected ? (
                        <CheckSquare className="w-5 h-5 text-blue-600" />
                      ) : (
                        <Square className="w-5 h-5" />
                      )}
                    </button>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm font-mono text-gray-900">{record.tag_id}</span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">{record.postal_center_name}</div>
                    <div className="text-xs text-gray-500">{record.postal_center_code}</div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span
                      className={`px-2 py-1 text-xs font-medium rounded-full ${getReaderTypeBadge(
                        record.reader_type
                      )}`}
                    >
                      {record.reader_type.toUpperCase()}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm font-mono text-gray-700">{record.entry_reader_id}</span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm font-mono text-gray-700">
                      {record.exit_reader_id || (
                        <span className="text-gray-400 italic">N/A</span>
                      )}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm text-gray-900">{formatDateTime(record.entry_time)}</span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm text-gray-900">
                      {record.exit_time ? (
                        formatDateTime(record.exit_time)
                      ) : (
                        <span className="text-gray-400 italic">N/A</span>
                      )}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center gap-1 text-sm text-gray-900">
                      <Clock className="w-4 h-4 text-gray-400" />
                      {formatMinutes(record.transit_minutes)}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="flex items-center gap-1 text-sm text-gray-900">
                      <Clock className="w-4 h-4 text-blue-400" />
                      {formatMinutes(record.adjusted_minutes)}
                    </div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
