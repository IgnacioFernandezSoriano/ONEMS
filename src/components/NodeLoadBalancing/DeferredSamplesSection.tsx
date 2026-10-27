import React, { useState } from 'react';
import type { DeferredSummary } from '../../hooks/useDeferredSamples';
import { useTranslation } from '../../hooks/useTranslation';

interface DeferredSamplesSectionProps {
  summary: DeferredSummary | null;
}

const th = 'px-3 py-2 text-xs font-medium text-gray-500 uppercase tracking-wider';

/** Seccion plegable (solo lectura) con las muestras por compensar: por ciudad de origen y por plan. */
export const DeferredSamplesSection: React.FC<DeferredSamplesSectionProps> = ({ summary }) => {
  const { t } = useTranslation();
  const [open, setOpen] = useState(true);

  // Sin resumen (sin cuenta seleccionada o RPC no disponible) no se muestra nada
  if (!summary) return null;

  const reasonLabel = (reason: string | null) => {
    if (!reason) return '—';
    const key = `lb2.deferred.waiting.${reason}`;
    const label = t(key);
    return label && label !== key ? label : reason;
  };

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200">
      <button
        type="button"
        onClick={() => setOpen(!open)}
        aria-expanded={open}
        className="w-full flex items-center justify-between p-4 text-left"
      >
        <div className="flex items-center gap-3">
          <svg
            className={`w-5 h-5 text-gray-600 transition-transform ${open ? '' : 'rotate-180'}`}
            fill="currentColor"
            viewBox="0 0 20 20"
          >
            <path fillRule="evenodd" d="M5 15l7-7 7 7" clipRule="evenodd" />
          </svg>
          <span className="text-lg font-semibold text-gray-900">{t('lb2.deferred.title')}</span>
        </div>
        <span className="text-sm text-gray-600">
          {t('lb2.deferred.pending_total')}:{' '}
          <span className="font-bold text-amber-700">{summary.pending_total}</span>
        </span>
      </button>

      {open && (
        <div className="p-4 border-t border-gray-200 space-y-6">
          {summary.pending_total === 0 && <p className="text-sm text-gray-500">{t('lb2.deferred.empty')}</p>}

          {summary.by_city.length > 0 && (
            <div>
              <h3 className="font-semibold text-gray-900 mb-2">{t('lb2.deferred.by_city')}</h3>
              <div className="overflow-x-auto border border-gray-200 rounded-lg">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className={`${th} text-left`}>{t('lb2.deferred.col_city')}</th>
                      <th className={`${th} text-center`}>{t('lb2.deferred.waiting')}</th>
                      <th className={`${th} text-left`}>{t('lb2.deferred.col_reason')}</th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {summary.by_city.map((c) => (
                      <tr key={c.city_id}>
                        <td className="px-3 py-2 text-sm font-medium text-gray-900">{c.city_name}</td>
                        <td className="px-3 py-2 text-center text-sm">{c.count}</td>
                        <td className="px-3 py-2 text-sm text-gray-700">{reasonLabel(c.waiting_reason)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {summary.by_plan.length > 0 && (
            <div>
              <h3 className="font-semibold text-gray-900 mb-2">{t('lb2.deferred.by_plan')}</h3>
              <div className="overflow-x-auto border border-gray-200 rounded-lg">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th className={`${th} text-left`}>{t('lb2.deferred.col_plan')}</th>
                      <th className={`${th} text-center`}>{t('lb2.deferred.col_total')}</th>
                      <th className={`${th} text-center`}>{t('lb2.deferred.col_scheduled')}</th>
                      <th className={`${th} text-center`}>{t('lb2.deferred.col_done')}</th>
                      <th className={`${th} text-center`}>{t('lb2.deferred.col_deferred')}</th>
                      <th className={`${th} text-center`}>{t('lb2.deferred.col_pobox_extra')}</th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {summary.by_plan.map((p) => (
                      <tr key={p.plan_id}>
                        <td className="px-3 py-2 text-sm font-medium text-gray-900">{p.plan_name}</td>
                        <td className="px-3 py-2 text-center text-sm">{p.total_samples}</td>
                        <td className="px-3 py-2 text-center text-sm">{p.scheduled}</td>
                        <td className="px-3 py-2 text-center text-sm">{p.done}</td>
                        <td className="px-3 py-2 text-center text-sm">{p.deferred}</td>
                        <td className="px-3 py-2 text-center text-sm">{p.pobox_extra}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          )}
        </div>
      )}
    </div>
  );
};
