import { useState } from 'react'
import type { Product } from '@/lib/types'

import { useTranslation } from '@/hooks/useTranslation';
interface ProductFormProps {
  product?: Product
  carrierId: string
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function ProductForm({ product, carrierId, onSubmit, onCancel }: ProductFormProps) {
  const { t } = useTranslation();
  const [formData, setFormData] = useState({
    carrier_id: carrierId,
    code: product?.code || '',
    description: product?.description || '',
    standard_delivery_hours: product?.standard_delivery_hours?.toString() || '',
    time_unit: product?.time_unit || 'hours',
    status: product?.status || 'active',
  })
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      const data: any = {
        carrier_id: formData.carrier_id,
        code: formData.code,
        description: formData.description,
        standard_delivery_hours: parseInt(formData.standard_delivery_hours),
        time_unit: formData.time_unit,
        status: formData.status,
      }
      
      await onSubmit(data)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label className="block text-sm font-medium mb-1">{t('productform.code')} *</label>
        <input
          type="text"
          required
          value={formData.code}
          onChange={(e) => setFormData({ ...formData, code: e.target.value.toUpperCase() })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="e.g., DHL-EXP-24"
          maxLength={50}
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">{t('productform.description')} *</label>
        <textarea
          required
          value={formData.description}
          onChange={(e) => setFormData({ ...formData, description: e.target.value })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="e.g., Express delivery 24 hours"
          rows={3}
        />
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">{t('productform.standard_delivery_time')} *</label>
          <input
            type="number"
            required
            min="1"
            value={formData.standard_delivery_hours}
            onChange={(e) => setFormData({ ...formData, standard_delivery_hours: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
            placeholder="e.g., 24"
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-1">{t('productform.time_unit')} *</label>
          <select
            required
            value={formData.time_unit}
            onChange={(e) => setFormData({ ...formData, time_unit: e.target.value as 'hours' | 'days' })}
            className="w-full px-3 py-2 border rounded-md"
          >
            <option value="hours">{t('deliverystandards.hours')}</option>
            <option value="days">{t('deliverystandards.days')}</option>
          </select>
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">Status *</label>
        <select
          required
          value={formData.status}
          onChange={(e) => setFormData({ ...formData, status: e.target.value as any })}
          className="w-full px-3 py-2 border rounded-md"
        >
          <option value="active">{t('common.active')}</option>
          <option value="inactive">{t('common.inactive')}</option>
        </select>
      </div>

      <div className="flex gap-2 justify-end">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 text-gray-700 hover:bg-gray-100 rounded-md"
        >
          {t('productform.cancel')}
        </button>
        <button
          type="submit"
          disabled={loading}
          className="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50"
        >
          {loading ? t('productform.saving') : product ? t('productform.update') : t('productform.create')}
        </button>
      </div>
    </form>
  )
}
