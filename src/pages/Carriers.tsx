import { useState, useMemo } from 'react'
import { useCarriers } from '@/hooks/useCarriers'
import { CarriersTree } from '@/components/carriers/CarriersTree'
import { SmartTooltip } from '@/components/common/SmartTooltip'
import { Modal } from '@/components/common/Modal'
import { CarrierForm } from '@/components/carriers/CarrierForm'

import { useTranslation } from '@/hooks/useTranslation';
export function Carriers() {
  const { t } = useTranslation();
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

  // State for filters and UI
  const [activeTab, setActiveTab] = useState<'carriers' | 'without-materials'>('carriers')
  const [searchTerm, setSearchTerm] = useState('')
  const [filterCarrier, setFilterCarrier] = useState<string>('all')
  const [filterStatus, setFilterStatus] = useState<string>('all')
  const [filterMaterialStatus, setFilterMaterialStatus] = useState<string>('all')
  const [expandAll, setExpandAll] = useState(false)
  const [showCarrierModal, setShowCarrierModal] = useState(false)

  // Calculate products with/without materials
  const productsWithMaterials = useMemo(() => {
    return products.map(product => {
      const materials = productMaterials.filter(pm => pm.product_id === product.id)
      return {
        ...product,
        hasMaterials: materials.length > 0,
        materialsCount: materials.length,
        materials
      }
    })
  }, [products, productMaterials])

  const productsWithoutMaterials = useMemo(() => {
    return productsWithMaterials.filter(p => !p.hasMaterials)
  }, [productsWithMaterials])

  // Filtered data
  const filteredData = useMemo(() => {
    let filteredCarriers = carriers
    let filteredProducts = productsWithMaterials

    // Search filter
    if (searchTerm) {
      const term = searchTerm.toLowerCase()
      const matchingCarriers = carriers.filter(c => 
        c.name.toLowerCase().includes(term) || 
        c.code?.toLowerCase().includes(term) ||
        c.type?.toLowerCase().includes(term)
      )
      const matchingProducts = filteredProducts.filter(p => 
        p.code?.toLowerCase().includes(term) ||
        p.description?.toLowerCase().includes(term)
      )

      const matchingCarrierIds = new Set([
        ...matchingCarriers.map(c => c.id),
        ...matchingProducts.map(p => p.carrier_id)
      ])

      filteredCarriers = carriers.filter(c => matchingCarrierIds.has(c.id))
      filteredProducts = filteredProducts.filter(p => matchingCarrierIds.has(p.carrier_id))
    }

    // Carrier filter
    if (filterCarrier !== 'all') {
      filteredCarriers = filteredCarriers.filter(c => c.id === filterCarrier)
      filteredProducts = filteredProducts.filter(p => p.carrier_id === filterCarrier)
    }

    // Status filter (for carriers)
    if (filterStatus !== 'all') {
      filteredCarriers = filteredCarriers.filter(c => c.status === filterStatus)
      filteredProducts = filteredProducts.filter(p => {
        const carrier = carriers.find(c => c.id === p.carrier_id)
        return carrier?.status === filterStatus
      })
    }

    // Material status filter (for products)
    if (filterMaterialStatus === 'with') {
      filteredProducts = filteredProducts.filter(p => p.hasMaterials)
    } else if (filterMaterialStatus === 'without') {
      filteredProducts = filteredProducts.filter(p => !p.hasMaterials)
    }

    // Filter carriers to only show those with products
    const carrierIdsWithProducts = new Set(filteredProducts.map(p => p.carrier_id))
    filteredCarriers = filteredCarriers.filter(c => carrierIdsWithProducts.has(c.id))

    return {
      carriers: filteredCarriers,
      products: filteredProducts
    }
  }, [carriers, productsWithMaterials, searchTerm, filterCarrier, filterStatus, filterMaterialStatus])

  // Export CSV for products without materials
  const exportProductsWithoutMaterialsCSV = () => {
    const csvData = productsWithoutMaterials.map(product => {
      const carrier = carriers.find(c => c.id === product.carrier_id)
      return {
        'Product Code': product.code || '',
        'Description': product.description || '',
        'Carrier': carrier?.name || '',
        'Delivery Hours': product.standard_delivery_hours || '',
        'Status': product.status || 'active'
      }
    })

    const headers = Object.keys(csvData[0] || {})
    const csvContent = [
      headers.join(','),
      ...csvData.map(row => headers.map(h => `"${row[h as keyof typeof row]}"`).join(','))
    ].join('\\n')

    const blob = new Blob([csvContent], { type: 'text/csv' })
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')
    link.href = url
    link.download = `products-without-materials-${new Date().toISOString().split('T')[0]}.csv`
    link.click()
    URL.revokeObjectURL(url)
  }

  if (loading) {
    return (
      <div className="p-8">
        <div className="text-center text-gray-600">Loading carriers...</div>
      </div>
    )
  }

  if (error) {
    return (
      <div className="p-8">
        <div className="bg-red-50 border border-red-200 text-red-700 px-4 py-3 rounded">
          Error: {error}
        </div>
      </div>
    )
  }

  const stats = {
    totalCarriers: carriers.length,
    activeCarriers: carriers.filter(c => c.status === 'active').length,
    inactiveCarriers: carriers.filter(c => c.status === 'inactive').length,
    totalProducts: products.length,
    productsWithMaterials: productsWithMaterials.filter(p => p.hasMaterials).length,
    productsWithoutMaterials: productsWithoutMaterials.length,
    totalMaterials: productMaterials.length,
  }

  return (
    <div className="p-8">
      {/* Header with Tooltip and Create Button */}
      <div className="mb-6">
        <div className="flex items-center justify-between mb-2">
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold text-gray-900">Carriers & Products</h1>
            <SmartTooltip content="About Carriers & Products - Purpose: Manage logistics carriers and their service products that will be used in allocation plans. Structure: Carriers (shipping companies) contain Products (delivery services), which require Materials (packaging, labels, etc.) from the material catalog. Key Features: Define carrier details, configure products with delivery standards, set cost structures, and manage material requirements. Usage: Add carriers, create products for each carrier, assign materials to products, specify delivery times and costs, and use these in allocation planning.">
              <svg className="w-5 h-5 text-gray-400 hover:text-gray-600 cursor-help" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </SmartTooltip>
          </div>
          
          {/* Create Carrier Button */}
          <button
            onClick={() => setShowCarrierModal(true)}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors shadow-sm"
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
            </svg>
            Create Carrier
          </button>
        </div>
        <p className="text-gray-600">
          Manage shipping carriers, products, and material requirements
        </p>
      </div>

      {/* Statistics Cards */}
      <div className="grid grid-cols-7 gap-4 mb-6">
        {/* Total Carriers */}
        <div className="bg-gradient-to-br from-red-50 to-white border border-red-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-red-700">{t('receivegenerator.carriers')}</span>
            <div className="w-8 h-8 bg-red-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 16V6a1 1 0 00-1-1H4a1 1 0 00-1 1v10a1 1 0 001 1h1m8-1a1 1 0 01-1 1H9m4-1V8a1 1 0 011-1h2.586a1 1 0 01.707.293l3.414 3.414a1 1 0 01.293.707V16a1 1 0 01-1 1h-1m-6-1a1 1 0 001 1h1M5 17a2 2 0 104 0m-4 0a2 2 0 114 0m6 0a2 2 0 104 0m-4 0a2 2 0 114 0" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.totalCarriers}</div>
        </div>

        {/* Active Carriers */}
        <div className="bg-gradient-to-br from-emerald-50 to-white border border-emerald-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-emerald-700">{t('common.active')}</span>
            <div className="w-8 h-8 bg-emerald-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-emerald-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.activeCarriers}</div>
        </div>

        {/* Inactive Carriers */}
        <div className="bg-gradient-to-br from-gray-50 to-white border border-gray-200 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-gray-700">{t('common.inactive')}</span>
            <div className="w-8 h-8 bg-gray-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-gray-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M18.364 18.364A9 9 0 005.636 5.636m12.728 12.728A9 9 0 015.636 5.636m12.728 12.728L5.636 5.636" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.inactiveCarriers}</div>
        </div>

        {/* Total Products */}
        <div className="bg-gradient-to-br from-blue-50 to-white border border-blue-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-blue-700">{t('receivegenerator.products')}</span>
            <div className="w-8 h-8 bg-blue-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-blue-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 7l-8-4-8 4m16 0l-8 4m8-4v10l-8 4m0-10L4 7m8 4v10M4 7v10l8 4" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.totalProducts}</div>
        </div>

        {/* Products with Materials */}
        <div className="bg-gradient-to-br from-green-50 to-white border border-green-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-green-700">With Materials</span>
            <div className="w-8 h-8 bg-green-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.productsWithMaterials}</div>
        </div>

        {/* Products without Materials */}
        <div className="bg-gradient-to-br from-amber-50 to-white border border-amber-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-amber-700">Without Materials</span>
            <div className="w-8 h-8 bg-amber-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-amber-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.productsWithoutMaterials}</div>
        </div>

        {/* Total Materials */}
        <div className="bg-gradient-to-br from-purple-50 to-white border border-purple-100 rounded-xl p-4 shadow-sm hover:shadow-md transition-shadow">
          <div className="flex items-center justify-between mb-2">
            <span className="text-xs font-medium text-purple-700">{t('stock.materials')}</span>
            <div className="w-8 h-8 bg-purple-100 rounded-lg flex items-center justify-center">
              <svg className="w-4 h-4 text-purple-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
            </div>
          </div>
          <div className="text-2xl font-bold text-gray-900">{stats.totalMaterials}</div>
        </div>
      </div>

      {/* Tabs */}
      <div className="mb-6">
        <div className="border-b border-gray-200">
          <nav className="-mb-px flex space-x-8">
            <button
              onClick={() => setActiveTab('carriers')}
              className={`py-4 px-1 border-b-2 font-medium text-sm transition-colors ${
                activeTab === 'carriers'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              Carriers & Products
            </button>
            <button
              onClick={() => setActiveTab('without-materials')}
              className={`py-4 px-1 border-b-2 font-medium text-sm transition-colors flex items-center gap-2 ${
                activeTab === 'without-materials'
                  ? 'border-blue-500 text-blue-600'
                  : 'border-transparent text-gray-500 hover:text-gray-700 hover:border-gray-300'
              }`}
            >
              Products without Materials
              {stats.productsWithoutMaterials > 0 && (
                <span className="bg-amber-100 text-amber-800 text-xs font-semibold px-2 py-0.5 rounded-full">
                  {stats.productsWithoutMaterials}
                </span>
              )}
            </button>
          </nav>
        </div>
      </div>

      {/* Filters */}
      {activeTab === 'carriers' && (
        <div className="bg-white border border-gray-200 rounded-lg p-4 mb-6">
          <div className="flex items-center gap-4 flex-wrap">
            {/* Search */}
            <div className="flex-1 min-w-[200px]">
              <div className="relative">
                <input
                  type="text"
                  placeholder="Search carriers or products..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
                />
                <svg className="absolute left-3 top-2.5 w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z" />
                </svg>
              </div>
            </div>

            {/* Carrier Filter */}
            <div className="min-w-[180px]">
              <select
                value={filterCarrier}
                onChange={(e) => setFilterCarrier(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="all">All Carriers</option>
                {carriers.map(carrier => (
                  <option key={carrier.id} value={carrier.id}>{carrier.name}</option>
                ))}
              </select>
            </div>

            {/* Status Filter */}
            <div className="min-w-[150px]">
              <select
                value={filterStatus}
                onChange={(e) => setFilterStatus(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="all">All Status</option>
                <option value="active">{t('common.active')}</option>
                <option value="inactive">{t('common.inactive')}</option>
              </select>
            </div>

            {/* Material Status Filter */}
            <div className="min-w-[180px]">
              <select
                value={filterMaterialStatus}
                onChange={(e) => setFilterMaterialStatus(e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="all">All Products</option>
                <option value="with">With Materials</option>
                <option value="without">Without Materials</option>
              </select>
            </div>

            {/* Expand/Collapse All Button */}
            <button
              onClick={() => setExpandAll(!expandAll)}
              className="px-4 py-2 border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors flex items-center gap-2"
            >
              {expandAll ? (
                <>
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M20 12H4" />
                  </svg>
                  Collapse All
                </>
              ) : (
                <>
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 4v16m8-8H4" />
                  </svg>
                  Expand All
                </>
              )}
            </button>

            {/* Clear Filters */}
            {(searchTerm || filterCarrier !== 'all' || filterStatus !== 'all' || filterMaterialStatus !== 'all') && (
              <button
                onClick={() => {
                  setSearchTerm('')
                  setFilterCarrier('all')
                  setFilterStatus('all')
                  setFilterMaterialStatus('all')
                }}
                className="px-4 py-2 text-gray-600 hover:text-gray-800 transition-colors"
              >
                Clear Filters
              </button>
            )}
          </div>
        </div>
      )}

      {/* Content */}
      {activeTab === 'carriers' ? (
        <div className="bg-gray-50 p-6 rounded-lg">
          {filteredData.carriers.length === 0 && !searchTerm && carriers.length === 0 && (
            <div className="text-center py-8 mb-6">
              <div className="text-4xl mb-4">🚚</div>
              <h3 className="text-lg font-semibold mb-2">No carriers defined yet</h3>
              <p className="text-gray-600 mb-4">
                Start by creating your first carrier to manage shipping products
              </p>
            </div>
          )}
          
          {filteredData.carriers.length === 0 && (searchTerm || filterCarrier !== 'all' || filterStatus !== 'all' || filterMaterialStatus !== 'all') && (
            <div className="text-center py-8">
              <div className="text-4xl mb-4">🔍</div>
              <h3 className="text-lg font-semibold mb-2">No results found</h3>
              <p className="text-gray-600">
                Try adjusting your search or filters
              </p>
            </div>
          )}
          
          {filteredData.carriers.length > 0 && (
            <CarriersTree
              carriers={filteredData.carriers}
              products={filteredData.products}
              productMaterials={productMaterials}
              expandAll={expandAll}
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
          )}
        </div>
      ) : (
        <div className="bg-white border border-gray-200 rounded-lg p-6">
          <div className="flex items-center justify-between mb-4">
            <div>
              <h3 className="text-lg font-semibold text-gray-900">Products without Materials</h3>
              <p className="text-sm text-gray-600 mt-1">
                These products need material assignments to be operational
              </p>
            </div>
            <button
              onClick={exportProductsWithoutMaterialsCSV}
              disabled={productsWithoutMaterials.length === 0}
              className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors shadow-sm disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
              </svg>
              Download CSV
            </button>
          </div>

          {productsWithoutMaterials.length === 0 ? (
            <div className="text-center py-12">
              <div className="text-4xl mb-4">✅</div>
              <h3 className="text-lg font-semibold mb-2 text-gray-900">All products have materials!</h3>
              <p className="text-gray-600">
                Every product has materials assigned from the catalog
              </p>
            </div>
          ) : (
            <div className="overflow-x-auto">
              <table className="min-w-full divide-y divide-gray-200">
                <thead className="bg-gray-50">
                  <tr>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Product Code
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Description
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Carrier
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Delivery Hours
                    </th>
                    <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                      Status
                    </th>
                  </tr>
                </thead>
                <tbody className="bg-white divide-y divide-gray-200">
                  {productsWithoutMaterials.map(product => {
                    const carrier = carriers.find(c => c.id === product.carrier_id)
                    return (
                      <tr key={product.id} className="hover:bg-gray-50">
                        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
                          {product.code}
                        </td>
                        <td className="px-6 py-4 text-sm text-gray-600">
                          {product.description || '-'}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                          {carrier?.name || '-'}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-600">
                          {product.standard_delivery_hours || '-'}
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <span className="px-2 py-1 text-xs font-medium rounded-full bg-amber-100 text-amber-800">
                            Pending Materials
                          </span>
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}

      {/* Create Carrier Modal */}
      {showCarrierModal && (
        <Modal
          isOpen={showCarrierModal}
          title={t('carriers.create_carrier')}
          onClose={() => setShowCarrierModal(false)}
        >
          <CarrierForm
            onSubmit={async (data) => {
              await createCarrier(data)
              setShowCarrierModal(false)
            }}
            onCancel={() => setShowCarrierModal(false)}
          />
        </Modal>
      )}
    </div>
  )
}
