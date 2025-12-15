import React from 'react';
import { BalanceResult } from '../../hooks/useNodeLoadBalancing';

interface BalancePreviewModalProps {
  isOpen: boolean;
  cityName: string;
  previewResult: BalanceResult | null;
  loading: boolean;
  onClose: () => void;
  onConfirm: () => void;
}

export const BalancePreviewModal: React.FC<BalancePreviewModalProps> = ({
  isOpen,
  cityName,
  previewResult,
  loading,
  onClose,
  onConfirm,
}) => {
  if (!isOpen) return null;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b border-gray-200">
          <div className="flex items-center justify-between">
            <h2 className="text-xl font-semibold text-gray-900">
              Balance Preview - {cityName}
            </h2>
            <button
              onClick={onClose}
              className="text-gray-400 hover:text-gray-600 transition-colors"
            >
              <span className="text-2xl">×</span>
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6">
          {loading && (
            <div className="flex items-center justify-center py-12">
              <div className="flex items-center gap-3 text-gray-600">
                <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-gray-600"></div>
                <span>Calculating balance preview...</span>
              </div>
            </div>
          )}

          {!loading && previewResult?.error && (
            <div className="bg-red-50 border border-red-200 rounded-lg p-4">
              <p className="text-red-700">Error: {previewResult.error}</p>
            </div>
          )}

          {!loading && previewResult && !previewResult.error && (
            <>
              {/* Summary */}
              <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
                <h3 className="font-semibold text-blue-900 mb-3">Summary</h3>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div>
                    <div className="text-sm text-blue-700">Movements</div>
                    <div className="text-2xl font-bold text-blue-900">
                      {previewResult.movements_count}
                    </div>
                  </div>
                  <div>
                    <div className="text-sm text-blue-700">Std Dev Before</div>
                    <div className="text-2xl font-bold text-blue-900">
                      {previewResult.stddev_before != null ? previewResult.stddev_before.toFixed(1) : 'N/A'}
                    </div>
                  </div>
                  <div>
                    <div className="text-sm text-blue-700">Std Dev After</div>
                    <div className="text-2xl font-bold text-green-700">
                      {previewResult.stddev_after != null ? previewResult.stddev_after.toFixed(1) : 'N/A'}
                    </div>
                  </div>
                  <div>
                    <div className="text-sm text-blue-700">Improvement</div>
                    <div className="text-2xl font-bold text-green-700">
                      {previewResult.improvement_percentage != null ? previewResult.improvement_percentage.toFixed(1) : 'N/A'}%
                    </div>
                  </div>
                </div>
              </div>

              {/* No movements needed */}
              {previewResult.movements_count === 0 && (
                <div className="bg-green-50 border border-green-200 rounded-lg p-4">
                  <p className="text-green-700">
                    ✓ No balancing needed - the city is already well balanced!
                  </p>
                </div>
              )}

              {/* Movements List */}
              {previewResult.movements_count > 0 && (
                <>
                  <h3 className="font-semibold text-gray-900 mb-3">
                    Planned Movements ({previewResult.movements.length})
                  </h3>
                  <div className="space-y-3">
                    {previewResult.movements.map((movement, index) => (
                      <div
                        key={index}
                        className="border border-gray-200 rounded-lg p-4 hover:bg-gray-50"
                      >
                        <div className="flex items-center justify-between mb-2">
                          <div className="flex items-center gap-3">
                            <span className="text-lg">📦</span>
                            <div>
                              <div className="font-medium text-gray-900">
                                {movement.count} shipment{movement.count > 1 ? 's' : ''}
                              </div>
                              <div className="text-sm text-gray-600">
                                From {movement.from_node_code} (Week {movement.from_week}) →{' '}
                                {movement.to_node_code} (Week {movement.to_week})
                              </div>
                            </div>
                          </div>
                          <div className="text-right">
                            <div className="text-xs text-gray-500">
                              {movement.from_week === movement.to_week
                                ? 'Same week'
                                : 'Cross-week'}
                            </div>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>

                  {/* Info */}
                  <div className="mt-6 bg-yellow-50 border border-yellow-200 rounded-lg p-4">
                    <div className="flex gap-3">
                      <span className="text-yellow-600">ℹ️</span>
                      <div className="text-sm text-yellow-800">
                        <p className="font-medium mb-1">Matrix Balancing Algorithm</p>
                        <p>
                          This algorithm considers the entire city-month matrix simultaneously,
                          redistributing shipments across both nodes and weeks to achieve optimal
                          balance. Only pending shipments without assigned panelists will be moved.
                        </p>
                      </div>
                    </div>
                  </div>
                </>
              )}
            </>
          )}
        </div>

        {/* Footer */}
        <div className="px-6 py-4 border-t border-gray-200 flex items-center justify-between">
          <button
            onClick={onClose}
            className="px-4 py-2 text-gray-700 hover:text-gray-900 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            disabled={
              loading ||
              !previewResult ||
              previewResult.error !== undefined ||
              previewResult.movements_count === 0
            }
            className="px-6 py-2 bg-blue-600 text-white rounded-md font-medium hover:bg-blue-700 transition-colors disabled:bg-gray-300 disabled:cursor-not-allowed"
          >
            {loading ? 'Loading...' : 'Apply Balance'}
          </button>
        </div>
      </div>
    </div>
  );
};
