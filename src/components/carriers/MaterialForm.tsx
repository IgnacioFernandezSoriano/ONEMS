import { useState, useEffect } from 'react'
import type { Material } from '@/lib/types'
import { Button } from '@/components/common/Button'

interface MaterialFormProps {
  material?: Material
  productId: string
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function MaterialForm({ material, productId, onSubmit, onCancel }: MaterialFormProps) {
  const [formData, setFormData] = useState({
    code: material?.code || '',
    name: material?.name || '',
    unit_measure: material?.unit_measure || '',
    quantity: material?.quantity || 1,
    description: material?.description || '',
    status: material?.status || 'active',
  })
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      await onSubmit({
        ...formData,
        product_id: productId,
      })
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Code *
        </label>
        <input
          type="text"
          required
          value={formData.code}
          onChange={(e) => setFormData({ ...formData, code: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder="MAT-001"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Name *
        </label>
        <input
          type="text"
          required
          value={formData.name}
          onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder="RFID Tag"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Unit Measure
        </label>
        <input
          type="text"
          value={formData.unit_measure}
          onChange={(e) => setFormData({ ...formData, unit_measure: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder="units, kg, etc."
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Quantity *
        </label>
        <input
          type="number"
          min="1"
          required
          value={formData.quantity}
          onChange={(e) => setFormData({ ...formData, quantity: parseInt(e.target.value) || 1 })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Description
        </label>
        <textarea
          value={formData.description}
          onChange={(e) => setFormData({ ...formData, description: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          rows={3}
          placeholder="Additional details..."
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Status
        </label>
        <select
          value={formData.status}
          onChange={(e) => setFormData({ ...formData, status: e.target.value as 'active' | 'inactive' })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        >
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>
      </div>

      <div className="flex gap-2 justify-end pt-4">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? 'Saving...' : material ? 'Update' : 'Create'}
        </Button>
      </div>
    </form>
  )
}
