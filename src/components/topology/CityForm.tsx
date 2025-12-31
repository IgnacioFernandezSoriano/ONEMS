import { useState } from 'react'
import { Button } from '@/components/common/Button'
import type { City } from '@/lib/types'

import { useTranslation } from '@/hooks/useTranslation';
interface CityFormProps {
  city?: City
  regionId: string
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function CityForm({ city, regionId, onSubmit, onCancel }: CityFormProps) {
  const { t } = useTranslation();
  const [formData, setFormData] = useState({
    region_id: regionId,
    name: city?.name || '',
    code: city?.code || '',
    classification: city?.classification || '',
    population: city?.population?.toString() || '',
    latitude: city?.latitude?.toString() || '',
    longitude: city?.longitude?.toString() || '',
    status: city?.status || 'active',
  })
  const [loading, setLoading] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    try {
      const data: any = {
        region_id: formData.region_id,
        name: formData.name,
        code: formData.code,
        status: formData.status,
      }
      if (formData.classification) data.classification = formData.classification
      if (formData.population) data.population = parseInt(formData.population)
      if (formData.latitude) data.latitude = parseFloat(formData.latitude)
      if (formData.longitude) data.longitude = parseFloat(formData.longitude)
      
      await onSubmit(data)
    } finally {
      setLoading(false)
    }
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-4">
      <div>
        <label className="block text-sm font-medium mb-1">{t('cityform.city_name')} *</label>
        <input
          type="text"
          required
          value={formData.name}
          onChange={(e) => setFormData({ ...formData, name: e.target.value })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="e.g., Madrid, Barcelona"
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">{t('cityform.city_code')} *</label>
        <input
          type="text"
          required
          value={formData.code}
          onChange={(e) => setFormData({ ...formData, code: e.target.value.toUpperCase() })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="e.g., MAD, BCN"
          maxLength={10}
        />
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">{t('cityform.city_class')}</label>
        <select
          value={formData.classification}
          onChange={(e) => setFormData({ ...formData, classification: e.target.value as any })}
          className="w-full px-3 py-2 border rounded-md"
        >
          <option value="">-- {t('cityform.optional')} --</option>
          <option value="A">{t('cityform.class_a')}</option>
          <option value="B">{t('cityform.class_b')}</option>
          <option value="C">{t('cityform.class_c')}</option>
        </select>
      </div>

      <div>
        <label className="block text-sm font-medium mb-1">
          {t('cityform.population')}
          <span className="text-xs text-gray-500 ml-2">({t('cityform.optional')})</span>
        </label>
        <input
          type="number"
          min="1"
          step="1"
          value={formData.population}
          onChange={(e) => setFormData({ ...formData, population: e.target.value })}
          className="w-full px-3 py-2 border rounded-md"
          placeholder="e.g., 3200000"
        />
        <p className="text-xs text-gray-500 mt-1">
          {t('cityform.population_description')}
        </p>
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

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">{t('topology.latitude')}</label>
          <input
            type="number"
            step="any"
            value={formData.latitude}
            onChange={(e) => setFormData({ ...formData, latitude: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
            placeholder="40.4168"
          />
        </div>
        <div>
          <label className="block text-sm font-medium mb-1">{t('topology.longitude')}</label>
          <input
            type="number"
            step="any"
            value={formData.longitude}
            onChange={(e) => setFormData({ ...formData, longitude: e.target.value })}
            className="w-full px-3 py-2 border rounded-md"
            placeholder="-3.7038"
          />
        </div>
      </div>

      <div className="flex gap-2 justify-end">
        <Button type="button" variant="secondary" onClick={onCancel}>
          {t('cityform.cancel')}
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? t('cityform.saving') : city ? t('cityform.update') : t('cityform.create')}
        </Button>
      </div>
    </form>
  )
}
