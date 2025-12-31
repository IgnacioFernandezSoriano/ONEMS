import { useState, useEffect } from 'react'
import { getISOWeekFromDate } from '@/utils/weekUtils'

import { useTranslation } from '@/hooks/useTranslation';
interface RecordModalProps {
  isOpen: boolean
  onClose: () => void
  onCreate: (record: any) => Promise<void>
  onUpdate?: (id: string, updates: any) => Promise<void>
  editRecord?: any | null
  plans: any[]
  carriers: any[]
  products: any[]
  cities: any[]
  nodes: any[]
  getNodesByCity: (cityId: string) => any[]
}

export function RecordModal({
  isOpen,
  onClose,
  onCreate,
  onUpdate,
  editRecord,
  plans,
  carriers,
  products,
  cities,
  nodes,
  getNodesByCity,
}: RecordModalProps) {
  const { t } = useTranslation();
  const isEditMode = !!editRecord
  
  const [formData, setFormData] = useState({
    plan_id: '',
    carrier_id: '',
    product_id: '',
    origin_city_id: '',
    origin_node_id: '',
    destination_city_id: '',
    destination_node_id: '',
    fecha_programada: '',
    tag_id: '',
  })

  const [loading, setLoading] = useState(false)

  // Load data when editing
  useEffect(() => {
    if (editRecord) {
      setFormData({
        plan_id: editRecord.plan_id || '',
        carrier_id: editRecord.carrier_id || '',
        product_id: editRecord.product_id || '',
        origin_city_id: editRecord.origin_city_id || '',
        origin_node_id: editRecord.origin_node_id || '',
        destination_city_id: editRecord.destination_city_id || '',
        destination_node_id: editRecord.destination_node_id || '',
        fecha_programada: editRecord.fecha_programada || '',
        tag_id: editRecord.tag_id || '',
      })
    } else {
      // Reset form when creating new record
      setFormData({
        plan_id: '',
        carrier_id: '',
        product_id: '',
        origin_city_id: '',
        origin_node_id: '',
        destination_city_id: '',
        destination_node_id: '',
        fecha_programada: '',
        tag_id: '',
      })
    }
  }, [editRecord])

  const handleChange = (field: string, value: string) => {
    setFormData(prev => ({ ...prev, [field]: value }))
    
    // Reset node when city changes
    if (field === 'origin_city_id') {
      setFormData(prev => ({ ...prev, origin_node_id: '' }))
    }
    if (field === 'destination_city_id') {
      setFormData(prev => ({ ...prev, destination_node_id: '' }))
    }
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)

    try {
      // Calculate week and year from fecha_programada
      const { week_number, year } = getISOWeekFromDate(formData.fecha_programada)

      const recordData = {
        ...formData,
        year,
        week_number,
      }

      if (isEditMode && editRecord && onUpdate) {
        // Update existing record
        await onUpdate(editRecord.id, recordData)
      } else {
        // Create new record
        const newRecord = {
          ...recordData,
          status: 'pending',
          origin_availability_status: 'available',
          destination_availability_status: 'available',
        }
        await onCreate(newRecord)
      }
      
      onClose()
    } catch (error) {
      console.error(`Error ${isEditMode ? 'updating' : 'creating'} record:`, error)
      alert(`Error ${isEditMode ? 'updating' : 'creating'} record. Please try again.`)
    } finally {
      setLoading(false)
    }
  }

  if (!isOpen) return null

  const originNodes = formData.origin_city_id ? getNodesByCity(formData.origin_city_id) : []
  const destinationNodes = formData.destination_city_id ? getNodesByCity(formData.destination_city_id) : []

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
      <div className="bg-white rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <div className="p-6">
          <div className="flex items-center justify-between mb-6">
            <h2 className="text-xl font-semibold">{isEditMode ? 'Edit Record' : 'Add New Record'}</h2>
            <button
              onClick={onClose}
              className="text-gray-400 hover:text-gray-600"
            >
              <svg className="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </button>
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Plan */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-1">
                Plan <span className="text-red-500">*</span>
              </label>
              <select
                value={formData.plan_id}
                onChange={(e) => handleChange('plan_id', e.target.value)}
                required
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">Select Plan</option>
                {plans.map(plan => (
                  <option key={plan.id} value={plan.id}>{plan.plan_name}</option>
                ))}
              </select>
            </div>

            {/* Carrier & Product */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Carrier <span className="text-red-500">*</span>
                </label>
                <select
                  value={formData.carrier_id}
                  onChange={(e) => handleChange('carrier_id', e.target.value)}
                  required
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="">Select Carrier</option>
                  {carriers.map(carrier => (
                    <option key={carrier.id} value={carrier.id}>{carrier.name}</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Product <span className="text-red-500">*</span>
                </label>
                <select
                  value={formData.product_id}
                  onChange={(e) => handleChange('product_id', e.target.value)}
                  required
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="">Select Product</option>
                  {products.map(product => (
                    <option key={product.id} value={product.id}>{product.description}</option>
                  ))}
                </select>
              </div>
            </div>

            {/* Origin City & Node */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Origin City <span className="text-red-500">*</span>
                </label>
                <select
                  value={formData.origin_city_id}
                  onChange={(e) => handleChange('origin_city_id', e.target.value)}
                  required
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="">Select City</option>
                  {cities.map(city => (
                    <option key={city.id} value={city.id}>{city.name}</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Origin Node <span className="text-red-500">*</span>
                </label>
                <select
                  value={formData.origin_node_id}
                  onChange={(e) => handleChange('origin_node_id', e.target.value)}
                  required
                  disabled={!formData.origin_city_id}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100"
                >
                  <option value="">Select Node</option>
                  {originNodes.map(node => (
                    <option key={node.id} value={node.id}>{node.auto_id}</option>
                  ))}
                </select>
              </div>
            </div>

            {/* Destination City & Node */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Destination City <span className="text-red-500">*</span>
                </label>
                <select
                  value={formData.destination_city_id}
                  onChange={(e) => handleChange('destination_city_id', e.target.value)}
                  required
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                >
                  <option value="">Select City</option>
                  {cities.map(city => (
                    <option key={city.id} value={city.id}>{city.name}</option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Destination Node <span className="text-red-500">*</span>
                </label>
                <select
                  value={formData.destination_node_id}
                  onChange={(e) => handleChange('destination_node_id', e.target.value)}
                  required
                  disabled={!formData.destination_city_id}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100"
                >
                  <option value="">Select Node</option>
                  {destinationNodes.map(node => (
                    <option key={node.id} value={node.id}>{node.auto_id}</option>
                  ))}
                </select>
              </div>
            </div>

            {/* Scheduled Date & Tag ID */}
            <div className="grid grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Scheduled Date <span className="text-red-500">*</span>
                </label>
                <input
                  type="date"
                  value={formData.fecha_programada}
                  onChange={(e) => handleChange('fecha_programada', e.target.value)}
                  required
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Tag ID
                </label>
                <input
                  type="text"
                  value={formData.tag_id}
                  onChange={(e) => handleChange('tag_id', e.target.value)}
                  placeholder={t('allocation_plans.optional')}
                  className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
              </div>
            </div>

            {/* Buttons */}
            <div className="flex items-center justify-end gap-3 pt-4 border-t">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200 transition-colors"
              >
                Cancel
              </button>
              <button
                type="submit"
                disabled={loading}
                className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:bg-gray-400"
              >
                {loading ? (isEditMode ? 'Updating...' : 'Creating...') : (isEditMode ? 'Update Record' : 'Create Record')}
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
  )
}
