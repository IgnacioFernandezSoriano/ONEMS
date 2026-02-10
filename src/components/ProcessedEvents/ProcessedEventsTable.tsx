import { ProcessedEvent } from '../../hooks/useProcessedEvents';
import { CheckSquare, Square, Link2, Link2Off } from 'lucide-react';
import { useTranslation } from '@/hooks/useTranslation';
import { SmartTooltip } from '../common/SmartTooltip';

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

  const getEventTypeBadge = (type: string) => {
    const badges = {
      entry: 'bg-blue-100 text-blue-700',
      exit: 'bg-green-100 text-green-700',
    };
    return badges[type as keyof typeof badges] || 'bg-gray-100 text-gray-700';
  };

  const getReaderTypeBadge = (type: string) => {
    const badges = {
      Entry: 'bg-blue-100 text-blue-700',
      Exit: 'bg-green-100 text-green-700',
      Mixed: 'bg-purple-100 text-purple-700',
    };
    return badges[type as keyof typeof badges] || 'bg-gray-100 text-gray-700';
  };

  const allSelected = records.length > 0 && selectedRecords.length === records.length;

  if (records.length === 0) {
    return (
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-12 text-center">
        <div className="text-gray-400 mb-2">
          <svg className="w-12 h-12 mx-auto" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 13V6a2 2 0 00-2-2H6a2 2 0 00-2 2v7m16 0v5a2 2 0 01-2 2H6a2 2 0 01-2-2v-5m16 0h-2.586a1 1 0 00-.707.293l-2.414 2.414a1 1 0 01-.707.293h-3.172a1 1 0 01-.707-.293l-2.414-2.414A1 1 0 006.586 13H4" />
          </svg>
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
                <div className="flex items-center gap-1">
                  {t('processed_events.pairing')}
                  <SmartTooltip content={t('processed_events.pairing_tooltip')} />
                </div>
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('processed_events.tag_id')}
                  <SmartTooltip content={t('processed_events.tag_id_tooltip')} />
                </div>
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('processed_events.postal_center')}
                  <SmartTooltip content={t('processed_events.postal_center_tooltip')} />
                </div>
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('processed_events.event_type')}
                  <SmartTooltip content={t('processed_events.event_type_tooltip')} />
                </div>
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('processed_events.reader_id')}
                  <SmartTooltip content={t('processed_events.reader_id_tooltip')} />
                </div>
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('processed_events.reader_type')}
                  <SmartTooltip content={t('processed_events.reader_type_tooltip')} />
                </div>
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('processed_events.timestamp')}
                  <SmartTooltip content={t('processed_events.timestamp_tooltip')} />
                </div>
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {records.map((record) => {
              const isSelected = selectedRecords.includes(record.id.toString());
              return (
                <tr
                  key={record.id}
                  className={`hover:bg-gray-50 transition-colors ${
                    isSelected ? 'bg-blue-50' : ''
                  }`}
                >
                  <td className="px-6 py-4">
                    <button
                      onClick={() => onSelectRecord(record.id.toString())}
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
                    {record.has_pair ? (
                      <div className="flex items-center gap-1 text-green-600" title={t('processed_events.has_pair')}>
                        <Link2 className="w-4 h-4" />
                      </div>
                    ) : (
                      <div className="flex items-center gap-1 text-orange-600" title={t('processed_events.no_pair')}>
                        <Link2Off className="w-4 h-4" />
                      </div>
                    )}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm font-mono text-gray-900">{record.tag_id}</span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">{record.postal_center_name_snapshot}</div>
                    <div className="text-xs text-gray-500">{record.postal_center_code_snapshot}</div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span
                      className={`px-2 py-1 text-xs font-medium rounded-full ${getEventTypeBadge(
                        record.event_type
                      )}`}
                    >
                      {record.event_type.toUpperCase()}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm font-mono text-gray-700">{record.reader_id_snapshot}</span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span
                      className={`px-2 py-1 text-xs font-medium rounded-full ${getReaderTypeBadge(
                        record.reader_type_snapshot
                      )}`}
                    >
                      {record.reader_type_snapshot}
                    </span>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <span className="text-sm text-gray-900">{formatDateTime(record.timestamp)}</span>
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
