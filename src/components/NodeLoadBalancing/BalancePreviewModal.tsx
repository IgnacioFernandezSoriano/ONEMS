import React, { useState } from 'react';
import type { BalanceResult, BalanceMovement, MatrixCell } from '../../hooks/useNodeLoadBalancing';
import { useTranslation } from '../../hooks/useTranslation';
import { cityHasChanges, groupMatrixByWeek, isCityFailed, totalsForAllCities } from '../../lib/balanceViews';

export interface BalanceCityResult {
  cityId: string;
  cityName: string;
  result?: BalanceResult;
  error?: string;
}

interface BalancePreviewModalProps {
  isOpen: boolean;
  mode: 'city' | 'all';
  cityName?: string;
  results: BalanceCityResult[];
  loading: boolean;
  progress?: { done: number; total: number } | null;
  /** An apply is running: close, cancel and confirm are locked */
  applying?: boolean;
  onClose: () => void;
  onConfirm: () => void;
}

const fmt = (n: number | null | undefined, digits = 1) => (n != null ? n.toFixed(digits) : 'N/A');

const hasChanges = cityHasChanges;

export const BalancePreviewModal: React.FC<BalancePreviewModalProps> = ({
  isOpen,
  mode,
  cityName,
  results,
  loading,
  progress,
  applying = false,
  onClose,
  onConfirm,
}) => {
  const { t } = useTranslation();
  if (!isOpen) return null;

  const single = results[0];
  const canApply = mode === 'city'
    ? hasChanges(single?.result) && !single?.error
    : results.some((r) => !isCityFailed(r) && hasChanges(r.result));

  // Muestras que se apartarian del plan al aplicar (ciudad: la suya; todas: suma de las ciudades correctas)
  const removedTotal = mode === 'city'
    ? (single?.error || single?.result?.error ? 0 : single?.result?.deferred?.removed ?? 0)
    : totalsForAllCities(results).deferredRemoved;

  const title = mode === 'all'
    ? t('lb2.preview_all_title')
    : `${t('nodeLoadBalancing.balancePreview')} - ${cityName ?? ''}`;

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50 p-4">
      <div className="bg-white rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] overflow-hidden flex flex-col">
        {/* Header */}
        <div className="px-6 py-4 border-b border-gray-200">
          <div className="flex items-center justify-between">
            <h2 className="text-xl font-semibold text-gray-900">{title}</h2>
            <button
              onClick={onClose}
              disabled={applying}
              aria-label={t('common.close')}
              className="text-gray-400 hover:text-gray-600 transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
            >
              <span className="text-2xl">×</span>
            </button>
          </div>
        </div>

        {/* Content */}
        <div className="flex-1 overflow-y-auto p-6">
          {loading && (
            <div className="flex items-center justify-center py-12">
              <div className="flex flex-col items-center gap-3 text-gray-600">
                <div className="flex items-center gap-3">
                  <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-gray-600"></div>
                  <span>
                    {progress && progress.total > 0
                      ? t('lb2.balance_all_progress', { done: progress.done, total: progress.total })
                      : t('nodeloadbalancing.calculating_balance_preview')}
                  </span>
                </div>
                {progress && progress.total > 0 && (
                  <div className="w-64 h-2 bg-gray-200 rounded-full overflow-hidden">
                    <div
                      className="h-2 bg-blue-600 transition-all"
                      style={{ width: `${Math.round((progress.done / progress.total) * 100)}%` }}
                    />
                  </div>
                )}
              </div>
            </div>
          )}

          {!loading && mode === 'city' && single && <CityBody item={single} />}

          {!loading && mode === 'all' && <AllBody results={results} />}
        </div>

        {/* Aviso rojo: muestras que se apartarian del plan (justo encima del boton de confirmar) */}
        {!loading && removedTotal > 0 && (
          <div role="alert" className="mx-6 mb-3 bg-red-50 border border-red-300 rounded-lg p-3 text-sm font-medium text-red-800">
            {t('lb2.deferred.remove_warning', { count: removedTotal })}
          </div>
        )}

        {/* Footer */}
        <div className="px-6 py-4 border-t border-gray-200 flex items-center justify-between">
          <button
            onClick={onClose}
            disabled={applying}
            className="px-4 py-2 text-gray-700 hover:text-gray-900 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {t('common.cancel')}
          </button>
          <button
            onClick={onConfirm}
            disabled={loading || applying || !canApply}
            className="px-6 py-2 bg-blue-600 text-white rounded-md font-medium hover:bg-blue-700 transition-colors disabled:bg-gray-300 disabled:cursor-not-allowed"
          >
            {loading ? t('nodeLoadBalancing.loading') : t('nodeLoadBalancing.applyBalance')}
          </button>
        </div>
      </div>
    </div>
  );
};

// ---------------------------------------------------------------- city mode

const WarningsList: React.FC<{ result: BalanceResult }> = ({ result }) => {
  const { t } = useTranslation();
  const warnings = result.warnings || [];
  if (warnings.length === 0) return null;
  return (
    <div className="bg-orange-50 border border-orange-300 rounded-lg p-4 mb-6">
      <h3 className="font-semibold text-orange-900 mb-2">{t('lb2.warnings_title')}</h3>
      <ul className="space-y-1 text-sm text-orange-800">
        {warnings.map((w, i) => {
          const key = `lb2.warning.${w.code}`;
          const label = t(key);
          return (
            <li key={`${w.code}-${i}`}>
              {label && label !== key ? label : w.code} ({w.count}){w.detail ? ` - ${w.detail}` : ''}
            </li>
          );
        })}
      </ul>
    </div>
  );
};

const CityBody: React.FC<{ item: BalanceCityResult }> = ({ item }) => {
  const { t } = useTranslation();
  const r = item.result;
  const errorText = item.error || r?.error || (r && r.success === false ? r.message : undefined);

  if (errorText || !r) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-4">
        <p className="text-red-700">{t('common.error')}: {errorText || ''}</p>
      </div>
    );
  }

  const pobox = r.pobox;
  const showPobox = !!pobox && (r.policy?.pobox_enabled === true ||
    pobox.days_missing + pobox.days_moved + pobox.days_created + pobox.days_uncovered > 0);

  return (
    <>
      {/* Summary */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4 mb-6">
        <h3 className="font-semibold text-blue-900 mb-3">{t('nodeloadbalancing.summary')}</h3>
        <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
          <div>
            <div className="text-sm text-blue-700">{t('nodeloadbalancing.movements')}</div>
            <div className="text-2xl font-bold text-blue-900">{r.movements_count}</div>
          </div>
          <div>
            <div className="text-sm text-blue-700">{t('nodeloadbalancing.std_dev_before')}</div>
            <div className="text-2xl font-bold text-blue-900">{fmt(r.stddev_before)}</div>
          </div>
          <div>
            <div className="text-sm text-blue-700">{t('nodeloadbalancing.std_dev_after')}</div>
            <div className="text-2xl font-bold text-green-700">{fmt(r.stddev_after)}</div>
          </div>
          <div>
            <div className="text-sm text-blue-700">{t('nodeloadbalancing.improvement')}</div>
            <div className="text-2xl font-bold text-green-700">{fmt(r.improvement_percentage)}%</div>
          </div>
        </div>
      </div>

      {/* POBOX */}
      {showPobox && pobox && (
        <div className="bg-purple-50 border border-purple-200 rounded-lg p-4 mb-6">
          <h3 className="font-semibold text-purple-900 mb-3">{t('lb2.pobox')}</h3>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            {([
              ['lb2.pobox_days_missing', pobox.days_missing],
              ['lb2.pobox_days_moved', pobox.days_moved],
              ['lb2.pobox_days_created', pobox.days_created],
              ['lb2.pobox_days_uncovered', pobox.days_uncovered],
            ] as const).map(([k, v]) => (
              <div key={k}>
                <div className="text-sm text-purple-700">{t(k)}</div>
                <div className="text-2xl font-bold text-purple-900">{v}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Muestras por compensar */}
      {r.deferred && (
        <div className="bg-amber-50 border border-amber-200 rounded-lg p-4 mb-6">
          <h3 className="font-semibold text-amber-900 mb-3">{t('lb2.deferred.title')}</h3>
          <div className="grid grid-cols-2 md:grid-cols-5 gap-4">
            {([
              ['lb2.deferred.removed', r.deferred.removed],
              ['lb2.deferred.reassigned_dest', r.deferred.reassigned_dest],
              ['lb2.deferred.reintroduced', r.deferred.reintroduced],
              ['lb2.deferred.waiting', r.deferred.waiting],
              ['lb2.deferred.blocked', r.deferred.blocked ?? 0],
            ] as const).map(([k, v]) => (
              <div key={k}>
                <div className="text-sm text-amber-700">{t(k)}</div>
                <div className="text-2xl font-bold text-amber-900">{v}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      <WarningsList result={r} />

      {!hasChanges(r) && (
        <div className="bg-green-50 border border-green-200 rounded-lg p-4">
          <p className="text-green-700">✓ {t('lb2.city_balanced')}</p>
        </div>
      )}

      {hasChanges(r) && (
        <MatrixVisualization
          matrixBefore={r.matrix_before}
          matrixAfter={r.matrix_after}
          movements={r.movements}
          movementsCount={r.movements_count}
        />
      )}
    </>
  );
};

// ---------------------------------------------------------------- all mode

const AllBody: React.FC<{ results: BalanceCityResult[] }> = ({ results }) => {
  const { t } = useTranslation();
  if (results.length === 0) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-4">
        <p className="text-gray-600">{t('lb2.no_pending_cities')}</p>
      </div>
    );
  }
  const totals = totalsForAllCities(results);
  const th = 'px-3 py-2 text-xs font-medium text-gray-500 uppercase tracking-wider';
  return (
    <div className="overflow-x-auto border border-gray-200 rounded-lg">
      <table className="min-w-full divide-y divide-gray-200">
        <thead className="bg-gray-50">
          <tr>
            <th className={`${th} text-left`}>{t('common.city')}</th>
            <th className={`${th} text-center`}>{t('nodeloadbalancing.movements')}</th>
            <th className={`${th} text-center`}>
              {t('nodeloadbalancing.std_dev_before')} → {t('nodeloadbalancing.std_dev_after')}
            </th>
            <th className={`${th} text-center`}>{t('nodeloadbalancing.improvement')}</th>
            <th className={`${th} text-center`}>{t('lb2.pobox_days_moved')}</th>
            <th className={`${th} text-center`}>{t('lb2.pobox_days_created')}</th>
            <th className={`${th} text-center`}>{t('lb2.pobox_days_uncovered')}</th>
            <th className={`${th} text-center`}>{t('lb2.deferred.removed')}</th>
            <th className={`${th} text-center`}>{t('lb2.deferred.reassigned_dest')}</th>
            <th className={`${th} text-center`}>{t('lb2.deferred.reintroduced')}</th>
            <th className={`${th} text-center`}>{t('lb2.deferred.waiting')}</th>
            <th className={`${th} text-center`}>{t('lb2.warnings_title')}</th>
          </tr>
        </thead>
        <tbody className="bg-white divide-y divide-gray-200">
          {results.map((row) => {
            if (isCityFailed(row)) {
              const msg = row.error || row.result?.error || row.result?.message || '';
              return (
                <tr key={row.cityId} className="bg-red-50">
                  <td className="px-3 py-2 text-sm font-medium text-red-800">{row.cityName}</td>
                  <td colSpan={11} className="px-3 py-2 text-sm text-red-700">
                    {t('lb2.city_failed', { city: row.cityName })}{msg ? `: ${msg}` : ''}
                  </td>
                </tr>
              );
            }
            const r = row.result!;
            return (
              <tr key={row.cityId}>
                <td className="px-3 py-2 text-sm font-medium text-gray-900">{row.cityName}</td>
                <td className="px-3 py-2 text-center text-sm">{r.movements_count}</td>
                <td className="px-3 py-2 text-center text-sm">
                  {fmt(r.stddev_before)} → <span className="text-green-700 font-semibold">{fmt(r.stddev_after)}</span>
                </td>
                <td className="px-3 py-2 text-center text-sm text-green-700">{fmt(r.improvement_percentage)}%</td>
                <td className="px-3 py-2 text-center text-sm">{r.pobox?.days_moved ?? 0}</td>
                <td className="px-3 py-2 text-center text-sm">{r.pobox?.days_created ?? 0}</td>
                <td className="px-3 py-2 text-center text-sm">{r.pobox?.days_uncovered ?? 0}</td>
                <td className="px-3 py-2 text-center text-sm">{r.deferred?.removed ?? 0}</td>
                <td className="px-3 py-2 text-center text-sm">{r.deferred?.reassigned_dest ?? 0}</td>
                <td className="px-3 py-2 text-center text-sm">{r.deferred?.reintroduced ?? 0}</td>
                <td className="px-3 py-2 text-center text-sm">{r.deferred?.waiting ?? 0}</td>
                <td className="px-3 py-2 text-center text-sm">{(r.warnings || []).length}</td>
              </tr>
            );
          })}
          <tr className="bg-gray-50 font-semibold">
            <td className="px-3 py-2 text-sm text-gray-900">{t('common.total')}</td>
            <td className="px-3 py-2 text-center text-sm">{totals.movements}</td>
            <td className="px-3 py-2 text-center text-sm text-gray-400">-</td>
            <td className="px-3 py-2 text-center text-sm text-gray-400">-</td>
            <td className="px-3 py-2 text-center text-sm">{totals.poboxMoved}</td>
            <td className="px-3 py-2 text-center text-sm">{totals.poboxCreated}</td>
            <td className="px-3 py-2 text-center text-sm">{totals.poboxUncovered}</td>
            <td className="px-3 py-2 text-center text-sm">{totals.deferredRemoved}</td>
            <td className="px-3 py-2 text-center text-sm">{totals.deferredReassignedDest}</td>
            <td className="px-3 py-2 text-center text-sm">{totals.deferredReintroduced}</td>
            <td className="px-3 py-2 text-center text-sm">{totals.deferredWaiting}</td>
            <td className="px-3 py-2 text-center text-sm">{totals.warnings}</td>
          </tr>
        </tbody>
      </table>
    </div>
  );
};

// ------------------------------------------------- matrix + movements (city)

interface MatrixVisualizationProps {
  matrixBefore?: MatrixCell[];
  matrixAfter?: MatrixCell[];
  movements: BalanceMovement[];
  movementsCount: number;
}

const MatrixVisualization: React.FC<MatrixVisualizationProps> = ({
  matrixBefore,
  matrixAfter,
  movements,
  movementsCount,
}) => {
  const { t } = useTranslation();
  const [activeTab, setActiveTab] = useState<'matrix' | 'movements'>('matrix');
  const [matrixView, setMatrixView] = useState<'before' | 'after'>('before');

  if (!matrixBefore || !matrixAfter || matrixBefore.length === 0) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-4">
        <p className="text-gray-600">{t('nodeloadbalancing.matrix_data_not_available')}</p>
      </div>
    );
  }

  // Columnas por semana: en politica diaria se suman los dias de cada semana
  const { nodes, weeks, lookup } = groupMatrixByWeek(matrixView === 'before' ? matrixBefore : matrixAfter);
  const val = (node: string, weekKey: string) => lookup[`${node}|${weekKey}`] || 0;

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
          {t('nodeLoadBalancing.matrixView')}
        </button>
        <button
          onClick={() => setActiveTab('movements')}
          className={`px-4 py-2 font-medium transition-colors ${
            activeTab === 'movements'
              ? 'border-b-2 border-blue-600 text-blue-600'
              : 'text-gray-600 hover:text-gray-900'
          }`}
        >
          {t('nodeloadbalancing.movements')} ({movementsCount})
        </button>
      </div>

      {activeTab === 'matrix' && (
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <h3 className="font-semibold text-gray-900">{t('nodeLoadBalancing.loadDistributionMatrix')}</h3>
            <div className="flex gap-2">
              <button
                onClick={() => setMatrixView('before')}
                className={`px-3 py-1 rounded-md text-sm font-medium transition-colors ${
                  matrixView === 'before' ? 'bg-blue-600 text-white' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
                }`}
              >
                {t('nodeLoadBalancing.before')}
              </button>
              <button
                onClick={() => setMatrixView('after')}
                className={`px-3 py-1 rounded-md text-sm font-medium transition-colors ${
                  matrixView === 'after' ? 'bg-green-600 text-white' : 'bg-gray-200 text-gray-700 hover:bg-gray-300'
                }`}
              >
                {t('nodeLoadBalancing.after')}
              </button>
            </div>
          </div>

          <div className="overflow-x-auto border border-gray-200 rounded-lg">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th className="px-3 py-2 text-left text-xs font-medium text-gray-500 uppercase tracking-wider sticky left-0 bg-gray-50">
                    {t('nodeloadbalancing.node')}
                  </th>
                  {weeks.map((w) => (
                    <th key={w.key} className="px-3 py-2 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                      {t('lb2.week_short', { week: w.weekNum })}
                    </th>
                  ))}
                  <th className="px-3 py-2 text-center text-xs font-medium text-gray-500 uppercase tracking-wider">
                    {t('common.total')}
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {nodes.map((node) => (
                  <tr key={node}>
                    <td className="px-3 py-2 text-sm font-medium text-gray-900 sticky left-0 bg-white">{node}</td>
                    {weeks.map((w) => {
                      const count = val(node, w.key);
                      return (
                        <td key={w.key} className={`px-3 py-2 text-center text-sm font-semibold ${getColorClass(count)}`}>
                          {count}
                        </td>
                      );
                    })}
                    <td className="px-3 py-2 text-center text-sm font-bold text-gray-900 bg-gray-50">
                      {weeks.reduce((s, w) => s + val(node, w.key), 0)}
                    </td>
                  </tr>
                ))}
                <tr className="bg-gray-50 font-semibold">
                  <td className="px-3 py-2 text-sm text-gray-900">{t('common.total')}</td>
                  {weeks.map((w) => (
                    <td key={w.key} className="px-3 py-2 text-center text-sm text-gray-900">
                      {nodes.reduce((s, n) => s + val(n, w.key), 0)}
                    </td>
                  ))}
                  <td className="px-3 py-2 text-center text-sm font-bold text-gray-900">
                    {nodes.reduce((s, n) => s + weeks.reduce((ws, w) => ws + val(n, w.key), 0), 0)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>

          <div className="flex items-center gap-4 text-xs text-gray-600">
            <span className="font-medium">{t('nodeLoadBalancing.loadLevel')}:</span>
            {[
              ['bg-gray-100 border-gray-300', '0'],
              ['bg-green-100 border-green-300', '1-5'],
              ['bg-yellow-100 border-yellow-300', '6-10'],
              ['bg-orange-100 border-orange-300', '11-15'],
              ['bg-red-100 border-red-300', '16+'],
            ].map(([cls, label]) => (
              <div key={label} className="flex items-center gap-2">
                <div className={`w-4 h-4 border ${cls}`}></div>
                <span>{label}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {activeTab === 'movements' && (
        <div className="space-y-3">
          <h3 className="font-semibold text-gray-900">{t('lb2.planned_movements')} ({movementsCount})</h3>
          {movements.length < movementsCount && (
            <p className="text-xs text-gray-500">
              {t('lb2.movements_truncated', { shown: movements.length, total: movementsCount })}
            </p>
          )}
          <div className="space-y-2 max-h-96 overflow-y-auto">
            {movements.map((m, index) => (
              <div key={index} className="border border-gray-200 rounded-lg p-3 hover:bg-gray-50 text-sm">
                <div className="font-medium text-gray-900">{t('lb2.shipments_count', { count: m.count })}</div>
                <div className="text-xs text-gray-600">
                  {m.from_node_code} ({m.from_date}) → {m.to_node_code} ({m.to_date})
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
};
