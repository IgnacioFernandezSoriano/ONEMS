import React from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import type { DatePolicy } from '../../lib/workingDays';

interface BalancePoliciesPanelProps {
  workingDows: Set<number>;
  onToggleDay: (dow: number, on: boolean) => void;
  datePolicy: DatePolicy;
  pobox: boolean;
  onChangePolicy: (p: { date_policy?: DatePolicy; pobox_enabled?: boolean }) => void;
  onBalanceAll: () => void;
  balancingAll?: { done: number; total: number } | null;
  disabled?: boolean;
  /** Locks the working-day chips and the policy controls (e.g. while a balance is being applied) */
  locked?: boolean;
  /** Hint shown (as tooltip) when "Balance all" is disabled by missing input */
  balanceAllHint?: string;
}

const WEEK_ORDER = [1, 2, 3, 4, 5, 6, 0];
const FOCUS = 'focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-1';

export function BalancePoliciesPanel({
  workingDows,
  onToggleDay,
  datePolicy,
  pobox,
  onChangePolicy,
  onBalanceAll,
  balancingAll,
  disabled,
  locked = false,
  balanceAllHint,
}: BalancePoliciesPanelProps) {
  const { t } = useTranslation();
  const running = !!balancingAll;
  const policies: DatePolicy[] = ['daily', 'weekly'];

  return (
    <section
      aria-label={t('lb2.policies_title')}
      className="bg-white rounded-lg shadow-sm border border-gray-200 p-4"
    >
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-semibold text-gray-900">{t('lb2.policies_title')}</h2>
        <button
          type="button"
          onClick={onBalanceAll}
          disabled={disabled || running}
          title={disabled ? balanceAllHint : undefined}
          className={`px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${FOCUS}`}
        >
          {running
            ? t('lb2.balance_all_progress', { done: balancingAll!.done, total: balancingAll!.total })
            : t('lb2.balance_all')}
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Working days */}
        <div>
          <span id="lb2-working-days" className="block text-sm font-medium text-gray-700 mb-2">
            {t('lb2.working_days')}
          </span>
          <div role="group" aria-labelledby="lb2-working-days" className="flex flex-wrap gap-2">
            {WEEK_ORDER.map((dow) => {
              const on = workingDows.has(dow);
              return (
                <button
                  key={dow}
                  type="button"
                  aria-pressed={on}
                  disabled={locked}
                  onClick={() => onToggleDay(dow, !on)}
                  className={`px-3 py-1.5 text-sm font-medium rounded-full border transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${FOCUS} ${
                    on
                      ? 'bg-blue-600 text-white border-blue-600 hover:bg-blue-700'
                      : 'bg-white text-gray-600 border-gray-300 hover:bg-gray-50'
                  }`}
                >
                  {t(`lb2.day_short.${dow}`)}
                </button>
              );
            })}
          </div>
        </div>

        {/* Date policy */}
        <div>
          <span id="lb2-date-policy" className="block text-sm font-medium text-gray-700 mb-2">
            {t('lb2.date_policy')}
          </span>
          <div
            role="radiogroup"
            aria-labelledby="lb2-date-policy"
            aria-disabled={pobox || locked}
            title={pobox ? t('lb2.pobox_forces_daily') : undefined}
            className="inline-flex rounded-lg border border-gray-300 overflow-hidden"
          >
            {policies.map((p) => {
              const selected = datePolicy === p;
              return (
                <button
                  key={p}
                  type="button"
                  role="radio"
                  aria-checked={selected}
                  disabled={pobox || locked}
                  onClick={() => onChangePolicy({ date_policy: p })}
                  className={`px-4 py-1.5 text-sm font-medium transition-colors disabled:cursor-not-allowed disabled:opacity-60 ${FOCUS} ${
                    selected ? 'bg-blue-600 text-white' : 'bg-white text-gray-700 hover:bg-gray-50'
                  }`}
                >
                  {t(p === 'daily' ? 'lb2.date_policy_daily' : 'lb2.date_policy_weekly')}
                </button>
              );
            })}
          </div>
          {pobox ? (
            <p className="text-xs text-amber-700 mt-2">{t('lb2.pobox_forces_daily')}</p>
          ) : (
            <p className="text-xs text-gray-500 mt-2">{t('lb2.date_policy_help')}</p>
          )}
        </div>

        {/* POBOX */}
        <div>
          <label className="flex items-center gap-2 text-sm font-medium text-gray-700 cursor-pointer">
            <input
              type="checkbox"
              checked={pobox}
              disabled={locked}
              onChange={(e) => onChangePolicy({ pobox_enabled: e.target.checked })}
              className={`h-4 w-4 rounded border-gray-300 text-blue-600 disabled:opacity-50 disabled:cursor-not-allowed ${FOCUS}`}
            />
            {t('lb2.pobox')}
          </label>
          <p className="text-xs text-gray-500 mt-2">{t('lb2.pobox_help')}</p>
        </div>
      </div>
    </section>
  );
}
