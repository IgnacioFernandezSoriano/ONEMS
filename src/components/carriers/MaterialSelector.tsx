import { useState } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
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
  const { t } = useTranslation()
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
      alert(t('hc.material_selector.select_material_qty_alert'))
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
      alert(t('hc.material_selector.fill_code_name_qty_alert'))
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
        <p className="text-gray-600 mb-4">{t('hc.material_selector.choose_how_to_add')}</p>
        
        <button
          onClick={() => setMode('select')}
          className="w-full p-6 border-2 border-gray-300 rounded-lg hover:border-blue-500 hover:bg-blue-50 transition-colors text-left"
        >
          <div className="flex items-center gap-3">
            <span className="text-3xl">📚</span>
            <div>
              <div className="font-medium text-lg">{t('hc.material_selector.select_from_catalog')}</div>
              <div className="text-sm text-gray-600">{t('hc.material_selector.choose_existing')}</div>
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
              <div className="font-medium text-lg">{t('hc.material_selector.create_new_material')}</div>
              <div className="text-sm text-gray-600">{t('hc.material_selector.add_new_to_catalog')}</div>
            </div>
          </div>
        </button>

        <div className="flex justify-end pt-4">
          <Button variant="secondary" onClick={onCancel}>
            {t('hc.material_selector.cancel')}
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
          {t('hc.material_selector.back_to_options')}
        </button>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('hc.material_selector.select_material_label')}
          </label>
          <select
            value={selectedMaterialId}
            onChange={(e) => setSelectedMaterialId(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md"
            required
          >
            <option value="">{t('hc.material_selector.choose_a_material')}</option>
            {activeMaterials.map((material) => (
              <option key={material.id} value={material.id}>
                {material.code} - {material.name} {material.unit_measure ? `(${material.unit_measure})` : ''}
              </option>
            ))}
          </select>
          {activeMaterials.length === 0 && (
            <p className="text-sm text-amber-600 mt-1">
              {t('hc.material_selector.no_active_materials')}
            </p>
          )}
        </div>

        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            {t('hc.material_selector.quantity_label')}
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
            {t('hc.material_selector.cancel')}
          </Button>
          <Button onClick={handleSelectFromCatalog} disabled={submitting || !selectedMaterialId}>
            {submitting ? t('hc.material_selector.adding') : t('hc.material_selector.add_to_product')}
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
        {t('hc.material_selector.back_to_options')}
      </button>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('hc.material_selector.code_label')}
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
          {t('hc.material_selector.name_label')}
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
          {t('hc.material_selector.unit_measure')}
        </label>
        <input
          type="text"
          value={newMaterial.unit_measure}
          onChange={(e) => setNewMaterial({ ...newMaterial, unit_measure: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          placeholder={t('hc.material_selector.unit_placeholder')}
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('hc.material_selector.description')}
        </label>
        <textarea
          value={newMaterial.description}
          onChange={(e) => setNewMaterial({ ...newMaterial, description: e.target.value })}
          className="w-full px-3 py-2 border border-gray-300 rounded-md"
          rows={2}
          placeholder={t('hc.material_selector.details_placeholder')}
        />
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          {t('hc.material_selector.quantity_label')}
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
          {t('hc.material_selector.cancel')}
        </Button>
        <Button onClick={handleCreateNew} disabled={submitting}>
          {submitting ? t('hc.material_selector.creating') : t('hc.material_selector.create_and_add')}
        </Button>
      </div>
    </div>
  )
}
