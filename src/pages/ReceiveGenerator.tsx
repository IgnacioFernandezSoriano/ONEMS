import { useState, useEffect } from 'react'
import { Play, AlertCircle, CheckCircle, Loader } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

interface GeneratorConfig {
  recordCount: number
  outOfSlaPercentage: number
  advanceVarianceDays: number
  delayVarianceDays: number
  productIds: string[]
  carrierIds: string[]
  startDate: string
  endDate: string
}

export default function ReceiveGenerator() {
  const { profile } = useAuth()
  const accountId = profile?.account_id

  const [config, setConfig] = useState<GeneratorConfig>({
    recordCount: 100,
    outOfSlaPercentage: 20,
    advanceVarianceDays: 2,
    delayVarianceDays: 3,
    productIds: [],
    carrierIds: [],
    startDate: new Date().toISOString().split('T')[0],
    endDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString().split('T')[0]
  })

  const [products, setProducts] = useState<any[]>([])
  const [carriers, setCarriers] = useState<any[]>([])
  const [cities, setCities] = useState<any[]>([])
  const [nodes, setNodes] = useState<any[]>([])
  const [panelists, setPanelists] = useState<any[]>([])
  
  const [generating, setGenerating] = useState(false)
  const [progress, setProgress] = useState(0)
  const [result, setResult] = useState<{ success: number; failed: number } | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [deliveryStandard, setDeliveryStandard] = useState<number | null>(null)

  useEffect(() => {
    loadData()
  }, [accountId])

  // Load delivery standard when products change (use first product for example)
  useEffect(() => {
    if (config.productIds.length > 0 && accountId) {
      supabase
        .from('delivery_standards')
        .select('standard_days')
        .eq('account_id', accountId)
        .eq('product_id', config.productIds[0])
        .maybeSingle()
        .then(({ data }) => {
          setDeliveryStandard(data?.standard_days || null)
        })
    } else {
      setDeliveryStandard(null)
    }
  }, [config.productIds, accountId])

  const loadData = async () => {
    if (!accountId) return

    try {
      // Load products
      const { data: productsData } = await supabase
        .from('products')
        .select('id, code, description')
        .eq('account_id', accountId)
        .order('code')

      setProducts(productsData || [])

      // Load carriers
      const { data: carriersData } = await supabase
        .from('carriers')
        .select('id, name')
        .eq('account_id', accountId)
        .order('name')

      setCarriers(carriersData || [])

      // Load cities
      const { data: citiesData } = await supabase
        .from('cities')
        .select('id, name')
        .eq('account_id', accountId)
        .order('name')

      setCities(citiesData || [])

      // Load nodes
      const { data: nodesData } = await supabase
        .from('nodes')
        .select('id, auto_id, city_id')
        .eq('account_id', accountId)
        .order('auto_id')

      setNodes(nodesData || [])

      // Load panelists with city_id from nodes
      const { data: panelistsData } = await supabase
        .from('panelists')
        .select(`
          id,
          name,
          panelist_code,
          node_id,
          nodes!inner (
            city_id
          )
        `)
        .eq('account_id', accountId)
        .order('name')

      // Transform data to include city_id at root level
      const panelistsWithCity = panelistsData?.map(p => ({
        id: p.id,
        name: p.name,
        panelist_code: p.panelist_code,
        node_id: p.node_id,
        city_id: (p.nodes as any)?.city_id
      })) || []

      setPanelists(panelistsWithCity)
    } catch (err: any) {
      console.error('Error loading data:', err)
      setError(err.message)
    }
  }

  const generateRandomTag = () => {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    let tag = ''
    for (let i = 0; i < 12; i++) {
      tag += chars.charAt(Math.floor(Math.random() * chars.length))
    }
    return tag
  }

  const getRandomElement = <T,>(array: T[]): T => {
    return array[Math.floor(Math.random() * array.length)]
  }

  const getRandomDate = (start: Date, end: Date): Date => {
    return new Date(start.getTime() + Math.random() * (end.getTime() - start.getTime()))
  }

  const generateRecords = async () => {
    if (!accountId || config.productIds.length === 0) {
      setError('Please select at least one product')
      return
    }
    if (config.carrierIds.length === 0) {
      setError('Please select at least one carrier')
      return
    }

    setGenerating(true)
    setProgress(0)
    setResult(null)
    setError(null)

    console.log('[Receive Generator] Starting generation...')
    console.log('[Receive Generator] Config:', config)
    console.log('[Receive Generator] Cities:', cities.length)
    console.log('[Receive Generator] Nodes:', nodes.length)
    console.log('[Receive Generator] Panelists:', panelists.length)
    console.log('[Receive Generator] Carriers:', carriers.length)
    console.log('[Receive Generator] Products:', products.length)

    try {
      // Get delivery standards for all products
      const { data: deliveryStandards } = await supabase
        .from('delivery_standards')
        .select('product_id, standard_days')
        .eq('account_id', accountId)
        .in('product_id', config.productIds)

      const standardDaysMap = new Map(
        deliveryStandards?.map(ds => [ds.product_id, ds.standard_days]) || []
      )

      const records = []
      const startDate = new Date(config.startDate)
      const endDate = new Date(config.endDate)

      // Calculate total records to generate (recordCount per product/carrier combination)
      const totalCombinations = config.productIds.length * config.carrierIds.length
      const recordsPerCombination = Math.floor(config.recordCount / totalCombinations)
      
      // Determine how many records should be out of SLA per combination
      const outOfSlaCountPerCombination = Math.floor(recordsPerCombination * (config.outOfSlaPercentage / 100))
      
      let totalRecordsGenerated = 0

      // Create maps for quick lookup
      const productMap = new Map(products.map(p => [p.id, p]))
      const carrierMap = new Map(carriers.map(c => [c.id, c]))
      const cityMap = new Map(cities.map(c => [c.id, c]))
      const nodeMap = new Map(nodes.map(n => [n.id, n]))
      const panelistMap = new Map(panelists.map(p => [p.id, p]))

      // Generate records for each product/carrier combination
      for (const productId of config.productIds) {
        const product = productMap.get(productId)
        if (!product) continue
        
        const standardDays = standardDaysMap.get(productId) || 3
        
        for (const carrierId of config.carrierIds) {
          const carrier = carrierMap.get(carrierId)
          if (!carrier) continue
          for (let i = 0; i < recordsPerCombination; i++) {
            const isOutOfSla = i < outOfSlaCountPerCombination

            // Random origin and destination
            const originCity = getRandomElement(cities)
            const destCity = getRandomElement(cities.filter(c => c.id !== originCity.id))
            
            const originNodesFiltered = nodes.filter(n => n.city_id === originCity.id)
            const destNodesFiltered = nodes.filter(n => n.city_id === destCity.id)
            
            if (originNodesFiltered.length === 0 || destNodesFiltered.length === 0) {
              console.warn('[Receive Generator] Skipping: No nodes found', { originCity: originCity.name, destCity: destCity.name })
              continue
            }

            const originNode = getRandomElement(originNodesFiltered)
            const destNode = getRandomElement(destNodesFiltered)

            // Random panelists
            const originPanelistsFiltered = panelists.filter(p => p.city_id === originCity.id)
            const destPanelistsFiltered = panelists.filter(p => p.city_id === destCity.id)

            if (originPanelistsFiltered.length === 0 || destPanelistsFiltered.length === 0) {
              console.warn('[Receive Generator] Skipping: No panelists found', { originCity: originCity.name, destCity: destCity.name })
              continue
            }

            const originPanelist = getRandomElement(originPanelistsFiltered)
            const destPanelist = getRandomElement(destPanelistsFiltered)

            // Random dates within the specified range
            const shipmentDate = getRandomDate(startDate, endDate)
            
            let receiveDate: Date
            if (isOutOfSla) {
              // Out of SLA: add delay
              const delayDays = standardDays + Math.floor(Math.random() * config.delayVarianceDays) + 1
              receiveDate = new Date(shipmentDate.getTime() + delayDays * 24 * 60 * 60 * 1000)
            } else {
              // Within SLA: random between advance and standard
              const variance = Math.random() < 0.5 
                ? -Math.floor(Math.random() * config.advanceVarianceDays) // advance
                : Math.floor(Math.random() * (standardDays - 1)) // within standard
              receiveDate = new Date(shipmentDate.getTime() + (standardDays + variance) * 24 * 60 * 60 * 1000)
            }

            const record = {
              account_id: accountId,
              tag_id: generateRandomTag(),
              carrier_name: carrier.name,
              product_name: `${product.code} - ${product.description}`,
              origin_city_name: originCity.name,
              origin_node_auto_id: originNode.auto_id,
              origin_panelist_code: originPanelist.panelist_code,
              destination_city_name: destCity.name,
              destination_node_auto_id: destNode.auto_id,
              destination_panelist_code: destPanelist.panelist_code,
              sent_at: shipmentDate.toISOString(),
              received_at: receiveDate.toISOString(),
              business_transit_days: Math.floor((receiveDate.getTime() - shipmentDate.getTime()) / (1000 * 60 * 60 * 24)),
              on_time_delivery: !isOutOfSla
            }

            records.push(record)
            totalRecordsGenerated++

            // Update progress
            setProgress(Math.floor((totalRecordsGenerated / (recordsPerCombination * totalCombinations)) * 50))
          }
        }
      }

      console.log('[Receive Generator] Records generated:', records.length)
      console.log('[Receive Generator] Starting batch insertion...')

      // Insert records in batches
      const batchSize = 100
      let successCount = 0
      let failedCount = 0

      for (let i = 0; i < records.length; i += batchSize) {
        const batch = records.slice(i, i + batchSize)
        const { error: insertError } = await supabase
          .from('one_db')
          .insert(batch)

        if (insertError) {
          console.error('Error inserting batch:', insertError)
          failedCount += batch.length
        } else {
          successCount += batch.length
        }

        // Update progress
        setProgress(50 + Math.floor(((i + batchSize) / records.length) * 50))
      }

      setResult({ success: successCount, failed: failedCount })
      setProgress(100)
    } catch (err: any) {
      console.error('Error generating records:', err)
      setError(err.message)
    } finally {
      setGenerating(false)
    }
  }

  return (
    <div className="p-6 max-w-4xl mx-auto">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Receive Generator</h1>
        <p className="text-sm text-gray-600 mt-1">
          Generate synthetic receive records for testing and demo purposes
        </p>
        <div className="mt-2 bg-yellow-50 border border-yellow-200 rounded-lg p-3">
          <div className="flex items-center gap-2">
            <AlertCircle className="h-4 w-4 text-yellow-600" />
            <span className="text-sm text-yellow-800 font-medium">
              Demo Account Only - This feature is only available for testing purposes
            </span>
          </div>
        </div>
      </div>

      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
        <h2 className="text-lg font-semibold text-gray-900 mb-4">Generator Configuration</h2>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {/* Number of Records */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Number of Records
            </label>
            <input
              type="number"
              min="1"
              max="10000"
              value={config.recordCount}
              onChange={(e) => setConfig({ ...config, recordCount: parseInt(e.target.value) || 0 })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          {/* Out of SLA Percentage */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Out of SLA Percentage (%)
            </label>
            <input
              type="number"
              min="0"
              max="100"
              value={config.outOfSlaPercentage}
              onChange={(e) => setConfig({ ...config, outOfSlaPercentage: parseInt(e.target.value) || 0 })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          {/* Advance Variance */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Advance Variance (days)
            </label>
            <input
              type="number"
              min="0"
              max="10"
              step="0.1"
              value={config.advanceVarianceDays}
              onChange={(e) => setConfig({ ...config, advanceVarianceDays: parseFloat(e.target.value) || 0 })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
            {deliveryStandard !== null ? (
              <p className="text-xs text-blue-600 mt-1 font-medium">
                📊 Example: Records can arrive between {Math.max(0, deliveryStandard - config.advanceVarianceDays)} and {deliveryStandard} days (SLA: {deliveryStandard} days)
              </p>
            ) : (
              <p className="text-xs text-gray-500 mt-1">Maximum days records can arrive early</p>
            )}
          </div>

          {/* Delay Variance */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Delay Variance (days)
            </label>
            <input
              type="number"
              min="0"
              max="30"
              step="0.1"
              value={config.delayVarianceDays}
              onChange={(e) => setConfig({ ...config, delayVarianceDays: parseFloat(e.target.value) || 0 })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
            {deliveryStandard !== null ? (
              <p className="text-xs text-red-600 mt-1 font-medium">
                📊 Example: Out-of-SLA records can arrive up to {deliveryStandard + config.delayVarianceDays} days (SLA: {deliveryStandard} days, delay: +{config.delayVarianceDays} days)
              </p>
            ) : (
              <p className="text-xs text-gray-500 mt-1">Maximum days records can be delayed beyond SLA</p>
            )}
          </div>

          {/* Products */}
          <div className="md:col-span-2">
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Products <span className="text-red-500">*</span>
            </label>
            <div className="border border-gray-300 rounded-lg p-3 max-h-40 overflow-y-auto">
              <div className="flex items-center gap-2 mb-2">
                <input
                  type="checkbox"
                  checked={config.productIds.length === products.length}
                  onChange={(e) => {
                    if (e.target.checked) {
                      setConfig({ ...config, productIds: products.map(p => p.id) })
                    } else {
                      setConfig({ ...config, productIds: [] })
                    }
                  }}
                  className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                />
                <span className="text-sm font-medium text-gray-900">Select All</span>
              </div>
              <div className="border-t border-gray-200 pt-2 space-y-2">
                {products.map((product) => (
                  <div key={product.id} className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      checked={config.productIds.includes(product.id)}
                      onChange={(e) => {
                        if (e.target.checked) {
                          setConfig({ ...config, productIds: [...config.productIds, product.id] })
                        } else {
                          setConfig({ ...config, productIds: config.productIds.filter(id => id !== product.id) })
                        }
                      }}
                      className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span className="text-sm text-gray-700">
                      {product.code} - {product.description}
                    </span>
                  </div>
                ))}
              </div>
            </div>
            <p className="text-xs text-gray-500 mt-1">
              Selected: {config.productIds.length} product(s)
            </p>
          </div>

          {/* Carriers */}
          <div className="md:col-span-2">
            <label className="block text-sm font-medium text-gray-700 mb-2">
              Carriers <span className="text-red-500">*</span>
            </label>
            <div className="border border-gray-300 rounded-lg p-3 max-h-40 overflow-y-auto">
              <div className="flex items-center gap-2 mb-2">
                <input
                  type="checkbox"
                  checked={config.carrierIds.length === carriers.length}
                  onChange={(e) => {
                    if (e.target.checked) {
                      setConfig({ ...config, carrierIds: carriers.map(c => c.id) })
                    } else {
                      setConfig({ ...config, carrierIds: [] })
                    }
                  }}
                  className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                />
                <span className="text-sm font-medium text-gray-900">Select All</span>
              </div>
              <div className="border-t border-gray-200 pt-2 space-y-2">
                {carriers.map((carrier) => (
                  <div key={carrier.id} className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      checked={config.carrierIds.includes(carrier.id)}
                      onChange={(e) => {
                        if (e.target.checked) {
                          setConfig({ ...config, carrierIds: [...config.carrierIds, carrier.id] })
                        } else {
                          setConfig({ ...config, carrierIds: config.carrierIds.filter(id => id !== carrier.id) })
                        }
                      }}
                      className="rounded border-gray-300 text-blue-600 focus:ring-blue-500"
                    />
                    <span className="text-sm text-gray-700">
                      {carrier.name}
                    </span>
                  </div>
                ))}
              </div>
            </div>
            <p className="text-xs text-gray-500 mt-1">
              Selected: {config.carrierIds.length} carrier(s)
            </p>
          </div>

          {/* Start Date */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Start Date
            </label>
            <input
              type="date"
              value={config.startDate}
              onChange={(e) => setConfig({ ...config, startDate: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>

          {/* End Date */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              End Date
            </label>
            <input
              type="date"
              value={config.endDate}
              onChange={(e) => setConfig({ ...config, endDate: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            />
          </div>
        </div>

        {/* Summary */}
        {config.productIds.length > 0 && config.carrierIds.length > 0 && (
          <div className="mt-4 bg-blue-50 border border-blue-200 rounded-lg p-4">
            <h3 className="text-sm font-semibold text-blue-900 mb-2">Generation Summary</h3>
            <div className="text-sm text-blue-800 space-y-1">
              <p>• <strong>{config.productIds.length}</strong> product(s) × <strong>{config.carrierIds.length}</strong> carrier(s) = <strong>{config.productIds.length * config.carrierIds.length}</strong> combinations</p>
              <p>• <strong>{Math.floor(config.recordCount / (config.productIds.length * config.carrierIds.length))}</strong> records per combination</p>
              <p>• <strong>~{Math.floor(config.recordCount / (config.productIds.length * config.carrierIds.length)) * config.productIds.length * config.carrierIds.length}</strong> total records will be generated</p>
              <p>• Date range: <strong>{config.startDate}</strong> to <strong>{config.endDate}</strong></p>
            </div>
          </div>
        )}

        {/* Generate Button */}
        <div className="mt-6">
          <button
            onClick={generateRecords}
            disabled={generating || config.productIds.length === 0 || config.carrierIds.length === 0}
            className="w-full flex items-center justify-center gap-2 px-4 py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:bg-gray-300 disabled:cursor-not-allowed transition-colors"
          >
            {generating ? (
              <>
                <Loader className="h-5 w-5 animate-spin" />
                Generating... {progress}%
              </>
            ) : (
              <>
                <Play className="h-5 w-5" />
                Generate Records
              </>
            )}
          </button>
        </div>

        {/* Progress Bar */}
        {generating && (
          <div className="mt-4">
            <div className="w-full bg-gray-200 rounded-full h-2">
              <div
                className="bg-blue-600 h-2 rounded-full transition-all duration-300"
                style={{ width: `${progress}%` }}
              />
            </div>
          </div>
        )}

        {/* Result */}
        {result && (
          <div className="mt-4 bg-green-50 border border-green-200 rounded-lg p-4">
            <div className="flex items-center gap-2">
              <CheckCircle className="h-5 w-5 text-green-600" />
              <div>
                <p className="text-sm font-medium text-green-900">
                  Generation Complete
                </p>
                <p className="text-sm text-green-700 mt-1">
                  Successfully created {result.success} records
                  {result.failed > 0 && ` (${result.failed} failed)`}
                </p>
              </div>
            </div>
          </div>
        )}

        {/* Error */}
        {error && (
          <div className="mt-4 bg-red-50 border border-red-200 rounded-lg p-4">
            <div className="flex items-center gap-2">
              <AlertCircle className="h-5 w-5 text-red-600" />
              <div>
                <p className="text-sm font-medium text-red-900">Error</p>
                <p className="text-sm text-red-700 mt-1">{error}</p>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
