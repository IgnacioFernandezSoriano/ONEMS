import React, { useEffect, useState } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import type { PoboxProductShare } from '../../hooks/useBalancePolicies';

interface PoboxProductSharesProps {
  shares: PoboxProductShare[];
  onSave: (shares: { product_id: string; pct: number }[]) => Promise<{ success: boolean; error?: string }>;
  locked?: boolean;
}

const FOCUS = 'focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-500 focus-visible:ring-offset-1';

/** Reparto de las muestras POBOX extra por producto (porcentajes enteros que suman 100; todo 0 = sin reparto). */
export function PoboxProductShares({ shares, onSave, locked = false }: PoboxProductSharesProps) {
  const { t } = useTranslation();
  const [draft, setDraft] = useState<Record<string, number>>({});
  const [saving, setSaving] = useState(false);
  const [message, setMessage] = useState<{ type: 'ok' | 'error'; text: string } | null>(null);

  useEffect(() => {
    setDraft(Object.fromEntries(shares.map((s) => [s.product_id, s.pct])));
  }, [shares]);

  const sum = Object.values(draft).reduce((a, b) => a + (Number.isFinite(b) ? b : 0), 0);
  const dirty = shares.some((s) => (draft[s.product_id] ?? 0) !== s.pct);
  const valid = sum === 0 || sum === 100;

  const save = async () => {
    setSaving(true);
    setMessage(null);
    const res = await onSave(shares.map((s) => ({ product_id: s.product_id, pct: draft[s.product_id] ?? 0 })));
    setSaving(false);
    setMessage(res.success
      ? { type: 'ok', text: t('lb2.pobox_shares_saved') }
      : { type: 'error', text: res.error === 'shares_must_sum_100' ? t('lb2.pobox_shares_sum_error') : (res.error ?? 'Error') });
  };

  if (shares.length === 0) {
    return <p className="text-xs text-gray-500">{t('lb2.pobox_shares_no_products')}</p>;
  }

  return (
    <div className="border-t border-gray-200 pt-4 mt-4">
      <h3 className="text-sm font-semibold text-gray-900">{t('lb2.pobox_shares_title')}</h3>
      <p className="text-xs text-gray-500 mt-1 mb-3">{t('lb2.pobox_shares_help')}</p>
      <div className="overflow-x-auto">
        <table className="min-w-full text-sm">
          <thead>
            <tr className="text-left text-xs font-medium text-gray-500 uppercase">
              <th className="py-1 pe-4">{t('lb2.pobox_shares_product')}</th>
              <th className="py-1 pe-4 text-center">%</th>
              <th className="py-1 text-center">{t('lb2.pobox_shares_current')}</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-100">
            {shares.map((s) => (
              <tr key={s.product_id}>
                <td className="py-1.5 pe-4">
                  <div className="font-medium text-gray-900">{s.code}</div>
                  {s.description && <div className="text-xs text-gray-500">{s.description}</div>}
                </td>
                <td className="py-1.5 pe-4 text-center">
                  <input
                    type="number"
                    min={0}
                    max={100}
                    step={1}
                    value={draft[s.product_id] ?? 0}
                    disabled={locked || saving}
                    aria-label={`${s.code} %`}
                    onChange={(e) => {
                      const v = Math.max(0, Math.min(100, Math.round(Number(e.target.value) || 0)));
                      setDraft((d) => ({ ...d, [s.product_id]: v }));
                    }}
                    className={`w-20 border border-gray-300 rounded-md py-1 px-2 text-sm text-center disabled:opacity-50 ${FOCUS}`}
                  />
                </td>
                <td className="py-1.5 text-center text-gray-700">{s.pobox_count}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <div className="flex flex-wrap items-center gap-3 mt-3">
        <span className={`text-sm font-medium ${valid ? 'text-gray-700' : 'text-red-600'}`}>
          {t('lb2.pobox_shares_total', { total: sum })}
        </span>
        <button
          type="button"
          onClick={save}
          disabled={locked || saving || !dirty || !valid}
          className={`px-3 py-1.5 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed ${FOCUS}`}
        >
          {t('common.save')}
        </button>
        {!valid && <span className="text-xs text-red-600">{t('lb2.pobox_shares_sum_error')}</span>}
        {message && (
          <span className={`text-xs ${message.type === 'ok' ? 'text-green-700' : 'text-red-600'}`}>{message.text}</span>
        )}
      </div>
    </div>
  );
}
