import { useState, useMemo } from 'react'
import { useAllocationPlanDetails } from '@/lib/hooks/useAllocationPlanDetails'
import { AllocationPlanFilters } from '@/components/allocation-plans/AllocationPlanFilters'
import { AllocationPlanDetailRow } from '@/components/allocation-plans/AllocationPlanDetailRow'
import { BulkOperationsPanel } from '@/components/allocation-plans/BulkOperationsPanel'
import { RecordModal } from '@/components/allocation-plans/RecordModal'
import { PageHeader } from '@/components/common/PageHeader'
import { SortableHeader } from '@/components/common/SortableHeader'
import { SmartTooltip } from '@/components/common/SmartTooltip'

import { useTranslation } from '@/hooks/useTranslation';
export function AllocationPlans() {
  const { t } = useTranslation();
  const {
    details,
    plans,
    carriers,
    products,
    cities,
    nodes,
    panelists,
    loading,
    error,
    updateDetail,
    createDetail,
    markAsSent,
    bulkUpdateDetails,
    bulkDeleteDetails,
    getNodesByCity,
  } = useAllocationPlanDetails()

  const [filters, setFilters] = useState({
    planId: '',
    carrierId: '',
    productId: '',
    originCityId: '',
    destinationCityId: '',
    originNodeId: '',
    destinationNodeId: '',
    startDate: '',
    endDate: '',
    status: '',
    availabilityIssue: '',
    tagId: '',
    eventId: '',
  })

  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [sortField, setSortField] = useState<string>('')
  const [sortDirection, setSortDirection] = useState<'asc' | 'desc'>('asc')
  const [showRecordModal, setShowRecordModal] = useState(false)
  const [editingRecord, setEditingRecord] = useState<any | null>(null)
  const [showIdColumn, setShowIdColumn] = useState(false)

  // Modal handlers
  const handleAddRecord = () => {
    setEditingRecord(null)
    setShowRecordModal(true)
  }

  const handleEditRecord = (record: any) => {
    setEditingRecord(record)
    setShowRecordModal(true)
  }

  const handleCloseModal = () => {
    setShowRecordModal(false)
    setEditingRecord(null)
  }

  // Sort handler
  const handleSort = (field: string) => {
    if (sortField === field) {
      setSortDirection(sortDirection === 'asc' ? 'desc' : 'asc')
    } else {
      setSortField(field)
      setSortDirection('asc')
    }
  }

  // Filter and sort details
  const filteredDetails = useMemo(() => {
    let filtered = details.filter((detail) => {
      if (filters.planId && detail.plan?.id !== filters.planId) return false
      if (filters.carrierId && detail.carrier?.id !== filters.carrierId) return false
      if (filters.productId && detail.product?.id !== filters.productId) return false
      if (filters.originCityId && detail.origin_city?.id !== filters.originCityId) return false
      if (filters.destinationCityId && detail.destination_city?.id !== filters.destinationCityId)
        return false
      if (filters.originNodeId && detail.origin_node_id !== filters.originNodeId) return false
      if (filters.destinationNodeId && detail.destination_node_id !== filters.destinationNodeId)
        return false
      if (filters.startDate && detail.fecha_programada < filters.startDate) return false
      if (filters.endDate && detail.fecha_programada > filters.endDate) return false
      if (filters.status && detail.status !== filters.status) return false
      
      // Tag ID filter (contains search)
      if (filters.tagId && detail.tag_id) {
        if (!detail.tag_id.toLowerCase().includes(filters.tagId.toLowerCase())) return false
      } else if (filters.tagId && !detail.tag_id) {
        return false
      }
      
      // Event ID filter (contains search)
      if (filters.eventId) {
        if (!detail.id.toLowerCase().includes(filters.eventId.toLowerCase())) return false
      }
      
      // Availability issue filter
      if (filters.availabilityIssue) {
        const originStatus = detail.origin_availability_status
        const destStatus = detail.destination_availability_status
        const hasOriginPanelist = !!detail.origin_panelist_id
        const hasDestPanelist = !!detail.destination_panelist_id
        
        if (filters.availabilityIssue === 'unavailable') {
          if (originStatus !== 'unavailable' && destStatus !== 'unavailable') return false
        } else if (filters.availabilityIssue === 'unassigned') {
          if (hasOriginPanelist && hasDestPanelist) return false
        } else if (filters.availabilityIssue === 'inactive') {
          if (originStatus !== 'inactive' && destStatus !== 'inactive') return false
        } else if (filters.availabilityIssue === 'any_issue') {
          if (hasOriginPanelist && hasDestPanelist && originStatus === 'available' && destStatus === 'available') return false
        }
      }
      
      return true
    })

    // Apply sorting
    if (sortField) {
      filtered.sort((a, b) => {
        let aVal: any
        let bVal: any

        switch (sortField) {
          case 'id':
            aVal = a.id || ''
            bVal = b.id || ''
            break
          case 'plan':
            aVal = a.plan?.plan_name || ''
            bVal = b.plan?.plan_name || ''
            break
          case 'carrier':
            aVal = a.carrier?.name || ''
            bVal = b.carrier?.name || ''
            break
          case 'product':
            aVal = a.product?.description || ''
            bVal = b.product?.description || ''
            break
          case 'originCity':
            aVal = a.origin_city?.name || ''
            bVal = b.origin_city?.name || ''
            break
          case 'originNode':
            aVal = a.origin_node?.auto_id || ''
            bVal = b.origin_node?.auto_id || ''
            break
          case 'destCity':
            aVal = a.destination_city?.name || ''
            bVal = b.destination_city?.name || ''
            break
          case 'destNode':
            aVal = a.destination_node?.auto_id || ''
            bVal = b.destination_node?.auto_id || ''
            break
          case 'date':
            aVal = a.fecha_programada || ''
            bVal = b.fecha_programada || ''
            break
          case 'week':
            aVal = a.week_number || 0
            bVal = b.week_number || 0
            break
          case 'tagId':
            aVal = a.tag_id || ''
            bVal = b.tag_id || ''
            break
          case 'originPanelist':
            aVal = a.origin_panelist_name || ''
            bVal = b.origin_panelist_name || ''
            break
          case 'destPanelist':
            aVal = a.destination_panelist_name || ''
            bVal = b.destination_panelist_name || ''
            break
          case 'status':
            aVal = a.status || ''
            bVal = b.status || ''
            break
          default:
            return 0
        }

        if (typeof aVal === 'string') {
          aVal = aVal.toLowerCase()
          bVal = bVal.toLowerCase()
        }

        if (aVal < bVal) return sortDirection === 'asc' ? -1 : 1
        if (aVal > bVal) return sortDirection === 'asc' ? 1 : -1
        return 0
      })
    }

    return filtered
  }, [details, filters, sortField, sortDirection])

  // Calculate availability issue counts
  const availabilityCounts = useMemo(() => {
    return {
      unavailable: details.filter(d => 
        d.origin_availability_status === 'unavailable' || 
        d.destination_availability_status === 'unavailable'
      ).length,
      unassigned: details.filter(d => 
        d.origin_availability_status === 'unassigned' || 
        d.destination_availability_status === 'unassigned'
      ).length,
      inactive: details.filter(d => 
        d.origin_availability_status === 'inactive' || 
        d.destination_availability_status === 'inactive'
      ).length,
      any_issue: details.filter(d => 
        !d.origin_panelist_id || 
        !d.destination_panelist_id ||
        d.origin_availability_status !== 'available' || 
        d.destination_availability_status !== 'available'
      ).length,
    }
  }, [details])

  // Calculate delayed shipments (scheduled date < today AND status != 'received')
  const delayedCounts = useMemo(() => {
    const today = new Date()
    today.setHours(0, 0, 0, 0)
    
    const delayed = details.filter(d => {
      if (!d.fecha_programada) return false
      const scheduledDate = new Date(d.fecha_programada)
      return scheduledDate < today && d.status !== 'received'
    })
    
    return {
      total: delayed.length,
      pending: delayed.filter(d => d.status === 'pending' || d.status === 'notified').length,
      sent: delayed.filter(d => d.status === 'sent').length,
      cancelled: delayed.filter(d => d.status === 'cancelled').length,
      invalid: delayed.filter(d => d.status === 'invalid').length,
      transfer_error: delayed.filter(d => d.status === 'transfer_error').length,
    }
  }, [details])

  const handleFilterChange = (key: string, value: string) => {
    setFilters((prev) => ({ ...prev, [key]: value }))
  }

  const handleClearFilters = () => {
    setFilters({
      planId: '',
      carrierId: '',
      productId: '',
      originCityId: '',
      destinationCityId: '',
      originNodeId: '',
      destinationNodeId: '',
      startDate: '',
      endDate: '',
      status: '',
      availabilityIssue: '',
      tagId: '',
      eventId: '',
    })
  }

  const handleCardClick = (filterType: string, filterValue: string) => {
    handleClearFilters()
    if (filterType === 'status') {
      setFilters(prev => ({ ...prev, status: filterValue }))
    } else if (filterType === 'availabilityIssue') {
      setFilters(prev => ({ ...prev, availabilityIssue: filterValue }))
    } else if (filterType === 'delayed') {
      // For delayed, set end date to yesterday
      const yesterday = new Date()
      yesterday.setDate(yesterday.getDate() - 1)
      const endDate = yesterday.toISOString().split('T')[0]
      setFilters(prev => ({ ...prev, endDate, status: filterValue }))
    }
  }

  const handleToggleSelect = (id: string) => {
    setSelectedIds((prev) => {
      const newSet = new Set(prev)
      if (newSet.has(id)) {
        newSet.delete(id)
      } else {
        newSet.add(id)
      }
      return newSet
    })
  }

  const handleSelectAll = () => {
    if (selectedIds.size === filteredDetails.length) {
      setSelectedIds(new Set())
    } else {
      setSelectedIds(new Set(filteredDetails.map((d) => d.id)))
    }
  }

  const handleClearSelection = () => {
    setSelectedIds(new Set())
  }

  const handleBulkUpdateOriginNode = async (nodeId: string) => {
    await bulkUpdateDetails(Array.from(selectedIds), { origin_node_id: nodeId })
    setSelectedIds(new Set())
  }

  const handleBulkUpdateDestinationNode = async (nodeId: string) => {
    await bulkUpdateDetails(Array.from(selectedIds), { destination_node_id: nodeId })
    setSelectedIds(new Set())
  }

  const handleBulkUpdateDate = async (date: string) => {
    // Calculate week number and month/year from date
    const dateObj = new Date(date)
    const weekNumber = getWeekNumber(dateObj)
    const month = dateObj.getMonth() + 1
    const year = dateObj.getFullYear()

    await bulkUpdateDetails(Array.from(selectedIds), {
      fecha_programada: date,
      week_number: weekNumber,
      month,
      year,
    })
    setSelectedIds(new Set())
  }

  const handleBulkCancel = async () => {
    await bulkUpdateDetails(Array.from(selectedIds), { status: 'cancelled' })
    setSelectedIds(new Set())
  }

  const handleBulkReprocess = async () => {
    const { supabase } = await import('@/lib/supabase')
    
    const idsToReprocess = Array.from(selectedIds)
    const { data, error } = await supabase.rpc('reprocess_transfer_errors', {
      p_detail_ids: idsToReprocess
    })
    
    if (error) throw error
    
    // Refresh the data
    window.location.reload()
    setSelectedIds(new Set())
  }

  const handleBulkDelete = async () => {
    await bulkDeleteDetails(Array.from(selectedIds))
    setSelectedIds(new Set())
  }

  const handleExportCSV = () => {
    const selectedDetails = filteredDetails.filter(d => selectedIds.has(d.id))
    
    // CSV Headers
    const headers = [
      'Plan Name',
      'Carrier',
      'Product',
      'Origin City',
      'Origin Node',
      'Destination City',
      'Destination Node',
      'Scheduled Date',
      'Week',
      'Month',
      'Year',
      'Status',
      'Tag ID',
      'Sent At',
      'Received At',
      'Origin Panelist',
      'Destination Panelist',
      'Origin Availability',
      'Destination Availability'
    ]

    // CSV Rows
    const rows = selectedDetails.map(detail => [
      detail.plan?.plan_name || '',
      detail.carrier?.name || '',
      detail.product?.description || '',
      detail.origin_city?.name || '',
      detail.origin_node?.auto_id || '',
      detail.destination_city?.name || '',
      detail.destination_node?.auto_id || '',
      detail.fecha_programada || '',
      detail.week_number || '',
      detail.month || '',
      detail.year || '',
      detail.status || '',
      detail.tag_id || '',
      detail.sent_at ? new Date(detail.sent_at).toLocaleString() : '',
      detail.received_at ? new Date(detail.received_at).toLocaleString() : '',
      detail.origin_panelist_name || '',
      detail.destination_panelist_name || '',
      detail.origin_availability_status || '',
      detail.destination_availability_status || ''
    ])

    // Create CSV content
    const csvContent = [
      headers.join(','),
      ...rows.map(row => row.map(cell => `"${cell}"`).join(','))
    ].join('\n')

    // Download CSV
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' })
    const link = document.createElement('a')
    const url = URL.createObjectURL(blob)
    link.setAttribute('href', url)
    link.setAttribute('download', `allocation_plans_${new Date().toISOString().split('T')[0]}.csv`)
    link.style.visibility = 'hidden'
    document.body.appendChild(link)
    link.click()
    document.body.removeChild(link)
  }

  // Helper function to calculate week number
  const getWeekNumber = (date: Date): number => {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
    const dayNum = d.getUTCDay() || 7
    d.setUTCDate(d.getUTCDate() + 4 - dayNum)
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
    return Math.ceil(((d.getTime() - yearStart.getTime()) / 86400000 + 1) / 7)
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-600">Loading...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-600">Error: {error}</div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Header with Tooltip */}
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2">
            <h1 className="text-2xl font-bold text-gray-900">Allocation Plans</h1>
            <SmartTooltip content="Allocation Plans Management - Purpose: View and manage generated allocation plans with detailed shipment assignments between origin and destination nodes. Key Features: Track scheduled shipments, monitor panelist assignments, identify availability issues, and perform bulk operations on multiple records. Usage: Filter plans by criteria, review assignments, update nodes or dates in bulk, cancel or reprocess shipments, and export data for analysis.">
              <svg
                className="w-5 h-5 text-gray-400 hover:text-gray-600 cursor-help"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <circle cx="12" cy="12" r="10" strokeWidth="2" />
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 16v-4m0-4h.01" />
              </svg>
            </SmartTooltip>
          </div>
          <p className="text-gray-600 mt-1">{t('allocation_plans.view_and_manage')}</p>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        {/* Total & Pending */}
        <div className="bg-gradient-to-br from-blue-50 to-white p-6 rounded-lg shadow hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-3">
            <div className="flex items-center gap-2">
              <p className="text-sm font-medium text-blue-600">Total & Pending</p>
              <SmartTooltip content="Total allocation records and pending shipments awaiting execution." />
            </div>
            <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2" />
              </svg>
            </div>
          </div>
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-600">📊 Total</span>
              <span className="text-lg font-bold text-blue-600">{details.length}</span>
            </div>
            <div className="flex items-center justify-between pt-2 border-t border-blue-100">
              <span className="text-xs text-gray-600">⏳ Pending</span>
              <button
                onClick={() => handleCardClick('status', 'pending')}
                className="text-lg font-bold text-amber-600 hover:text-amber-700 hover:underline cursor-pointer transition-colors"
              >
                {details.filter(d => d.status === 'pending' || d.status === 'notified').length}
              </button>
            </div>
          </div>
        </div>

        {/* Shipment Status Breakdown */}
        <div className="bg-gradient-to-br from-green-50 to-white p-6 rounded-lg shadow hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-3">
            <p className="text-sm font-medium text-green-600">Shipment Status</p>
            <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4" />
              </svg>
            </div>
          </div>
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-600">{t('stock.pending')}</span>
              <button
                onClick={() => handleCardClick('status', 'pending')}
                className="text-sm font-semibold text-amber-600 hover:text-amber-700 hover:underline cursor-pointer transition-colors"
              >
                {details.filter(d => d.status === 'pending' || d.status === 'notified').length}
              </button>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-600">{t('stock.sent')}</span>
              <button
                onClick={() => handleCardClick('status', 'sent')}
                className="text-sm font-semibold text-blue-600 hover:text-blue-700 hover:underline cursor-pointer transition-colors"
              >
                {details.filter(d => d.status === 'sent').length}
              </button>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-xs text-gray-600">{t('stock.received')}</span>
              <button
                onClick={() => handleCardClick('status', 'received')}
                className="text-sm font-semibold text-green-600 hover:text-green-700 hover:underline cursor-pointer transition-colors"
              >
                {details.filter(d => d.status === 'received').length}
              </button>
            </div>
          </div>
        </div>

        {/* Availability Issues */}
        <div className="bg-gradient-to-br from-red-50 to-white p-6 rounded-lg shadow hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <p className="text-sm font-medium text-red-600">Availability Issues</p>
              <SmartTooltip content="Shipments with panelist availability problems. Unavailable: Panelist not available on scheduled date. No Panelist: No panelist assigned to route. Inactive: Assigned panelist is inactive. Action required: Review and reassign panelists or adjust scheduled dates." />
            </div>
            <div className="w-12 h-12 bg-red-100 rounded-lg flex items-center justify-center">
              <svg className="w-6 h-6 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
            </div>
          </div>
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-600">⚠️ Unavailable</span>
                <SmartTooltip content="Panelist not available on the scheduled date. Review panelist calendar and either reassign to another panelist or change the scheduled date." />
              </div>
              <button
                onClick={() => handleCardClick('availabilityIssue', 'unavailable')}
                className="text-sm font-semibold text-red-600 hover:text-red-700 hover:underline cursor-pointer transition-colors"
              >
                {availabilityCounts.unavailable}
              </button>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-600">📋 No Panelist</span>
                <SmartTooltip content="No panelist assigned to this route. Assign a panelist from the available pool for the origin and destination nodes." />
              </div>
              <button
                onClick={() => handleCardClick('availabilityIssue', 'unassigned')}
                className="text-sm font-semibold text-orange-600 hover:text-orange-700 hover:underline cursor-pointer transition-colors"
              >
                {availabilityCounts.unassigned}
              </button>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-600">❌ Inactive</span>
                <SmartTooltip content="Assigned panelist is marked as inactive. Reassign to an active panelist to proceed with the shipment." />
              </div>
              <button
                onClick={() => handleCardClick('availabilityIssue', 'inactive')}
                className="text-sm font-semibold text-gray-600 hover:text-gray-700 hover:underline cursor-pointer transition-colors"
              >
                {availabilityCounts.inactive}
              </button>
            </div>
            <div className="flex items-center justify-between pt-2 border-t border-red-100">
              <span className="text-xs font-medium text-gray-700">Total Issues</span>
              <button
                onClick={() => handleCardClick('availabilityIssue', 'any_issue')}
                className="text-lg font-bold text-red-600 hover:text-red-700 hover:underline cursor-pointer transition-colors"
              >
                {availabilityCounts.any_issue}
              </button>
            </div>
          </div>
        </div>

        {/* Delayed Shipments */}
        <div className="bg-gradient-to-br from-orange-50 to-white p-6 rounded-lg shadow hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-4">
            <div className="flex items-center gap-2">
              <p className="text-sm font-medium text-orange-600">Delayed Shipments</p>
              <SmartTooltip content="Shipments scheduled before today but not yet received. Breakdown by status: Pending (not sent), Sent (awaiting receipt), Cancelled, Invalid, Transfer Error. Action required: Review and expedite or update status." />
            </div>
            <div className="w-12 h-12 bg-orange-100 rounded-lg flex items-center justify-center">
              <svg className="w-6 h-6 text-orange-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
          <div className="space-y-2">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-600">⏳ Pending</span>
                <SmartTooltip content="Delayed shipments not yet sent. Send immediately or reschedule." />
              </div>
              <button
                onClick={() => handleCardClick('delayed', 'pending')}
                className="text-sm font-semibold text-amber-600 hover:text-amber-700 hover:underline cursor-pointer transition-colors"
              >
                {delayedCounts.pending}
              </button>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-600">📦 Sent</span>
                <SmartTooltip content="Delayed shipments sent but not received. Follow up with panelists." />
              </div>
              <button
                onClick={() => handleCardClick('delayed', 'sent')}
                className="text-sm font-semibold text-blue-600 hover:text-blue-700 hover:underline cursor-pointer transition-colors"
              >
                {delayedCounts.sent}
              </button>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-600">❌ Cancelled</span>
                <SmartTooltip content="Delayed shipments that were cancelled." />
              </div>
              <button
                onClick={() => handleCardClick('delayed', 'cancelled')}
                className="text-sm font-semibold text-gray-600 hover:text-gray-700 hover:underline cursor-pointer transition-colors"
              >
                {delayedCounts.cancelled}
              </button>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-600">⚠️ Invalid</span>
                <SmartTooltip content="Delayed shipments marked as invalid." />
              </div>
              <button
                onClick={() => handleCardClick('delayed', 'invalid')}
                className="text-sm font-semibold text-gray-600 hover:text-gray-700 hover:underline cursor-pointer transition-colors"
              >
                {delayedCounts.invalid}
              </button>
            </div>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2">
                <span className="text-xs text-gray-600">🔄 Transfer Error</span>
                <SmartTooltip content="Delayed shipments with transfer errors. Reprocess or fix manually." />
              </div>
              <button
                onClick={() => handleCardClick('delayed', 'transfer_error')}
                className="text-sm font-semibold text-gray-600 hover:text-gray-700 hover:underline cursor-pointer transition-colors"
              >
                {delayedCounts.transfer_error}
              </button>
            </div>
            <div className="flex items-center justify-between pt-2 border-t border-orange-100">
              <span className="text-xs font-medium text-gray-700">Total Delayed</span>
              <button
                onClick={() => handleCardClick('delayed', '')}
                className="text-lg font-bold text-orange-600 hover:text-orange-700 hover:underline cursor-pointer transition-colors"
              >
                {delayedCounts.total}
              </button>
            </div>
          </div>
        </div>
      </div>

      <AllocationPlanFilters
        filters={filters}
        plans={plans}
        carriers={carriers}
        products={products}
        cities={cities}
        nodes={nodes}
        availabilityCounts={availabilityCounts}
        onFilterChange={handleFilterChange}
        onClearFilters={handleClearFilters}
      />

      <BulkOperationsPanel
        selectedCount={selectedIds.size}
        selectedDetails={filteredDetails.filter(d => selectedIds.has(d.id))}
        nodes={nodes}
        onBulkUpdateOriginNode={handleBulkUpdateOriginNode}
        onBulkUpdateDestinationNode={handleBulkUpdateDestinationNode}
        onBulkUpdateDate={handleBulkUpdateDate}
        onBulkCancel={handleBulkCancel}
        onBulkReprocess={handleBulkReprocess}
        onBulkDelete={handleBulkDelete}
        onClearSelection={handleClearSelection}
      />

      <div className="bg-white rounded-lg shadow">
        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-medium">
              Allocation Plan Details ({filteredDetails.length})
            </h2>
            <div className="flex items-center gap-3">
              <button
                onClick={() => setShowIdColumn(!showIdColumn)}
                className={`flex items-center gap-2 px-3 py-2 rounded-md transition-colors text-sm ${
                  showIdColumn
                    ? 'bg-blue-100 text-blue-700 hover:bg-blue-200'
                    : 'bg-gray-100 text-gray-700 hover:bg-gray-200'
                }`}
                title={showIdColumn ? 'Hide Event ID column' : 'Show Event ID column'}
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z" />
                </svg>
                {showIdColumn ? 'Hide' : 'Show'} ID
              </button>
              <button
                onClick={handleExportCSV}
                disabled={selectedIds.size === 0}
                className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-md hover:bg-green-700 transition-colors disabled:bg-gray-300 disabled:cursor-not-allowed"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                </svg>
                {t('common.export_csv')} {selectedIds.size > 0 ? `(${selectedIds.size})` : ''}
              </button>
              <button
                onClick={handleAddRecord}
                className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition-colors"
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M12 4v16m8-8H4" />
                </svg>
                {t('common.add_record')}
              </button>
            </div>
          </div>
        </div>

        {filteredDetails.length === 0 ? (
          <div className="text-gray-500 text-center py-8 px-6">No records found</div>
        ) : (
          <div className="overflow-x-auto">
            <div className="max-h-[600px] overflow-y-auto">
              <table className="min-w-full divide-y divide-gray-200">
                <thead className="bg-gray-50 sticky top-0 z-10">
                  <tr>
                    <th className="px-4 py-3 text-left">
                      <input
                        type="checkbox"
                        checked={
                          filteredDetails.length > 0 &&
                          selectedIds.size === filteredDetails.length
                        }
                        onChange={handleSelectAll}
                        className="rounded border-gray-300"
                      />
                    </th>
                    {showIdColumn && (
                      <SortableHeader field="id" label="Event ID" sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="Unique identifier for this allocation plan detail event. Used to track material movements and shipments." />
                    )}
                    <SortableHeader field="plan" label={t('onedb.plan')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The allocation plan name that this shipment belongs to." />
                    <SortableHeader field="carrier" label={t('reporting.carrier')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The logistics carrier responsible for this shipment." />
                    <SortableHeader field="product" label={t('reporting.product')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The carrier product/service type used for this shipment." />
                    <SortableHeader field="originCity" label={t('allocation_plans.origin_city')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The city where the package is picked up." />
                    <SortableHeader field="originNode" label={t('allocation_plans.origin_node')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The specific node within the origin city where pickup occurs." />
                    <SortableHeader field="destCity" label={t('allocation_plans.dest_city')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The city where the package is delivered." />
                    <SortableHeader field="destNode" label={t('allocation_plans.dest_node')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The specific node within the destination city where delivery occurs." />
                    <SortableHeader field="date" label={t('allocation_plans.scheduled_date')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The date when this shipment is scheduled to be executed." />
                    <SortableHeader field="week" label={t('allocationplans.week')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The ISO week number of the scheduled date (1-53)." />
                    <SortableHeader field="tagId" label="Tag ID" sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The physical tag identifier assigned to track this shipment." />
                    <SortableHeader field="originPanelist" label={t('allocation_plans.origin_panelist')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The panelist assigned to send the package from the origin node." />
                    <SortableHeader field="originStatus" label={t('allocation_plans.origin_status')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="Origin panelist availability: Available, Unavailable (not available on date), No Panelist (no panelist), or Inactive." />
                    <SortableHeader field="destPanelist" label={t('allocation_plans.dest_panelist')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="The panelist assigned to receive the package at the destination node." />
                    <SortableHeader field="destStatus" label={t('allocation_plans.dest_status')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="Destination panelist availability: Available, Unavailable (not available on date), No Panelist (no panelist), or Inactive." />
                    <SortableHeader field="status" label={t('common.status')} sortField={sortField} sortDirection={sortDirection} onSort={handleSort} tooltip="Shipment status: Pending (not started), Notified, Sent (dispatched), Received (delivered), Cancelled, Invalid, or Transfer Error." />
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Actions
                    </th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-gray-200">
                  {filteredDetails.map((detail) => (
                    <AllocationPlanDetailRow
                      key={detail.id}
                      detail={detail}
                      nodes={nodes}
                      panelists={panelists}
                      selected={selectedIds.has(detail.id)}
                      showIdColumn={showIdColumn}
                      onToggleSelect={() => handleToggleSelect(detail.id)}
                      onUpdate={updateDetail}
                      onMarkAsSent={markAsSent}
                      onEdit={handleEditRecord}
                      getNodesByCity={getNodesByCity}
                    />
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>

      <RecordModal
        isOpen={showRecordModal}
        onClose={handleCloseModal}
        onCreate={createDetail}
        onUpdate={updateDetail}
        editRecord={editingRecord}
        plans={plans}
        carriers={carriers}
        products={products}
        cities={cities}
        nodes={nodes}
        getNodesByCity={getNodesByCity}
      />
    </div>
  )
}
