import { useState } from 'react'
import { Button } from '@/components/common/Button'
import type { Region } from '@/lib/types'

import { useTranslation } from '@/hooks/useTranslation';
interface RegionFormProps {
  region?: Region
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function RegionForm({ region, onSubmit, onCancel }: RegionFormProps) {
  const { t } = useTranslation();
  const [formData, setFormData] = useState({
    name: region?.name || '',
    code: region?.code || '',
    country_code: region?.country_code || '',
    description: region?.description || '',
    status: region?.status || 'active',
  })
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      await onSubmit(formData)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label className="block text-sm font-medium mb-1">Region Name *</label>
        <input
          type="text"
          required
          value={formData.name}
          onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="e.g., Spain, France"
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">Region Code *</label>
        <input
          type="text"
          required
          value={formData.code}
          onChange={(e) => setFormData({ ...formData, code: e.target.value.toUpperCase() })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="e.g., ES, FR"
          maxLength={10}
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">Country Code *</label>
        <input
          type="text"
          required
          value={formData.country_code}
          onChange={(e) => setFormData({ ...formData, country_code: e.target.value.toUpperCase() })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="e.g., ES, FR"
          maxLength={2}
        />
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

      <div>
        <label className="block text-sm font-medium mb-1">{t('topology.description')}</label>
        <textarea
          value={formData.description}
          onChange={(e) => setFormData({ ...formData, description: e.target.value })}
          className="w-full px-3 py-2 border rounded-md"
          rows={3}
        />
      </div>

      <div className="flex gap-2 justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? 'Saving...' : region ? 'Update' : 'Create'}
        </Button>
      </div>
    </form>
  )
}
