import React, { useState, useMemo } from 'react'
import { useTranslation } from '@/hooks/useTranslation'
import { Search, User, Package, Edit, Download } from 'lucide-react'
import { useStockManagement } from '../../hooks/useStockManagement'
import { SmartTooltip } from '../common/SmartTooltip'
import { supabase } from '../../lib/supabase'
import { useAuth } from '../../contexts/AuthContext'
import { downloadCSV } from '../../lib/exportUtils'

export default function PanelistStockTab() {
  const { t } = useTranslation()
  const { panelistStocks, loading } = useStockManagement()
  const { user } = useAuth()
  const [searchTerm, setSearchTerm] = useState('')
  const [selectedPanelist, setSelectedPanelist] = useState<string>('')
  const [showAdjustModal, setShowAdjustModal] = useState(false)
  const [selectedStock, setSelectedStock] = useState<any>(null)
  const [adjustQuantity, setAdjustQuantity] = useState<string>('')
  const [adjustNote, setAdjustNote] = useState('')
  const [adjusting, setAdjusting] = useState(false)

  // Get unique panelists
  const panelists = Array.from(
    new Set(panelistStocks.map(s => s.panelist_id))
  ).map(id => {
    const stock = panelistStocks.find(s => s.panelist_id === id)
    return {
      id,
      name: stock?.panelist?.name || 'No name',
      code: stock?.panelist?.panelist_code || 'N/A'
    }
  }).sort((a, b) => a.name.localeCompare(b.name))

  // Filter stocks
  const filteredStocks = panelistStocks.filter(stock => {
    const materialName = stock.material?.name?.toLowerCase() || ''
    const materialCode = stock.material?.code?.toLowerCase() || ''
    const panelistName = stock.panelist?.name?.toLowerCase() || ''
    const search = searchTerm.toLowerCase()
    
    const matchesSearch = materialName.includes(search) || 
                         materialCode.includes(search) || 
                         panelistName.includes(search)
    
    const matchesPanelist = !selectedPanelist || stock.panelist_id === selectedPanelist
    
    return matchesSearch && matchesPanelist
  })

  // Group by panelist
  const groupedStocks = filteredStocks.reduce((acc, stock) => {
    const panelistId = stock.panelist_id
    if (!acc[panelistId]) {
      acc[panelistId] = {
        panelist: stock.panelist,
        stocks: []
      }
    }
    acc[panelistId].stocks.push(stock)
    return acc
  }, {} as Record<string, { panelist: any; stocks: typeof panelistStocks }>)

  const handleExportCSV = () => {
    if (filteredStocks.length === 0) {
      alert('No stock data to export')
      return
    }

    const csvData = filteredStocks.map(stock => ({
      'Panelist Code': stock.panelist?.panelist_code || 'N/A',
      'Panelist Name': stock.panelist?.name || 'Unknown',
      'Material Code': stock.material?.code || 'N/A',
      'Material Name': stock.material?.name || 'Unknown',
      'Quantity': stock.quantity,
      'Unit': stock.material?.unit_measure || 'un'
    }))

    downloadCSV(csvData, `panelist-stock-${new Date().toISOString().split('T')[0]}.csv`)
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">Loading panelist stock...</div>
      </div>
    )
  }

  return (
    <div className="space-y-4">
      {/* Search and Filters */}
      <div className="flex items-center gap-4">
        <div className="flex-1 max-w-lg">
          <div className="relative">
            <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none">
              <Search className="h-5 w-5 text-gray-400" />
            </div>
            <input
              type="text"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="block w-full pl-10 pr-3 py-2 border border-gray-300 rounded-md leading-5 bg-white placeholder-gray-500 focus:outline-none focus:placeholder-gray-400 focus:ring-1 focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
              placeholder={t('stock.search_by_material_or_panelist')}
            />
          </div>
        </div>

        <div className="w-64">
          <select
            value={selectedPanelist}
            onChange={(e) => setSelectedPanelist(e.target.value)}
            className="block w-full pl-3 pr-10 py-2 text-base border border-gray-300 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm rounded-md"
          >
            <option value="">{t('stock.all_panelists')}</option>
            {panelists.map((panelist) => (
              <option key={panelist.id} value={panelist.id}>
                {panelist.name} ({panelist.code})
              </option>
            ))}
          </select>
        </div>

        <button
          onClick={handleExportCSV}
          className="inline-flex items-center px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500"
        >
          <Download className="h-4 w-4 mr-2" />
          {t('common.export_csv')}
        </button>
      </div>

      {/* Grouped Stock Display */}
      <div className="space-y-6">
        {Object.keys(groupedStocks).length === 0 ? (
          <div className="text-center py-12 text-gray-500">
            {searchTerm || selectedPanelist ? 'No materials found' : 'No panelist stock'}
          </div>
        ) : (
          Object.entries(groupedStocks).map(([panelistId, { panelist, stocks }]) => (
            <div key={panelistId} className="border border-gray-200 rounded-lg overflow-hidden">
              {/* Panelist Header */}
              <div className="bg-gray-50 px-6 py-4 border-b border-gray-200">
                <div className="flex items-center gap-3">
                  <User className="h-5 w-5 text-gray-400" />
                  <div>
                    <h3 className="text-lg font-medium text-gray-900">
                      {panelist?.name || 'No name'}
                    </h3>
                    <p className="text-sm text-gray-500">
                      {t('stock.panelist_code_materials_count', { code: panelist?.panelist_code || 'N/A', count: stocks.length })}
                    </p>
                  </div>
                </div>
              </div>

              {/* Materials Table */}
              <div className="overflow-x-auto">
                <table className="min-w-full divide-y divide-gray-200">
                  <thead className="bg-gray-50">
                    <tr>
                      <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        <div className="flex items-center gap-1">
                          {t('common.material')}
                          <SmartTooltip content="Material code and name" />
                        </div>
                      </th>
                      <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        <div className="flex items-center gap-1">
                          {t('stock.quantity')}
                          <SmartTooltip content="Current quantity in panelist stock" />
                        </div>
                      </th>
                      <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        {t('common.unit')}
                      </th>
                      <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        <div className="flex items-center gap-1">
                          {t('stock.last_updated')}
                          <SmartTooltip content="Date of last movement for this material" />
                        </div>
                      </th>
                      <th scope="col" className="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase tracking-wider">
                        {t('common.actions')}
                      </th>
                    </tr>
                  </thead>
                  <tbody className="bg-white divide-y divide-gray-200">
                    {stocks.map((stock) => (
                      <tr key={stock.id}>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <div className="text-sm font-medium text-gray-900">
                            {stock.material?.code || 'N/A'}
                          </div>
                          <div className="text-sm text-gray-500">
                            {stock.material?.name || 'No name'}
                          </div>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <div className="text-sm text-gray-900 font-semibold">
                            {stock.quantity.toLocaleString()}
                          </div>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <div className="text-sm text-gray-500">
                            {stock.material?.unit_measure || 'N/A'}
                          </div>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap">
                          <div className="text-sm text-gray-500">
                            {stock.last_updated 
                              ? new Date(stock.last_updated).toLocaleDateString('en-US')
                              : 'N/A'
                            }
                          </div>
                        </td>
                        <td className="px-6 py-4 whitespace-nowrap text-right text-sm font-medium">
                          <button
                            onClick={() => {
                              setSelectedStock(stock)
                              setAdjustQuantity(stock.quantity.toString())
                              setAdjustNote('')
                              setShowAdjustModal(true)
                            }}
                            className="inline-flex items-center gap-1 text-blue-600 hover:text-blue-900"
                          >
                            <Edit className="h-4 w-4" />
                            {t('stock.adjust_stock')}
                          </button>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </div>
          ))
        )}
      </div>

      {/* Summary */}
      <div className="bg-gray-50 px-4 py-3 rounded-md">
        <div className="text-sm text-gray-700">
          <span className="font-medium">Total records:</span> {filteredStocks.length}
          {(searchTerm || selectedPanelist) && ` (filtered from ${panelistStocks.length})`}
        </div>
      </div>

      {/* Adjust Stock Modal */}
      {showAdjustModal && selectedStock && (
        <div className="fixed inset-0 bg-gray-500 bg-opacity-75 flex items-center justify-center z-50">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full mx-4">
            <div className="px-6 py-4 border-b border-gray-200">
              <h3 className="text-lg font-medium text-gray-900">
                Adjust Panelist Stock: {selectedStock.material?.code}
              </h3>
              <p className="text-sm text-gray-500 mt-1">
                {selectedStock.material?.name}
              </p>
              <p className="text-sm text-gray-600 mt-1">
                Panelist: {selectedStock.panelist?.name} ({selectedStock.panelist?.panelist_code})
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
                  value={adjustQuantity}
                  onChange={(e) => setAdjustQuantity(e.target.value)}
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
                  value={adjustNote}
                  onChange={(e) => setAdjustNote(e.target.value)}
                  rows={3}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                  placeholder="Explain the reason for this adjustment..."
                />
              </div>

              {adjustQuantity && (
                <div className="bg-blue-50 border border-blue-200 rounded-md p-3">
                  <p className="text-sm text-blue-800">
                    <strong>Change:</strong> {parseInt(adjustQuantity) - selectedStock.quantity > 0 ? '+' : ''}
                    {(parseInt(adjustQuantity) - selectedStock.quantity).toLocaleString()} {selectedStock.material?.unit_measure || 'un'}
                  </p>
                </div>
              )}
            </div>

            <div className="px-6 py-4 border-t border-gray-200 flex items-center justify-end gap-3">
              <button
                onClick={() => {
                  setShowAdjustModal(false)
                  setSelectedStock(null)
                  setAdjustQuantity('')
                  setAdjustNote('')
                }}
                disabled={adjusting}
                className="px-4 py-2 border border-gray-300 text-sm font-medium rounded-md text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
              >
                Cancel
              </button>
              <button
                onClick={async () => {
                  if (!adjustQuantity || !adjustNote.trim()) {
                    alert('Please enter new quantity and adjustment note')
                    return
                  }

                  const qty = parseInt(adjustQuantity)
                  if (isNaN(qty) || qty < 0) {
                    alert('Please enter a valid quantity')
                    return
                  }

                  try {
                    setAdjusting(true)
                    
                    // Update panelist stock
                    const { error: updateError } = await supabase
                      .from('panelist_material_stocks')
                      .update({ 
                        quantity: qty,
                        updated_at: new Date().toISOString()
                      })
                      .eq('id', selectedStock.id)

                    if (updateError) throw updateError
                    
                    // Create adjustment movement record
                    const { error: movementError } = await supabase
                      .from('material_movements')
                      .insert({
                        account_id: selectedStock.account_id,
                        material_id: selectedStock.material_id,
                        reference_id: selectedStock.panelist_id,
                        movement_type: 'adjustment',
                        quantity: qty - selectedStock.quantity,
                        from_location: 'panelist',
                        to_location: 'panelist',
                        notes: adjustNote,
                        created_by: user?.id
                      })

                    if (movementError) throw movementError

                    // Reload data
                    window.location.reload()
                    
                    setShowAdjustModal(false)
                    setSelectedStock(null)
                    setAdjustQuantity('')
                    setAdjustNote('')
                    alert('Panelist stock adjusted successfully')
                  } catch (error: any) {
                    console.error('Error adjusting panelist stock:', error)
                    alert('Failed to adjust stock: ' + error.message)
                  } finally {
                    setAdjusting(false)
                  }
                }}
                disabled={adjusting || !adjustQuantity || !adjustNote.trim()}
                className="px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-blue-600 hover:bg-blue-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500 disabled:opacity-50"
              >
                {adjusting ? 'Adjusting...' : 'Confirm Adjustment'}
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
