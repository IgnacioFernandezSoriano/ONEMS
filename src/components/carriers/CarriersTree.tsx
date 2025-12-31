import { useState, useEffect } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { Modal } from '@/components/common/Modal'
import { CarrierForm } from './CarrierForm'
import { ProductForm } from './ProductForm'
import { MaterialSelector } from './MaterialSelector'
import type { Carrier, Product, ProductMaterial } from '@/lib/types'

interface CarriersTreeProps {
  carriers: Carrier[]
  products: (Product & { hasMaterials?: boolean; materialsCount?: number })[]
  productMaterials: ProductMaterial[]
  expandAll: boolean
  onCreateCarrier: (data: any) => Promise<void>
  onCreateProduct: (data: any) => Promise<void>
  onUpdateCarrier: (id: string, data: any) => Promise<void>
  onUpdateProduct: (id: string, data: any) => Promise<void>
  onDeleteCarrier: (id: string) => Promise<void>
  onDeleteProduct: (id: string) => Promise<void>
  onAddMaterialToProduct: (data: { product_id: string; material_id: string; quantity: number }) => Promise<void>
  onUpdateProductMaterial: (id: string, data: { quantity: number }) => Promise<void>
  onRemoveProductMaterial: (id: string) => Promise<void>
}

export function CarriersTree({
  carriers,
  products,
  productMaterials,
  expandAll,
  onCreateCarrier,
  onCreateProduct,
  onUpdateCarrier,
  onUpdateProduct,
  onDeleteCarrier,
  onDeleteProduct,
  onAddMaterialToProduct,
  onUpdateProductMaterial,
  onRemoveProductMaterial,
}: CarriersTreeProps) {
  const { t } = useTranslation()
  const [expandedCarriers, setExpandedCarriers] = useState<Set<string>>(new Set())
  const [expandedProducts, setExpandedProducts] = useState<Set<string>>(new Set())
  const [modal, setModal] = useState<any>(null)

  // Handle expandAll prop changes
  useEffect(() => {
    if (expandAll) {
      setExpandedCarriers(new Set(carriers.map(c => c.id)))
      setExpandedProducts(new Set(products.map(p => p.id)))
    } else {
      setExpandedCarriers(new Set())
      setExpandedProducts(new Set())
    }
  }, [expandAll, carriers, products])

  const toggleCarrier = (id: string) => {
    const newExpanded = new Set(expandedCarriers)
    if (newExpanded.has(id)) {
      newExpanded.delete(id)
      // Also collapse all products in this carrier
      const carrierProducts = getProductsForCarrier(id)
      const newExpandedProducts = new Set(expandedProducts)
      carrierProducts.forEach(product => newExpandedProducts.delete(product.id))
      setExpandedProducts(newExpandedProducts)
    } else {
      newExpanded.add(id)
    }
    setExpandedCarriers(newExpanded)
  }

  const toggleProduct = (id: string) => {
    const newExpanded = new Set(expandedProducts)
    if (newExpanded.has(id)) {
      newExpanded.delete(id)
    } else {
      newExpanded.add(id)
    }
    setExpandedProducts(newExpanded)
  }

  const expandCarrierAndProducts = (carrierId: string) => {
    const newExpandedCarriers = new Set(expandedCarriers)
    newExpandedCarriers.add(carrierId)
    setExpandedCarriers(newExpandedCarriers)

    const carrierProducts = getProductsForCarrier(carrierId)
    const newExpandedProducts = new Set(expandedProducts)
    carrierProducts.forEach(product => newExpandedProducts.add(product.id))
    setExpandedProducts(newExpandedProducts)
  }

  const getProductsForCarrier = (carrierId: string) => {
    return products.filter((p) => p.carrier_id === carrierId)
  }

  const getMaterialsForProduct = (productId: string) => {
    return productMaterials.filter((pm) => pm.product_id === productId)
  }

  const handleSubmit = async (data: any) => {
    try {
      await modal.onSubmit(data)
      setModal(null)
    } catch (error) {
      console.error('Error submitting:', error)
    }
  }

  const handleDelete = async (type: 'carrier' | 'product', id: string, name: string) => {
    if (!confirm(`Are you sure you want to delete ${name}?`)) return
    
    try {
      if (type === 'carrier') await onDeleteCarrier(id)
      else if (type === 'product') await onDeleteProduct(id)
    } catch (error) {
      console.error('Error deleting:', error)
    }
  }

  const handleRemoveMaterial = async (pmId: string, materialName: string) => {
    if (!confirm(`Remove material "${materialName}" from this product?`)) return
    
    try {
      await onRemoveProductMaterial(pmId)
    } catch (error) {
      console.error('Error removing material:', error)
    }
  }

  const handleUpdateQuantity = async (pmId: string, currentQty: number, materialName: string) => {
    const newQty = prompt(`Enter new quantity for "${materialName}":`, currentQty.toString())
    if (!newQty) return
    
    const quantity = parseFloat(newQty)
    if (isNaN(quantity) || quantity <= 0) {
      alert('Please enter a valid positive number')
      return
    }
    
    try {
      await onUpdateProductMaterial(pmId, { quantity })
    } catch (error) {
      console.error('Error updating quantity:', error)
    }
  }

  return (
    <>
      <div className="space-y-2">
        {carriers.map((carrier) => {
          const carrierProducts = getProductsForCarrier(carrier.id)
          const isExpanded = expandedCarriers.has(carrier.id)

          return (
            <div key={carrier.id} className="border rounded-lg bg-white shadow-sm">
              <div className="flex items-center gap-3 p-4 hover:bg-gray-50 transition-colors">
                {/* Expand/Collapse Button */}
                <button
                  onClick={() => toggleCarrier(carrier.id)}
                  className="text-gray-400 hover:text-gray-600 transition-colors"
                  title={isExpanded ? 'Collapse carrier' : 'Expand carrier'}
                >
                  <svg className="w-5 h-5" fill="currentColor" viewBox="0 0 20 20">
                    {isExpanded ? (
                      <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
                    ) : (
                      <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />
                    )}
                  </svg>
                </button>

                {/* Carrier Icon */}
                <div className="w-10 h-10 bg-red-100 rounded-lg flex items-center justify-center">
                  <svg className="w-5 h-5 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h1m8-1a1 1 0 01-1 1H9m4-1V8a1 1 0 011-1h2.586a1 1 0 01.707.293l3.414 3.414a1 1 0 01.293.707V16a1 1 0 01-1 1h-1m-6-1a1 1 0 001 1h1M5 17a2 2 0 104 0m-4 0a2 2 0 114 0m6 0a2 2 0 104 0m-4 0a2 2 0 114 0" />
                  </svg>
                </div>

                {/* Carrier Name + Code + Type + Status */}
                <div className="flex-1 flex items-center gap-3">
                  <span className="font-semibold text-gray-900">{carrier.name}</span>
                  <span className="text-sm text-gray-500">({carrier.code})</span>
                  {carrier.type && (
                    <span className="text-xs font-medium bg-gray-100 text-gray-700 px-2 py-0.5 rounded-full">
                      {carrier.type}
                    </span>
                  )}
                  <span
                    className={`text-xs font-medium px-2.5 py-0.5 rounded-full ${
                      carrier.status === 'active'
                        ? 'bg-green-100 text-green-700'
                        : 'bg-gray-100 text-gray-600'
                    }`}
                  >
                    {carrier.status === 'active' ? 'Active' : 'Inactive'}
                  </span>
                </div>

                {/* Action Buttons */}
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => expandCarrierAndProducts(carrier.id)}
                    className="px-3 py-1.5 text-sm text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
                    title="Expand all products in this carrier"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M4 8V4m0 0h4M4 4l5 5m11-1V4m0 0h-4m4 0l-5 5M4 16v4m0 0h4m-4 0l5-5m11 5l-5-5m5 5v-4m0 4h-4" />
                    </svg>
                  </button>
                  <button
                    onClick={() =>
                      setModal({
                        title: 'Add Product',
                        type: 'product',
                        carrierId: carrier.id,
                        onSubmit: onCreateProduct,
                      })
                    }
                    className="flex items-center gap-2 px-3 py-1.5 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
                  >
                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                    </svg>
                    Product
                  </button>
                  <button
                    onClick={() =>
                      setModal({
                        title: 'Edit Carrier',
                        type: 'carrier',
                        data: carrier,
                        onSubmit: (data: any) => onUpdateCarrier(carrier.id, data),
                      })
                    }
                    className="p-1.5 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
                    title="Edit carrier"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                    </svg>
                  </button>
                  <button
                    onClick={() => handleDelete('carrier', carrier.id, carrier.name)}
                    className="p-1.5 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                    title="Delete carrier"
                  >
                    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                    </svg>
                  </button>
                </div>
              </div>

              {isExpanded && (
                <div className="pl-8 pb-2 space-y-1">
                  {carrierProducts.length === 0 && (
                    <div className="text-sm text-gray-500 italic p-4">
                      No products for this carrier yet
                    </div>
                  )}
                  {carrierProducts.map((product) => {
                    const productMats = getMaterialsForProduct(product.id)
                    const isProductExpanded = expandedProducts.has(product.id)

                    return (
                      <div key={product.id} className="border-l-2 border-blue-200 ml-4">
                        <div className="flex items-center gap-3 p-3 hover:bg-gray-50 transition-colors">
                          {/* Expand/Collapse Button */}
                          <button
                            onClick={() => toggleProduct(product.id)}
                            className="text-gray-400 hover:text-gray-600 transition-colors ml-2"
                            title={isProductExpanded ? 'Collapse product' : 'Expand product'}
                          >
                            <svg className="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                              {isProductExpanded ? (
                                <path fillRule="evenodd" d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z" clipRule="evenodd" />
                              ) : (
                                <path fillRule="evenodd" d="M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z" clipRule="evenodd" />
                              )}
                            </svg>
                          </button>

                          {/* Product Icon */}
                          <div className="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
                            <svg className="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
                            </svg>
                          </div>

                          {/* Product Code + Description */}
                          <div className="flex-1 flex items-center gap-2">
                            <span className="font-medium text-gray-900">{product.code}</span>
                            {product.description && (
                              <span className="text-sm text-gray-500">- {product.description}</span>
                            )}
                            
                            {/* Material Status Badge */}
                            {product.hasMaterials ? (
                              <span className="inline-flex items-center gap-1 text-xs font-medium bg-green-100 text-green-700 px-2 py-0.5 rounded-full">
                                <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
                                </svg>
                                Materials Assigned ({product.materialsCount})
                              </span>
                            ) : (
                              <span className="inline-flex items-center gap-1 text-xs font-medium bg-amber-100 text-amber-700 px-2 py-0.5 rounded-full">
                                <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
                                </svg>
                                Pending Materials
                              </span>
                            )}

                            {product.standard_delivery_hours && (
                              <span className="text-xs font-medium bg-purple-100 text-purple-700 px-2 py-0.5 rounded-full">
                                {product.standard_delivery_hours}h
                              </span>
                            )}

                            <span
                              className={`text-xs font-medium px-2 py-0.5 rounded-full ${
                                product.status === 'active'
                                  ? 'bg-green-100 text-green-700'
                                  : 'bg-gray-100 text-gray-600'
                              }`}
                            >
                              {product.status === 'active' ? 'Active' : 'Inactive'}
                            </span>
                          </div>

                          {/* Action Buttons */}
                          <div className="flex items-center gap-2">
                            <button
                              onClick={() =>
                                setModal({
                                  title: 'Add Material',
                                  type: 'material',
                                  productId: product.id,
                                  onSubmit: onAddMaterialToProduct,
                                })
                              }
                              className="flex items-center gap-1.5 px-2.5 py-1 text-xs font-medium bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
                            >
                              <svg className="w-3.5 h-3.5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                              </svg>
                              Material
                            </button>
                            <button
                              onClick={() =>
                                setModal({
                                  title: 'Edit Product',
                                  type: 'product',
                                  carrierId: product.carrier_id,
                                  data: product,
                                  onSubmit: (data: any) => onUpdateProduct(product.id, data),
                                })
                              }
                              className="p-1 text-gray-600 hover:bg-gray-100 rounded-lg transition-colors"
                              title="Edit product"
                            >
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                              </svg>
                            </button>
                            <button
                              onClick={() => handleDelete('product', product.id, product.code || 'product')}
                              className="p-1 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                              title="Delete product"
                            >
                              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                              </svg>
                            </button>
                          </div>
                        </div>

                        {isProductExpanded && (
                          <div className="pl-6 pb-2 space-y-1">
                            {productMats.length === 0 && (
                              <div className="text-sm text-gray-500 italic p-3 ml-4">
                                No materials assigned yet
                              </div>
                            )}
                            {productMats.map((pm) => (
                              <div
                                key={pm.id}
                                className="flex items-center gap-3 p-2 ml-4 hover:bg-gray-50 transition-colors rounded-lg"
                              >
                                {/* Material Icon */}
                                <div className="w-7 h-7 bg-green-100 rounded-lg flex items-center justify-center ml-4">
                                  <svg className="w-3.5 h-3.5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                                  </svg>
                                </div>

                                {/* Material Info */}
                                <div className="flex-1 flex items-center gap-2">
                                  <span className="text-sm font-medium text-gray-900">
                                    {pm.material_catalog?.name || 'Unknown Material'}
                                  </span>
                                  <span className="text-xs text-gray-500">
                                    ({pm.material_catalog?.code})
                                  </span>
                                  <span className="text-xs font-medium bg-blue-100 text-blue-700 px-2 py-0.5 rounded-full">
                                    Qty: {pm.quantity}
                                  </span>
                                </div>

                                {/* Action Buttons */}
                                <div className="flex items-center gap-1">
                                  <button
                                    onClick={() => handleUpdateQuantity(pm.id, pm.quantity, pm.material_catalog?.name || 'material')}
                                    className="p-1 text-blue-600 hover:bg-blue-50 rounded-lg transition-colors"
                                    title="Update quantity"
                                  >
                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
                                    </svg>
                                  </button>
                                  <button
                                    onClick={() => handleRemoveMaterial(pm.id, pm.material_catalog?.name || 'material')}
                                    className="p-1 text-red-600 hover:bg-red-50 rounded-lg transition-colors"
                                    title="Remove material"
                                  >
                                    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                      <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
                                    </svg>
                                  </button>
                                </div>
                              </div>
                            ))}
                          </div>
                        )}
                      </div>
                    )
                  })}
                </div>
              )}
            </div>
          )
        })}
      </div>

      {modal && (
        <Modal
          isOpen={true}
          onClose={() => setModal(null)}
          title={modal.title}
        >
          {modal.type === 'carrier' && (
            <CarrierForm
              carrier={modal.data}
              onSubmit={handleSubmit}
              onCancel={() => setModal(null)}
            />
          )}
          {modal.type === 'product' && (
            <ProductForm
              product={modal.data}
              carrierId={modal.carrierId}
              onSubmit={handleSubmit}
              onCancel={() => setModal(null)}
            />
          )}
          {modal.type === 'material' && (
            <MaterialSelector
              productId={modal.productId}
              onSelect={async (materialId: string, quantity: number) => {
                await onAddMaterialToProduct({
                  product_id: modal.productId,
                  material_id: materialId,
                  quantity
                })
                setModal(null)
              }}
              onCreateNew={async (data: any, quantity: number) => {
                // This is handled internally by MaterialSelector
                setModal(null)
              }}
              onCancel={() => setModal(null)}
            />
          )}
        </Modal>
      )}
    </>
  )
}
