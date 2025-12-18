import React, { useState } from 'react'
import { Search, User, Package } from 'lucide-react'
import { useStockManagement } from '../../hooks/useStockManagement'
import { SmartTooltip } from '../common/SmartTooltip'

export default function PanelistStockTab() {
  const { panelistStocks, loading } = useStockManagement()
  const [searchTerm, setSearchTerm] = useState('')
  const [selectedPanelist, setSelectedPanelist] = useState<string>('')

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
              placeholder="Search by material or panelist..."
            />
          </div>
        </div>

        <div className="w-64">
          <select
            value={selectedPanelist}
            onChange={(e) => setSelectedPanelist(e.target.value)}
            className="block w-full pl-3 pr-10 py-2 text-base border border-gray-300 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm rounded-md"
          >
            <option value="">All panelists</option>
            {panelists.map((panelist) => (
              <option key={panelist.id} value={panelist.id}>
                {panelist.name} ({panelist.code})
              </option>
            ))}
          </select>
        </div>
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
                      Code: {panelist?.panelist_code || 'N/A'} • {stocks.length} material(s)
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
                          Material
                          <SmartTooltip content="Material code and name" />
                        </div>
                      </th>
                      <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        <div className="flex items-center gap-1">
                          Quantity
                          <SmartTooltip content="Current quantity in panelist stock" />
                        </div>
                      </th>
                      <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        Unit
                      </th>
                      <th scope="col" className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                        <div className="flex items-center gap-1">
                          Last Updated
                          <SmartTooltip content="Date of last movement for this material" />
                        </div>
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
    </div>
  )
}
