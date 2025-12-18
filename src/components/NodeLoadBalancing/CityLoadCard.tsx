import React from 'react';
import { NodeLoadData } from '../../hooks/useNodeLoadBalancing';

interface CityLoadCardProps {
  cityName: string;
  cityData: NodeLoadData[];
  onBalance: () => void;
}

export const CityLoadCard: React.FC<CityLoadCardProps> = ({
  cityName,
  cityData,
  onBalance,
}) => {
  const [isRecommendationsExpanded, setIsRecommendationsExpanded] = React.useState(false);
  
  // Get unique weeks and nodes
  const weeks = Array.from(new Set(cityData.map((d) => d.week_number))).sort();
  const nodes = Array.from(new Set(cityData.map((d) => d.node_code))).sort();

  // Calculate city stats
  const totalShipments = cityData.reduce((sum, d) => sum + d.shipment_count, 0);
  const avgPerNode = totalShipments / nodes.length;
  const monthlyStddev = cityData[0]?.city_monthly_stddev || cityData[0]?.city_period_stddev || 0;
  
  // Always allow balancing (user can force it)
  const hasSaturatedNodes = cityData.some((d) => d.saturation_level === 'saturated');
  const hasHighNodes = cityData.some((d) => d.saturation_level === 'high');
  const needsBalancing = true;  // Always allow balancing

  // Create matrix data structure
  const matrix: { [nodeCode: string]: { [week: number]: NodeLoadData } } = {};
  cityData.forEach((d) => {
    if (!matrix[d.node_code]) {
      matrix[d.node_code] = {};
    }
    matrix[d.node_code][d.week_number] = d;
  });

  // Calculate node averages
  const nodeAverages: { [nodeCode: string]: number } = {};
  nodes.forEach((nodeCode) => {
    const nodeData = cityData.filter((d) => d.node_code === nodeCode);
    const sum = nodeData.reduce((s, d) => s + d.shipment_count, 0);
    nodeAverages[nodeCode] = sum / nodeData.length;
  });

  // Calculate week totals and averages
  const weekTotals: { [week: number]: number } = {};
  const weekAverages: { [week: number]: number } = {};
  const weekStddevs: { [week: number]: number } = {};

  weeks.forEach((week) => {
    const weekData = cityData.filter((d) => d.week_number === week);
    weekTotals[week] = weekData.reduce((sum, d) => sum + d.shipment_count, 0);
    weekAverages[week] = weekTotals[week] / nodes.length;
    weekStddevs[week] = weekData[0]?.city_weekly_stddev || 0;
  });

  // Get reference load and deviation from cityData
  const referenceLoad = cityData[0]?.reference_load || 6;
  const deviationPercent = cityData[0]?.deviation_threshold 
    ? ((cityData[0].deviation_threshold - referenceLoad) / referenceLoad) * 100 
    : 20;
  
  // Calculate thresholds based on reference and deviation
  const highThreshold = referenceLoad * (1 + deviationPercent / 100);
  const saturatedThreshold = referenceLoad * (1 + (deviationPercent * 1.5) / 100);

  const getLoadColor = (count: number) => {
    if (count >= saturatedThreshold) return 'text-red-700';
    if (count >= highThreshold) return 'text-orange-600';
    return 'text-green-700';
  };

  const getLoadIcon = (count: number) => {
    if (count >= saturatedThreshold) return '🔴';
    if (count >= highThreshold) return '🟡';
    return '🟢';
  };

  const getStddevColor = (stddev: number) => {
    if (stddev > 15) return 'text-red-700';
    if (stddev > 10) return 'text-orange-600';
    if (stddev > 5) return 'text-yellow-600';
    return 'text-green-700';
  };

  const getStatusBadge = (nodeCode: string) => {
    const nodeData = cityData.filter((d) => d.node_code === nodeCode);
    const hasSaturated = nodeData.some((d) => d.saturation_level === 'saturated');
    const hasHigh = nodeData.some((d) => d.saturation_level === 'high');

    if (hasSaturated) {
      return (
        <span className="inline-flex items-center gap-1 px-2 py-1 bg-red-100 text-red-700 text-xs font-medium rounded-full">
          SATURATED
        </span>
      );
    }
    if (hasHigh) {
      return (
        <span className="inline-flex items-center gap-1 px-2 py-1 bg-orange-100 text-orange-700 text-xs font-medium rounded-full">
          HIGH
        </span>
      );
    }
    return (
      <span className="inline-flex items-center gap-1 px-2 py-1 bg-green-100 text-green-700 text-xs font-medium rounded-full">
        NORMAL
      </span>
    );
  };

  return (
    <div className="border border-gray-200 rounded-lg overflow-hidden mb-6">
      {/* Header */}
      <div className="bg-gray-50 px-6 py-4 border-b border-gray-200">
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-blue-100 rounded-full flex items-center justify-center">
              <svg className="w-6 h-6 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M4 4a2 2 0 012-2h8a2 2 0 012 2v12a1 1 0 110 2h-3a1 1 0 01-1-1v-2a1 1 0 00-1-1H9a1 1 0 00-1 1v2a1 1 0 01-1 1H4a1 1 0 110-2V4zm3 1h2v2H7V5zm2 4H7v2h2V9zm2-4h2v2h-2V5zm2 4h-2v2h2V9z" clipRule="evenodd" />
              </svg>
            </div>
            <h3 className="text-lg font-semibold text-gray-900">{cityName}</h3>
          </div>
          <div className="flex items-center gap-6 text-sm">
            <div className="flex items-center gap-2">
              <span className="text-gray-600">Total:</span>
              <strong className="text-gray-900">{totalShipments} shipments</strong>
            </div>
            <div className="flex items-center gap-2">
              <span className="text-gray-600">Avg/Node:</span>
              <strong className="text-gray-900">{avgPerNode.toFixed(1)}</strong>
            </div>
          </div>
        </div>
      </div>

      {/* Heat Map Table */}
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Node
              </th>
              {weeks.map((week) => (
                <th
                  key={week}
                  className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase"
                >
                  Week {week}
                </th>
              ))}
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                Monthly Avg
              </th>
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                Status
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {nodes.map((nodeCode) => {
              // Get panelist name for this node
              const nodeData = cityData.find(d => d.node_code === nodeCode);
              const panelistName = nodeData?.panelist_name;
              
              return (
              <tr key={nodeCode} className="hover:bg-gray-50">
                <td className="px-4 py-3">
                  <div className="flex flex-col">
                    <span className="font-medium text-gray-900">{nodeCode}</span>
                    <span className="text-xs text-gray-500">
                      {panelistName || 'No panelist'}
                    </span>
                  </div>
                </td>
                {weeks.map((week) => {
                  const data = matrix[nodeCode]?.[week];
                  if (!data) {
                    return (
                      <td key={week} className="px-4 py-3 text-center text-gray-400">
                        —
                      </td>
                    );
                  }
                  return (
                    <td key={week} className="px-4 py-3 text-center">
                      <span
                        className={`inline-flex items-center gap-1 font-medium ${getLoadColor(
                          data.shipment_count
                        )}`}
                      >
                        <span>{getLoadIcon(data.shipment_count)}</span>
                        {data.shipment_count}
                      </span>
                    </td>
                  );
                })}
                <td className="px-4 py-3 text-center font-semibold text-gray-900">
                  {nodeAverages[nodeCode].toFixed(1)}
                </td>
                <td className="px-4 py-3 text-center">{getStatusBadge(nodeCode)}</td>
              </tr>
              );
            })}

            {/* Totals Row */}
            <tr className="bg-gray-50 font-semibold border-t-2 border-gray-300">
              <td className="px-4 py-3 text-gray-900">TOTAL</td>
              {weeks.map((week) => (
                <td key={week} className="px-4 py-3 text-center text-gray-900">
                  {weekTotals[week]}
                </td>
              ))}
              <td className="px-4 py-3 text-center text-gray-900">
                {(totalShipments / weeks.length).toFixed(1)}
              </td>
              <td></td>
            </tr>

            {/* Average Row */}
            <tr className="bg-gray-50 font-semibold">
              <td className="px-4 py-3 text-gray-900">AVG/NODE</td>
              {weeks.map((week) => (
                <td key={week} className="px-4 py-3 text-center text-gray-900">
                  {weekAverages[week].toFixed(1)}
                </td>
              ))}
              <td className="px-4 py-3 text-center text-gray-900">{avgPerNode.toFixed(1)}</td>
              <td></td>
            </tr>


          </tbody>
        </table>
      </div>

      {/* Recommendations Section */}
      <div className="bg-gradient-to-r from-blue-50 to-indigo-50 px-6 py-4 border-t border-gray-200">
        <button
          onClick={() => setIsRecommendationsExpanded(!isRecommendationsExpanded)}
          className="w-full flex items-center justify-between hover:opacity-80 transition-opacity"
        >
          <div className="flex items-center gap-3">
            <div className="flex-shrink-0">
              <svg className="w-6 h-6 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
              </svg>
            </div>
            <h4 className="text-sm font-semibold text-gray-900">💡 Recommendations</h4>
          </div>
          <svg
            className={`w-5 h-5 text-gray-600 transition-transform ${isRecommendationsExpanded ? 'rotate-180' : ''}`}
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
          </svg>
        </button>
        
        {isRecommendationsExpanded && (
          <div className="mt-4 flex items-start gap-3">
            <div className="flex-1">
            
              {/* Optimization Recommendations */}
              <div className="mb-3">
                <p className="text-xs font-medium text-gray-700 mb-1">📊 Optimization:</p>
                <ul className="text-xs text-gray-600 space-y-1 ml-4">
                  {(() => {
                    // Analyze individual cells
                    const saturatedCells: string[] = [];
                    const highCells: string[] = [];
                    const normalCells: string[] = [];
                    
                    nodes.forEach(nodeCode => {
                      weeks.forEach(week => {
                        const count = matrix[nodeCode]?.[week]?.shipment_count || 0;
                        const cellId = `${nodeCode}-W${week}`;
                        if (count >= saturatedThreshold) {
                          saturatedCells.push(cellId);
                        } else if (count >= highThreshold) {
                          highCells.push(cellId);
                        } else {
                          normalCells.push(cellId);
                        }
                      });
                    });
                    
                    const totalCells = nodes.length * weeks.length;
                    const saturatedPct = (saturatedCells.length / totalCells) * 100;
                    const highPct = (highCells.length / totalCells) * 100;
                    const normalPct = (normalCells.length / totalCells) * 100;
                    
                    return (
                      <>
                        {saturatedCells.length > 0 && (
                          <li className="flex items-start gap-1">
                            <span className="text-red-600">•</span>
                            <span><strong>Critical:</strong> {saturatedCells.length} cells ({saturatedPct.toFixed(0)}%) are saturated (≥{saturatedThreshold.toFixed(1)} shipments). Urgent balancing required.</span>
                          </li>
                        )}
                        {highCells.length > 0 && (
                          <li className="flex items-start gap-1">
                            <span className="text-orange-600">•</span>
                            <span><strong>Warning:</strong> {highCells.length} cells ({highPct.toFixed(0)}%) have high load (≥{highThreshold.toFixed(1)} shipments). Consider preventive balancing.</span>
                          </li>
                        )}
                        {saturatedCells.length === 0 && highCells.length === 0 && (
                          <li className="flex items-start gap-1">
                            <span className="text-green-600">•</span>
                            <span><strong>Optimal:</strong> All {totalCells} cells are within normal range (&lt;{highThreshold.toFixed(1)} shipments). No balancing required.</span>
                          </li>
                        )}
                        {normalCells.length > 0 && (saturatedCells.length > 0 || highCells.length > 0) && (
                          <li className="flex items-start gap-1">
                            <span className="text-blue-600">•</span>
                            <span>{normalCells.length} cells ({normalPct.toFixed(0)}%) are operating normally.</span>
                          </li>
                        )}
                      </>
                    );
                  })()}
                </ul>
              </div>

              {/* Action Recommendations */}
              <div className="mb-3">
                <p className="text-xs font-medium text-gray-700 mb-1">🎯 Suggested Actions:</p>
                <ul className="text-xs text-gray-600 space-y-1 ml-4">
                  {(() => {
                    // Find specific problematic cells
                    const saturatedCells: {node: string, week: number, count: number}[] = [];
                    const highCells: {node: string, week: number, count: number}[] = [];
                    
                    nodes.forEach(nodeCode => {
                      weeks.forEach(week => {
                        const count = matrix[nodeCode]?.[week]?.shipment_count || 0;
                        if (count >= saturatedThreshold) {
                          saturatedCells.push({node: nodeCode, week, count});
                        } else if (count >= highThreshold) {
                          highCells.push({node: nodeCode, week, count});
                        }
                      });
                    });
                    
                    // Group by node
                    const saturatedNodes = [...new Set(saturatedCells.map(c => c.node))];
                    const highNodes = [...new Set(highCells.map(c => c.node))];
                    
                    return (
                      <>
                        {saturatedCells.length > 0 && (
                          <li className="flex items-start gap-1">
                            <span className="text-red-600">•</span>
                            <span><strong>Urgent:</strong> Balance immediately. Saturated cells in nodes: {saturatedNodes.join(', ')}.</span>
                          </li>
                        )}
                        {highCells.length > 0 && saturatedCells.length === 0 && (
                          <li className="flex items-start gap-1">
                            <span className="text-orange-600">•</span>
                            <span><strong>Preventive:</strong> Balance recommended. High load cells in nodes: {highNodes.join(', ')}.</span>
                          </li>
                        )}
                        {saturatedCells.length === 0 && highCells.length === 0 && (
                          <li className="flex items-start gap-1">
                            <span className="text-green-600">•</span>
                            <span>No action required. All cells are within acceptable range.</span>
                          </li>
                        )}
                        {(saturatedCells.length > 0 || highCells.length > 0) && (
                          <li className="flex items-start gap-1">
                            <span className="text-blue-600">•</span>
                            <span>Use the "Auto-Balance" button below to redistribute load automatically.</span>
                          </li>
                        )}
                      </>
                    );
                  })()}
                </ul>
              </div>

              {/* Additional Statistics */}
              <div>
                <p className="text-xs font-medium text-gray-700 mb-1">📈 Additional Statistics:</p>
                <ul className="text-xs text-gray-600 space-y-1 ml-4">
                  {(() => {
                    // Find cell with max load
                    let maxCell = {node: '', week: 0, count: 0};
                    nodes.forEach(nodeCode => {
                      weeks.forEach(week => {
                        const count = matrix[nodeCode]?.[week]?.shipment_count || 0;
                        if (count > maxCell.count) {
                          maxCell = {node: nodeCode, week, count};
                        }
                      });
                    });
                    
                    // Find cells above threshold
                    const problematicCells: string[] = [];
                    nodes.forEach(nodeCode => {
                      weeks.forEach(week => {
                        const count = matrix[nodeCode]?.[week]?.shipment_count || 0;
                        if (count >= highThreshold) {
                          problematicCells.push(`${nodeCode}/W${week}`);
                        }
                      });
                    });
                    
                    return (
                      <>
                        {maxCell.count > 0 && (
                          <li className="flex items-start gap-1">
                            <span className="text-blue-600">•</span>
                            <span>Highest load cell: {maxCell.node} / W{maxCell.week} ({maxCell.count} shipments)</span>
                          </li>
                        )}
                        <li className="flex items-start gap-1">
                          <span className="text-blue-600">•</span>
                          <span>Cells requiring attention: {problematicCells.length > 0 ? problematicCells.slice(0, 5).join(', ') + (problematicCells.length > 5 ? ` +${problematicCells.length - 5} more` : '') : 'None'}</span>
                        </li>
                        <li className="flex items-start gap-1">
                          <span className="text-blue-600">•</span>
                          <span>Thresholds: High ≥{highThreshold.toFixed(1)}, Saturated ≥{saturatedThreshold.toFixed(1)} shipments/cell</span>
                        </li>
                        <li className="flex items-start gap-1">
                          <span className="text-blue-600">•</span>
                          <span>Reference: {referenceLoad} samples/node, {deviationPercent.toFixed(0)}% tolerance</span>
                        </li>
                      </>
                    );
                  })()}
                </ul>
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Actions */}
      <div className="bg-gray-50 px-6 py-4 border-t border-gray-200 flex items-center gap-3">
        <div className="group relative">
          <button
            onClick={onBalance}
            disabled={!needsBalancing}
            className={`flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
              needsBalancing
                ? 'bg-blue-600 text-white hover:bg-blue-700 cursor-pointer'
                : 'bg-gray-300 text-gray-500 cursor-not-allowed'
            }`}
          >
            <span>⚖️</span>
            Auto-Balance {cityName}
          </button>
          {!needsBalancing && (
            <div className="invisible group-hover:visible absolute z-10 w-64 p-3 bg-gray-900 text-white text-xs rounded-lg shadow-lg bottom-full left-0 mb-2">
              <p className="font-semibold mb-1">Balance Not Needed</p>
              <p>
                {monthlyStddev < 5
                  ? 'Load is already well balanced (stddev < 5)'
                  : 'No saturated or high load nodes detected'}
              </p>
            </div>
          )}
        </div>
        <span className="group relative">
          <svg
            className="w-5 h-5 text-gray-400 cursor-help"
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path
              fillRule="evenodd"
              d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
              clipRule="evenodd"
            />
          </svg>
          <div className="invisible group-hover:visible absolute z-10 w-[480px] p-4 bg-gray-900 text-white text-xs rounded-lg shadow-lg bottom-full left-0 mb-2">
            <p className="font-semibold mb-2 text-sm">🎯 Algoritmo de Balanceo de Matriz Alícuota</p>
            
            <p className="mb-2">
              <strong>Concepto:</strong> Trata toda la matriz (nodos × semanas) como un espacio único de distribución. Objetivo: que todas las celdas se acerquen al promedio global.
            </p>
            
            <p className="mb-2">
              <strong>Cálculo del objetivo:</strong><br/>
              Promedio objetivo = Total shipments / (Nodos × Semanas)<br/>
              <em>Ejemplo: 305 shipments / (1 nodo × 5 semanas) = 61 por celda</em>
            </p>
            
            <p className="mb-2">
              <strong>Proceso:</strong>
            </p>
            <ol className="list-decimal list-inside space-y-1 mb-2 ml-2">
              <li>Identifica celdas sobrecargadas (&gt; objetivo × 1.2)</li>
              <li>Identifica celdas subcargadas (&lt; objetivo × 0.9)</li>
              <li>Mueve shipments de celdas sobrecargadas a subcargadas</li>
              <li>Actualiza fecha_programada y node_id en allocation_plan_details</li>
              <li>Minimiza la desviación estándar de toda la matriz</li>
            </ol>
            
            <p className="mb-2">
              <strong>Resultado:</strong> Distribución equitativa que reduce varianza, previene saturación y optimiza la eficiencia del sistema.
            </p>
            
            <p className="text-yellow-300">
              ⚠️ El preview muestra los cambios propuestos. Debes confirmar para aplicarlos al Allocation Plan.
            </p>
          </div>
        </span>
      </div>
    </div>
  );
};
