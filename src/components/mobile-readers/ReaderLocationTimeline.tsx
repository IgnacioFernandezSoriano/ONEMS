import { MapPin, Calendar, Clock, FileText } from 'lucide-react';
import { useReaderLocationHistory, type ReaderLocationHistory } from '@/hooks/useReaderLocationHistory';
import { useTranslation } from '@/hooks/useTranslation';

interface ReaderLocationTimelineProps {
  readerId: string;
}

export function ReaderLocationTimeline({ readerId }: ReaderLocationTimelineProps) {
  const { t } = useTranslation();
  const { history, loading, error } = useReaderLocationHistory(readerId);

  if (loading) {
    return (
      <div className="flex items-center justify-center py-8">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 text-red-700 dark:text-red-400 px-4 py-3 rounded-lg">
        {error}
      </div>
    );
  }

  if (history.length === 0) {
    return (
      <div className="text-center py-8 text-gray-500 dark:text-gray-400">
        <MapPin className="w-12 h-12 mx-auto mb-2 opacity-50" />
        <p>{t('mobile_readers.no_location_history')}</p>
      </div>
    );
  }

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleString('es-ES', {
      year: 'numeric',
      month: 'short',
      day: 'numeric',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const formatDuration = (days: number) => {
    if (days === 0) return t('mobile_readers.less_than_day');
    if (days === 1) return t('mobile_readers.one_day');
    return `${days} ${t('mobile_readers.days')}`;
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-semibold text-gray-900 dark:text-white">
          {t('mobile_readers.location_history')}
        </h3>
        <span className="text-sm text-gray-500 dark:text-gray-400">
          {history.length} {t('mobile_readers.assignments')}
        </span>
      </div>

      <div className="relative">
        {/* Timeline line */}
        <div className="absolute left-4 top-0 bottom-0 w-0.5 bg-gray-200 dark:bg-gray-700"></div>

        {/* Timeline items */}
        <div className="space-y-6">
          {history.map((entry: ReaderLocationHistory, index: number) => (
            <div key={entry.id} className="relative pl-10">
              {/* Timeline dot */}
              <div
                className={`absolute left-2 top-2 w-4 h-4 rounded-full border-2 ${
                  entry.is_current
                    ? 'bg-green-500 border-green-500 animate-pulse'
                    : 'bg-white dark:bg-gray-800 border-gray-300 dark:border-gray-600'
                }`}
              ></div>

              {/* Content card */}
              <div
                className={`bg-white dark:bg-gray-800 rounded-lg border p-4 ${
                  entry.is_current
                    ? 'border-green-500 shadow-md'
                    : 'border-gray-200 dark:border-gray-700'
                }`}
              >
                {/* Header */}
                <div className="flex items-start justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <MapPin
                      className={`w-5 h-5 ${
                        entry.is_current ? 'text-green-600' : 'text-gray-500 dark:text-gray-400'
                      }`}
                    />
                    <div>
                      <h4 className="font-semibold text-gray-900 dark:text-white">
                        {entry.postal_center_name}
                      </h4>
                      <p className="text-sm text-gray-500 dark:text-gray-400">
                        {entry.postal_center_code}
                      </p>
                    </div>
                  </div>
                  {entry.is_current && (
                    <span className="px-2 py-1 bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 text-xs font-medium rounded">
                      {t('mobile_readers.current')}
                    </span>
                  )}
                </div>

                {/* Dates */}
                <div className="grid grid-cols-2 gap-4 mb-2">
                  <div className="flex items-center gap-2 text-sm">
                    <Calendar className="w-4 h-4 text-gray-400" />
                    <div>
                      <p className="text-gray-500 dark:text-gray-400">
                        {t('mobile_readers.assigned')}
                      </p>
                      <p className="text-gray-900 dark:text-white font-medium">
                        {formatDate(entry.assigned_at)}
                      </p>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 text-sm">
                    <Calendar className="w-4 h-4 text-gray-400" />
                    <div>
                      <p className="text-gray-500 dark:text-gray-400">
                        {t('mobile_readers.unassigned')}
                      </p>
                      <p className="text-gray-900 dark:text-white font-medium">
                        {entry.unassigned_at
                          ? formatDate(entry.unassigned_at)
                          : t('mobile_readers.currently_active')}
                      </p>
                    </div>
                  </div>
                </div>

                {/* Duration */}
                <div className="flex items-center gap-2 text-sm mb-2">
                  <Clock className="w-4 h-4 text-gray-400" />
                  <span className="text-gray-700 dark:text-gray-300">
                    {t('mobile_readers.duration')}: {formatDuration(entry.duration_days)}
                  </span>
                </div>

                {/* Notes */}
                {entry.notes && (
                  <div className="flex items-start gap-2 text-sm mt-3 pt-3 border-t border-gray-200 dark:border-gray-700">
                    <FileText className="w-4 h-4 text-gray-400 mt-0.5" />
                    <div className="flex-1">
                      <p className="text-gray-500 dark:text-gray-400 mb-1">
                        {t('mobile_readers.notes')}:
                      </p>
                      <p className="text-gray-700 dark:text-gray-300">{entry.notes}</p>
                    </div>
                  </div>
                )}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
