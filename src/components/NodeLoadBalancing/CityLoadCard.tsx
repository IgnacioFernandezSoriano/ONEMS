import React from 'react';
import { NodeLoadData, NodeDayLoad } from '../../hooks/useNodeLoadBalancing';
import { localDateKey, type DatePolicy } from '../../lib/workingDays';
import { analyzeCity, type Severity } from '../../lib/cityAnalysis';
import { buildDayView, buildMonthView, compareNatural, dayCellKey, dayTotals, isConflict, isPoboxGap, orderWeekNumbers } from '../../lib/loadViews';
import { useTranslation } from '@/hooks/useTranslation';

export type LoadScale = 'day' | 'week' | 'month';

export interface CityPolicyView {
  datePolicy: DatePolicy;
  pobox: boolean;
  cityOverride: { date_policy: DatePolicy | null; pobox_enabled: boolean | null };
}

interface CityLoadCardProps {
  cityName: string;
  cityData: NodeLoadData[];
  onBalance: () => void;
  /** Extra lock (e.g. a balance is being applied): also locks the per-city policy selects */
  balanceDisabled?: boolean;
  dayData?: NodeDayLoad[];
  /** muestras por compensar de esta ciudad que esperan en el registro */
  deferredPending?: number;
  /** muestras que la ultima vista previa apartaria del plan */
  willRemove?: number;
  scale?: LoadScale;
  onScaleChange?: (s: LoadScale) => void;
  policy?: CityPolicyView;
  onCityPolicyChange?: (p: { date_policy?: DatePolicy | null; pobox_enabled?: boolean | null }) => void;
}

const FINDING_BULLET: Record<Severity, string> = {
  critical: 'text-red-600',
  warning: 'text-orange-600',
  info: 'text-blue-600',
  ok: 'text-green-600',
};

const UNAVAILABLE_CLASS =
  'bg-gray-200 bg-[repeating-linear-gradient(45deg,transparent,transparent_4px,rgba(0,0,0,.08)_4px,rgba(0,0,0,.08)_8px)]';

export const CityLoadCard: React.FC<CityLoadCardProps> = ({
  cityName,
  cityData,
  onBalance,
  balanceDisabled = false,
  dayData = [],
  deferredPending = 0,
  willRemove = 0,
  scale = 'week',
  onScaleChange,
  policy,
  onCityPolicyChange,
}) => {
  const { t } = useTranslation();
  const dayView = React.useMemo(() => buildDayView(dayData), [dayData]);
  const dayTotalsMap = React.useMemo(() => dayTotals(dayView), [dayView]);
  const monthView = React.useMemo(() => buildMonthView(dayData), [dayData]);
  const dayNodes = React.useMemo(() => {
    const m = new Map<string, string | null>();
    dayData.forEach((r) => { if (!m.has(r.node_code)) m.set(r.node_code, r.panelist_name); });
    return [...m.entries()].sort((a, b) => compareNatural(a[0], b[0]));
  }, [dayData]);
  const [isRecommendationsExpanded, setIsRecommendationsExpanded] = React.useState(true);
  
  // Get unique weeks and nodes
  const weeks = orderWeekNumbers(cityData);
  const nodes = Array.from(new Set(cityData.map((d) => d.node_code))).sort(compareNatural);

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

  // Analisis y recomendaciones segun las reglas del balanceador (carga, ausencias, nodos sin panelista,
  // atrasados, picos diarios y huecos POBOX); los textos salen de lb2.rec.* en el idioma del usuario.
  const findings = React.useMemo(
    () =>
      analyzeCity({
        weekCells: cityData,
        highThreshold,
        saturatedThreshold,
        dayRows: dayData,
        datePolicy: policy?.datePolicy ?? 'daily',
        pobox: !!policy?.pobox,
        today: localDateKey(new Date()),
        deferredPending,
        willRemove,
      }),
    [cityData, dayData, highThreshold, saturatedThreshold, policy?.datePolicy, policy?.pobox, deferredPending, willRemove]
  );
  const actionableFindings = findings.filter((f) => f.severity === 'critical' || f.severity === 'warning').length;
  const maxCell = React.useMemo(() => {
    let best = { node: '', week: 0, count: 0 };
    cityData.forEach((d) => {
      if (d.shipment_count > best.count) best = { node: d.node_code, week: d.week_number, count: d.shipment_count };
    });
    return best;
  }, [cityData]);

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
        Normal
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
            {policy && (
              <div className="flex items-center gap-1">
                <span className="px-2 py-0.5 text-xs rounded-full bg-gray-200 text-gray-700">
                  {policy.datePolicy === 'daily' ? t('lb2.date_policy_daily') : t('lb2.date_policy_weekly')}
                </span>
                {policy.pobox && (
                  <span className="px-2 py-0.5 text-xs rounded-full bg-purple-100 text-purple-700">
                    {t('lb2.pobox')}
                  </span>
                )}
              </div>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-4 text-sm">
            {onScaleChange && (
              <div className="inline-flex rounded-md border border-gray-300 overflow-hidden" role="group">
                {(['day', 'week', 'month'] as LoadScale[]).map((sc) => (
                  <button
                    key={sc}
                    type="button"
                    onClick={() => onScaleChange(sc)}
                    aria-pressed={scale === sc}
                    className={`px-3 py-1 text-xs font-medium ${
                      scale === sc ? 'bg-blue-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'
                    }`}
                  >
                    {t(`lb2.scale_${sc}`)}
                  </button>
                ))}
              </div>
            )}
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
        {policy && onCityPolicyChange && (
          <div className="mt-3 flex flex-wrap items-center gap-3 text-xs text-gray-700">
            <label className="flex items-center gap-1">
              <span>{t('lb2.date_policy')}</span>
              <select
                value={policy.cityOverride.date_policy ?? ''}
                disabled={policy.pobox || balanceDisabled}
                title={policy.pobox ? t('lb2.pobox_forces_daily') : undefined}
                onChange={(e) =>
                  onCityPolicyChange({ date_policy: (e.target.value || null) as DatePolicy | null })
                }
                className="border border-gray-300 rounded px-2 py-1 disabled:bg-gray-100 disabled:text-gray-400"
              >
                <option value="">{t('lb2.city_policy_inherit')}</option>
                <option value="daily">{t('lb2.date_policy_daily')}</option>
                <option value="weekly">{t('lb2.date_policy_weekly')}</option>
              </select>
            </label>
            {policy.pobox && <span className="text-gray-500">{t('lb2.pobox_forces_daily')}</span>}
            <label className="flex items-center gap-1">
              <span>{t('lb2.pobox')}</span>
              <select
                value={policy.cityOverride.pobox_enabled === null ? '' : String(policy.cityOverride.pobox_enabled)}
                disabled={balanceDisabled}
                onChange={(e) =>
                  onCityPolicyChange({ pobox_enabled: e.target.value === '' ? null : e.target.value === 'true' })
                }
                className="border border-gray-300 rounded px-2 py-1 disabled:bg-gray-100 disabled:text-gray-400"
              >
                <option value="">{t('lb2.city_policy_inherit')}</option>
                <option value="true">{t('common.yes')}</option>
                <option value="false">{t('common.no')}</option>
              </select>
            </label>
          </div>
        )}
      </div>

      {scale === 'day' && (
        dayView.columns.length === 0 ? (
          <p className="px-6 py-8 text-center text-gray-500">{t('node_load_balancing.no_data_message')}</p>
        ) : (
          <>
            <div className="overflow-x-auto">
              <table className="text-sm border-collapse">
                <thead className="bg-gray-50 border-b border-gray-200">
                  <tr>
                    <th className="sticky left-0 z-10 bg-white px-4 py-2 text-left text-xs font-medium text-gray-500 uppercase">
                      {t('common.node')}
                    </th>
                    {dayView.columns.map((c) => (
                      <th
                        key={c.day}
                        className={`px-2 py-2 text-center text-xs font-medium ${
                          c.isWorkingDay ? 'text-gray-600' : 'text-gray-400 bg-gray-100'
                        }`}
                      >
                        <div>{t(`lb2.day_short.${c.dow}`)}</div>
                        <div>{c.dayNum}</div>
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {dayNodes.map(([nodeCode, panelist]) => (
                    <tr key={nodeCode}>
                      <td className="sticky left-0 z-10 bg-white px-4 py-2">
                        <div className="flex flex-col">
                          <span className="font-medium text-gray-900">{nodeCode}</span>
                          <span className="text-xs text-gray-500">{panelist || t('common.no_panelist')}</span>
                        </div>
                      </td>
                      {dayView.columns.map((c) => {
                        const r = dayView.cells.get(dayCellKey(nodeCode, c.day));
                        const shaded = r ? r.is_unavailable || !r.is_working_day : !c.isWorkingDay;
                        const bg = r?.is_unavailable ? UNAVAILABLE_CLASS : shaded ? 'bg-gray-100' : '';
                        const conflict = isConflict(r);
                        return (
                          <td key={c.day} className={`px-2 py-2 text-center min-w-[2.5rem] ${bg}`}>
                            {r ? (
                              <span className={conflict ? 'text-red-700 font-semibold' : 'text-gray-900'}>
                                {r.shipment_count}
                              </span>
                            ) : (
                              <span className="text-gray-300">—</span>
                            )}
                          </td>
                        );
                      })}
                    </tr>
                  ))}
                </tbody>
                <tfoot className="border-t-2 border-gray-300 bg-gray-50">
                  <tr>
                    <td className="sticky left-0 z-10 bg-gray-50 px-4 py-2 font-semibold text-gray-900">
                      {t('common.total')}
                    </td>
                    {dayView.columns.map((c) => {
                      const total = dayTotalsMap.get(c.day) ?? 0;
                      const gap = isPoboxGap(total, c.isWorkingDay, !!policy?.pobox);
                      return (
                        <td
                          key={c.day}
                          className={`px-2 py-2 text-center ${c.isWorkingDay ? '' : 'bg-gray-100'} ${gap ? 'bg-red-50' : ''}`}
                          title={gap ? t('lb2.pobox_gap_legend') : undefined}
                        >
                          <span className={gap ? 'text-red-700 font-bold' : 'font-semibold text-gray-900'}>{total}</span>
                        </td>
                      );
                    })}
                  </tr>
                </tfoot>
              </table>
            </div>
            <div className="flex flex-wrap items-center gap-4 px-6 py-2 text-xs text-gray-600 border-t border-gray-200">
              {policy?.pobox && (
                <span className="flex items-center gap-1">
                  <span className="text-red-700 font-bold">0</span>
                  {t('lb2.pobox_gap_legend')}
                </span>
              )}
              <span className="flex items-center gap-1">
                <span className={`inline-block w-4 h-4 border border-gray-300 ${UNAVAILABLE_CLASS}`} />
                {t('lb2.unavailable_legend')}
              </span>
              <span className="flex items-center gap-1">
                <span className="inline-block w-4 h-4 border border-gray-300 bg-gray-100" />
                {t('lb2.non_working_legend')}
              </span>
              <span className="flex items-center gap-1">
                <span className="text-red-700 font-semibold">1</span>
                {t('lb2.conflict_legend')}
              </span>
            </div>
          </>
        )
      )}

      {scale === 'month' && (
        monthView.months.length === 0 ? (
          <p className="px-6 py-8 text-center text-gray-500">{t('node_load_balancing.no_data_message')}</p>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead className="bg-gray-50 border-b border-gray-200">
                <tr>
                  <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('common.node')}</th>
                  {monthView.months.map((m) => (
                    <th key={m} className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">{m}</th>
                  ))}
                  <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                    {t('nodeloadbalancing.monthly_avg')}
                  </th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-200">
                {dayNodes.map(([nodeCode, panelist]) => (
                  <tr key={nodeCode} className="hover:bg-gray-50">
                    <td className="px-4 py-3">
                      <div className="flex flex-col">
                        <span className="font-medium text-gray-900">{nodeCode}</span>
                        <span className="text-xs text-gray-500">{panelist || t('common.no_panelist')}</span>
                      </div>
                    </td>
                    {monthView.months.map((m) => (
                      <td key={m} className="px-4 py-3 text-center text-gray-900">
                        {monthView.totals[nodeCode]?.[m] ?? 0}
                      </td>
                    ))}
                    <td className="px-4 py-3 text-center font-semibold text-gray-900">
                      {(monthView.nodeAverages[nodeCode] ?? 0).toFixed(1)}
                    </td>
                  </tr>
                ))}
                <tr className="bg-gray-50 font-semibold border-t-2 border-gray-300">
                  <td className="px-4 py-3 text-gray-900">{t('common.total')}</td>
                  {monthView.months.map((m) => (
                    <td key={m} className="px-4 py-3 text-center text-gray-900">{monthView.monthTotals[m] ?? 0}</td>
                  ))}
                  <td className="px-4 py-3 text-center text-gray-900">
                    {(monthView.grandTotal / monthView.months.length).toFixed(1)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        )
      )}

      {/* Heat Map Table */}
      {scale === 'week' && (
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                Nœud
              </th>
              {weeks.map((week) => (
                <th
                  key={week}
                  className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase"
                >
                  Semaine {week}
                </th>
              ))}
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                Moyenne mensuelle
              </th>
              <th className="px-4 py-3 text-center text-xs font-medium text-gray-500 uppercase">
                Statut
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
              <td className="px-4 py-3 text-gray-900">Total</td>
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
              <td className="px-4 py-3 text-gray-900">Moy/Nœud</td>
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
      )}

      {/* Recommendations Section */}
      <div className="bg-gradient-to-r from-blue-50 to-indigo-50 px-6 py-4 border-t border-gray-200">
        <button
          onClick={() => setIsRecommendationsExpanded(!isRecommendationsExpanded)}
          aria-expanded={isRecommendationsExpanded}
          className="w-full flex items-center justify-between hover:opacity-80 transition-opacity"
        >
          <div className="flex items-center gap-3">
            <h4 className="text-sm font-semibold text-gray-900">💡 {t('lb2.rec.title')}</h4>
            {actionableFindings > 0 && (
              <span className="px-2 py-0.5 rounded-full bg-red-100 text-red-700 text-xs font-semibold">{actionableFindings}</span>
            )}
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
          <div className="mt-4 space-y-3">
            <div>
              <p className="text-xs font-medium text-gray-700 mb-1">📊 {t('lb2.rec.analysis')}</p>
              <ul className="text-xs text-gray-700 space-y-1 ml-4">
                {findings.map((f) => (
                  <li key={f.code} className="flex items-start gap-1">
                    <span className={FINDING_BULLET[f.severity]}>•</span>
                    <span>{t(`lb2.rec.${f.code}`, f.params)}</span>
                  </li>
                ))}
              </ul>
            </div>

            {maxCell.count > 0 && (
              <div>
                <p className="text-xs font-medium text-gray-700 mb-1">📈 {t('lb2.rec.stats')}</p>
                <ul className="text-xs text-gray-600 space-y-1 ml-4">
                  <li className="flex items-start gap-1">
                    <span className="text-blue-600">•</span>
                    <span>{t('lb2.rec.stat_max', { node: maxCell.node, week: maxCell.week, count: maxCell.count })}</span>
                  </li>
                  <li className="flex items-start gap-1">
                    <span className="text-blue-600">•</span>
                    <span>{t('lb2.rec.stat_thresholds', { high: highThreshold.toFixed(1), saturated: saturatedThreshold.toFixed(1) })}</span>
                  </li>
                  <li className="flex items-start gap-1">
                    <span className="text-blue-600">•</span>
                    <span>{t('lb2.rec.stat_reference', { reference: referenceLoad, tolerance: deviationPercent.toFixed(0) })}</span>
                  </li>
                </ul>
              </div>
            )}
          </div>
        )}
      </div>

      {/* Actions */}
      <div className="bg-gray-50 px-6 py-4 border-t border-gray-200 flex items-center gap-3">
        <div className="group relative">
          <button
            onClick={onBalance}
            disabled={!needsBalancing || balanceDisabled}
            className={`flex items-center gap-2 px-4 py-2 rounded-md text-sm font-medium transition-colors ${
              needsBalancing
                ? 'bg-blue-600 text-white hover:bg-blue-700 cursor-pointer'
                : 'bg-gray-300 text-gray-500 cursor-not-allowed'
            }`}
          >
            <span>⚖️</span>
            {t('lb2.auto_balance_city', { city: cityName })}
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
            <p className="font-semibold mb-2 text-sm">🎯 {t('lb2.help.title')}</p>

            <p className="mb-2">{t('lb2.help.concept')}</p>

            <p className="mb-1 font-semibold">{t('lb2.help.rules_title')}</p>
            <ol className="list-decimal list-inside space-y-1 mb-2 ml-2">
              <li>{t('lb2.help.rule1')}</li>
              <li>{t('lb2.help.rule2')}</li>
              <li>{t('lb2.help.rule3')}</li>
              <li>{t('lb2.help.rule4')}</li>
              <li>{t('lb2.help.rule5')}</li>
              <li>{t('lb2.help.rule6')}</li>
              <li>{t('lb2.help.rule7')}</li>
            </ol>

            <p className="text-yellow-300">⚠️ {t('lb2.help.preview_warning')}</p>
          </div>
        </span>
      </div>
    </div>
  );
};
