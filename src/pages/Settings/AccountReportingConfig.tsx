import React, { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useEffectiveAccountId } from '@/hooks/useEffectiveAccountId';
import { useAccountReportingConfig, useCityClassifications } from '@/hooks/useAccountReportingConfig';
import { ThresholdSlider } from '@/components/settings/ThresholdSlider';
import { CityClassificationTable } from '@/components/settings/CityClassificationTable';
import { Save, AlertCircle, CheckCircle } from 'lucide-react';

import { useTranslation } from '@/hooks/useTranslation';
export default function AccountReportingConfig() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  // Cuenta efectiva: un superadmin no tiene account_id en el perfil, usa la cuenta seleccionada
  const effectiveAccountId = useEffectiveAccountId();
  const accountId = effectiveAccountId || profile?.account_id || undefined;
  
  const { config, loading: configLoading, error: configError, updateConfig } = useAccountReportingConfig(accountId);
  const { classifications, loading: classLoading, error: classError, updateClassification, deleteClassification } = useCityClassifications(accountId);

  const [warningThreshold, setWarningThreshold] = useState(85);
  const [criticalThreshold, setCriticalThreshold] = useState(75);
  const [reportPeriod, setReportPeriod] = useState<'week' | 'month' | 'quarter'>('week');
  const [hasChanges, setHasChanges] = useState(false);
  const [saveStatus, setSaveStatus] = useState<'idle' | 'saving' | 'success' | 'error'>('idle');

  // Load config into state when it arrives
  useEffect(() => {
    if (config) {
      setWarningThreshold(config.complianceThresholdWarning);
      setCriticalThreshold(config.complianceThresholdCritical);
      setReportPeriod(config.defaultReportPeriod);
    }
  }, [config]);

  // Track changes
  useEffect(() => {
    if (config) {
      const changed = 
        warningThreshold !== config.complianceThresholdWarning ||
        criticalThreshold !== config.complianceThresholdCritical ||
        reportPeriod !== config.defaultReportPeriod;
      setHasChanges(changed);
    }
  }, [warningThreshold, criticalThreshold, reportPeriod, config]);

  const handleSave = async () => {
    if (!accountId) return;

    // Validation
    if (warningThreshold <= criticalThreshold) {
      alert(t('hc.account_reporting_config.warning_gt_critical'));
      return;
    }

    setSaveStatus('saving');

    const result = await updateConfig({
      complianceThresholdWarning: warningThreshold,
      complianceThresholdCritical: criticalThreshold,
      defaultReportPeriod: reportPeriod
    });

    if (result?.success) {
      setSaveStatus('success');
      setHasChanges(false);
      setTimeout(() => setSaveStatus('idle'), 3000);
    } else {
      setSaveStatus('error');
      setTimeout(() => setSaveStatus('idle'), 3000);
    }
  };

  const handleReset = () => {
    if (config) {
      setWarningThreshold(config.complianceThresholdWarning);
      setCriticalThreshold(config.complianceThresholdCritical);
      setReportPeriod(config.defaultReportPeriod);
      setHasChanges(false);
    }
  };

  if (configLoading || classLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">{t('hc.account_reporting_config.loading')}</div>
      </div>
    );
  }

  if (configError || classError) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">
          {t('hc.account_reporting_config.error_loading', { message: (configError || classError)?.message })}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">{t('hc.account_reporting_config.title')}</h1>
        <p className="text-gray-600 mt-1">
          {t('hc.account_reporting_config.subtitle')}
        </p>
      </div>

      {/* General Settings Card */}
      <div className="bg-white rounded-lg shadow p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">{t('hc.account_reporting_config.general_settings')}</h2>
        
        <div className="space-y-6">
          <ThresholdSlider
            label={t('hc.account_reporting_config.warning_threshold')}
            value={warningThreshold}
            onChange={setWarningThreshold}
            color="yellow"
            description={t('hc.account_reporting_config.warning_desc')}
          />

          <ThresholdSlider
            label={t('hc.account_reporting_config.critical_threshold')}
            value={criticalThreshold}
            onChange={setCriticalThreshold}
            color="red"
            description={t('hc.account_reporting_config.critical_desc')}
          />

          <div className="space-y-2">
            <label className="block text-sm font-medium text-gray-700">
              {t('hc.account_reporting_config.default_period')}
            </label>
            <select
              value={reportPeriod}
              onChange={(e) => setReportPeriod(e.target.value as 'week' | 'month' | 'quarter')}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="week">{t('settings.weekly')}</option>
              <option value="month">{t('settings.monthly')}</option>
              <option value="quarter">{t('settings.quarterly')}</option>
            </select>
            <p className="text-xs text-gray-600">
              {t('hc.account_reporting_config.default_period_desc')}
            </p>
          </div>
        </div>

        {/* Save/Cancel Buttons */}
        <div className="flex items-center justify-between mt-6 pt-6 border-t">
          <div className="flex items-center gap-2">
            {saveStatus === 'success' && (
              <div className="flex items-center gap-2 text-green-600">
                <CheckCircle className="w-5 h-5" />
                <span className="text-sm font-medium">{t('hc.account_reporting_config.saved')}</span>
              </div>
            )}
            {saveStatus === 'error' && (
              <div className="flex items-center gap-2 text-red-600">
                <AlertCircle className="w-5 h-5" />
                <span className="text-sm font-medium">{t('hc.account_reporting_config.save_error')}</span>
              </div>
            )}
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={handleReset}
              disabled={!hasChanges || saveStatus === 'saving'}
              className="px-4 py-2 text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {t('hc.account_reporting_config.reset')}
            </button>
            <button
              onClick={handleSave}
              disabled={!hasChanges || saveStatus === 'saving'}
              className="flex items-center gap-2 px-4 py-2 text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <Save className="w-4 h-4" />
              {saveStatus === 'saving' ? t('hc.account_reporting_config.saving') : t('hc.account_reporting_config.save_changes')}
            </button>
          </div>
        </div>
      </div>

      {/* City Classification Card */}
      <div className="bg-white rounded-lg shadow p-6">
        <div className="mb-4">
          <h2 className="text-lg font-semibold text-gray-900">{t('hc.account_reporting_config.city_classifications')}</h2>
          <p className="text-sm text-gray-600 mt-1">
            {t('hc.account_reporting_config.city_classifications_desc')}
          </p>
        </div>

        <CityClassificationTable
          classifications={classifications}
          onUpdate={updateClassification}
          onDelete={deleteClassification}
        />
      </div>

      {/* Info Box */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
        <div className="flex gap-3">
          <AlertCircle className="w-5 h-5 text-blue-600 flex-shrink-0 mt-0.5" />
          <div className="text-sm text-blue-800">
            <p className="font-semibold mb-1">{t('hc.account_reporting_config.notes_title')}</p>
            <ul className="list-disc list-inside space-y-1">
              <li>{t('hc.account_reporting_config.note_warning')}</li>
              <li>{t('hc.account_reporting_config.note_changes')}</li>
              <li>{t('hc.account_reporting_config.note_classifications')}</li>
              <li>{t('hc.account_reporting_config.note_superadmin')}</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
