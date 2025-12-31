import React, { useState } from 'react';
import { Filter, RotateCcw } from 'lucide-react';
import { SmartTooltip } from '../common/SmartTooltip';

import { useTranslation } from '@/hooks/useTranslation';
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
    eventId: string
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
  const { t } = useTranslation();
  const [isExpanded, setIsExpanded] = useState(false);

  const originNodes = filters.originCityId
    ? nodes.filter((n) => n.city_id === filters.originCityId)
    : nodes;

  const destinationNodes = filters.destinationCityId
    ? nodes.filter((n) => n.city_id === filters.destinationCityId)
    : nodes;

  const activeFilterCount = Object.values(filters).filter(
    (v) => v !== undefined && v !== null && v !== ''
  ).length;

  const clearFilters = () => {
    onClearFilters();
  };

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200">
      {/* Header */}
      <button
        onClick={() => setIsExpanded(!isExpanded)}
        className="w-full px-6 py-4 flex items-center justify-between hover:bg-gray-50 transition-colors"
      >
        <div className="flex items-center gap-3">
          <Filter className="w-5 h-5 text-gray-400" />
          <span className="font-medium text-gray-900">{t('stock.filters')}</span>
          <SmartTooltip content="Filter allocation plan details by plan, carrier, product, route, dates, status, or availability issues to focus on specific shipments." />
          {activeFilterCount > 0 && (
            <span className="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-medium rounded-full">
              {activeFilterCount} Active
            </span>
          )}
        </div>
        <div className="flex items-center gap-3">
          {activeFilterCount > 0 && (
            <button
              onClick={(e) => {
                e.stopPropagation();
                clearFilters();
              }}
              className="flex items-center gap-2 px-3 py-1.5 text-sm text-gray-700 hover:text-gray-900 transition-colors"
              title="Reset filters"
            >
              <RotateCcw className="w-4 h-4" />
              Reset
            </button>
          )}
          <span className="text-gray-400">{isExpanded ? '▲' : '▼'}</span>
        </div>
      </button>

      {/* Filter Content */}
      {isExpanded && (
        <div className="px-6 pb-6 border-t border-gray-200">
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mt-4">
            {/* Plan */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📋</span>
                Plan
                <SmartTooltip content="Filter by allocation plan name. Shows only shipments belonging to the selected plan." />
              </label>
              <select
                value={filters.planId}
                onChange={(e) => onFilterChange('planId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
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
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🚚</span>
                Carrier
                <SmartTooltip content="Filter by logistics carrier. Shows only shipments for the selected carrier." />
              </label>
              <select
                value={filters.carrierId}
                onChange={(e) => onFilterChange('carrierId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
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
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📦</span>
                Product
                <SmartTooltip content="Filter by carrier product/service type. Shows only shipments for the selected product." />
              </label>
              <select
                value={filters.productId}
                onChange={(e) => onFilterChange('productId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
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
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🔵</span>
                Status
                <SmartTooltip content="Filter by shipment status: Pending (not started), Sent (dispatched), Received (delivered), Cancelled, etc." />
              </label>
              <select
                value={filters.status}
                onChange={(e) => onFilterChange('status', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">All Status</option>
                <option value="pending">{t('stock.pending')}</option>
                <option value="notified">{t('allocation_plans.notified')}</option>
                <option value="sent">{t('stock.sent')}</option>
                <option value="received">{t('stock.received')}</option>
                <option value="cancelled">{t('stock.cancelled')}</option>
                <option value="invalid">{t('allocation_plans.invalid')}</option>
                <option value="transfer_error">Transfer Error</option>
              </select>
            </div>

            {/* Origin City */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📍</span>
                Origin City
                <SmartTooltip content="Filter by origin city (where packages are picked up). Shows only routes starting from the selected city." />
              </label>
              <select
                value={filters.originCityId}
                onChange={(e) => {
                  onFilterChange('originCityId', e.target.value);
                  onFilterChange('originNodeId', '');
                }}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
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
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📤</span>
                Origin Node
                <SmartTooltip content="Filter by specific origin node within the selected city. Requires origin city to be selected first." />
              </label>
              <select
                value={filters.originNodeId}
                onChange={(e) => onFilterChange('originNodeId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100 disabled:cursor-not-allowed"
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
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🎯</span>
                Destination City
                <SmartTooltip content="Filter by destination city (where packages are delivered). Shows only routes ending in the selected city." />
              </label>
              <select
                value={filters.destinationCityId}
                onChange={(e) => {
                  onFilterChange('destinationCityId', e.target.value);
                  onFilterChange('destinationNodeId', '');
                }}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
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
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📥</span>
                Destination Node
                <SmartTooltip content="Filter by specific destination node within the selected city. Requires destination city to be selected first." />
              </label>
              <select
                value={filters.destinationNodeId}
                onChange={(e) => onFilterChange('destinationNodeId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100 disabled:cursor-not-allowed"
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
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📅</span>
                Start Date
                <SmartTooltip content="Filter shipments scheduled on or after this date. Combine with End Date for date range filtering." />
              </label>
              <input
                type="date"
                value={filters.startDate}
                onChange={(e) => onFilterChange('startDate', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {/* End Date */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📅</span>
                End Date
                <SmartTooltip content="Filter shipments scheduled on or before this date. Combine with Start Date for date range filtering." />
              </label>
              <input
                type="date"
                value={filters.endDate}
                onChange={(e) => onFilterChange('endDate', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {/* Tag ID */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🏷️</span>
                Tag ID
                <SmartTooltip content="Search by physical tag identifier. Finds shipments with matching tag IDs (partial match supported)." />
              </label>
              <input
                type="text"
                value={filters.tagId}
                onChange={(e) => onFilterChange('tagId', e.target.value)}
                placeholder="Search by Tag ID..."
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {/* Event ID */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🔑</span>
                Event ID
                <SmartTooltip content="Search by allocation plan detail event ID. Useful for tracking specific shipment records in material movements (partial match supported)." />
              </label>
              <input
                type="text"
                value={filters.eventId}
                onChange={(e) => onFilterChange('eventId', e.target.value)}
                placeholder="Search by Event ID..."
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {/* Availability Issues */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>⚠️</span>
                Availability Issues
                <SmartTooltip content="Filter by panelist availability problems: Unavailable (not available on date), Unassigned (no panelist assigned), Inactive (panelist inactive)." />
              </label>
              <select
                value={filters.availabilityIssue}
                onChange={(e) => onFilterChange('availabilityIssue', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">All Records</option>
                <option value="unavailable">⚠ Unavailable ({availabilityCounts.unavailable})</option>
                <option value="unassigned">Unassigned ({availabilityCounts.unassigned})</option>
                <option value="inactive">Inactive ({availabilityCounts.inactive})</option>
                <option value="any_issue">Any Issue ({availabilityCounts.any_issue})</option>
              </select>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
