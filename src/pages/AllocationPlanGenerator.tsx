import { useState } from 'react'
import { useAllocationPlans } from '@/hooks/useAllocationPlans'
import { useAppliedAllocationPlans } from '@/hooks/useAppliedAllocationPlans'
import { AllocationPlanGeneratorForm } from '@/components/allocation-plans/AllocationPlanGeneratorForm'
import { CSVHandler } from '@/components/allocation-plans/CSVHandler'
import { PageHeader } from '@/components/common/PageHeader'
import { Button } from '@/components/common/Button'
import { downloadCSV, convertToCSV, type CSVExportData } from '@/lib/csvExport'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/contexts/AuthContext'

export function AllocationPlanGenerator() {
  const { profile } = useAuth()
  const [activeTab, setActiveTab] = useState<'generator' | 'generated' | 'applied'>('generator')
  const {
    generatedPlans,
    carriers,
    products,
    cities,
    nodes,
    loading,
    createPlan,
    createPlanDetails,
    deletePlan,
    applyPlan,
  } = useAllocationPlans()

  const { appliedPlans, loading: appliedLoading } = useAppliedAllocationPlans()

  const handleGenerate = async (planData: any, details: any[]) => {
    const plan = await createPlan(planData)
    await createPlanDetails(plan.id, details)
  }

  const handleApplyPlan = async (planId: string) => {
    if (!confirm('Apply this plan? It will be moved to the applied plans.')) return
    try {
      if (!profile?.id) {
        alert('User not authenticated')
        return
      }
      await applyPlan(planId, profile.id)
      alert('Plan applied successfully!')
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    }
  }

  const handleDeletePlan = async (planId: string) => {
    if (!confirm('Delete this plan?')) return
    try {
      await deletePlan(planId)
      alert('Plan deleted successfully!')
    } catch (error: any) {
      alert(`Error: ${error.message}`)
    }
  }

  const handleDownloadPlan = async (planId: string, planName: string) => {
    try {
      // Fetch plan details with joins
      const { data: details, error } = await supabase
        .from('generated_allocation_plan_details')
        .select(`
          *,
          plan:generated_allocation_plans(
            plan_name,
            carrier:carriers(code),
            product:products(code)
          ),
          origin_node:nodes!generated_allocation_plan_details_origin_node_id_fkey(
            auto_id,
            city:cities(code)
          ),
          destination_node:nodes!generated_allocation_plan_details_destination_node_id_fkey(
            auto_id,
            city:cities(code)
          )
        `)
        .eq('plan_id', planId)

      if (error) throw error
      if (!details || details.length === 0) {
        alert('No details found for this plan')
        return
      }

      // Convert to CSV format
      const csvData: CSVExportData[] = details.map((detail: any) => ({
        plan_name: detail.plan?.plan_name || '',
        account_code: 'ACCOUNT', // TODO: Get from account
        carrier_code: detail.plan?.carrier?.code || '',
        product_code: detail.plan?.product?.code || '',
        origin_city_code: detail.origin_node?.city?.code || '',
        origin_node_code: detail.origin_node?.auto_id || '',
        destination_city_code: detail.destination_node?.city?.code || '',
        destination_node_code: detail.destination_node?.auto_id || '',
        fecha_programada: detail.fecha_programada,
        week_number: detail.week_number,
        month: detail.month,
        year: detail.year,
        status: detail.status,
      }))

      const csv = convertToCSV(csvData)
      const filename = `${planName.replace(/\s+/g, '_')}_${new Date().toISOString().split('T')[0]}.csv`
      downloadCSV(filename, csv)
    } catch (error: any) {
      alert(`Error downloading plan: ${error.message}`)
    }
  }

  const handleDownloadTemplate = () => {
    const headers = [
      'account_code',
      'carrier_code',
      'product_code',
      'origin_city_code',
      'origin_node_code',
      'destination_city_code',
      'destination_node_code',
      'fecha_programada',
      'status',
    ]
    const csv = headers.join(',')
    const blob = new Blob([csv], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'allocation_plan_template.csv'
    a.click()
  }

  const handleImportCSV = async (file: File) => {
    alert('CSV import functionality coming soon!')
    // TODO: Implement CSV parsing and import
  }

  if (loading || appliedLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-600">Loading...</div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <PageHeader title="Allocation Plan Generator" />

      {/* Tabs */}
      <div className="border-b">
        <div className="flex gap-4">
          <button
            onClick={() => setActiveTab('generator')}
            className={`px-4 py-2 border-b-2 ${
              activeTab === 'generator'
                ? 'border-blue-600 text-blue-600'
                : 'border-transparent text-gray-600'
            }`}
          >
            Generator
          </button>
          <button
            onClick={() => setActiveTab('generated')}
            className={`px-4 py-2 border-b-2 ${
              activeTab === 'generated'
                ? 'border-blue-600 text-blue-600'
                : 'border-transparent text-gray-600'
            }`}
          >
            Generated Plans ({generatedPlans.length})
          </button>
          <button
            onClick={() => setActiveTab('applied')}
            className={`px-4 py-2 border-b-2 ${
              activeTab === 'applied'
                ? 'border-blue-600 text-blue-600'
                : 'border-transparent text-gray-600'
            }`}
          >
            Applied Plans ({appliedPlans.length})
          </button>
        </div>
      </div>

      {/* Tab Content */}
      {activeTab === 'generator' && (
        <div className="space-y-6">
          <div className="bg-white rounded-lg shadow p-6">
            <h2 className="text-lg font-medium mb-4">Automatic Generator</h2>
            <AllocationPlanGeneratorForm
              carriers={carriers}
              products={products}
              cities={cities}
              nodes={nodes}
              onGenerate={handleGenerate}
            />
          </div>

          <div className="bg-white rounded-lg shadow p-6">
            <h2 className="text-lg font-medium mb-4">Manual Import</h2>
            <CSVHandler onImport={handleImportCSV} onDownloadTemplate={handleDownloadTemplate} />
          </div>
        </div>
      )}

      {activeTab === 'generated' && (
        <div className="bg-white rounded-lg shadow">
          <div className="p-6">
            <h2 className="text-lg font-medium mb-4">Generated Plans</h2>
            {generatedPlans.length === 0 ? (
              <div className="text-gray-500 text-center py-8">No generated plans yet</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead>
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Plan Name
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Carrier
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Product
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Samples
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Period
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Status
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Actions
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-200">
                    {generatedPlans.map((plan) => (
                      <tr key={plan.id}>
                        <td className="px-6 py-4">{plan.plan_name}</td>
                        <td className="px-6 py-4">{plan.carrier?.name}</td>
                        <td className="px-6 py-4">{plan.product?.description}</td>
                        <td className="px-6 py-4">{plan.details_count}</td>
                        <td className="px-6 py-4">
                          {plan.start_date} to {plan.end_date}
                        </td>
                        <td className="px-6 py-4">
                          <span
                            className={`px-2 py-1 rounded text-xs ${
                              plan.status === 'applied'
                                ? 'bg-green-100 text-green-800'
                                : 'bg-yellow-100 text-yellow-800'
                            }`}
                          >
                            {plan.status}
                          </span>
                        </td>
                        <td className="px-6 py-4">
                          <div className="flex gap-2">
                            <button
                              onClick={() => handleDownloadPlan(plan.id, plan.plan_name)}
                              className="text-blue-600 hover:text-blue-800 text-sm"
                            >
                              Download CSV
                            </button>
                            {plan.status !== 'applied' && (
                              <>
                                <button
                                  onClick={() => handleApplyPlan(plan.id)}
                                  className="text-green-600 hover:text-green-800 text-sm"
                                >
                                  Apply
                                </button>
                                <button
                                  onClick={() => handleDeletePlan(plan.id)}
                                  className="text-red-600 hover:text-red-800 text-sm"
                                >
                                  Delete
                                </button>
                              </>
                            )}
                          </div>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      )}

      {activeTab === 'applied' && (
        <div className="bg-white rounded-lg shadow">
          <div className="p-6">
            <h2 className="text-lg font-medium mb-4">Applied Plans (Historical)</h2>
            {appliedPlans.length === 0 ? (
              <div className="text-gray-500 text-center py-8">No applied plans yet</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead>
                    <tr>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Plan Name
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Carrier
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Product
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Samples
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Applied Date
                      </th>
                      <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">
                        Status
                      </th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-gray-200">
                    {appliedPlans.map((plan) => (
                      <tr key={plan.id}>
                        <td className="px-6 py-4">{plan.plan_name}</td>
                        <td className="px-6 py-4">{plan.carrier?.name}</td>
                        <td className="px-6 py-4">{plan.product?.description}</td>
                        <td className="px-6 py-4">{plan.details_count}</td>
                        <td className="px-6 py-4">
                          {new Date(plan.applied_date).toLocaleDateString()}
                        </td>
                        <td className="px-6 py-4">
                          <span className="px-2 py-1 rounded text-xs bg-green-100 text-green-800">
                            {plan.status}
                          </span>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  )
}
