import React, { useState } from 'react';
import { BalanceResult, MatrixCell } from '../../hooks/useNodeLoadBalancing';

import { useTranslation } from '@/hooks/useTranslation';
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
                <h3 className="font-semibold text-blue-900 mb-3">{t('nodeloadbalancing.summary')}</h3>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <div>
                    <div className="text-sm text-blue-700">{t('nodeloadbalancing.movements')}</div>
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
                    <div className="text-sm text-blue-700">{t('nodeloadbalancing.improvement')}</div>
                    <div className="text-2xl font-bold text-green-700">
                      {previewResult.improvement_percentage != null ? previewResult.improvement_percentage.toFixed(1) : 'N/A'}%
                    </div>
                  </div>
                </div>
              </div>

              {/* Nodes Needed Warning */}
              {previewResult.nodes_needed != null && previewResult.nodes_needed > 0 && (
                <div className="bg-orange-50 border border-orange-300 rounded-lg p-4 mb-6">
                  <div className="flex gap-3">
                    <span className="text-orange-600 text-xl">⚠️</span>
                    <div>
                      <h3 className="font-semibold text-orange-900 mb-2">
                        Additional Nodes Required
                      </h3>
                      <p className="text-sm text-orange-800 mb-3">
                        Even after optimal balancing, the average load per node (
                        <strong>{previewResult.avg_load_per_node?.toFixed(1)}</strong> samples/node)
                        exceeds the acceptable threshold of{' '}
                        <strong>{previewResult.max_acceptable_load?.toFixed(1)}</strong> samples/node
                        (Reference: {previewResult.reference_load} + {previewResult.deviation_percent}% tolerance).
                      </p>
                      <div className="bg-orange-100 border border-orange-200 rounded-md p-3">
                        <div className="flex items-center gap-2">
                          <span className="text-3xl font-bold text-orange-900">
                            +{previewResult.nodes_needed}
                          </span>
                          <div className="text-sm text-orange-800">
                            <div className="font-semibold">Additional node{previewResult.nodes_needed > 1 ? 's' : ''} needed</div>
                            <div>Current nodes: {previewResult.nodes_count}</div>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              )}

              {/* No movements needed */}
              {previewResult.movements_count === 0 && (
                <div className="bg-green-50 border border-green-200 rounded-lg p-4">
                  <p className="text-green-700">
                    ✓ No balancing needed - the city is already well balanced!
                  </p>
                </div>
              )}

              {/* Matrix Visualization and Movements */}
              {previewResult.movements_count > 0 && (
                <MatrixVisualization
                  matrixBefore={previewResult.matrix_before}
                  matrixAfter={previewResult.matrix_after}
                  movements={previewResult.movements}
                />
              )}

              {/* Movements List (legacy, kept for reference) */}
              {false && (
                <>
                  <h3 className="font-semibold text-gray-900 mb-3">
                    Planned Movements ({previewResult?.movements?.length || 0})
                  </h3>
                  <div className="space-y-3">
                    {previewResult?.movements?.map((movement, index) => (
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

// Matrix Visualization Component
interface MatrixVisualizationProps {
  matrixBefore?: MatrixCell[];
  matrixAfter?: MatrixCell[];
  movements: BalanceResult['movements'];
}

const MatrixVisualization: React.FC<MatrixVisualizationProps> = ({
  matrixBefore,
  matrixAfter,
  movements,
}) => {
  const [activeTab, setActiveTab] = useState<'matrix' | 'movements'>('matrix');
  const [matrixView, setMatrixView] = useState<'before' | 'after'>('before');

  if (!matrixBefore || !matrixAfter) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-4">
        <p className="text-gray-600">Matrix data not available</p>
      </div>
    );
  }

  // Extract unique nodes and weeks
  const nodes = Array.from(new Set(matrixBefore.map((cell) => cell.node_code))).sort();
  const weeks = Array.from(new Set(matrixBefore.map((cell) => cell.week_num))).sort((a, b) => a - b);

  // Build matrix lookup
  const buildMatrixLookup = (matrix: MatrixCell[]) => {
    const lookup: { [key: string]: number } = {};
    matrix.forEach((cell) => {
      lookup[`${cell.node_code}-${cell.week_num}`] = cell.load_count;
    });
    return lookup;
  };

  const matrixBeforeLookup = buildMatrixLookup(matrixBefore);
  const matrixAfterLookup = buildMatrixLookup(matrixAfter);

  // DEBUG: Log matrices for audit
  console.log('=== MATRIX DEBUG ===');
  console.log('Matrix Before:', JSON.stringify(matrixBefore, null, 2));
  console.log('Matrix After:', JSON.stringify(matrixAfter, null, 2));
  console.log('Nodes:', nodes);
  console.log('Weeks:', weeks);
  console.log('Before Lookup:', matrixBeforeLookup);
  console.log('After Lookup:', matrixAfterLookup);
  console.log('===================');

  const currentMatrix = matrixView === 'before' ? matrixBeforeLookup : matrixAfterLookup;

  // Calculate color intensity based on load
  const getColorClass = (count: number) => {
    if (count === 0) return 'bg-gray-100 text-gray-400';
    if (count <= 5) return 'bg-green-100 text-green-800';
    if (count <= 10) return 'bg-yellow-100 text-yellow-800';
    if (count <= 15) return 'bg-orange-100 text-orange-800';
    return 'bg-red-100 text-red-800';
  };

  return (
    <div className="space-y-4">
      {/* Tabs */}
      <div className="flex border-b border-gray-200">
        <button
          onClick={() => setActiveTab('matrix')}
          className={`px-4 py-2 font-medium transition-colors ${
            activeTab === 'matrix'
              ? 'border-b-2 border-blue-600 text-blue-600'
              : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          📊 Matrix View
        </button>
        <button
          onClick={() => setActiveTab('movements')}
          className={`px-4 py-2 font-medium transition-colors ${
            activeTab === 'movements'
              ? 'border-b-2 border-blue-600 text-blue-600'
              : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          📦 Movements ({movements.length})
        </button>
      </div>

      {/* Matrix Tab */}
      {activeTab === 'matrix' && (
        <div className="space-y-4">
          {/* Before/After Toggle */}
          <div className="flex items-center justify-between">
            <h3 className="font-semibold text-gray-900">
              Load Distribution Matrix
            </h3>
            <div className="flex gap-2">
              <button
                onClick={() => setMatrixView('before')}
                className={`px-3 py-1 rounded-md text-sm font-medium transition-colors ${
                  matrixView === 'before'
                    ? 'bg-blue-600 text-white'
                    : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
                }`}
              >
                Before
              </button>
              <button
                onClick={() => setMatrixView('after')}
                className={`px-3 py-1 rounded-md text-sm font-medium transition-colors ${
                  matrixView === 'after'
                    ? 'bg-green-600 text-white'
                    : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
                }`}
              >
                After
              </button>
            </div>
          </div>

          {/* Matrix Table */}
          <div className="overflow-x-auto border border-gray-200 rounded-lg">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider sticky left-0 bg-gray-50">
                    Node
                  </th>
                  {weeks.map((week) => (
                    <th
                      key={week}
                      className="px-3 py-2 text-center text-xs font-medium text-gray-500 uppercase tracking-wider"
                    >
                      W{week}
                    </th>
                  ))}
                  <th className="px-3 py-2 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Total
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {nodes.map((node) => {
                  const rowTotal = weeks.reduce(
                    (sum, week) => sum + (currentMatrix[`${node}-${week}`] || 0),
                    0
                  );
                  return (
                    <tr key={node}>
                      <td className="px-3 py-2 text-sm font-medium text-gray-900 sticky left-0 bg-white">
                        {node}
                      </td>
                      {weeks.map((week) => {
                        const count = currentMatrix[`${node}-${week}`] || 0;
                        return (
                          <td
                            key={week}
                            className={`px-3 py-2 text-center text-sm font-semibold ${getColorClass(
                              count
                            )}`}
                          >
                            {count}
                          </td>
                        );
                      })}
                      <td className="px-3 py-2 text-center text-sm font-bold text-gray-900 bg-gray-50">
                        {rowTotal}
                      </td>
                    </tr>
                  );
                })}
                {/* Totals Row */}
                <tr className="bg-gray-50 font-semibold">
                  <td className="px-3 py-2 text-sm text-gray-900">{t('common.total')}</td>
                  {weeks.map((week) => {
                    const colTotal = nodes.reduce(
                      (sum, node) => sum + (currentMatrix[`${node}-${week}`] || 0),
                      0
                    );
                    return (
                      <td key={week} className="px-3 py-2 text-center text-sm text-gray-900">
                        {colTotal}
                      </td>
                    );
                  })}
                  <td className="px-3 py-2 text-center text-sm font-bold text-gray-900">
                    {nodes.reduce(
                      (sum, node) =>
                        sum +
                        weeks.reduce(
                          (wSum, week) => wSum + (currentMatrix[`${node}-${week}`] || 0),
                          0
                        ),
                      0
                    )}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          {/* Legend */}
          <div className="flex items-center gap-4 text-xs text-gray-600">
            <span className="font-medium">Load Level:</span>
            <div className="flex items-center gap-2">
              <div className="w-4 h-4 bg-gray-100 border border-gray-300"></div>
              <span>0</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-4 h-4 bg-green-100 border border-green-300"></div>
              <span>1-5</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-4 h-4 bg-yellow-100 border border-yellow-300"></div>
              <span>6-10</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-4 h-4 bg-orange-100 border border-orange-300"></div>
              <span>11-15</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-4 h-4 bg-red-100 border border-red-300"></div>
              <span>16+</span>
            </div>
          </div>
        </div>
      )}

      {/* Movements Tab */}
      {activeTab === 'movements' && (
        <div className="space-y-3">
          <h3 className="font-semibold text-gray-900">
            Planned Movements ({movements.length})
          </h3>
          <div className="space-y-2 max-h-96 overflow-y-auto">
            {movements.map((movement, index) => (
              <div
                key={index}
                className="border border-gray-200 rounded-lg p-3 hover:bg-gray-50 text-sm"
              >
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-2">
                    <span className="text-base">📦</span>
                    <div>
                      <div className="font-medium text-gray-900">
                        {movement.count} shipment{movement.count > 1 ? 's' : ''}
                      </div>
                      <div className="text-xs text-gray-600">
                        {movement.from_node_code} (W{movement.from_week}) →{' '}
                        {movement.to_node_code} (W{movement.to_week})
                      </div>
                    </div>
                  </div>
                  <div className="text-xs text-gray-500">
                    {movement.from_week === movement.to_week ? 'Same week' : 'Cross-week'}
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
