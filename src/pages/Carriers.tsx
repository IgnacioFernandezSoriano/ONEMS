import { useCarriers } from '@/hooks/useCarriers'
import { CarriersTree } from '@/components/carriers/CarriersTree'
import { SmartTooltip } from '@/components/common/SmartTooltip'

export function Carriers() {
  const {
    carriers,
    products,
    productMaterials,
    loading,
    error,
    createCarrier,
    updateCarrier,
    deleteCarrier,
    createProduct,
    updateProduct,
    deleteProduct,
    addMaterialToProduct,
    updateProductMaterial,
    removeProductMaterial,
  } = useCarriers()

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading carriers...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-red-500">Error: {error}</div>
      </div>
    )
  }

  const totalCarriers = carriers.length
  const totalProducts = products.length
  const totalMaterials = productMaterials.length

  return (
    <div className="p-8">
      {/* Header with Tooltip and Create Button */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold text-gray-900">Carriers & Products</h1>
            <SmartTooltip content="About Carriers & Products - Purpose: Manage logistics carriers and their service products that will be used in allocation plans. Key Features: Define carrier details, configure products with delivery standards, set cost structures, and manage carrier-product relationships. Usage: Add carriers, create products for each carrier, specify delivery times and costs, and use these in allocation planning.">
              <svg className="w-5 h-5 text-gray-400 hover:text-gray-600 cursor-help" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </SmartTooltip>
          </div>
          
          {/* Create Carrier Button */}
          <button
            onClick={() => createCarrier({ name: '', code: '', type: '', status: 'active' })}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors shadow-sm"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
            </svg>
            Create Carrier
          </button>
        </div>
        <p className="text-gray-600">
          Manage shipping carriers and their products
        </p>
      </div>

      {/* Statistics Cards */}
      <div className="grid grid-cols-3 gap-6 mb-8">
        {/* Carriers */}
        <div className="bg-gradient-to-br from-red-50 to-white border border-red-100 rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-red-700">Carriers</span>
            <div className="w-10 h-10 bg-red-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h1m8-1a1 1 0 01-1 1H9m4-1V8a1 1 0 011-1h2.586a1 1 0 01.707.293l3.414 3.414a1 1 0 01.293.707V16a1 1 0 01-1 1h-1m-6-1a1 1 0 001 1h1M5 17a2 2 0 104 0m-4 0a2 2 0 114 0m6 0a2 2 0 104 0m-4 0a2 2 0 114 0" />
              </svg>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">{totalCarriers}</div>
          <div className="text-xs text-gray-500 mt-1">Shipping companies</div>
        </div>

        {/* Products */}
        <div className="bg-gradient-to-br from-blue-50 to-white border border-blue-100 rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-blue-700">Products</span>
            <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
              </svg>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">{totalProducts}</div>
          <div className="text-xs text-gray-500 mt-1">Delivery services</div>
        </div>

        {/* Materials */}
        <div className="bg-gradient-to-br from-green-50 to-white border border-green-100 rounded-xl p-6 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-sm font-medium text-green-700">Materials</span>
            <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
              <svg className="w-5 h-5 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
            </div>
          </div>
          <div className="text-3xl font-bold text-gray-900">{totalMaterials}</div>
          <div className="text-xs text-gray-500 mt-1">Material assignments</div>
        </div>
      </div>

      {carriers.length === 0 ? (
        <div className="bg-white rounded-lg border p-12 text-center">
          <div className="text-4xl mb-4">🚚</div>
          <h3 className="text-lg font-medium text-gray-900 mb-2">No carriers defined yet</h3>
          <p className="text-gray-600 mb-6">
            Start by creating your first carrier to manage shipping products
          </p>
        </div>
      ) : null}

      <CarriersTree
        carriers={carriers}
        products={products}
        productMaterials={productMaterials}
        onCreateCarrier={createCarrier}
        onCreateProduct={createProduct}
        onUpdateCarrier={updateCarrier}
        onUpdateProduct={updateProduct}
        onDeleteCarrier={deleteCarrier}
        onDeleteProduct={deleteProduct}
        onAddMaterialToProduct={addMaterialToProduct}
        onUpdateProductMaterial={updateProductMaterial}
        onRemoveProductMaterial={removeProductMaterial}
      />
    </div>
  )
}
