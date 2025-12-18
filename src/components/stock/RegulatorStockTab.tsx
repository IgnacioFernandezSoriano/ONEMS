import React, { useState, useMemo } from 'react'
import { Search, Filter, RotateCcw } from 'lucide-react'
import { useStockManagement } from '../../hooks/useStockManagement'
import { useMaterialCatalog } from '../../hooks/useMaterialCatalog'
import { SmartTooltip } from '../common/SmartTooltip'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../contexts/AuthContext'

export default function RegulatorStockTab() {
  const { regulatorStocks, loading, updateRegulatorStock, reload } = useStockManagement()
  const { catalog: materials } = useMaterialCatalog()
  const { user } = useAuth()

  // Filters
  const [searchTerm, setSearchTerm] = useState('')
  const [selectedMaterialId, setSelectedMaterialId] = useState('')
  const [showLowStockOnly, setShowLowStockOnly] = useState(false)

  // Adjust Stock Modal
  const [showAdjustModal, setShowAdjustModal] = useState(false)
  const [selectedStock, setSelectedStock] = useState<typeof regulatorStocks[0] | null>(null)
  const [newQuantity, setNewQuantity] = useState('')
  const [adjustmentNote, setAdjustmentNote] = useState('')
  const [isAdjusting, setIsAdjusting] = useState(false)

  // Filter stocks
  const filteredStocks = useMemo(() => {
    let filtered = regulatorStocks

    // Filter by material
    if (selectedMaterialId) {
      filtered = filtered.filter(s => s.material_id === selectedMaterialId)
    }

    // Filter by search term
    if (searchTerm) {
      const term = searchTerm.toLowerCase()
      filtered = filtered.filter(s =>
        s.material?.code?.toLowerCase().includes(term) ||
        s.material?.name?.toLowerCase().includes(term)
      )
    }

    // Filter by low stock
    if (showLowStockOnly) {
      filtered = filtered.filter(s => {
        const minStock = s.min_stock || 0
        return s.quantity < minStock && minStock > 0
      })
    }

    return filtered
  }, [regulatorStocks, selectedMaterialId, searchTerm, showLowStockOnly])

  const handleResetFilters = () => {
    setSearchTerm('')
    setSelectedMaterialId('')
    setShowLowStockOnly(false)
  }

  const getStatusBadge = (stock: typeof regulatorStocks[0]) => {
    const minStock = stock.min_stock || 0
    if (minStock > 0 && stock.quantity < minStock) {
      return (
        <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-red-100 text-red-800">
          Low Stock
        </span>
      )
    }
    return (
      <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800">
        Normal
      </span>
    )
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="text-center">
          <div className="inline-block animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600"></div>
          <p className="mt-2 text-sm text-gray-500">Loading stock...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      {/* Filters */}
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-4">
        <div className="flex items-center gap-2 mb-4">
          <Filter className="h-5 w-5 text-gray-500" />
          <span className="font-medium text-gray-900">Filters</span>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {/* Search */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Search
            </label>
            <div className="relative">
              <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
                <Search className="h-4 w-4 text-gray-400" />
              </div>
              <input
                type="text"
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                placeholder="Search by material or code..."
                className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
              />
            </div>
          </div>

          {/* Material Filter */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              Material
              <SmartTooltip content="Filter by specific material" />
            </label>
            <select
              value={selectedMaterialId}
              onChange={(e) => setSelectedMaterialId(e.target.value)}
              className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
            >
              <option value="">All Materials</option>
              {materials.map(m => (
                <option key={m.id} value={m.id}>{m.code} - {m.name}</option>
              ))}
            </select>
          </div>

          {/* Low Stock Toggle */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1 flex items-center gap-1">
              Stock Status
              <SmartTooltip content="Show only materials with low stock" />
            </label>
            <label className="flex items-center h-10 px-3 border border-gray-300 rounded-md bg-white cursor-pointer hover:bg-gray-50">
              <input
                type="checkbox"
                checked={showLowStockOnly}
                onChange={(e) => setShowLowStockOnly(e.target.checked)}
                className="h-4 w-4 text-blue-600 focus:ring-blue-500 border-gray-300 rounded"
              />
              <span className="ml-2 text-sm text-gray-700">Low Stock Only</span>
            </label>
          </div>
        </div>

        {/* Reset Button */}
        <div className="mt-4">
          <button
            onClick={handleResetFilters}
            className="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
          >
            <RotateCcw className="h-4 w-4 mr-2" />
            Reset Filters
          </button>
        </div>
      </div>

      {/* Stock Table */}
      <div className="bg-white border border-gray-200 rounded-lg">
        <div className="px-4 py-3 border-b border-gray-200">
          <h3 className="text-lg font-medium text-gray-900">
            Current Regulator Stock ({filteredStocks.length})
          </h3>
        </div>

        {filteredStocks.length === 0 ? (
          <div className="text-center py-12">
            <p className="text-sm text-gray-500">No stock records found</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="min-w-full divide-y divide-gray-200">
              <thead className="bg-gray-50">
                <tr>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Material
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Quantity
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Minimum
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Maximum
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Status
                  </th>
                  <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody className="bg-white divide-y divide-gray-200">
                {filteredStocks.map((stock) => {
                  const isLowStock = stock.min_stock && stock.quantity < stock.min_stock
                  return (
                    <tr key={stock.id} className={isLowStock ? 'bg-red-50' : ''}>
                      <td className="px-6 py-4">
                        <div className="text-sm font-medium text-gray-900">
                          {stock.material?.code || 'N/A'}
                        </div>
                        <div className="text-sm text-gray-500">
                          {stock.material?.name || 'No name'}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className={`text-sm font-semibold ${isLowStock ? 'text-red-600' : 'text-gray-900'}`}>
                          {stock.quantity.toLocaleString()} {stock.material?.unit_measure || 'un'}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="text-sm text-gray-900">
                          {stock.min_stock || 0}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <div className="text-sm text-gray-900">
                          {stock.max_stock || 0}
                        </div>
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        {getStatusBadge(stock)}
                      </td>
                      <td className="px-6 py-4 whitespace-nowrap">
                        <button
                          onClick={() => {
                            setSelectedStock(stock)
                            setNewQuantity(stock.quantity.toString())
                            setAdjustmentNote('')
                            setShowAdjustModal(true)
                          }}
                          className="inline-flex items-center px-3 py-1.5 border border-gray-300 text-xs font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
                        >
                          Adjust Stock
                        </button>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Adjust Stock Modal */}
      {showAdjustModal && selectedStock && (
        <div className="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-medium text-gray-900">
                Adjust Stock: {selectedStock.material?.code}
              </h3>
              <p className="text-sm text-gray-500 mt-1">
                {selectedStock.material?.name}
              </p>
            </div>

            <div className="px-6 py-4 space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Current Quantity
                </label>
                <div className="text-lg font-semibold text-gray-900">
                  {selectedStock.quantity.toLocaleString()} {selectedStock.material?.unit_measure || 'un'}
                </div>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  New Quantity <span className="text-red-500">*</span>
                </label>
                <input
                  type="number"
                  value={newQuantity}
                  onChange={(e) => setNewQuantity(e.target.value)}
                  min="0"
                  step="1"
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="Enter new absolute quantity"
                />
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Adjustment Note <span className="text-red-500">*</span>
                </label>
                <textarea
                  value={adjustmentNote}
                  onChange={(e) => setAdjustmentNote(e.target.value)}
                  rows={3}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="Explain the reason for this adjustment..."
                />
              </div>

              {newQuantity && (
                <div className="bg-blue-50 border border-blue-200 rounded-md p-3">
                  <p className="text-sm text-blue-800">
                    <strong>Change:</strong> {parseInt(newQuantity) - selectedStock.quantity > 0 ? '+' : ''}
                    {(parseInt(newQuantity) - selectedStock.quantity).toLocaleString()} {selectedStock.material?.unit_measure || 'un'}
                  </p>
                </div>
              )}
            </div>

            <div className="px-6 py-4 border-t border-gray-200 flex items-center justify-end gap-3">
              <button
                onClick={() => {
                  setShowAdjustModal(false)
                  setSelectedStock(null)
                  setNewQuantity('')
                  setAdjustmentNote('')
                }}
                disabled={isAdjusting}
                className="px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                onClick={async () => {
                  if (!newQuantity || !adjustmentNote.trim()) {
                    alert('Please enter new quantity and adjustment note')
                    return
                  }

                  const qty = parseInt(newQuantity)
                  if (isNaN(qty) || qty < 0) {
                    alert('Please enter a valid quantity')
                    return
                  }

                  try {
                    setIsAdjusting(true)
                    await updateRegulatorStock(
                      selectedStock.material_id,
                      qty,
                      selectedStock.min_stock || undefined,
                      selectedStock.max_stock || undefined
                    )
                    
                    // Create adjustment movement record
                    await supabase.from('material_movements').insert({
                      account_id: selectedStock.account_id,
                      material_id: selectedStock.material_id,
                      movement_type: 'adjustment',
                      quantity: qty - selectedStock.quantity,
                      from_location: 'regulator',
                      to_location: 'regulator',
                      notes: adjustmentNote,
                      created_by: user?.id
                    })

                    await reload()
                    setShowAdjustModal(false)
                    setSelectedStock(null)
                    setNewQuantity('')
                    setAdjustmentNote('')
                    alert('Stock adjusted successfully')
                  } catch (error: any) {
                    console.error('Error adjusting stock:', error)
                    alert('Failed to adjust stock: ' + error.message)
                  } finally {
                    setIsAdjusting(false)
                  }
                }}
                disabled={isAdjusting || !newQuantity || !adjustmentNote.trim()}
                className="px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
              >
                {isAdjusting ? 'Adjusting...' : 'Confirm Adjustment'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
