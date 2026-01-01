import { useState } from 'react'
import { Button } from '@/components/common/Button'
import { Modal } from '@/components/common/Modal'
import { MaterialCatalogForm } from '@/components/material-catalog/MaterialCatalogForm'
import { useMaterialCatalog } from '@/hooks/useMaterialCatalog'
import type { MaterialCatalog } from '@/lib/types'

import { useTranslation } from '@/hooks/useTranslation';
export function MaterialCatalogPage() {
  const { t } = useTranslation();
  const {
    catalog,
    loading,
    createCatalogItem,
    updateCatalogItem,
    deleteCatalogItem,
  } = useMaterialCatalog()

  const [modal, setModal] = useState<{
    title: string
    material?: MaterialCatalog
    onSubmit: (data: any) => Promise<void>
  } | null>(null)

  const handleCreate = async (data: any) => {
    await createCatalogItem(data)
    setModal(null)
  }

  const handleUpdate = async (id: string, data: any) => {
    await updateCatalogItem(id, data)
    setModal(null)
  }

  const handleDelete = async (id: string, name: string) => {
    if (confirm(`Delete material "${name}"? This will remove it from all products.`)) {
      await deleteCatalogItem(id)
    }
  }

  if (loading) {
    return <div className="p-8">Loading...</div>
  }

  return (
    <div className="p-8">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Material Catalog</h1>
        <p className="text-gray-600 mt-1">Manage reusable materials for all products</p>
      </div>

      <div className="mb-6">
        <Button onClick={() => setModal({ title: 'Create Material', onSubmit: handleCreate })}>
          + {t('material.add_material')}
        </Button>
      </div>

      <div className="bg-white rounded-lg shadow overflow-hidden">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('panelists.code')}</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('users.name')}</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('stock.unit')}</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Min Stock</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('topology.description')}</th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">{t('common.status')}</th>
              <th className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">{t('common.actions')}</th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {catalog.map((material) => (
              <tr key={material.id}>
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                  {material.code}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {material.name}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {material.unit_measure || '-'}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900 font-medium">
                  {material.min_stock || 0}
                </td>
                <td className="px-6 py-4 text-sm text-gray-500">
                  {material.description || '-'}
                </td>
                <td className="px-6 py-4 whitespace-nowrap">
                  <span
                    className={`px-2 py-1 text-xs rounded ${
                      material.status === 'active'
                        ? 'bg-green-100 text-green-800'
                        : 'bg-gray-100 text-gray-800'
                    }`}
                  >
                    {material.status}
                  </span>
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                  <button
                    onClick={() =>
                      setModal({
                        title: 'Edit Material',
                        material,
                        onSubmit: (data) => handleUpdate(material.id, data),
                      })
                    }
                    className="text-blue-600 hover:text-blue-900 mr-4"
                  >
                    Edit
                  </button>
                  <button
                    onClick={() => handleDelete(material.id, material.name)}
                    className="text-red-600 hover:text-red-900"
                  >
                    Delete
                  </button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>

        {catalog.length === 0 && (
          <div className="text-center py-12 text-gray-500">
            No materials in catalog. Create your first material to get started.
          </div>
        )}
      </div>

      {modal && (
        <Modal isOpen={true} title={modal.title} onClose={() => setModal(null)}>
          <MaterialCatalogForm
            material={modal.material}
            onSubmit={modal.onSubmit}
            onCancel={() => setModal(null)}
          />
        </Modal>
      )}
    </div>
  )
}
