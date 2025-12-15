import React, { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useAccountReportingConfig, useCityClassifications } from '@/hooks/useAccountReportingConfig';
import { ThresholdSlider } from '@/components/settings/ThresholdSlider';
import { CityClassificationTable } from '@/components/settings/CityClassificationTable';
import { Save, AlertCircle, CheckCircle } from 'lucide-react';

export default function AccountReportingConfig() {
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;
  
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
      alert('Warning threshold must be greater than critical threshold');
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
        <div className="text-gray-500">Loading configuration...</div>
      </div>
    );
  }

  if (configError || classError) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">
          Error loading configuration: {(configError || classError)?.message}
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Account Reporting Configuration</h1>
        <p className="text-gray-600 mt-1">
          Configure reporting thresholds and city classifications for this account
        </p>
      </div>

      {/* General Settings Card */}
      <div className="bg-white rounded-lg shadow p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">General Settings</h2>
        
        <div className="space-y-6">
          <ThresholdSlider
            label="Compliance Warning Threshold"
            value={warningThreshold}
            onChange={setWarningThreshold}
            color="yellow"
            description="Shipments below this threshold will show a yellow warning"
          />

          <ThresholdSlider
            label="Compliance Critical Threshold"
            value={criticalThreshold}
            onChange={setCriticalThreshold}
            color="red"
            description="Shipments below this threshold will show a red alert"
          />

          <div className="space-y-2">
            <label className="block text-sm font-medium text-gray-700">
              Default Report Period
            </label>
            <select
              value={reportPeriod}
              onChange={(e) => setReportPeriod(e.target.value as 'week' | 'month' | 'quarter')}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="week">Weekly</option>
              <option value="month">Monthly</option>
              <option value="quarter">Quarterly</option>
            </select>
            <p className="text-xs text-gray-600">
              Default time period for generating reports
            </p>
          </div>
        </div>

        {/* Save/Cancel Buttons */}
        <div className="flex items-center justify-between mt-6 pt-6 border-t">
          <div className="flex items-center gap-2">
            {saveStatus === 'success' && (
              <div className="flex items-center gap-2 text-green-600">
                <CheckCircle className="w-5 h-5" />
                <span className="text-sm font-medium">Configuration saved successfully</span>
              </div>
            )}
            {saveStatus === 'error' && (
              <div className="flex items-center gap-2 text-red-600">
                <AlertCircle className="w-5 h-5" />
                <span className="text-sm font-medium">Error saving configuration</span>
              </div>
            )}
          </div>

          <div className="flex items-center gap-3">
            <button
              onClick={handleReset}
              disabled={!hasChanges || saveStatus === 'saving'}
              className="px-4 py-2 text-gray-700 bg-gray-100 rounded-lg hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              Reset
            </button>
            <button
              onClick={handleSave}
              disabled={!hasChanges || saveStatus === 'saving'}
              className="flex items-center gap-2 px-4 py-2 text-white bg-blue-600 rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <Save className="w-4 h-4" />
              {saveStatus === 'saving' ? 'Saving...' : 'Save Changes'}
            </button>
          </div>
        </div>
      </div>

      {/* City Classification Card */}
      <div className="bg-white rounded-lg shadow p-6">
        <div className="mb-4">
          <h2 className="text-lg font-semibold text-gray-900">City Classifications</h2>
          <p className="text-sm text-gray-600 mt-1">
            Define custom city classifications for this account. Cities not listed here will use default classifications.
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
            <p className="font-semibold mb-1">Configuration Notes:</p>
            <ul className="list-disc list-inside space-y-1">
              <li>Warning threshold must be greater than critical threshold</li>
              <li>Changes to thresholds will affect all reporting views</li>
              <li>City classifications override default classifications from the topology</li>
              <li>Only superadmin users can modify these settings</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
