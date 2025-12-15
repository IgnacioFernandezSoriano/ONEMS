import { useState } from 'react'
import { Button } from '@/components/common/Button'
import type { City } from '@/lib/types'

interface CityFormProps {
  city?: City
  regionId: string
  onSubmit: (data: any) => Promise<void>
  onCancel: () => void
}

export function CityForm({ city, regionId, onSubmit, onCancel }: CityFormProps) {
  const [formData, setFormData] = useState({
    region_id: regionId,
    name: city?.name || '',
    code: city?.code || '',
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
        <label className="block text-sm font-medium mb-1">City Name *</label>
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
        <label className="block text-sm font-medium mb-1">City Code *</label>
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
        <label className="block text-sm font-medium mb-1">
          Population
          <span className="text-xs text-gray-500 ml-2">(optional)</span>
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
          Total population of the city (used for impact analysis in reporting)
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
          <option value="active">Active</option>
          <option value="inactive">Inactive</option>
        </select>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="block text-sm font-medium mb-1">Latitude</label>
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
          <label className="block text-sm font-medium mb-1">Longitude</label>
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
          Cancel
        </Button>
        <Button type="submit" disabled={loading}>
          {loading ? 'Saving...' : city ? 'Update' : 'Create'}
        </Button>
      </div>
    </form>
  )
}
