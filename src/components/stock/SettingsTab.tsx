import React, { useState, useEffect } from 'react'
import { Save, AlertCircle, Settings } from 'lucide-react'
import { useStockManagement } from '../../hooks/useStockManagement'
import { SmartTooltip } from '../common/SmartTooltip'

import { useTranslation } from '@/hooks/useTranslation';
export default function SettingsTab() {
  const { t } = useTranslation();
  const { settings, loading, updateSettings } = useStockManagement()
  const [formData, setFormData] = useState({
    stock_control_enabled: true,
    auto_generate_purchase_orders: false,
    auto_generate_shipments: false,
    purchase_lead_time_days: 7,
    shipment_lead_time_days: 3
  })
  const [saving, setSaving] = useState(false)
  const [saveMessage, setSaveMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)

  useEffect(() => {
    if (settings) {
      setFormData({
        stock_control_enabled: settings.stock_control_enabled ?? true,
        auto_generate_purchase_orders: settings.auto_generate_purchase_orders ?? false,
        auto_generate_shipments: settings.auto_generate_shipments ?? false,
        purchase_lead_time_days: settings.purchase_lead_time_days ?? 7,
        shipment_lead_time_days: settings.shipment_lead_time_days ?? 3
      })
    }
  }, [settings])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setSaving(true)
    setSaveMessage(null)

    try {
      await updateSettings(formData)
      setSaveMessage({ type: 'success', text: 'Settings saved successfully' })
    } catch (error: any) {
      setSaveMessage({ type: 'error', text: error.message || 'Error saving settings' })
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading settings...</div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <div className="max-w-3xl">
        <form onSubmit={handleSubmit} className="space-y-6">
          {/* Stock Control */}
          <div className="bg-white border border-gray-200 rounded-lg p-6">
            <h3 className="text-lg font-medium text-gray-900 mb-4">{t('stock.stock_control')}</h3>
            
            <div className="space-y-4">
              <div className="flex items-start">
                <div className="flex items-center h-5">
                  <input
                    id="stock_control_enabled"
                    name="stock_control_enabled"
                    type="checkbox"
                    checked={formData.stock_control_enabled}
                    onChange={(e) => setFormData({ ...formData, stock_control_enabled: e.target.checked })}
                    className="focus:ring-blue-500 h-4 w-4 text-blue-600 border-gray-300 rounded"
                  />
                </div>
                <div className="ml-3 text-sm">
                  <label htmlFor="stock_control_enabled" className="font-medium text-gray-700 flex items-center gap-1">
                    {t('stock.enable_stock_control')}
                    <SmartTooltip content="Activates inventory monitoring and alert system" />
                  </label>
                  <p className="text-gray-500">
                    {t('stock.stock_control_description')}
                  </p>
                </div>
              </div>
            </div>
          </div>

          {/* Automation */}
          <div className="bg-white border border-gray-200 rounded-lg p-6">
            <h3 className="text-lg font-medium text-gray-900 mb-4">{t('stock.automation')}</h3>
            
            <div className="space-y-4">
              <div className="flex items-start">
                <div className="flex items-center h-5">
                  <input
                    id="auto_generate_purchase_orders"
                    name="auto_generate_purchase_orders"
                    type="checkbox"
                    checked={formData.auto_generate_purchase_orders}
                    onChange={(e) => setFormData({ ...formData, auto_generate_purchase_orders: e.target.checked })}
                    className="focus:ring-blue-500 h-4 w-4 text-blue-600 border-gray-300 rounded"
                    disabled
                  />
                </div>
                <div className="ml-3 text-sm">
                  <label htmlFor="auto_generate_purchase_orders" className="font-medium text-gray-700 flex items-center gap-1">
                    {t('stock.auto_generate_purchase_orders')}
                    <SmartTooltip content="Feature disabled - Purchase orders are not used in this module" />
                  </label>
                  <p className="text-gray-500">
                    {t('stock.feature_not_available')}
                  </p>
                </div>
              </div>

              <div className="flex items-start">
                <div className="flex items-center h-5">
                  <input
                    id="auto_generate_shipments"
                    name="auto_generate_shipments"
                    type="checkbox"
                    checked={formData.auto_generate_shipments}
                    onChange={(e) => setFormData({ ...formData, auto_generate_shipments: e.target.checked })}
                    className="focus:ring-blue-500 h-4 w-4 text-blue-600 border-gray-300 rounded"
                  />
                </div>
                <div className="ml-3 text-sm">
                  <label htmlFor="auto_generate_shipments" className="font-medium text-gray-700 flex items-center gap-1">
                    {t('stock.auto_generate_shipments')}
                    <SmartTooltip content="Automatically creates shipments when panelist stock is low" />
                  </label>
                  <p className="text-gray-500">
                    {t('stock.auto_generate_shipments_description')}
                  </p>
                </div>
              </div>
            </div>
          </div>

          {/* Lead Times */}
          <div className="bg-white border border-gray-200 rounded-lg p-6">
            <h3 className="text-lg font-medium text-gray-900 mb-4">{t('stock.lead_times')}</h3>
            
            <div className="grid grid-cols-1 gap-6 sm:grid-cols-2">
              <div>
                <label htmlFor="purchase_lead_time_days" className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  {t('stock.purchase_lead_time_days')}
                  <SmartTooltip content="Estimated days from purchase order to receipt" />
                </label>
                <input
                  type="number"
                  id="purchase_lead_time_days"
                  name="purchase_lead_time_days"
                  min="1"
                  value={formData.purchase_lead_time_days}
                  onChange={(e) => setFormData({ ...formData, purchase_lead_time_days: parseInt(e.target.value) || 0 })}
                  className="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  disabled
                />
                <p className="mt-1 text-xs text-gray-500">
                  {t('stock.not_applicable_purchase_orders')}
                </p>
              </div>

              <div>
                <label htmlFor="shipment_lead_time_days" className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  {t('stock.shipment_lead_time_days')}
                  <SmartTooltip content="Estimated days from shipment to panelist delivery" />
                </label>
                <input
                  type="number"
                  id="shipment_lead_time_days"
                  name="shipment_lead_time_days"
                  min="1"
                  value={formData.shipment_lead_time_days}
                  onChange={(e) => setFormData({ ...formData, shipment_lead_time_days: parseInt(e.target.value) || 0 })}
                  className="mt-1 block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
                <p className="mt-1 text-xs text-gray-500">
                  {t('stock.used_to_calculate_delivery_dates')}
                </p>
              </div>
            </div>
          </div>

          {/* Save Message */}
          {saveMessage && (
            <div className={`rounded-md p-4 ${saveMessage.type === 'success' ? 'bg-green-50' : 'bg-red-50'}`}>
              <div className="flex">
                <div className="flex-shrink-0">
                  {saveMessage.type === 'success' ? (
                    <svg className="h-5 w-5 text-green-400" viewBox="0 0 20 20" fill="currentColor">
                      <path fillRule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z" clipRule="evenodd" />
                    </svg>
                  ) : (
                    <AlertCircle className="h-5 w-5 text-red-400" />
                  )}
                </div>
                <div className="ml-3">
                  <p className={`text-sm font-medium ${saveMessage.type === 'success' ? 'text-green-800' : 'text-red-800'}`}>
                    {saveMessage.text}
                  </p>
                </div>
              </div>
            </div>
          )}

          {/* Save Button */}
          <div className="flex justify-end">
            <button
              type="submit"
              disabled={saving}
              className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <Save className="h-4 w-4 mr-2" />
              {saving ? t('common.saving') : t('stock.save_settings')}
            </button>
          </div>
        </form>
      </div>
    </div>
  )
}
