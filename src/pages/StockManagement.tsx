import { useState } from 'react'
import { Package, Truck, Settings, TrendingUp, ClipboardList, AlertTriangle } from 'lucide-react'
import { useStockManagement } from '../hooks/useStockManagement'
import { useStockAlerts } from '../hooks/useStockAlerts'
import { SmartTooltip } from '../components/common/SmartTooltip'
import MaterialRequirementsTab from '../components/stock/MaterialRequirementsTab'
import RegulatorStockTab from '../components/stock/RegulatorStockTab'
import PanelistStockTab from '../components/stock/PanelistStockTab'
import MovementsTab from '../components/stock/MovementsTab'
import ShipmentsTab from '../components/stock/ShipmentsTab'
import SettingsTab from '../components/stock/SettingsTab'
import StockAlertsTab from '../components/stock/StockAlertsTab'

import { useTranslation } from '@/hooks/useTranslation';
type TabType = 'requirements' | 'regulator' | 'shipments' | 'panelist' | 'movements' | 'alerts' | 'settings'

export default function StockManagement() {
  const { t } = useTranslation();
  const [activeTab, setActiveTab] = useState<TabType>('requirements')
  const { shipments, loading } = useStockManagement()
  const { getAlertCounts } = useStockAlerts()

  // Calculate KPIs
  const pendingShipments = shipments.filter(s => s.status === 'pending').length
  const alertCounts = getAlertCounts()

  const tabs = [
    { 
      id: 'requirements' as TabType, 
      label: 'Material Requirements', 
      icon: ClipboardList,
      help: 'Calculate material requirements from allocation plans. Order materials and receive purchase orders to update regulator stock.'
    },
    { 
      id: 'regulator' as TabType, 
      label: 'Regulator Stock', 
      icon: Package,
      help: 'View and manage current inventory in regulator (HAL) warehouse. Stock is updated when receiving purchase orders.'
    },
    { 
      id: 'shipments' as TabType, 
      label: 'Shipments', 
      icon: Truck,
      help: 'Generate shipments to panelists based on allocation plans. Create pending shipments, then send them to update stocks automatically.'
    },
    { 
      id: 'panelist' as TabType, 
      label: 'Panelist Stock', 
      icon: Package,
      help: 'View current inventory distributed to each panelist. Stock is automatically updated when shipments are sent.'
    },
    { 
      id: 'movements' as TabType, 
      label: 'Movements', 
      icon: TrendingUp,
      help: 'Complete audit trail of all material movements including receipts, dispatches, and transfers with full traceability.'
    },
    { 
      id: 'alerts' as TabType, 
      label: 'Stock Alerts', 
      icon: AlertTriangle,
      help: 'View and manage stock alerts for insufficient regulator stock and negative panelist stock. Alerts auto-resolve when stock returns to positive.'
    },
    { 
      id: 'settings' as TabType, 
      label: 'Settings', 
      icon: Settings,
      help: 'Configure stock control parameters, automation rules, and lead times for shipments and deliveries.'
    }
  ]

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900">Stock Management & Alerts</h1>
        <p className="mt-1 text-sm text-gray-500">
          Manage material requirements, regulator and panelist inventory, track movements and shipments
        </p>
      </div>

      {/* Stock Alerts Summary Card */}
      {alertCounts.total > 0 && (
        <button
          onClick={() => setActiveTab('alerts')}
          className="w-full bg-gradient-to-r from-red-50 to-orange-50 border-2 border-red-200 rounded-lg p-4 hover:border-red-400 hover:shadow-lg transition-all text-left group"
        >
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <div className="p-3 bg-red-100 rounded-lg group-hover:bg-red-200 transition-colors">
                <AlertTriangle className="h-6 w-6 text-red-600" />
              </div>
              <div>
                <div className="text-lg font-bold text-red-900">Stock Alerts</div>
                <div className="text-sm text-red-700 mt-1">
                  {alertCounts.regulator > 0 && (
                    <span className="mr-4">
                      <span className="font-semibold">{alertCounts.regulator}</span> Regulator issue{alertCounts.regulator !== 1 ? 's' : ''}
                    </span>
                  )}
                  {alertCounts.panelist > 0 && (
                    <span>
                      <span className="font-semibold">{alertCounts.panelist}</span> Panelist issue{alertCounts.panelist !== 1 ? 's' : ''}
                    </span>
                  )}
                </div>
              </div>
            </div>
            <div className="text-red-400 group-hover:text-red-600 transition-colors">
              <svg className="h-6 w-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
              </svg>
            </div>
          </div>
        </button>
      )}

      {/* Tabs */}
      <div className="bg-white shadow rounded-lg">
        <div className="border-b border-gray-200">
          <nav className="-mb-px flex space-x-8 px-6" aria-label={t('stockmanagement.tabs')}>
            {tabs.map((tab) => {
              const Icon = tab.icon
              const isActive = activeTab === tab.id
              const hasAlerts = tab.id === 'alerts' && alertCounts.total > 0
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`
                    group inline-flex items-center py-4 px-1 border-b-2 font-medium text-sm gap-2
                    ${isActive
                      ? hasAlerts ? 'border-red-500 text-red-600' : 'border-blue-500 text-blue-600'
                      : hasAlerts ? 'border-transparent text-red-600 hover:text-red-700 hover:border-red-300' : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                    }
                  `}
                >
                  <Icon className="h-5 w-5" />
                  {tab.label}
                  {hasAlerts && (
                    <span className="ml-1 px-2 py-0.5 text-xs font-semibold bg-red-100 text-red-800 rounded-full">
                      {alertCounts.total}
                    </span>
                  )}
                  <SmartTooltip content={tab.help} />
                </button>
              )
            })}
          </nav>
        </div>

        <div className="p-6">
          {activeTab === 'requirements' && <MaterialRequirementsTab />}
          {activeTab === 'regulator' && <RegulatorStockTab />}
          {activeTab === 'shipments' && <ShipmentsTab />}
          {activeTab === 'panelist' && <PanelistStockTab />}
          {activeTab === 'movements' && <MovementsTab />}
          {activeTab === 'alerts' && (
            <StockAlertsTab
              onNavigateToRegulatorStock={(materialIds) => {
                setActiveTab('regulator')
                // TODO: Pass materialIds to RegulatorStockTab for filtering
              }}
              onNavigateToPanelistStock={(materialIds) => {
                setActiveTab('panelist')
                // TODO: Pass materialIds to PanelistStockTab for filtering
              }}
            />
          )}
          {activeTab === 'settings' && <SettingsTab />}
        </div>
      </div>
    </div>
  )
}
