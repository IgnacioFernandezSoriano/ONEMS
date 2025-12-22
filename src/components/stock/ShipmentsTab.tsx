import React, { useState, useMemo } from 'react'
import { Package, Search, Filter, RotateCcw, Send, Trash2, AlertCircle, CheckCircle, Clock, Download, FileText, ChevronDown, ChevronUp, Info, Calendar, CheckSquare, Square, Edit } from 'lucide-react'
import { useStockManagement } from '../../hooks/useStockManagement'
import { useProposedShipments } from '../../hooks/useProposedShipments'
import { useMaterialCatalog } from '../../hooks/useMaterialCatalog'
import { SmartTooltip } from '../common/SmartTooltip'
import { downloadCSV, generatePackingListPDF, printPDF } from '../../lib/exportUtils'
import EditShipmentItemModal from './EditShipmentItemModal'
import type { MaterialShipmentItem } from '../../hooks/useStockManagement'

export default function ShipmentsTab() {
  const { shipments, loading: loadingShipments, createShipment, updateShipmentStatus, updateShipmentItem, deleteShipment, reload } = useStockManagement()
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
  const [isMetricsCollapsed, setIsMetricsCollapsed] = useState(false)

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

  // Edit shipment item modal
  const [editingItem, setEditingItem] = useState<MaterialShipmentItem | null>(null)
  const [showEditModal, setShowEditModal] = useState(false)

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

  // Calculate metrics
  const metrics = useMemo(() => {
    const pending = pendingShipments.length
    const confirmed = filteredShipments.filter(s => s.status === 'sent').length
    const totalItems = pendingShipments.reduce((sum, s) => sum + (s.items?.length || 0), 0)
    
    return { pending, confirmed, totalItems }
  }, [pendingShipments, filteredShipments])

  const handleCalculate = () => {
    if (!startDate || !endDate) {
      alert('Please select both start and end dates')
      return
    }
    calculate(startDate, endDate)
  }

  const formatDateLocal = (date: Date) => {
    const y = date.getFullYear()
    const m = String(date.getMonth() + 1).padStart(2, '0')
    const d = String(date.getDate()).padStart(2, '0')
    return `${y}-${m}-${d}`
  }

  const handleMonthSelect = (year: number, month: number) => {
    const firstDay = new Date(year, month - 1, 1)
    const lastDay = new Date(year, month, 0)
    
    setStartDate(formatDateLocal(firstDay))
    setEndDate(formatDateLocal(lastDay))
  }

  const handleFirstSemesterSelect = () => {
    const currentYear = new Date().getFullYear()
    const firstDay = new Date(currentYear, 0, 1) // Jan 1
    const lastDay = new Date(currentYear, 5, 30) // Jun 30
    
    setStartDate(formatDateLocal(firstDay))
    setEndDate(formatDateLocal(lastDay))
  }

  const handleSecondSemesterSelect = () => {
    const currentYear = new Date().getFullYear()
    const firstDay = new Date(currentYear, 6, 1) // Jul 1
    const lastDay = new Date(currentYear, 11, 31) // Dec 31
    
    setStartDate(formatDateLocal(firstDay))
    setEndDate(formatDateLocal(lastDay))
  }

  const handleYearSelect = () => {
    const currentYear = new Date().getFullYear()
    const firstDay = new Date(currentYear, 0, 1) // Jan 1
    const lastDay = new Date(currentYear, 11, 31) // Dec 31
    
    setStartDate(formatDateLocal(firstDay))
    setEndDate(formatDateLocal(lastDay))
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

  const handleDelete = async (shipmentId: string) => {
    const confirmed = confirm('Are you sure you want to delete this shipment?')
    if (!confirmed) return

    try {
      await deleteShipment(shipmentId)
      alert('Shipment deleted successfully')
      setSelectedShipmentIds(new Set())
    } catch (error: any) {
      alert(`Error deleting shipment: ${error.message}`)
    }
  }

  const handleDeleteSelected = async () => {
    if (selectedShipmentIds.size === 0) return
    
    const confirmed = confirm(`Delete ${selectedShipmentIds.size} shipment(s)? This action cannot be undone.`)
    if (!confirmed) return

    try {
      for (const shipmentId of selectedShipmentIds) {
        await deleteShipment(shipmentId)
      }
      alert(`${selectedShipmentIds.size} shipment(s) deleted successfully`)
      setSelectedShipmentIds(new Set())
    } catch (error: any) {
      alert(`Error deleting shipments: ${error.message}`)
    }
  }

  const handleExportCSV = () => {
    if (selectedShipmentIds.size === 0) {
      alert('Please select shipments to export')
      return
    }

    const selectedData = pendingShipments
      .filter(s => selectedShipmentIds.has(s.id))
      .flatMap(s => 
        s.items?.map((item: any) => ({
          'Shipment ID': s.id.substring(0, 8),
          'Panelist': s.panelist?.name || 'N/A',
          'Panelist Code': s.panelist?.panelist_code || 'N/A',
          'Material Code': item.material_code || 'N/A',
          'Material Name': item.material_name || 'Unknown',
          'Quantity': item.quantity_sent,
          'Unit': item.unit_measure || 'un',
          'Expected Date': s.expected_date ? new Date(s.expected_date).toLocaleDateString() : 'N/A'
        })) || []
      )

    downloadCSV(selectedData, `shipments-${new Date().toISOString().split('T')[0]}.csv`)
  }

  const handleGeneratePackingList = () => {
    if (selectedShipmentIds.size === 0) {
      alert('Please select shipments to generate packing list')
      return
    }

    const selectedData = pendingShipments.filter(s => selectedShipmentIds.has(s.id))
    const htmlContent = generatePackingListPDF(selectedData, 'ONEMS')
    printPDF(htmlContent, 'packing-list.pdf')
  }

  const months = [
    { num: 1, name: 'Jan' }, { num: 2, name: 'Feb' }, { num: 3, name: 'Mar' },
    { num: 4, name: 'Apr' }, { num: 5, name: 'May' }, { num: 6, name: 'Jun' },
    { num: 7, name: 'Jul' }, { num: 8, name: 'Aug' }, { num: 9, name: 'Sep' },
    { num: 10, name: 'Oct' }, { num: 11, name: 'Nov' }, { num: 12, name: 'Dec' }
  ]

  return (
    <div className="space-y-6">
      {/* Metrics Cards */}
      {pendingShipments.length > 0 && (
        <div className="bg-white border border-gray-200 rounded-lg">
          <button
            onClick={() => setIsMetricsCollapsed(!isMetricsCollapsed)}
            className="w-full px-4 py-3 flex items-center justify-between text-left hover:bg-gray-50"
          >
            <div className="flex items-center gap-2">
              <Package className="h-4 w-4 text-gray-500" />
              <span className="font-medium text-gray-900">Metrics Overview</span>
            </div>
            {isMetricsCollapsed ? (
              <ChevronDown className="h-4 w-4 text-gray-500" />
            ) : (
              <ChevronUp className="h-4 w-4 text-gray-500" />
            )}
          </button>

          {!isMetricsCollapsed && (
            <div className="px-4 pb-4">
              <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium text-yellow-800">Pending Shipments</p>
                      <p className="text-2xl font-bold text-yellow-900 mt-1">{metrics.pending}</p>
                    </div>
                    <AlertCircle className="h-8 w-8 text-yellow-600" />
                  </div>
                </div>

                <div className="bg-green-50 border border-green-200 rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium text-green-800">Confirmed Shipments</p>
                      <p className="text-2xl font-bold text-green-900 mt-1">{metrics.confirmed}</p>
                    </div>
                    <CheckCircle className="h-8 w-8 text-green-600" />
                  </div>
                </div>

                <div className="bg-blue-50 border border-blue-200 rounded-lg p-4">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm font-medium text-blue-800">Total Items Pending</p>
                      <p className="text-2xl font-bold text-blue-900 mt-1">{metrics.totalItems}</p>
                    </div>
                    <Package className="h-8 w-8 text-blue-600" />
                  </div>
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Calculate Shipments Section */}
      <div className="bg-white border border-gray-200 rounded-lg">
        <button
          onClick={() => setIsFiltersCollapsed(!isFiltersCollapsed)}
          className="w-full px-4 py-3 flex items-center justify-between text-left hover:bg-gray-50"
        >
          <div className="flex items-center gap-2">
            <Filter className="h-4 w-4 text-gray-500" />
            <span className="font-medium text-gray-900">Calculate & Generate Shipments</span>
            <SmartTooltip content="Use this section to calculate material requirements for panelists based on allocation plans, then generate shipments to send materials to them" />
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
                  <button
                    onClick={handleFirstSemesterSelect}
                    className="px-2 py-1 text-xs font-medium rounded border border-green-300 bg-green-50 hover:bg-green-100 hover:border-green-500 focus:outline-none focus:ring-2 focus:ring-green-500"
                  >
                    1st Semester
                  </button>
                  <button
                    onClick={handleSecondSemesterSelect}
                    className="px-2 py-1 text-xs font-medium rounded border border-teal-300 bg-teal-50 hover:bg-teal-100 hover:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500"
                  >
                    2nd Semester
                  </button>
                  <button
                    onClick={handleYearSelect}
                    className="px-2 py-1 text-xs font-medium rounded border border-purple-300 bg-purple-50 hover:bg-purple-100 hover:border-purple-500 focus:outline-none focus:ring-2 focus:ring-purple-500"
                  >
                    Year
                  </button>
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
                <>
                  <button
                    onClick={handleGenerateShipments}
                    className="inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md shadow-sm text-white bg-green-600 hover:bg-green-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-green-500"
                  >
                    <Package className="h-4 w-4 mr-2" />
                    Generate Shipments ({filteredProposedShipments.filter(ps => ps.panelist_id).length})
                  </button>
                  <SmartTooltip content="Generate shipments for panelists based on allocation plans. The system will:

1. Analyze all allocation plans in the date range
2. Group materials by panelist (based on origin_panelist_id)
3. Calculate quantity needed per material per panelist
4. Discount panelist stock (if panelist already has the material)
5. Create shipment records with status 'pending'

Unification Logic:
- If a pending shipment already exists for the same panelist, it will be unified
- All materials for that panelist will be consolidated into one shipment
- Quantities will be summed
- The expected date will be updated to the most recent

Note: Only panelists with assigned allocation plans will have shipments generated">
                    <Info className="h-5 w-5 text-green-500 cursor-help" />
                  </SmartTooltip>
                </>
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

      {/* Shipments Filters */}
      <div className="bg-white border border-gray-200 rounded-lg">
        <div className="px-4 py-3 border-b border-gray-200 flex items-center gap-2">
          <h3 className="text-lg font-medium text-gray-900">Shipments</h3>
          <SmartTooltip content="View and manage all generated shipments. Filter by status, panelist, or material to find specific shipments. Pending shipments can be confirmed for sending." />
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
              <div className="flex items-center gap-2">
                <button
                  onClick={handleSendSelected}
                  className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  <Send className="h-4 w-4 mr-1" />
                  Send {selectedShipmentIds.size} Selected
                </button>
                <button
                  onClick={handleExportCSV}
                  className="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  <Download className="h-4 w-4 mr-1" />
                  Export CSV
                </button>
                <button
                  onClick={handleGeneratePackingList}
                  className="inline-flex items-center px-3 py-1.5 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                >
                  <FileText className="h-4 w-4 mr-1" />
                  Packing List PDF
                </button>
                <button
                  onClick={handleDeleteSelected}
                  className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-red-600 hover:bg-red-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                >
                  <Trash2 className="h-4 w-4 mr-1" />
                  Delete {selectedShipmentIds.size} Selected
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
                          <div className="space-y-1">
                            {shipment.items.map(item => (
                              <div key={item.id} className="flex items-center justify-between gap-2">
                                <span>
                                  {item.material?.code}: {item.quantity_sent} {item.material?.unit_measure}
                                </span>
                                {shipment.status === 'pending' && (
                                  <button
                                    onClick={() => {
                                      setEditingItem(item)
                                      setShowEditModal(true)
                                    }}
                                    className="inline-flex items-center px-2 py-1 text-xs font-medium text-blue-700 bg-blue-100 hover:bg-blue-200 rounded"
                                    title="Edit quantity"
                                  >
                                    <Edit className="h-3 w-3" />
                                  </button>
                                )}
                              </div>
                            ))}
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
                      <div className="flex items-center gap-2">
                        <button
                          onClick={() => handleSendShipment(shipment.id)}
                          className="inline-flex items-center px-3 py-1.5 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                        >
                          <Send className="h-4 w-4 mr-1" />
                          Send
                        </button>
                        <button
                          onClick={() => handleDelete(shipment.id)}
                          className="inline-flex items-center px-2 py-1.5 border border-transparent text-sm font-medium rounded-md text-red-700 bg-red-100 hover:bg-red-200 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </div>
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

      {/* Edit Shipment Item Modal */}
      {showEditModal && editingItem && (
        <EditShipmentItemModal
          item={editingItem}
          onClose={() => {
            setShowEditModal(false)
            setEditingItem(null)
          }}
          onSave={async (itemId, quantity) => {
            await updateShipmentItem(itemId, quantity)
            setShowEditModal(false)
            setEditingItem(null)
          }}
        />
      )}
    </div>
  )
}
