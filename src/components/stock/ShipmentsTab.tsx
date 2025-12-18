import React, { useState, useMemo } from 'react'
import { Search, Truck, Calendar, Filter, RotateCcw, CheckSquare, Square, Send, Package } from 'lucide-react'
import { useStockManagement } from '../../hooks/useStockManagement'
import { useProposedShipments } from '../../hooks/useProposedShipments'
import { useMaterialCatalog } from '../../hooks/useMaterialCatalog'
import { SmartTooltip } from '../common/SmartTooltip'

export default function ShipmentsTab() {
  const { shipments, loading: loadingShipments, createShipment, updateShipmentStatus, reload } = useStockManagement()
  const { proposedShipments, loading: loadingProposed, calculate } = useProposedShipments()
  const { catalog: materials } = useMaterialCatalog()

  // Filters
  const [startDate, setStartDate] = useState('')
  const [endDate, setEndDate] = useState('')
  const [selectedMaterialId, setSelectedMaterialId] = useState('')
  const [selectedNodeId, setSelectedNodeId] = useState('')
  const [selectedStatus, setSelectedStatus] = useState<string>('')
  const [selectedPanelistId, setSelectedPanelistId] = useState<string>('')
  const [selectedYear, setSelectedYear] = useState(new Date().getFullYear())
  const [isFiltersCollapsed, setIsFiltersCollapsed] = useState(false)

  // Generate year range (current year to current year + 10)
  const yearRange = useMemo(() => {
    const currentYear = new Date().getFullYear()
    const years = []
    for (let i = currentYear; i <= currentYear + 10; i++) {
      years.push(i)
    }
    return years
  }, [])

  // Selection for bulk actions
  const [selectedShipmentIds, setSelectedShipmentIds] = useState<Set<string>>(new Set())

  // Get unique nodes from proposed shipments
  const uniqueNodes = useMemo(() => {
    const nodesMap = new Map()
    proposedShipments.forEach(ps => {
      if (ps.node_id && ps.node_name) {
        nodesMap.set(ps.node_id, ps.node_name)
      }
    })
    return Array.from(nodesMap.entries()).map(([id, name]) => ({ id, name }))
  }, [proposedShipments])

  // Filter proposed shipments
  const filteredProposedShipments = useMemo(() => {
    let filtered = proposedShipments

    if (selectedNodeId) {
      filtered = filtered.filter(ps => ps.node_id === selectedNodeId)
    }

    if (selectedMaterialId) {
      filtered = filtered.map(ps => ({
        ...ps,
        materials: ps.materials.filter(m => m.material_id === selectedMaterialId),
        total_items: ps.materials.filter(m => m.material_id === selectedMaterialId).length,
        total_quantity: ps.materials
          .filter(m => m.material_id === selectedMaterialId)
          .reduce((sum, m) => sum + m.quantity_needed, 0)
      })).filter(ps => ps.materials.length > 0)
    }

    return filtered
  }, [proposedShipments, selectedNodeId, selectedMaterialId])

  // Filters for historical shipments
  const [historyStatusFilter, setHistoryStatusFilter] = useState<string>('')
  const [historyPanelistFilter, setHistoryPanelistFilter] = useState<string>('')
  const [historyMaterialFilter, setHistoryMaterialFilter] = useState<string>('')

  // Get unique panelists from shipments
  const uniquePanelists = useMemo(() => {
    const panelistsMap = new Map()
    shipments.forEach(s => {
      if (s.panelist_id && s.panelist?.name) {
        panelistsMap.set(s.panelist_id, s.panelist.name)
      }
    })
    return Array.from(panelistsMap.entries()).map(([id, name]) => ({ id, name }))
  }, [shipments])

  // Filter shipments
  const filteredShipments = useMemo(() => {
    let filtered = shipments

    if (historyStatusFilter) {
      filtered = filtered.filter(s => s.status === historyStatusFilter)
    }

    if (historyPanelistFilter) {
      filtered = filtered.filter(s => s.panelist_id === historyPanelistFilter)
    }

    if (historyMaterialFilter) {
      filtered = filtered.filter(s => 
        s.items?.some(item => item.material_id === historyMaterialFilter)
      )
    }

    return filtered
  }, [shipments, historyStatusFilter, historyPanelistFilter, historyMaterialFilter])

  // Get pending shipments (status = 'pending')
  const pendingShipments = useMemo(() => {
    return filteredShipments.filter(s => s.status === 'pending')
  }, [filteredShipments])

  const handleCalculate = () => {
    if (!startDate || !endDate) {
      alert('Please select both start and end dates')
      return
    }
    calculate(startDate, endDate)
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
    setSelectedNodeId('')
    setSelectedYear(new Date().getFullYear())
  }

  const handleGenerateShipments = async () => {
    if (filteredProposedShipments.length === 0) {
      alert('No shipments to generate')
      return
    }

    const shipmentsWithoutPanelist = filteredProposedShipments.filter(ps => !ps.panelist_id)
    if (shipmentsWithoutPanelist.length > 0) {
      alert(`Warning: ${shipmentsWithoutPanelist.length} node(s) don't have assigned panelists and will be skipped`)
    }

    const validShipments = filteredProposedShipments.filter(ps => ps.panelist_id)
    if (validShipments.length === 0) {
      alert('No valid shipments to generate (all nodes need assigned panelists)')
      return
    }

    try {
      for (const shipment of validShipments) {
        const expectedDate = new Date()
        expectedDate.setDate(expectedDate.getDate() + 3) // 3 days lead time

        await createShipment({
          panelist_id: shipment.panelist_id!,
          items: shipment.materials.map(m => ({
            material_id: m.material_id,
            quantity_sent: m.quantity_needed
          })),
          expected_date: expectedDate.toISOString(),
          notes: `Generated from allocation plans ${startDate} to ${endDate}`
        })
      }

      alert(`${validShipments.length} shipment(s) generated successfully as pending`)
      reload()
    } catch (error: any) {
      alert(`Error generating shipments: ${error.message}`)
    }
  }

  const handleToggleSelection = (shipmentId: string) => {
    const newSelection = new Set(selectedShipmentIds)
    if (newSelection.has(shipmentId)) {
      newSelection.delete(shipmentId)
    } else {
      newSelection.add(shipmentId)
    }
    setSelectedShipmentIds(newSelection)
  }

  const handleSelectAll = () => {
    if (selectedShipmentIds.size === pendingShipments.length) {
      setSelectedShipmentIds(new Set())
    } else {
      setSelectedShipmentIds(new Set(pendingShipments.map(s => s.id)))
    }
  }

  const handleSendShipment = async (shipmentId: string) => {
    try {
      await updateShipmentStatus(shipmentId, 'sent')
      alert('Shipment sent successfully')
      reload()
      setSelectedShipmentIds(new Set())
    } catch (error: any) {
      alert(`Error sending shipment: ${error.message}`)
    }
  }

  const handleSendSelected = async () => {
    if (selectedShipmentIds.size === 0) {
      alert('No shipments selected')
      return
    }

    try {
      for (const shipmentId of selectedShipmentIds) {
        await updateShipmentStatus(shipmentId, 'sent')
      }
      alert(`${selectedShipmentIds.size} shipment(s) sent successfully`)
      reload()
      setSelectedShipmentIds(new Set())
    } catch (error: any) {
      alert(`Error sending shipments: ${error.message}`)
    }
  }

  const months = [
    { num: 1, name: 'Jan' }, { num: 2, name: 'Feb' }, { num: 3, name: 'Mar' },
    { num: 4, name: 'Apr' }, { num: 5, name: 'May' }, { num: 6, name: 'Jun' },
    { num: 7, name: 'Jul' }, { num: 8, name: 'Aug' }, { num: 9, name: 'Sep' },
    { num: 10, name: 'Oct' }, { num: 11, name: 'Nov' }, { num: 12, name: 'Dec' }
  ]

  return (
    <div className="space-y-6">
      {/* Filters Section */}
      <div className="bg-white border border-gray-200 rounded-lg">
        <button
          onClick={() => setIsFiltersCollapsed(!isFiltersCollapsed)}
          className="w-full px-4 py-3 flex items-center justify-between text-left hover:bg-gray-50"
        >
          <div className="flex items-center gap-2">
            <Filter className="h-4 w-4 text-gray-500" />
            <span className="font-medium text-gray-900">Filters</span>
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
                  Node
                  <SmartTooltip content="Filter by specific node" />
                </label>
                <select
                  value={selectedNodeId}
                  onChange={(e) => setSelectedNodeId(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                >
                  <option value="">All Nodes</option>
                  {uniqueNodes.map(n => (
                    <option key={n.id} value={n.id}>{n.name}</option>
                  ))}
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
                disabled={loadingProposed}
                className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
              >
                <Search className="h-4 w-4 mr-2" />
                {loadingProposed ? 'Calculating...' : 'Calculate'}
              </button>

              {filteredProposedShipments.length > 0 && (
                <button
                  onClick={handleGenerateShipments}
                  className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                >
                  <Package className="h-4 w-4 mr-2" />
                  Generate Shipments ({filteredProposedShipments.filter(ps => ps.panelist_id).length})
                </button>
              )}

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

      {/* Proposed Shipments Preview */}
      {filteredProposedShipments.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg p-4">
          <h3 className="text-sm font-medium text-gray-900 mb-2">
            Preview: {filteredProposedShipments.length} shipment(s) will be generated
          </h3>
          <div className="text-sm text-gray-600">
            {filteredProposedShipments.filter(ps => ps.panelist_id).length} with assigned panelists, 
            {' '}{filteredProposedShipments.filter(ps => !ps.panelist_id).length} without panelist (will be skipped)
          </div>
        </div>
      )}

      {/* Shipments History Filters */}
      <div className="bg-white border border-gray-200 rounded-lg">
        <div className="px-4 py-3 border-b border-gray-200">
          <h3 className="text-lg font-medium text-gray-900">Shipments History</h3>
        </div>
        <div className="px-4 py-4">
          <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                Status
                <SmartTooltip content="Filter shipments by status" />
              </label>
              <select
                value={historyStatusFilter}
                onChange={(e) => setHistoryStatusFilter(e.target.value)}
                className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
              >
                <option value="">All Statuses</option>
                <option value="pending">Pending</option>
                <option value="sent">Sent</option>
                <option value="received">Received</option>
                <option value="cancelled">Cancelled</option>
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                Panelist
                <SmartTooltip content="Filter shipments by panelist" />
              </label>
              <select
                value={historyPanelistFilter}
                onChange={(e) => setHistoryPanelistFilter(e.target.value)}
                className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
              >
                <option value="">All Panelists</option>
                {uniquePanelists.map(p => (
                  <option key={p.id} value={p.id}>{p.name}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
                Material
                <SmartTooltip content="Filter shipments containing specific material" />
              </label>
              <select
                value={historyMaterialFilter}
                onChange={(e) => setHistoryMaterialFilter(e.target.value)}
                className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
              >
                <option value="">All Materials</option>
                {materials.map(m => (
                  <option key={m.id} value={m.id}>{m.code} - {m.name}</option>
                ))}
              </select>
            </div>
          </div>

          {(historyStatusFilter || historyPanelistFilter || historyMaterialFilter) && (
            <div className="mt-4">
              <button
                onClick={() => {
                  setHistoryStatusFilter('')
                  setHistoryPanelistFilter('')
                  setHistoryMaterialFilter('')
                }}
                className="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <RotateCcw className="h-4 w-4 mr-1" />
                Clear Filters
              </button>
            </div>
          )}
        </div>
      </div>

      {/* Pending Shipments Table */}
      {pendingShipments.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg">
          <div className="px-4 py-3 border-b border-gray-200 flex items-center justify-between">
            <h3 className="text-lg font-medium text-gray-900">
              Pending Shipments ({pendingShipments.length})
            </h3>
            {selectedShipmentIds.size > 0 && (
              <button
                onClick={handleSendSelected}
                className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
              >
                <Send className="h-4 w-4 mr-1" />
                Send {selectedShipmentIds.size} Selected
              </button>
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
                      {selectedShipmentIds.size === pendingShipments.length ? (
                        <CheckSquare className="h-4 w-4" />
                      ) : (
                        <Square className="h-4 w-4" />
                      )}
                      Select
                    </button>
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Shipment #
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Panelist
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Materials
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Expected Date
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {pendingShipments.map((shipment) => (
                  <tr key={shipment.id} className={selectedShipmentIds.has(shipment.id) ? 'bg-blue-50' : ''}>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <button
                        onClick={() => handleToggleSelection(shipment.id)}
                        className="text-gray-400 hover:text-gray-600"
                      >
                        {selectedShipmentIds.has(shipment.id) ? (
                          <CheckSquare className="h-5 w-5 text-blue-600" />
                        ) : (
                          <Square className="h-5 w-5" />
                        )}
                      </button>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm font-medium text-gray-900">
                        {shipment.shipment_number || 'N/A'}
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="text-sm font-medium text-gray-900">
                        {shipment.panelist?.name || 'No panelist'}
                      </div>
                      <div className="text-sm text-gray-500">
                        {shipment.panelist?.panelist_code || 'N/A'}
                      </div>
                    </td>
                    <td className="px-6 py-4">
                      <div className="text-sm text-gray-900">
                        {shipment.items && shipment.items.length > 0 ? (
                          <div>
                            {shipment.items.slice(0, 2).map(item => (
                              <div key={item.id}>
                                {item.material?.code}: {item.quantity_sent} {item.material?.unit_measure}
                              </div>
                            ))}
                            {shipment.items.length > 2 && (
                              <div className="text-xs text-gray-500">
                                +{shipment.items.length - 2} more
                              </div>
                            )}
                          </div>
                        ) : (
                          'No items'
                        )}
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <div className="text-sm text-gray-900">
                        {shipment.expected_date 
                          ? new Date(shipment.expected_date).toLocaleDateString('en-US')
                          : '-'
                        }
                      </div>
                    </td>
                    <td className="px-6 py-4 whitespace-nowrap">
                      <button
                        onClick={() => handleSendShipment(shipment.id)}
                        className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                      >
                        <Send className="h-4 w-4 mr-1" />
                        Send
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Empty States */}
      {!loadingProposed && !loadingShipments && pendingShipments.length === 0 && filteredProposedShipments.length === 0 && (
        <div className="text-center py-12 text-gray-500">
          Select date range and click "Calculate" to generate shipments from allocation plans
        </div>
      )}
    </div>
  )
}
