import { useState } from 'react'
import type { MaterialCatalog } from '@/lib/types'
import { Button } from '@/components/common/Button'

import { useTranslation } from '@/hooks/useTranslation';
interface MaterialCatalogFormProps {
  material?: MaterialCatalog
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function MaterialCatalogForm({ material, onSubmit, onCancel }: MaterialCatalogFormProps) {
  const { t } = useTranslation();
  const [formData, setFormData] = useState({
    code: material?.code || '',
    name: material?.name || '',
    unit_measure: material?.unit_measure || '',
    min_stock: material?.min_stock || 0,
    description: material?.description || '',
    status: material?.status || 'active',
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
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('hc.material_catalog_form.code')} *
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
          {t('hc.material_catalog_form.name')} *
        </label>
        <input
          type="text"
          required
          value={formData.name}
          onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder={t('hc.material_catalog_form.name_placeholder')}
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('hc.material_catalog_form.unit_measure')}
        </label>
        <input
          type="text"
          value={formData.unit_measure}
          onChange={(e) => setFormData({ ...formData, unit_measure: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder={t('hc.material_catalog_form.unit_placeholder')}
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('hc.material_catalog_form.min_stock')}
        </label>
        <input
          type="number"
          min="0"
          step="1"
          value={formData.min_stock}
          onChange={(e) => setFormData({ ...formData, min_stock: parseInt(e.target.value) || 0 })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder="0"
        />
        <p className="text-xs text-gray-500 mt-1">
          {t('hc.material_catalog_form.min_stock_help')}
        </p>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('hc.material_catalog_form.description')}
        </label>
        <textarea
          value={formData.description}
          onChange={(e) => setFormData({ ...formData, description: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          rows={3}
          placeholder={t('hc.material_catalog_form.description_placeholder')}
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('hc.material_catalog_form.status')}
        </label>
        <select
          value={formData.status}
          onChange={(e) => setFormData({ ...formData, status: e.target.value as 'active' | 'inactive' })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
        >
          <option value="active">{t('common.active')}</option>
          <option value="inactive">{t('common.inactive')}</option>
        </select>
      </div>

      <div className="flex gap-2 justify-end pt-4">
        <Button type="button" variant="secondary" onClick={onCancel}>
          {t('hc.material_catalog_form.cancel')}
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? t('hc.material_catalog_form.saving') : material ? t('hc.material_catalog_form.update') : t('hc.material_catalog_form.create')}
        </Button>
      </div>
    </form>
  )
}
