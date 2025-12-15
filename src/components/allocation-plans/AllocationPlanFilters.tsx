interface Props {
  filters: {
    planId: string
    carrierId: string
    productId: string
    originCityId: string
    destinationCityId: string
    originNodeId: string
    destinationNodeId: string
    startDate: string
    endDate: string
    status: string
    availabilityIssue: string
    tagId: string
  }
  plans: any[]
  carriers: any[]
  products: any[]
  cities: any[]
  nodes: any[]
  availabilityCounts: {
    unavailable: number
    unassigned: number
    inactive: number
    any_issue: number
  }
  onFilterChange: (key: string, value: string) => void
  onClearFilters: () => void
}

export function AllocationPlanFilters({
  filters,
  plans,
  carriers,
  products,
  cities,
  nodes,
  availabilityCounts,
  onFilterChange,
  onClearFilters,
}: Props) {
  const originNodes = filters.originCityId
    ? nodes.filter((n) => n.city_id === filters.originCityId)
    : nodes

  const destinationNodes = filters.destinationCityId
    ? nodes.filter((n) => n.city_id === filters.destinationCityId)
    : nodes

  return (
    <div className="bg-white rounded-lg shadow p-6 mb-6">
      <div className="flex items-center justify-between mb-4">
        <h3 className="text-lg font-medium">Filters</h3>
        <button
          onClick={onClearFilters}
          className="text-sm text-blue-600 hover:text-blue-800"
        >
          Clear All
        </button>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Plan */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Plan</label>
          <select
            value={filters.planId}
            onChange={(e) => onFilterChange('planId', e.target.value)}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          >
            <option value="">All Plans</option>
            {plans.map((plan) => (
              <option key={plan.id} value={plan.id}>
                {plan.plan_name}
              </option>
            ))}
          </select>
        </div>

        {/* Carrier */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Carrier</label>
          <select
            value={filters.carrierId}
            onChange={(e) => onFilterChange('carrierId', e.target.value)}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          >
            <option value="">All Carriers</option>
            {carriers.map((carrier) => (
              <option key={carrier.id} value={carrier.id}>
                {carrier.name}
              </option>
            ))}
          </select>
        </div>

        {/* Product */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Product</label>
          <select
            value={filters.productId}
            onChange={(e) => onFilterChange('productId', e.target.value)}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          >
            <option value="">All Products</option>
            {products.map((product) => (
              <option key={product.id} value={product.id}>
                {product.description}
              </option>
            ))}
          </select>
        </div>

        {/* Status */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Status</label>
          <select
            value={filters.status}
            onChange={(e) => onFilterChange('status', e.target.value)}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          >
            <option value="">All Status</option>
            <option value="pending">Pending</option>
            <option value="notified">Notified</option>
            <option value="sent">Sent</option>
            <option value="received">Received</option>
            <option value="cancelled">Cancelled</option>
            <option value="invalid">Invalid</option>
            <option value="transfer_error">Transfer Error</option>
          </select>
        </div>

        {/* Origin City */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Origin City</label>
          <select
            value={filters.originCityId}
            onChange={(e) => {
              onFilterChange('originCityId', e.target.value)
              onFilterChange('originNodeId', '') // Reset node when city changes
            }}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          >
            <option value="">All Cities</option>
            {cities.map((city) => (
              <option key={city.id} value={city.id}>
                {city.name}
              </option>
            ))}
          </select>
        </div>

        {/* Origin Node */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Origin Node</label>
          <select
            value={filters.originNodeId}
            onChange={(e) => onFilterChange('originNodeId', e.target.value)}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
            disabled={!filters.originCityId}
          >
            <option value="">All Nodes</option>
            {originNodes.map((node) => (
              <option key={node.id} value={node.id}>
                {node.auto_id}
              </option>
            ))}
          </select>
        </div>

        {/* Destination City */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Destination City
          </label>
          <select
            value={filters.destinationCityId}
            onChange={(e) => {
              onFilterChange('destinationCityId', e.target.value)
              onFilterChange('destinationNodeId', '') // Reset node when city changes
            }}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          >
            <option value="">All Cities</option>
            {cities.map((city) => (
              <option key={city.id} value={city.id}>
                {city.name}
              </option>
            ))}
          </select>
        </div>

        {/* Destination Node */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            Destination Node
          </label>
          <select
            value={filters.destinationNodeId}
            onChange={(e) => onFilterChange('destinationNodeId', e.target.value)}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
            disabled={!filters.destinationCityId}
          >
            <option value="">All Nodes</option>
            {destinationNodes.map((node) => (
              <option key={node.id} value={node.id}>
                {node.auto_id}
              </option>
            ))}
          </select>
        </div>

        {/* Start Date */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Start Date</label>
          <input
            type="date"
            value={filters.startDate}
            onChange={(e) => onFilterChange('startDate', e.target.value)}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          />
        </div>

        {/* End Date */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">End Date</label>
          <input
            type="date"
            value={filters.endDate}
            onChange={(e) => onFilterChange('endDate', e.target.value)}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          />
        </div>

        {/* Tag ID */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">Tag ID</label>
          <input
            type="text"
            value={filters.tagId}
            onChange={(e) => onFilterChange('tagId', e.target.value)}
            placeholder="Search by Tag ID..."
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          />
        </div>

        {/* Availability Issues */}
        <div>
          <label className="block text-sm font-medium text-gray-700 mb-1">
            <div className="flex items-center gap-2">
              <span>Availability Issues</span>
              {availabilityCounts.any_issue > 0 && (
                <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold bg-red-100 text-red-800 border border-red-300">
                  <span className="text-base">⚠</span>
                  {availabilityCounts.any_issue} issues
                </span>
              )}
            </div>
          </label>
          <select
            value={filters.availabilityIssue}
            onChange={(e) => onFilterChange('availabilityIssue', e.target.value)}
            className="w-full border border-gray-300 rounded-md px-3 py-2 text-sm"
          >
            <option value="">All Records</option>
            <option value="unavailable">⚠ Unavailable Panelists ({availabilityCounts.unavailable})</option>
            <option value="unassigned">Unassigned Panelists ({availabilityCounts.unassigned})</option>
            <option value="inactive">Inactive Panelists ({availabilityCounts.inactive})</option>
            <option value="any_issue">Any Issue ({availabilityCounts.any_issue})</option>
          </select>
        </div>
      </div>
    </div>
  )
}
