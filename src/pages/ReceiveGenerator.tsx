import { useState, useEffect } from 'react'
import { Play, AlertCircle, CheckCircle, Loader } from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../contexts/AuthContext'

interface GeneratorConfig {
  recordCount: number
  outOfSlaPercentage: number
  advanceVarianceDays: number
  delayVarianceDays: number
  productId: string
  carrierId: string
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
    productId: '',
    carrierId: '',
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

  // Load delivery standard when product changes
  useEffect(() => {
    if (config.productId && accountId) {
      supabase
        .from('delivery_standards')
        .select('standard_days')
        .eq('account_id', accountId)
        .eq('product_id', config.productId)
        .maybeSingle()
        .then(({ data }) => {
          setDeliveryStandard(data?.standard_days || null)
        })
    } else {
      setDeliveryStandard(null)
    }
  }, [config.productId, accountId])

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

      // Load panelists
      const { data: panelistsData } = await supabase
        .from('panelists')
        .select('id, name, panelist_code, city_id')
        .eq('account_id', accountId)
        .order('name')

      setPanelists(panelistsData || [])
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
    if (!accountId || !config.productId) {
      setError('Please select a product')
      return
    }

    setGenerating(true)
    setProgress(0)
    setResult(null)
    setError(null)

    try {
      // Get delivery standard for the product
      const { data: deliveryStandard } = await supabase
        .from('delivery_standards')
        .select('standard_days')
        .eq('account_id', accountId)
        .eq('product_id', config.productId)
        .maybeSingle()

      const standardDays = deliveryStandard?.standard_days || 3

      const records = []
      const startDate = new Date(config.startDate)
      const endDate = new Date(config.endDate)

      // Determine how many records should be out of SLA
      const outOfSlaCount = Math.floor(config.recordCount * (config.outOfSlaPercentage / 100))

      for (let i = 0; i < config.recordCount; i++) {
        const isOutOfSla = i < outOfSlaCount

        // Random origin and destination
        const originCity = getRandomElement(cities)
        const destCity = getRandomElement(cities.filter(c => c.id !== originCity.id))
        
        const originNodesFiltered = nodes.filter(n => n.city_id === originCity.id)
        const destNodesFiltered = nodes.filter(n => n.city_id === destCity.id)
        
        if (originNodesFiltered.length === 0 || destNodesFiltered.length === 0) continue

        const originNode = getRandomElement(originNodesFiltered)
        const destNode = getRandomElement(destNodesFiltered)

        // Random panelists
        const originPanelistsFiltered = panelists.filter(p => p.city_id === originCity.id)
        const destPanelistsFiltered = panelists.filter(p => p.city_id === destCity.id)

        if (originPanelistsFiltered.length === 0 || destPanelistsFiltered.length === 0) continue

        const originPanelist = getRandomElement(originPanelistsFiltered)
        const destPanelist = getRandomElement(destPanelistsFiltered)

        // Random dates
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
          product_id: config.productId,
          carrier_id: config.carrierId || getRandomElement(carriers).id,
          origin_city_id: originCity.id,
          origin_node_id: originNode.id,
          origin_panelist_id: originPanelist.id,
          destination_city_id: destCity.id,
          destination_node_id: destNode.id,
          destination_panelist_id: destPanelist.id,
          shipment_date: shipmentDate.toISOString().split('T')[0],
          receive_date: receiveDate.toISOString().split('T')[0],
          status: 'pending_validation'
        }

        records.push(record)

        // Update progress
        setProgress(Math.floor(((i + 1) / config.recordCount) * 50))
      }

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
              value={config.advanceVarianceDays}
              onChange={(e) => setConfig({ ...config, advanceVarianceDays: parseInt(e.target.value) || 0 })}
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
              value={config.delayVarianceDays}
              onChange={(e) => setConfig({ ...config, delayVarianceDays: parseInt(e.target.value) || 0 })}
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

          {/* Product */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Product <span className="text-red-500">*</span>
            </label>
            <select
              value={config.productId}
              onChange={(e) => setConfig({ ...config, productId: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="">Select Product</option>
              {products.map((product) => (
                <option key={product.id} value={product.id}>
                  {product.code} - {product.description}
                </option>
              ))}
            </select>
          </div>

          {/* Carrier */}
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Carrier (optional)
            </label>
            <select
              value={config.carrierId}
              onChange={(e) => setConfig({ ...config, carrierId: e.target.value })}
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
            >
              <option value="">Random Carrier</option>
              {carriers.map((carrier) => (
                <option key={carrier.id} value={carrier.id}>
                  {carrier.name}
                </option>
              ))}
            </select>
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

        {/* Generate Button */}
        <div className="mt-6">
          <button
            onClick={generateRecords}
            disabled={generating || !config.productId}
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
