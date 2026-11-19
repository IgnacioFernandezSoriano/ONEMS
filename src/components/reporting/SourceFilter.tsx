import { useEffect, useState } from 'react';
import { supabase } from '@/lib/supabase';
import { useTranslation } from '@/hooks/useTranslation';

export type DataSource = '' | 'panelist' | 'carrier';

/**
 * Indica si la cuenta tiene filas de cada origen en one_db.
 * Consulta con head:true y acotada a la cuenta, igual que el resto de consultas de filtros.
 */
export function useSourcePresence(accountId: string | undefined) {
  const [presence, setPresence] = useState({ carrier: false, panelist: false });

  useEffect(() => {
    let cancelled = false;
    async function load() {
      if (!accountId) {
        setPresence({ carrier: false, panelist: false });
        return;
      }
      try {
        const [carrierRes, panelistRes] = await Promise.all([
          supabase.from('one_db').select('id', { count: 'exact', head: true }).eq('account_id', accountId).eq('source', 'carrier'),
          supabase.from('one_db').select('id', { count: 'exact', head: true }).eq('account_id', accountId).eq('source', 'panelist'),
        ]);
        if (cancelled) return;
        setPresence({
          carrier: (carrierRes.count ?? 0) > 0,
          panelist: (panelistRes.count ?? 0) > 0,
        });
      } catch (error) {
        if (cancelled) return;
        console.error('Error checking data sources:', error);
      }
    }
    load();
    return () => { cancelled = true; };
  }, [accountId]);

  return presence;
}

interface SourceFilterProps {
  accountId: string | undefined;
  value: DataSource;
  onChange: (value: DataSource) => void;
}

/** Selector "Origen del dato": solo aparece si la cuenta tiene muestras de carrier. */
export function SourceFilter({ accountId, value, onChange }: SourceFilterProps) {
  const { t } = useTranslation();
  const { carrier, panelist } = useSourcePresence(accountId);

  if (!carrier) return null;

  return (
    <div className="mt-4">
      <label className="block text-sm font-medium text-gray-700 mb-1">
        {t('reporting.data_source')}
      </label>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value as DataSource)}
        className="w-full md:w-64 px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
      >
        <option value="">{t('reporting.source_all')}</option>
        <option value="panelist">{t('reporting.source_panelists')}</option>
        <option value="carrier">{t('reporting.source_carrier')}</option>
      </select>
      {value === '' && panelist && (
        <p className="mt-2 text-xs text-amber-800 bg-amber-50 border border-amber-200 rounded-lg p-2">
          {t('reporting.source_method_note')}
        </p>
      )}
    </div>
  );
}
