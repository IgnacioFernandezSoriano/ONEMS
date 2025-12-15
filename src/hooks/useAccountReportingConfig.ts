import { useState, useEffect } from 'react';
import { supabase } from '@/lib/supabase';

export interface AccountReportingConfig {
  accountId: string;
  complianceThresholdWarning: number;
  complianceThresholdCritical: number;
  defaultReportPeriod: 'week' | 'month' | 'quarter';
}

export interface CityClassification {
  id: string;
  accountId: string;
  cityId: string;
  cityName: string;
  classification: 'capital' | 'major' | 'minor';
}

export function useAccountReportingConfig(accountId: string | undefined) {
  const [config, setConfig] = useState<AccountReportingConfig | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!accountId) {
      setLoading(false);
      return;
    }

    async function fetchConfig() {
      try {
        setLoading(true);
        const { data, error: err } = await supabase
          .rpc('get_account_reporting_config', { p_account_id: accountId });

        if (err) throw err;

        if (data && data.length > 0) {
          const row = data[0];
          setConfig({
            accountId: row.account_id,
            complianceThresholdWarning: row.compliance_threshold_warning,
            complianceThresholdCritical: row.compliance_threshold_critical,
            defaultReportPeriod: row.default_report_period
          });
        }
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchConfig();
  }, [accountId]);

  const updateConfig = async (newConfig: Partial<AccountReportingConfig>) => {
    if (!accountId) return;

    try {
      const { error: err } = await supabase
        .from('account_reporting_config')
        .upsert({
          account_id: accountId,
          compliance_threshold_warning: newConfig.complianceThresholdWarning,
          compliance_threshold_critical: newConfig.complianceThresholdCritical,
          default_report_period: newConfig.defaultReportPeriod
        });

      if (err) throw err;

      // Refresh config
      const { data } = await supabase
        .rpc('get_account_reporting_config', { p_account_id: accountId });

      if (data && data.length > 0) {
        const row = data[0];
        setConfig({
          accountId: row.account_id,
          complianceThresholdWarning: row.compliance_threshold_warning,
          complianceThresholdCritical: row.compliance_threshold_critical,
          defaultReportPeriod: row.default_report_period
        });
      }

      return { success: true };
    } catch (err) {
      return { success: false, error: err as Error };
    }
  };

  return { config, loading, error, updateConfig };
}

export function useCityClassifications(accountId: string | undefined) {
  const [classifications, setClassifications] = useState<CityClassification[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    if (!accountId) {
      setLoading(false);
      return;
    }

    async function fetchClassifications() {
      try {
        setLoading(true);
        const { data, error: err } = await supabase
          .from('account_city_classification')
          .select(`
            id,
            account_id,
            city_id,
            classification,
            cities (
              name
            )
          `)
          .eq('account_id', accountId);

        if (err) throw err;

        const mapped = (data || []).map(row => ({
          id: row.id,
          accountId: row.account_id,
          cityId: row.city_id,
          cityName: (row.cities as any)?.name || 'Unknown',
          classification: row.classification as 'capital' | 'major' | 'minor'
        }));

        setClassifications(mapped);
      } catch (err) {
        setError(err as Error);
      } finally {
        setLoading(false);
      }
    }

    fetchClassifications();
  }, [accountId]);

  const updateClassification = async (
    cityId: string,
    classification: 'capital' | 'major' | 'minor'
  ) => {
    if (!accountId) return { success: false, error: new Error('No account ID') };

    try {
      const { error: err } = await supabase
        .from('account_city_classification')
        .upsert({
          account_id: accountId,
          city_id: cityId,
          classification
        });

      if (err) throw err;

      // Refresh classifications
      const { data } = await supabase
        .from('account_city_classification')
        .select(`
          id,
          account_id,
          city_id,
          classification,
          cities (
            name
          )
        `)
        .eq('account_id', accountId);

      if (data) {
        const mapped = data.map(row => ({
          id: row.id,
          accountId: row.account_id,
          cityId: row.city_id,
          cityName: (row.cities as any)?.name || 'Unknown',
          classification: row.classification as 'capital' | 'major' | 'minor'
        }));
        setClassifications(mapped);
      }

      return { success: true };
    } catch (err) {
      return { success: false, error: err as Error };
    }
  };

  const deleteClassification = async (cityId: string) => {
    if (!accountId) return { success: false, error: new Error('No account ID') };

    try {
      const { error: err } = await supabase
        .from('account_city_classification')
        .delete()
        .eq('account_id', accountId)
        .eq('city_id', cityId);

      if (err) throw err;

      // Remove from state
      setClassifications(prev => prev.filter(c => c.cityId !== cityId));

      return { success: true };
    } catch (err) {
      return { success: false, error: err as Error };
    }
  };

  return { classifications, loading, error, updateClassification, deleteClassification };
}
