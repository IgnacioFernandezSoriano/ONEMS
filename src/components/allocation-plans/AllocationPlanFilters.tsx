import React, { useState } from 'react';
import { Filter, RotateCcw } from 'lucide-react';
import { SmartTooltip } from '../common/SmartTooltip';

import { useTranslation } from '@/hooks/useTranslation';
interface Props {
  filters: {
    planId: string
    carrierId: string
    productId: string
    panelistId: string
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
  panelists: any[]
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
  panelists,
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
          <SmartTooltip content={t('allocation_plans.tt_filter_header')} />
          {activeFilterCount > 0 && (
            <span className="px-2 py-1 bg-blue-100 text-blue-700 text-xs font-medium rounded-full">
              {t('allocation_plans.active_filters').replace('{count}', String(activeFilterCount))}
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
              title={t('allocation_plans.reset_filters')}
            >
              <RotateCcw className="w-4 h-4" />
              {t('common.reset')}
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
                {t('allocation_plans.plan')}
                <SmartTooltip content={t('allocation_plans.tt_plan')} />
              </label>
              <select
                value={filters.planId}
                onChange={(e) => onFilterChange('planId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('allocation_plans.all_plans')}</option>
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
                {t('allocation_plans.carrier')}
                <SmartTooltip content={t('allocation_plans.tt_carrier')} />
              </label>
              <select
                value={filters.carrierId}
                onChange={(e) => onFilterChange('carrierId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('allocation_plans.all_carriers')}</option>
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
                {t('allocation_plans.product')}
                <SmartTooltip content={t('allocation_plans.tt_product')} />
              </label>
              <select
                value={filters.productId}
                onChange={(e) => onFilterChange('productId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('allocation_plans.all_products')}</option>
                {products.map((product) => (
                  <option key={product.id} value={product.id}>
                    {product.description}
                  </option>
                ))}
              </select>
            </div>

            {/* Panelist (origin or destination) */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>👤</span>
                {t('allocation_plans.panelist_filter')}
                <SmartTooltip content={t('allocation_plans.tt_panelist')} />
              </label>
              <select
                value={filters.panelistId}
                onChange={(e) => onFilterChange('panelistId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('allocation_plans.all_panelists')}</option>
                {panelists.map((panelist) => (
                  <option key={panelist.id} value={panelist.id}>
                    {panelist.name}
                  </option>
                ))}
              </select>
            </div>

            {/* Status */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🔵</span>
                {t('allocation_plans.status')}
                <SmartTooltip content={t('allocation_plans.tt_status')} />
              </label>
              <select
                value={filters.status}
                onChange={(e) => onFilterChange('status', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('allocation_plans.all_status')}</option>
                <option value="pending">{t('stock.pending')}</option>
                <option value="notified">{t('allocation_plans.notified')}</option>
                <option value="sent">{t('stock.sent')}</option>
                <option value="received">{t('stock.received')}</option>
                <option value="cancelled">{t('stock.cancelled')}</option>
                <option value="invalid">{t('allocation_plans.invalid')}</option>
                <option value="transfer_error">{t('allocation_plans.transfer_error')}</option>
              </select>
            </div>

            {/* Origin City */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>📍</span>
                {t('allocation_plans.origin_city')}
                <SmartTooltip content={t('allocation_plans.tt_origin_city')} />
              </label>
              <select
                value={filters.originCityId}
                onChange={(e) => {
                  onFilterChange('originCityId', e.target.value);
                  onFilterChange('originNodeId', '');
                }}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('allocation_plans.all_cities')}</option>
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
                {t('allocation_plans.origin_node')}
                <SmartTooltip content={t('allocation_plans.tt_origin_node')} />
              </label>
              <select
                value={filters.originNodeId}
                onChange={(e) => onFilterChange('originNodeId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100 disabled:cursor-not-allowed"
                disabled={!filters.originCityId}
              >
                <option value="">{t('allocation_plans.all_nodes')}</option>
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
                {t('allocation_plans.destination_city')}
                <SmartTooltip content={t('allocation_plans.tt_dest_city')} />
              </label>
              <select
                value={filters.destinationCityId}
                onChange={(e) => {
                  onFilterChange('destinationCityId', e.target.value);
                  onFilterChange('destinationNodeId', '');
                }}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('allocation_plans.all_cities')}</option>
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
                {t('allocation_plans.destination_node')}
                <SmartTooltip content={t('allocation_plans.tt_dest_node')} />
              </label>
              <select
                value={filters.destinationNodeId}
                onChange={(e) => onFilterChange('destinationNodeId', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:bg-gray-100 disabled:cursor-not-allowed"
                disabled={!filters.destinationCityId}
              >
                <option value="">{t('allocation_plans.all_nodes')}</option>
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
                {t('allocation_plans.start_date')}
                <SmartTooltip content={t('allocation_plans.tt_start_date')} />
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
                {t('allocation_plans.end_date')}
                <SmartTooltip content={t('allocation_plans.tt_end_date')} />
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
                {t('allocation_plans.tag_id')}
                <SmartTooltip content={t('allocation_plans.tt_tag_id')} />
              </label>
              <input
                type="text"
                value={filters.tagId}
                onChange={(e) => onFilterChange('tagId', e.target.value)}
                placeholder={t('allocation_plans.search_by_tag_id')}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {/* Event ID */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>🔑</span>
                {t('allocation_plans.event_id')}
                <SmartTooltip content={t('allocation_plans.tt_event_id')} />
              </label>
              <input
                type="text"
                value={filters.eventId}
                onChange={(e) => onFilterChange('eventId', e.target.value)}
                placeholder={t('allocation_plans.search_by_event_id')}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              />
            </div>

            {/* Availability Issues */}
            <div>
              <label className="flex items-center gap-2 text-sm font-medium text-gray-700 mb-2">
                <span>⚠️</span>
                {t('allocation_plans.availability_issues')}
                <SmartTooltip content={t('allocation_plans.tt_availability')} />
              </label>
              <select
                value={filters.availabilityIssue}
                onChange={(e) => onFilterChange('availabilityIssue', e.target.value)}
                className="w-full px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-transparent"
              >
                <option value="">{t('allocation_plans.all_records')}</option>
                <option value="unavailable">⚠ {t('allocation_plans.unavailable')} ({availabilityCounts.unavailable})</option>
                <option value="unassigned">{t('allocation_plans.unassigned')} ({availabilityCounts.unassigned})</option>
                <option value="inactive">{t('allocation_plans.inactive')} ({availabilityCounts.inactive})</option>
                <option value="any_issue">{t('allocation_plans.any_issue')} ({availabilityCounts.any_issue})</option>
              </select>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
