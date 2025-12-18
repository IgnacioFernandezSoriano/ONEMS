import { useState, useMemo } from 'react'
import { Search, Calendar, Filter, RotateCcw, CheckSquare, Square, ShoppingCart, Package } from 'lucide-react'
import { useStockManagement } from '../../hooks/useStockManagement'
import { useRegulatorRequirements } from '../../hooks/useRegulatorRequirements'
import { useMaterialCatalog } from '../../hooks/useMaterialCatalog'
import { SmartTooltip } from '../common/SmartTooltip'
import OrderMaterialModal from './OrderMaterialModal'
import ReceivePOModal from './ReceivePOModal'

export default function MaterialRequirementsTab() {
  const { regulatorStocks, reload } = useStockManagement()
  const { requirements, loading: loadingRequirements, calculate, markAsOrdered, receivePO } = useRegulatorRequirements()
  const { catalog: materials } = useMaterialCatalog()

  // Filters
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [selectedMaterialId, setSelectedMaterialId] = useState('')
  const [selectedStatus, setSelectedStatus] = useState<string>('')
  const [selectedYear, setSelectedYear] = useState(new Date().getFullYear())
  const [isFiltersCollapsed, setIsFiltersCollapsed] = useState(false)

  // Selection for bulk actions
  const [selectedRequirements, setSelectedRequirements] = useState<Set<string>>(new Set())

  // Modals
  const [showOrderModal, setShowOrderModal] = useState(false)
  const [showReceiveModal, setShowReceiveModal] = useState(false)
  const [selectedRequirement, setSelectedRequirement] = useState<typeof requirements[0] | null>(null)

  // Month names
  const months = [
    { name: 'Jan', num: 1 }, { name: 'Feb', num: 2 }, { name: 'Mar', num: 3 },
    { name: 'Apr', num: 4 }, { name: 'May', num: 5 }, { name: 'Jun', num: 6 },
    { name: 'Jul', num: 7 }, { name: 'Aug', num: 8 }, { name: 'Sep', num: 9 },
    { name: 'Oct', num: 10 }, { name: 'Nov', num: 11 }, { name: 'Dec', num: 12 }
  ]

  // Generate year range (current year to current year + 10)
  const yearRange = useMemo(() => {
    const currentYear = new Date().getFullYear()
    const years = []
    for (let i = currentYear; i <= currentYear + 10; i++) {
      years.push(i)
    }
    return years
  }, [])

  // Filter requirements
  const filteredRequirements = useMemo(() => {
    let filtered = requirements
    
    // Filter by material
    if (selectedMaterialId) {
      filtered = filtered.filter(r => r.material_id === selectedMaterialId)
    }
    
    // Filter by status
    if (selectedStatus) {
      filtered = filtered.filter(r => r.status === selectedStatus)
    }
    
    return filtered
  }, [requirements, selectedMaterialId, selectedStatus])

  // Enrich requirements with net quantity and current stock
  const enrichedRequirements = useMemo(() => {
    return filteredRequirements.map(req => {
      const currentStock = regulatorStocks.find(s => s.material_id === req.material_id)
      const currentQuantity = currentStock?.quantity || 0
      const netQuantity = Math.max(0, req.quantity_needed - currentQuantity)
      
      return {
        ...req,
        current_stock: currentQuantity,
        net_quantity: netQuantity
      }
    })
  }, [filteredRequirements, regulatorStocks])

  const handleCalculate = () => {
    if (!startDate || !endDate) {
      alert('Please select both start and end dates')
      return
    }
    calculate(startDate, endDate)
    setSelectedRequirements(new Set())
  }

  const handleMonthSelect = (year: number, month: number) => {
    const firstDay = new Date(year, month - 1, 1)
    const lastDay = new Date(year, month, 0)
    
    setStartDate(firstDay.toISOString().split('T')[0])
    setEndDate(lastDay.toISOString().split('T')[0])
  }

  const handleResetFilters = () => {
    setStartDate('')
    setEndDate('')
    setSelectedMaterialId('')
    setSelectedYear(new Date().getFullYear())
    setSelectedRequirements(new Set())
  }

  const handleToggleSelection = (requirementId: string) => {
    const newSelection = new Set(selectedRequirements)
    if (newSelection.has(requirementId)) {
      newSelection.delete(requirementId)
    } else {
      newSelection.add(requirementId)
    }
    setSelectedRequirements(newSelection)
  }

  const handleSelectAll = () => {
    if (selectedRequirements.size === enrichedRequirements.length) {
      setSelectedRequirements(new Set())
    } else {
      setSelectedRequirements(new Set(enrichedRequirements.map(r => r.id)))
    }
  }

  const handleOrder = (requirement: typeof enrichedRequirements[0]) => {
    setSelectedRequirement(requirement)
    setShowOrderModal(true)
  }

  const handleReceive = (requirement: typeof enrichedRequirements[0]) => {
    setSelectedRequirement(requirement)
    setShowReceiveModal(true)
  }

  const handleMarkSelectedAsOrdered = async () => {
    if (selectedRequirements.size === 0) return
    
    const confirmed = confirm(`Mark ${selectedRequirements.size} requirement(s) as ordered?`)
    if (!confirmed) return

    for (const reqId of selectedRequirements) {
      await markAsOrdered(reqId, null) // null = use net quantity as default
    }
    
    setSelectedRequirements(new Set())
  }

  const getStatusBadge = (status: string) => {
    const styles = {
      pending: 'bg-yellow-100 text-yellow-800',
      ordered: 'bg-blue-100 text-blue-800',
      received: 'bg-green-100 text-green-800'
    }
    
    return (
      <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${styles[status as keyof typeof styles] || styles.pending}`}>
        {status.charAt(0).toUpperCase() + status.slice(1)}
      </span>
    )
  }

  return (
    <div className="space-y-6">
      {/* Filters */}
      <div className="bg-gray-50 border border-gray-200 rounded-lg">
        <button
          onClick={() => setIsFiltersCollapsed(!isFiltersCollapsed)}
          className="w-full px-4 py-3 flex items-center justify-between text-left hover:bg-gray-100 transition-colors"
        >
          <div className="flex items-center gap-2">
            <Filter className="h-5 w-5 text-gray-500" />
            <span className="font-medium text-gray-900">Calculate Requirements</span>
          </div>
          <span className="text-sm text-gray-500">
            {isFiltersCollapsed ? 'Show' : 'Hide'}
          </span>
        </button>

        {!isFiltersCollapsed && (
          <div className="px-4 pb-4 space-y-4">
            {/* Date Filters */}
            <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  Start Date
                  <SmartTooltip content="Start date for allocation plans to include" />
                </label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  End Date
                  <SmartTooltip content="End date for allocation plans to include" />
                </label>
                <input
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  Material
                  <SmartTooltip content="Filter by specific material" />
                </label>
                <select
                  value={selectedMaterialId}
                  onChange={(e) => setSelectedMaterialId(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="">All Materials</option>
                  {materials.map(m => (
                    <option key={m.id} value={m.id}>{m.code} - {m.name}</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                  Status
                  <SmartTooltip content="Filter by requirement status" />
                </label>
                <select
                  value={selectedStatus}
                  onChange={(e) => setSelectedStatus(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="">All Status</option>
                  <option value="pending">Pending</option>
                  <option value="ordered">Ordered</option>
                  <option value="received">Received</option>
                </select>
              </div>
            </div>

            {/* Month Selectors */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2 flex items-center gap-1">
                <Calendar className="h-4 w-4" />
                Quick Month Selection
                <SmartTooltip content="Click a month to set start/end dates for that entire month" />
              </label>
              <div className="flex items-center gap-2">
                <select
                  value={selectedYear}
                  onChange={(e) => setSelectedYear(parseInt(e.target.value))}
                  className="border border-gray-300 rounded-md shadow-sm py-1 px-2 text-sm focus:outline-none focus:ring-blue-500 focus:border-blue-500"
                >
                  {yearRange.map(year => (
                    <option key={year} value={year}>{year}</option>
                  ))}
                </select>
                <div className="flex flex-wrap gap-1">
                  {months.map(month => (
                    <button
                      key={month.num}
                      onClick={() => handleMonthSelect(selectedYear, month.num)}
                      className="px-2 py-1 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    >
                      {month.name}
                    </button>
                  ))}
                </div>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex items-center gap-2">
              <button
                onClick={handleCalculate}
                disabled={loadingRequirements}
                className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
              >
                <Search className="h-4 w-4 mr-2" />
                {loadingRequirements ? 'Calculating...' : 'Calculate Requirements'}
              </button>

              <button
                onClick={handleResetFilters}
                className="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <RotateCcw className="h-4 w-4 mr-2" />
                Reset
              </button>
            </div>
          </div>
        )}
      </div>

      {/* Requirements Table */}
      {enrichedRequirements.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg">
          <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
            <h3 className="text-lg font-medium text-gray-900">
              Material Requirements ({enrichedRequirements.length})
            </h3>
            {selectedRequirements.size > 0 && (
              <div className="flex items-center gap-2">
                <button
                  onClick={handleMarkSelectedAsOrdered}
                  className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-orange-600 hover:bg-orange-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500"
                >
                  <ShoppingCart className="h-4 w-4 mr-1" />
                  Order {selectedRequirements.size} Selected
                </button>
              </div>
            )}
          </div>

          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th scope="col" className="px-6 py-3 text-left">
                    <button
                      onClick={handleSelectAll}
                      className="flex items-center gap-2 text-xs font-medium text-gray-500 uppercase tracking-wider hover:text-gray-700"
                    >
                      {selectedRequirements.size === enrichedRequirements.length ? (
                        <CheckSquare className="h-4 w-4" />
                      ) : (
                        <Square className="h-4 w-4" />
                      )}
                      Select
                    </button>
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Material
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Quantity Needed
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Current Stock
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Net Quantity
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Quantity Ordered
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Received
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {enrichedRequirements.map((requirement) => (
                  <tr key={requirement.id} className={selectedRequirements.has(requirement.id) ? 'bg-blue-50' : ''}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <button
                        onClick={() => handleToggleSelection(requirement.id)}
                        className="text-gray-400 hover:text-gray-600"
                      >
                        {selectedRequirements.has(requirement.id) ? (
                          <CheckSquare className="h-5 w-5 text-blue-600" />
                        ) : (
                          <Square className="h-5 w-5" />
                        )}
                      </button>
                    </td>
                    <td className="px-6 py-4">
                      <div className="text-sm font-medium text-gray-900">
                        {requirement.material_code}
                      </div>
                      <div className="text-sm text-gray-500">
                        {requirement.material_name}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm font-semibold text-gray-900">
                        {requirement.quantity_needed.toLocaleString()} {requirement.unit_measure}
                      </div>
                      <div className="text-xs text-gray-500">
                        {requirement.plans_count} plan(s)
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-gray-900">
                        {requirement.current_stock.toLocaleString()} {requirement.unit_measure}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className={`text-sm font-semibold ${requirement.net_quantity > 0 ? 'text-red-600' : 'text-green-600'}`}>
                        {requirement.net_quantity.toLocaleString()} {requirement.unit_measure}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-gray-900">
                        {requirement.quantity_ordered.toLocaleString()} {requirement.unit_measure}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-gray-900">
                        {requirement.quantity_received.toLocaleString()} {requirement.unit_measure}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      {getStatusBadge(requirement.status)}
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="flex items-center gap-2">
                        {requirement.status === 'pending' && (
                          <button
                            onClick={() => handleOrder(requirement)}
                            className="inline-flex items-center px-2 py-1 border border-transparent text-xs font-medium rounded text-orange-700 bg-orange-100 hover:bg-orange-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-orange-500"
                          >
                            <ShoppingCart className="h-3 w-3 mr-1" />
                            Order
                          </button>
                        )}
                        {requirement.status === 'ordered' && (
                          <button
                            onClick={() => handleReceive(requirement)}
                            className="inline-flex items-center px-2 py-1 border border-transparent text-xs font-medium rounded text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                          >
                            <Package className="h-3 w-3 mr-1" />
                            Receive PO
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Modals */}
      {showOrderModal && selectedRequirement && (
        <OrderMaterialModal
          requirement={selectedRequirement}
          onConfirm={async (materialId, quantity) => {
            await markAsOrdered(selectedRequirement.id, quantity)
            setShowOrderModal(false)
            setSelectedRequirement(null)
          }}
          onClose={() => {
            setShowOrderModal(false)
            setSelectedRequirement(null)
          }}
        />
      )}

      {showReceiveModal && selectedRequirement && (
        <ReceivePOModal
          requirement={selectedRequirement}
          onConfirm={async (requirementId, quantity) => {
            await receivePO(requirementId, quantity)
            await reload()
            setShowReceiveModal(false)
            setSelectedRequirement(null)
          }}
          onClose={() => {
            setShowReceiveModal(false)
            setSelectedRequirement(null)
          }}
        />
      )}
    </div>
  )
}
