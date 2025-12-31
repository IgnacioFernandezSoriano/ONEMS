import { useState, useEffect } from 'react'
import type { DeliveryStandard, Carrier, Product, City } from '@/lib/types'

import { useTranslation } from '@/hooks/useTranslation';
interface DeliveryStandardFormProps {
  standard?: DeliveryStandard
  carriers: Carrier[]
  products: Product[]
  cities: City[]
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function DeliveryStandardForm({
  standard,
  carriers,
  products,
  cities,
  onSubmit,
  onCancel,
}: DeliveryStandardFormProps) {
  const { t } = useTranslation();
  const [formData, setFormData] = useState({
    carrier_id: standard?.carrier_id || '',
    product_id: standard?.product_id || '',
    origin_city_id: standard?.origin_city_id || '',
    destination_city_id: standard?.destination_city_id || '',
    standard_time: standard?.standard_time?.toString() || '',
    success_percentage: standard?.success_percentage?.toString() || '',
    time_unit: standard?.time_unit || 'hours',
  })
  const [loading, setLoading] = useState(false)

  // Filter products by selected carrier
  const availableProducts = products.filter(
    (p) => !formData.carrier_id || p.carrier_id === formData.carrier_id
  )

  // Reset product if carrier changes and product doesn't belong to new carrier
  useEffect(() => {
    if (formData.carrier_id && formData.product_id) {
      const product = products.find((p) => p.id === formData.product_id)
      if (product && product.carrier_id !== formData.carrier_id) {
        setFormData((prev) => ({ ...prev, product_id: '' }))
      }
    }
  }, [formData.carrier_id, formData.product_id, products])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()

    // Validation
    if (formData.origin_city_id === formData.destination_city_id) {
      alert('Origin and destination cities must be different')
      return
    }

    setLoading(true)
    try {
      const data: any = {
        carrier_id: formData.carrier_id,
        product_id: formData.product_id,
        origin_city_id: formData.origin_city_id,
        destination_city_id: formData.destination_city_id,
        standard_time: formData.standard_time ? parseFloat(formData.standard_time) : null,
        success_percentage: formData.success_percentage
          ? parseFloat(formData.success_percentage)
          : null,
        time_unit: formData.time_unit,
      }

      await onSubmit(data)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">Carrier *</label>
          <select
            required
            disabled={!!standard}
            value={formData.carrier_id}
            onChange={(e) => setFormData({ ...formData, carrier_id: e.target.value })}
            className="w-full px-3 py-2 border rounded-md disabled:bg-gray-100"
          >
            <option value="">Select carrier</option>
            {carriers.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name} ({c.code})
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Product *</label>
          <select
            required
            disabled={!!standard}
            value={formData.product_id}
            onChange={(e) => setFormData({ ...formData, product_id: e.target.value })}
            className="w-full px-3 py-2 border rounded-md disabled:bg-gray-100"
          >
            <option value="">Select product</option>
            {availableProducts.map((p) => (
              <option key={p.id} value={p.id}>
                {p.description} ({p.code})
              </option>
            ))}
          </select>
          {formData.carrier_id && availableProducts.length === 0 && (
            <p className="text-xs text-amber-600 mt-1">No products for this carrier</p>
          )}
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">Origin City *</label>
          <select
            required
            disabled={!!standard}
            value={formData.origin_city_id}
            onChange={(e) => setFormData({ ...formData, origin_city_id: e.target.value })}
            className="w-full px-3 py-2 border rounded-md disabled:bg-gray-100"
          >
            <option value="">Select origin</option>
            {cities.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name} ({c.code})
                {c.classification && ` - Type ${c.classification}`}
              </option>
            ))}
          </select>
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Destination City *</label>
          <select
            required
            disabled={!!standard}
            value={formData.destination_city_id}
            onChange={(e) => setFormData({ ...formData, destination_city_id: e.target.value })}
            className="w-full px-3 py-2 border rounded-md disabled:bg-gray-100"
          >
            <option value="">Select destination</option>
            {cities
              .filter((c) => c.id !== formData.origin_city_id)
              .map((c) => (
                <option key={c.id} value={c.id}>
                  {c.name} ({c.code})
                  {c.classification && ` - Type ${c.classification}`}
                </option>
              ))}
          </select>
        </div>
      </div>

      {standard && (
        <div className="bg-blue-50 border border-blue-200 rounded p-3 text-sm text-blue-800">
          ℹ️ Carrier, Product, Origin and Destination cannot be changed. Delete and create a new
          record if needed.
        </div>
      )}

      <div className="grid grid-cols-3 gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">Standard Time</label>
          <input
            type="number"
            step="0.01"
            min="0"
            value={formData.standard_time}
            onChange={(e) => setFormData({ ...formData, standard_time: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
            placeholder="e.g., 24"
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Success %</label>
          <input
            type="number"
            step="0.01"
            min="0"
            max="100"
            value={formData.success_percentage}
            onChange={(e) => setFormData({ ...formData, success_percentage: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
            placeholder="e.g., 85"
          />
        </div>

        <div>
          <label className="block text-sm font-medium mb-1">Time Unit *</label>
          <select
            required
            value={formData.time_unit}
            onChange={(e) =>
              setFormData({ ...formData, time_unit: e.target.value as 'hours' | 'days' })
            }
            className="w-full px-3 py-2 border rounded-md"
          >
            <option value="hours">{t('deliverystandards.hours')}</option>
            <option value="days">{t('deliverystandards.days')}</option>
          </select>
        </div>
      </div>

      <div className="flex gap-2 justify-end pt-4 border-t">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 text-gray-700 hover:bg-gray-100 rounded-md"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={loading}
          className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? 'Saving...' : standard ? 'Update' : 'Create'}
        </button>
      </div>
    </form>
  )
}
