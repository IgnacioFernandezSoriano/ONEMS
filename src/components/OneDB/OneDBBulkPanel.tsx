import React from 'react';

interface OneDBBulkPanelProps {
  selectedCount: number;
  totalCount: number;
  onExport: () => void;
  onClearSelection: () => void;
}

export const OneDBBulkPanel: React.FC<OneDBBulkPanelProps> = ({
  selectedCount,
  totalCount,
  onExport,
  onClearSelection,
}) => {
  if (selectedCount === 0) return null;

  return (
    <div className="fixed bottom-6 left-1/2 transform -translate-x-1/2 z-50">
      <div className="bg-gray-900 text-white rounded-lg shadow-2xl px-6 py-4 flex items-center gap-6">
        {/* Selection Info */}
        <div className="flex items-center gap-2">
          <span className="font-medium">
            {selectedCount} of {totalCount} selected
          </span>
        </div>

        {/* Divider */}
        <div className="h-6 w-px bg-gray-600"></div>

        {/* Export Button */}
        <button
          onClick={onExport}
          className="flex items-center gap-2 px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded-md transition-colors"
        >
          <span>⬇</span>
          Export CSV
        </button>

        {/* Clear Selection */}
        <button
          onClick={onClearSelection}
          className="flex items-center gap-2 px-3 py-2 hover:bg-gray-800 rounded-md transition-colors"
        >
          <span>✕</span>
          Clear
        </button>
      </div>
    </div>
  );
};
