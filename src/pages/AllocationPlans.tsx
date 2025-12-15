import { useState, useMemo } from 'react'
import { useAllocationPlanDetails } from '@/lib/hooks/useAllocationPlanDetails'
import { AllocationPlanFilters } from '@/components/allocation-plans/AllocationPlanFilters'
import { AllocationPlanDetailRow } from '@/components/allocation-plans/AllocationPlanDetailRow'
import { BulkOperationsPanel } from '@/components/allocation-plans/BulkOperationsPanel'
import { PageHeader } from '@/components/common/PageHeader'

export function AllocationPlans() {
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
  })

  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())

  // Filter details
  const filteredDetails = useMemo(() => {
    return details.filter((detail) => {
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
      
      // Availability issue filter
      if (filters.availabilityIssue) {
        const originStatus = detail.origin_availability_status
        const destStatus = detail.destination_availability_status
        
        if (filters.availabilityIssue === 'unavailable') {
          if (originStatus !== 'unavailable' && destStatus !== 'unavailable') return false
        } else if (filters.availabilityIssue === 'unassigned') {
          if (originStatus !== 'unassigned' && destStatus !== 'unassigned') return false
        } else if (filters.availabilityIssue === 'inactive') {
          if (originStatus !== 'inactive' && destStatus !== 'inactive') return false
        } else if (filters.availabilityIssue === 'any_issue') {
          if (originStatus === 'available' && destStatus === 'available') return false
        }
      }
      
      return true
    })
  }, [details, filters])

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
        d.origin_availability_status !== 'available' || 
        d.destination_availability_status !== 'available'
      ).length,
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
    })
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
      detail.origin_panelist?.name || '',
      detail.destination_panelist?.name || '',
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
      <PageHeader title="Allocation Plans" />

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
        onExportCSV={handleExportCSV}
        onClearSelection={handleClearSelection}
      />

      <div className="bg-white rounded-lg shadow">
        <div className="p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-medium">
              Allocation Plan Details ({filteredDetails.length})
            </h2>
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
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Plan
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Carrier
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Product
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Origin City
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Origin Node
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Dest. City
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Dest. Node
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Scheduled Date
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Week
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Tag ID
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Origin Panelist
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Origin Status
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Dest. Panelist
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Dest. Status
                    </th>
                    <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                      Status
                    </th>
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
                      onToggleSelect={() => handleToggleSelect(detail.id)}
                      onUpdate={updateDetail}
                      getNodesByCity={getNodesByCity}
                    />
                  ))}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
