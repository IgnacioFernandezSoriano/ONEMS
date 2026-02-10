import { Download, X } from 'lucide-react';
import { useTranslation } from '@/hooks/useTranslation';

interface ProcessedEventsBulkPanelProps {
  selectedCount: number;
  totalCount: number;
  onExport: () => void;
  onClearSelection: () => void;
}

export function ProcessedEventsBulkPanel({
  selectedCount,
  totalCount,
  onExport,
  onClearSelection,
}: ProcessedEventsBulkPanelProps) {
  const { t } = useTranslation();

  if (selectedCount === 0) return null;

  return (
    <div className="fixed bottom-6 left-1/2 transform -translate-x-1/2 z-50">
      <div className="bg-gray-900 text-white rounded-lg shadow-2xl px-6 py-4 flex items-center gap-6">
        <div className="flex items-center gap-2">
          <span className="font-medium">
            {selectedCount} {t('processed_events.selected_of')} {totalCount}
          </span>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={onExport}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-lg transition-colors"
          >
            <Download className="w-4 h-4" />
            {t('processed_events.export_csv')}
          </button>

          <button
            onClick={onClearSelection}
            className="flex items-center gap-2 px-4 py-2 bg-gray-700 hover:bg-gray-600 rounded-lg transition-colors"
          >
            <X className="w-4 h-4" />
            {t('processed_events.clear_selection')}
          </button>
        </div>
      </div>
    </div>
  );
}
