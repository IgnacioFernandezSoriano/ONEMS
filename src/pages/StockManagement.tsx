import { useState } from 'react'
import { Package, Truck, Settings, TrendingUp, ClipboardList, AlertTriangle } from 'lucide-react'
import { useStockManagement } from '../hooks/useStockManagement'
import { SmartTooltip } from '../components/common/SmartTooltip'
import MaterialRequirementsTab from '../components/stock/MaterialRequirementsTab'
import RegulatorStockTab from '../components/stock/RegulatorStockTab'
import PanelistStockTab from '../components/stock/PanelistStockTab'
import MovementsTab from '../components/stock/MovementsTab'
import ShipmentsTab from '../components/stock/ShipmentsTab'
import SettingsTab from '../components/stock/SettingsTab'
import StockAlertsTab from '../components/stock/StockAlertsTab'

type TabType = 'requirements' | 'regulator' | 'shipments' | 'panelist' | 'movements' | 'alerts' | 'settings'

export default function StockManagement() {
  const [activeTab, setActiveTab] = useState<TabType>('requirements')
  const { shipments, loading } = useStockManagement()

  // Calculate KPIs
  const pendingShipments = shipments.filter(s => s.status === 'pending').length

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

      {/* KPIs */}
      {/* Tabs */}
      <div className="bg-white shadow rounded-lg">
        <div className="border-b border-gray-200">
          <nav className="-mb-px flex space-x-8 px-6" aria-label="Tabs">
            {tabs.map((tab) => {
              const Icon = tab.icon
              const isActive = activeTab === tab.id
              return (
                <button
                  key={tab.id}
                  onClick={() => setActiveTab(tab.id)}
                  className={`
                    group inline-flex items-center py-4 px-1 border-b-2 font-medium text-sm gap-2
                    ${isActive
                      ? 'border-blue-500 text-blue-600'
                      : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
                    }
                  `}
                >
                  <Icon className="h-5 w-5" />
                  {tab.label}
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
