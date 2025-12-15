import { useState } from 'react'
import { useMaterialCatalog } from '@/hooks/useMaterialCatalog'
import { Button } from '@/components/common/Button'
import type { MaterialCatalog } from '@/lib/types'

interface MaterialSelectorProps {
  productId: string
  onSelect: (materialId: string, quantity: number) => Promise<void>
  onCreateNew: (data: any, quantity: number) => Promise<void>
  onCancel: () => void
}

export function MaterialSelector({ productId, onSelect, onCreateNew, onCancel }: MaterialSelectorProps) {
  const { catalog, loading, createCatalogItem } = useMaterialCatalog()
  const [mode, setMode] = useState<'select' | 'create' | null>(null)
  const [selectedMaterialId, setSelectedMaterialId] = useState('')
  const [quantity, setQuantity] = useState(1)
  const [newMaterial, setNewMaterial] = useState({
    code: '',
    name: '',
    unit_measure: '',
    description: '',
    status: 'active' as const,
  })
  const [submitting, setSubmitting] = useState(false)

  const handleSelectFromCatalog = async () => {
    if (!selectedMaterialId || quantity <= 0) {
      alert('Please select a material and enter a valid quantity')
      return
    }
    
    setSubmitting(true)
    try {
      await onSelect(selectedMaterialId, quantity)
    } finally {
      setSubmitting(false)
    }
  }

  const handleCreateNew = async () => {
    if (!newMaterial.code || !newMaterial.name || quantity <= 0) {
      alert('Please fill in code, name, and quantity')
      return
    }

    setSubmitting(true)
    try {
      // First create the material in catalog
      const catalogItem = await createCatalogItem(newMaterial)
      // Then add it to the product
      await onSelect(catalogItem.id, quantity)
    } finally {
      setSubmitting(false)
    }
  }

  if (!mode) {
    return (
      <div className="space-y-4">
        <p className="text-gray-600 mb-4">Choose how to add material to this product:</p>
        
        <button
          onClick={() => setMode('select')}
          className="w-full p-6 border-2 border-gray-300 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-colors text-left"
        >
          <div className="flex items-center gap-3">
            <span className="text-3xl">📚</span>
            <div>
              <div className="font-medium text-lg">Select from Catalog</div>
              <div className="text-sm text-gray-600">Choose an existing material from your catalog</div>
            </div>
          </div>
        </button>

        <button
          onClick={() => setMode('create')}
          className="w-full p-6 border-2 border-gray-300 rounded-lg hover:border-green-500 hover:bg-green-50 transition-colors text-left"
        >
          <div className="flex items-center gap-3">
            <span className="text-3xl">➕</span>
            <div>
              <div className="font-medium text-lg">Create New Material</div>
              <div className="text-sm text-gray-600">Add a new material to catalog and assign to product</div>
            </div>
          </div>
        </button>

        <div className="flex justify-end pt-4">
          <Button variant="secondary" onClick={onCancel}>
            Cancel
          </Button>
        </div>
      </div>
    )
  }

  if (mode === 'select') {
    const activeMaterials = catalog.filter(m => m.status === 'active')
    
    return (
      <div className="space-y-4">
        <button
          onClick={() => setMode(null)}
          className="text-sm text-blue-600 hover:text-blue-800 mb-2"
        >
          ← Back to options
        </button>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Select Material *
          </label>
          <select
            value={selectedMaterialId}
            onChange={(e) => setSelectedMaterialId(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
            required
          >
            <option value="">-- Choose a material --</option>
            {activeMaterials.map((material) => (
              <option key={material.id} value={material.id}>
                {material.code} - {material.name} {material.unit_measure ? `(${material.unit_measure})` : ''}
              </option>
            ))}
          </select>
          {activeMaterials.length === 0 && (
            <p className="text-sm text-amber-600 mt-1">
              No active materials in catalog. Create a new one instead.
            </p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Quantity *
          </label>
          <input
            type="number"
            min="0.01"
            step="0.01"
            value={quantity}
            onChange={(e) => setQuantity(parseFloat(e.target.value) || 0)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
            required
          />
        </div>

        <div className="flex gap-2 justify-end pt-4">
          <Button variant="secondary" onClick={onCancel}>
            Cancel
          </Button>
          <Button onClick={handleSelectFromCatalog} disabled={submitting || !selectedMaterialId}>
            {submitting ? 'Adding...' : 'Add to Product'}
          </Button>
        </div>
      </div>
    )
  }

  // mode === 'create'
  return (
    <div className="space-y-4">
      <button
        onClick={() => setMode(null)}
        className="text-sm text-blue-600 hover:text-blue-800 mb-2"
      >
        ← Back to options
      </button>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Code *
        </label>
        <input
          type="text"
          required
          value={newMaterial.code}
          onChange={(e) => setNewMaterial({ ...newMaterial, code: e.target.value })}
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
          value={newMaterial.name}
          onChange={(e) => setNewMaterial({ ...newMaterial, name: e.target.value })}
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
          value={newMaterial.unit_measure}
          onChange={(e) => setNewMaterial({ ...newMaterial, unit_measure: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder="units, kg, etc."
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Description
        </label>
        <textarea
          value={newMaterial.description}
          onChange={(e) => setNewMaterial({ ...newMaterial, description: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          rows={2}
          placeholder="Additional details..."
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Quantity *
        </label>
        <input
          type="number"
          min="0.01"
          step="0.01"
          value={quantity}
          onChange={(e) => setQuantity(parseFloat(e.target.value) || 0)}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          required
        />
      </div>

      <div className="flex gap-2 justify-end pt-4">
        <Button variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
        <Button onClick={handleCreateNew} disabled={submitting}>
          {submitting ? 'Creating...' : 'Create & Add to Product'}
        </Button>
      </div>
    </div>
  )
}
