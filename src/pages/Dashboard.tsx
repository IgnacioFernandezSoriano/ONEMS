import React, { useMemo, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';

import { useAllocationPlanDetails } from '@/lib/hooks/useAllocationPlanDetails';
import { usePanelists } from '@/lib/hooks/usePanelists';
import { usePanelistUnavailability } from '@/lib/hooks/usePanelistUnavailability';
import { useCarriers } from '@/hooks/useCarriers';
import { useDeliveryStandards } from '@/hooks/useDeliveryStandards';
import { useStockAlerts } from '@/hooks/useStockAlerts';
import { useStockManagement } from '@/hooks/useStockManagement';
import { useRegulatorRequirements } from '@/hooks/useRegulatorRequirements';
import { useProposedShipments } from '@/hooks/useProposedShipments';
import { SmartTooltip } from '@/components/common/SmartTooltip';
import { useTranslation } from '@/hooks/useTranslation';
import { 
  AlertTriangle, 
  CheckCircle, 
  Clock, 
  Package, 
  Users,
  Truck,
  Calendar,
  AlertCircle,
  UserX,
  Box,
  ShoppingCart,
  Scale
} from 'lucide-react';

type PeriodOption = 'current_month' | 'next_month' | 'last_30_days' | 'last_60_days' | 'last_90_days';

interface PeriodConfig {
  label: string;
  startDate: string;
  endDate: string;
}

function getPeriodDates(period: PeriodOption): PeriodConfig {
  const today = new Date();
  const year = today.getFullYear();
  const month = today.getMonth();
  
  switch (period) {
    case 'current_month': {
      const start = new Date(year, month, 1);
      const end = new Date(year, month + 1, 0);
      return {
        label: `Current Month (${start.toLocaleString('default', { month: 'long' })} ${year})`,
        startDate: start.toISOString().split('T')[0],
        endDate: end.toISOString().split('T')[0]
      };
    }
    case 'next_month': {
      const start = new Date(year, month + 1, 1);
      const end = new Date(year, month + 2, 0);
      return {
        label: `Next Month (${start.toLocaleString('default', { month: 'long' })} ${start.getFullYear()})`,
        startDate: start.toISOString().split('T')[0],
        endDate: end.toISOString().split('T')[0]
      };
    }
    case 'last_30_days': {
      const start = new Date(today);
      start.setDate(today.getDate() - 30);
      return {
        label: 'Last 30 days',
        startDate: start.toISOString().split('T')[0],
        endDate: today.toISOString().split('T')[0]
      };
    }
    case 'last_60_days': {
      const start = new Date(today);
      start.setDate(today.getDate() - 60);
      return {
        label: 'Last 60 days',
        startDate: start.toISOString().split('T')[0],
        endDate: today.toISOString().split('T')[0]
      };
    }
    case 'last_90_days': {
      const start = new Date(today);
      start.setDate(today.getDate() - 90);
      return {
        label: 'Last 90 days',
        startDate: start.toISOString().split('T')[0],
        endDate: today.toISOString().split('T')[0]
      };
    }
  }
}

export function Dashboard() {
  const { t } = useTranslation();
  const { profile } = useAuth();
  const accountId = profile?.account_id || undefined;
  const navigate = useNavigate();
  
  const [selectedPeriod, setSelectedPeriod] = useState<PeriodOption>('current_month');
  const periodConfig = getPeriodDates(selectedPeriod);
  
  // Get allocation plans data
  const { details, loading: plansLoading } = useAllocationPlanDetails();

  // Get panelists data
  const { panelists, loading: panelistsLoading } = usePanelists();
  const { unavailabilityPeriods, loading: unavailabilityLoading } = usePanelistUnavailability();

  // Get carriers data
  const { carriers, products, loading: carriersLoading } = useCarriers();

  // Get delivery standards
  const { standards, loading: standardsLoading } = useDeliveryStandards();

  // Get stock data
  const { alerts: stockAlerts, loading: stockAlertsLoading } = useStockAlerts();
  const { shipments, loading: shipmentsLoading } = useStockManagement();

  // Get material requirements and purchase orders
  const { requirements: regulatorRequirements, loading: regulatorLoading } = useRegulatorRequirements();
  const { proposedShipments, loading: proposedLoading } = useProposedShipments();

  // Calculate panelist metrics
  const panelistMetrics = useMemo(() => {
    const activePanelists = panelists.filter(p => p.status === 'active').length;
    const inactivePanelists = panelists.filter(p => p.status === 'inactive').length;
    const total = panelists.length;

    // Calculate panelists on vacation TODAY
    const today = new Date().toISOString().split('T')[0];
    const onVacationToday = unavailabilityPeriods.filter(period => {
      const startDate = period.start_date;
      const endDate = period.end_date;
      return startDate <= today && endDate >= today;
    }).length;

    // Calculate upcoming vacations (next 30 days)
    const thirtyDaysFromNow = new Date();
    thirtyDaysFromNow.setDate(thirtyDaysFromNow.getDate() + 30);
    const thirtyDaysStr = thirtyDaysFromNow.toISOString().split('T')[0];
    
    const upcomingVacations = unavailabilityPeriods.filter(period => {
      const startDate = period.start_date;
      return startDate > today && startDate <= thirtyDaysStr;
    }).length;

    const availabilityRate = total > 0 ? ((total - onVacationToday) / total) * 100 : 100;

    return {
      total,
      active: activePanelists,
      inactive: inactivePanelists,
      onVacation: onVacationToday,
      upcomingVacations,
      availabilityRate
    };
  }, [panelists, unavailabilityPeriods]);

  // Calculate carrier and product metrics
  const carrierProductMetrics = useMemo(() => {
    const activeCarriers = carriers.filter(c => c.status === 'active').length;
    const totalCarriers = carriers.length;
    
    // Count active products from the products array
    const activeProductsCount = products.filter(p => p.status === 'active').length;

    return {
      activeCarriers,
      totalCarriers,
      activeProducts: activeProductsCount
    };
  }, [carriers, products]);

  // Calculate delivery standards metrics
  const standardsMetrics = useMemo(() => {
    const totalStandards = standards.length;
    const standardsWithoutTime = standards.filter((s: any) => !s.time || s.time === 0).length;
    const standardsWithoutPercentage = standards.filter((s: any) => !s.success_percentage || s.success_percentage === 0).length;
    const standardsNeedingReview = standardsWithoutTime + standardsWithoutPercentage;
    const coverageRate = totalStandards > 0 ? ((totalStandards - standardsNeedingReview) / totalStandards) * 100 : 0;

    return {
      totalStandards,
      coverageRate: Math.round(coverageRate),
      standardsNeedingReview
    };
  }, [standards]);

  // Calculate material metrics
  const materialMetrics = useMemo(() => {
    const pendingRequirements = regulatorRequirements.filter(r => r.status === 'pending').length;
    const pendingPurchaseOrders = regulatorRequirements.filter(r => r.status === 'ordered').length;
    const pendingMaterialShipments = proposedShipments.filter((s: any) => s.status === 'pending').length;
    
    return {
      pendingRequirements,
      pendingPurchaseOrders,
      pendingMaterialShipments
    };
  }, [regulatorRequirements, proposedShipments]);

  // Calculate stock alert counts
  const alertCounts = useMemo(() => {
    const regulatorAlerts = stockAlerts.filter((a: any) => a.location_type === 'regulator').length;
    const panelistAlerts = stockAlerts.filter((a: any) => a.location_type === 'panelist').length;
    const pendingShipments = shipments.filter(s => s.status === 'pending').length;
    
    return {
      regulator: regulatorAlerts,
      panelist: panelistAlerts,
      pendingShipments,
      total: regulatorAlerts + panelistAlerts
    };
  }, [stockAlerts, shipments]);

  // Calculate allocation plans metrics filtered by selected period
  const allocationMetrics = useMemo(() => {
    if (!details || details.length === 0) {
      return {
        total: 0,
        pending: 0,
        sent: 0,
        received: 0,
        availability: {
          unavailable: 0,
          unassigned: 0,
          inactive: 0,
          any_issue: 0
        },
        delayed: {
          pending: 0,
          sent: 0,
          cancelled: 0,
          invalid: 0,
          transfer_error: 0,
          total: 0
        }
      };
    }

    // Filter by selected period
    const filteredDetails = details.filter(detail => {
      const scheduledDate = detail.fecha_programada;
      if (!scheduledDate) return false;
      return scheduledDate >= periodConfig.startDate && scheduledDate <= periodConfig.endDate;
    });

    const total = filteredDetails.length;
    const pending = filteredDetails.filter(d => d.status === 'pending').length;
    const sent = filteredDetails.filter(d => d.status === 'sent').length;
    const received = filteredDetails.filter(d => d.status === 'received').length;

    // Calculate availability issues
    const unavailable = filteredDetails.filter(d => 
      d.origin_availability_status === 'unavailable' || d.destination_availability_status === 'unavailable'
    ).length;
    
    const unassigned = filteredDetails.filter(d => 
      d.origin_availability_status === 'unassigned' || d.destination_availability_status === 'unassigned'
    ).length;
    
    const inactive = filteredDetails.filter(d => 
      d.origin_panelist_status === 'inactive' || d.destination_panelist_status === 'inactive'
    ).length;

    // Only count REAL availability issues (unavailable or inactive panelists)
    // Do NOT count unassigned plans as critical issues
    const any_issue = filteredDetails.filter(d => 
      d.origin_availability_status === 'unavailable' ||
      d.destination_availability_status === 'unavailable' ||
      d.origin_panelist_status === 'inactive' ||
      d.destination_panelist_status === 'inactive'
    ).length;

    // Calculate delayed shipments (scheduled before today but not received)
    const today = new Date().toISOString().split('T')[0];
    const delayedDetails = filteredDetails.filter(d => {
      const scheduledDate = d.fecha_programada;
      return scheduledDate && scheduledDate < today && d.status !== 'received';
    });

    const delayed = {
      pending: delayedDetails.filter(d => d.status === 'pending').length,
      sent: delayedDetails.filter(d => d.status === 'sent').length,
      cancelled: delayedDetails.filter(d => d.status === 'cancelled').length,
      invalid: delayedDetails.filter(d => d.status === 'invalid').length,
      transfer_error: delayedDetails.filter(d => d.status === 'transfer_error').length,
      total: delayedDetails.length
    };

    const availability = {
      unavailable,
      unassigned,
      inactive,
      any_issue
    };

    return {
      total,
      pending,
      sent,
      received,
      availability,
      delayed
    };
  }, [details, periodConfig]);

  const loading = plansLoading || panelistsLoading || unavailabilityLoading || 
                  carriersLoading || standardsLoading || regulatorLoading || proposedLoading;

  // Handler to navigate to allocation plans with filter
  const navigateWithFilter = (filterType: string, filterValue: string) => {
    const params = new URLSearchParams();
    params.set(filterType, filterValue);
    navigate(`/allocation-plans?${params.toString()}`);
  };

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="text-gray-500">{t('dashboard.loading_dashboard')}</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <h1 className="text-2xl font-bold text-gray-900">{t('dashboard.management_dashboard')}</h1>
          <SmartTooltip content={t('dashboard.tooltip_management_dashboard')} />
        </div>
        
        {/* Period Selector */}
        <div className="flex items-center gap-3">
          <Calendar className="w-5 h-5 text-gray-400" />
          <select
            value={selectedPeriod}
            onChange={(e) => setSelectedPeriod(e.target.value as PeriodOption)}
            className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
          >
            <option value="current_month">{t('dashboard.current_month')}</option>
            <option value="next_month">{t('dashboard.next_month')}</option>
            <option value="last_30_days">{t('dashboard.last_30_days')}</option>
            <option value="last_60_days">{t('dashboard.last_60_days')}</option>
            <option value="last_90_days">{t('dashboard.last_90_days')}</option>
          </select>
        </div>
      </div>

      {/* Selected Period Info */}
      <div className="bg-blue-50 border border-blue-200 rounded-lg px-4 py-2 text-sm text-blue-800">
        <strong>{t('dashboard.selected_period')}:</strong> {periodConfig.label} ({periodConfig.startDate} to {periodConfig.endDate})
      </div>

      {/* Critical Alerts - Only show if there are real issues */}
      {(allocationMetrics.delayed.total > 0 || allocationMetrics.availability.any_issue > 0 || 
        alertCounts.total > 0 || panelistMetrics.onVacation > 0 || 
        materialMetrics.pendingRequirements > 0) && (
        <div className="bg-red-50 border-l-4 border-red-500 p-4 rounded-lg">
          <div className="flex items-start">
            <AlertTriangle className="w-6 h-6 text-red-500 mt-0.5 mr-3 flex-shrink-0" />
            <div className="flex-1">
              <h3 className="text-sm font-semibold text-red-900 mb-2">{t('dashboard.critical_alerts')}</h3>
              <div className="space-y-1 text-sm text-red-700">
                {allocationMetrics.delayed.total > 0 && (
                  <button
                    onClick={() => navigateWithFilter('endDate', 'yesterday')}
                    className="block hover:text-red-900 hover:underline text-left"
                  >
                    • <strong>{allocationMetrics.delayed.total}</strong> delayed shipments in selected period
                  </button>
                )}
                {allocationMetrics.availability.any_issue > 0 && (
                  <button
                    onClick={() => navigateWithFilter('availabilityIssue', 'any')}
                    className="block hover:text-red-900 hover:underline text-left"
                  >
                    • <strong>{allocationMetrics.availability.any_issue}</strong> plans with panelist availability issues
                  </button>
                )}
                {alertCounts.total > 0 && (
                  <Link to="/stock-management" className="block text-red-700 hover:text-red-900 hover:underline">
                    • <strong>{alertCounts.total}</strong> stock alerts ({alertCounts.regulator} regulator, {alertCounts.panelist} panelist)
                  </Link>
                )}
                {panelistMetrics.onVacation > 0 && (
                  <Link to="/panelists" className="block text-red-700 hover:text-red-900 hover:underline">
                    • <strong>{panelistMetrics.onVacation}</strong> panelists currently on vacation
                  </Link>
                )}
                {materialMetrics.pendingRequirements > 0 && (
                  <Link to="/stock-management" className="block text-red-700 hover:text-red-900 hover:underline">
                    • <strong>{materialMetrics.pendingRequirements}</strong> pending material requirements
                  </Link>
                )}
              </div>
            </div>
          </div>
        </div>
      )}

      {/* ALLOCATION PLANS SECTION - 2 unified cards */}
      <div>
        <div className="flex items-center gap-2 mb-4">
          <h2 className="text-xl font-semibold text-gray-900">{t('dashboard.allocation_plans')}</h2>
          <SmartTooltip content="Allocation Plans: Manage shipment assignments between panelists. Monitor pending plans, shipment status, availability issues, and delayed shipments in the selected period." />
        </div>
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* Total & Status Card */}
          <Link to="/allocation-plans" className="bg-white rounded-lg shadow p-6 hover:shadow-lg transition-shadow">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-gray-900">{t('dashboard.total_status')}</h3>
              <Package className="w-8 h-8 text-blue-400" />
            </div>
            <div className="space-y-4">
              <div className="flex justify-between items-center py-2 border-b border-gray-100">
                <div className="flex items-center gap-2">
                  <span className="text-gray-600">{t('dashboard.total_plans')}</span>
                  <SmartTooltip content={t('dashboard.tooltip_total_plans')} />
                </div>
                <span className="text-2xl font-bold text-gray-900">{allocationMetrics.total}</span>
              </div>
              <div className="flex justify-between items-center py-2 border-b border-gray-100">
                <div className="flex items-center gap-2">
                  <span className="text-orange-600">⏳ Pending</span>
                  <SmartTooltip content="Plans awaiting action (pending/notified status)" />
                </div>
                <span className="text-2xl font-bold text-orange-600">{allocationMetrics.pending}</span>
              </div>
              <div className="flex justify-between items-center py-2 border-b border-gray-100">
                <div className="flex items-center gap-2">
                  <span className="text-blue-600">📤 Sent</span>
                  <SmartTooltip content={t('dashboard.tooltip_sent_plans')} />
                </div>
                <span className="text-2xl font-bold text-blue-600">{allocationMetrics.sent}</span>
              </div>
              <div className="flex justify-between items-center py-2">
                <div className="flex items-center gap-2">
                  <span className="text-green-600">✓ Received</span>
                  <SmartTooltip content={t('dashboard.tooltip_received_plans')} />
                </div>
                <span className="text-2xl font-bold text-green-600">{allocationMetrics.received}</span>
              </div>
            </div>
          </Link>

          {/* Issues & Delays Card */}
          <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-gray-900">{t('dashboard.issues_delays')}</h3>
              <AlertTriangle className="w-8 h-8 text-red-400" />
            </div>
            <div className="space-y-4">
              <div className="flex justify-between items-center py-2 border-b border-gray-100">
                <div className="flex items-center gap-2">
                  <span className="text-gray-600">{t('dashboard.availability_issues')}</span>
                  <SmartTooltip content="Plans with panelist availability problems (unavailable, unassigned, inactive)" />
                </div>
                <button
                  onClick={() => navigateWithFilter('availabilityIssue', 'any')}
                  className="text-2xl font-bold text-red-600 hover:text-red-700"
                >
                  {allocationMetrics.availability.any_issue}
                </button>
              </div>
              <div className="pl-4 space-y-2 text-sm">
                <div className="flex justify-between items-center">
                  <span className="text-gray-500">⚠️ Unavailable</span>
                  <span className="font-semibold text-gray-700">{allocationMetrics.availability.unavailable}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-500">👤 No Panelist</span>
                  <span className="font-semibold text-gray-700">{allocationMetrics.availability.unassigned}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-500">✗ Inactive</span>
                  <span className="font-semibold text-gray-700">{allocationMetrics.availability.inactive}</span>
                </div>
              </div>
              
              <div className="flex justify-between items-center py-2 border-t border-gray-200 mt-4">
                <div className="flex items-center gap-2">
                  <span className="text-gray-600">{t('dashboard.delayed_shipments')}</span>
                  <SmartTooltip content={t('dashboard.tooltip_delayed_shipments')} />
                </div>
                <button
                  onClick={() => navigateWithFilter('endDate', 'yesterday')}
                  className="text-2xl font-bold text-orange-600 hover:text-orange-700"
                >
                  {allocationMetrics.delayed.total}
                </button>
              </div>
              <div className="pl-4 space-y-2 text-sm">
                <div className="flex justify-between items-center">
                  <span className="text-gray-500">⏳ Pending</span>
                  <span className="font-semibold text-gray-700">{allocationMetrics.delayed.pending}</span>
                </div>
                <div className="flex justify-between items-center">
                  <span className="text-gray-500">📤 Sent</span>
                  <span className="font-semibold text-gray-700">{allocationMetrics.delayed.sent}</span>
                </div>
                {(allocationMetrics.delayed.cancelled + allocationMetrics.delayed.invalid + allocationMetrics.delayed.transfer_error) > 0 && (
                  <>
                    <div className="flex justify-between items-center">
                      <span className="text-gray-500">✗ Cancelled</span>
                      <span className="font-semibold text-gray-700">{allocationMetrics.delayed.cancelled}</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-gray-500">⚠️ Invalid</span>
                      <span className="font-semibold text-gray-700">{allocationMetrics.delayed.invalid}</span>
                    </div>
                    <div className="flex justify-between items-center">
                      <span className="text-gray-500">🔄 Transfer Error</span>
                      <span className="font-semibold text-gray-700">{allocationMetrics.delayed.transfer_error}</span>
                    </div>
                  </>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* PANELISTS & AVAILABILITY SECTION - 1 unified card */}
      <div>
        <div className="flex items-center gap-2 mb-4">
          <h2 className="text-xl font-semibold text-gray-900">{t('dashboard.panelists_availability')}</h2>
          <SmartTooltip content="Panelists & Availability: Monitor panelist status and vacation periods. Track active/inactive panelists, current vacations, and upcoming unavailability to plan allocation assignments effectively." />
        </div>
        <Link to="/panelists" className="block bg-white rounded-lg shadow p-6 hover:shadow-lg transition-shadow">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900">{t('dashboard.panelist_status')}</h3>
            <Users className="w-8 h-8 text-gray-400" />
          </div>
          <div className="grid grid-cols-2 lg:grid-cols-4 gap-6">
            <div>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-gray-600">{t('dashboard.total_panelists')}</p>
                <SmartTooltip content={t('dashboard.tooltip_total_panelists')} />
              </div>
              <p className="text-3xl font-bold text-gray-900">{panelistMetrics.total}</p>
              <div className="flex gap-3 mt-2 text-xs">
                <span className="text-green-600">✓ {panelistMetrics.active} {t('dashboard.active_lowercase')}</span>
                <span className="text-gray-500">✗ {panelistMetrics.inactive} {t('dashboard.inactive_lowercase')}</span>
              </div>
            </div>

            <div className={panelistMetrics.onVacation > 0 ? "border-l-4 border-red-500 pl-4" : ""}>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-red-600">{t('dashboard.on_vacation')}</p>
                <SmartTooltip content="Panelists currently unavailable (vacation period includes today)" />
              </div>
              <p className="text-3xl font-bold text-red-600">{panelistMetrics.onVacation}</p>
              <p className="text-xs text-gray-500 mt-2">{t('dashboard.currently_unavailable')}</p>
            </div>

            <div className={panelistMetrics.upcomingVacations > 0 ? "border-l-4 border-yellow-500 pl-4" : ""}>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-yellow-600">{t('dashboard.upcoming_vacations')}</p>
                <SmartTooltip content="Panelists with vacation periods starting in the next 30 days" />
              </div>
              <p className="text-3xl font-bold text-yellow-600">{panelistMetrics.upcomingVacations}</p>
              <p className="text-xs text-gray-500 mt-2">{t('dashboard.next_30_days')}</p>
            </div>

            <div>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-blue-600">{t('dashboard.availability_rate')}</p>
                <SmartTooltip content="Percentage of panelists currently available (not on vacation)" />
              </div>
              <p className="text-3xl font-bold text-blue-600">{panelistMetrics.availabilityRate.toFixed(1)}%</p>
              <p className="text-xs text-gray-500 mt-2">{panelistMetrics.total - panelistMetrics.onVacation} {t('dashboard.of')} {panelistMetrics.total} {t('dashboard.available')}</p>
            </div>
          </div>
        </Link>
      </div>

      {/* CARRIERS & PRODUCTS SECTION - 1 unified card */}
      <div>
        <div className="flex items-center gap-2 mb-4">
          <h2 className="text-xl font-semibold text-gray-900">{t('carriers.carriers_products')}</h2>
          <SmartTooltip content="Carriers & Products: Monitor active carriers and products. Track available carrier-product combinations for routing and allocation planning." />
        </div>
        <Link to="/carriers" className="block bg-white rounded-lg shadow p-6 hover:shadow-lg transition-shadow">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900">{t('dashboard.active_resources')}</h3>
            <Truck className="w-8 h-8 text-gray-400" />
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-gray-600">{t('dashboard.active_carriers')}</p>
                <SmartTooltip content={t('dashboard.tooltip_active_carriers')} />
              </div>
              <p className="text-3xl font-bold text-gray-900">{carrierProductMetrics.activeCarriers}</p>
              <p className="text-xs text-gray-500 mt-2">{t('dashboard.of')} {carrierProductMetrics.totalCarriers} {t('dashboard.total')}</p>
            </div>

            <div>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-gray-600">{t('dashboard.active_products')}</p>
                <SmartTooltip content={t('dashboard.tooltip_active_products')} />
              </div>
              <p className="text-3xl font-bold text-gray-900">{carrierProductMetrics.activeProducts}</p>
              <p className="text-xs text-gray-500 mt-2">of 1 total</p>
            </div>

            <div>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-blue-600">{t('dashboard.carrier_product_pairs')}</p>
                <SmartTooltip content="Total number of carrier-product combinations available for routing" />
              </div>
              <p className="text-3xl font-bold text-blue-600">
                {carrierProductMetrics.activeCarriers * carrierProductMetrics.activeProducts}
              </p>
              <p className="text-xs text-gray-500 mt-2">{t('dashboard.available_combinations')}</p>
            </div>
          </div>
        </Link>
      </div>

      {/* MATERIAL MANAGEMENT & STOCK SECTION - 2 cards side by side */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Material Management Card */}
        <div>
          <div className="flex items-center gap-2 mb-4">
            <h2 className="text-xl font-semibold text-gray-900">{t('dashboard.material_management')}</h2>
            <SmartTooltip content="Material Management: Track material requirements, purchase orders, and shipments to panelists. Monitor pending items to ensure timely material availability." />
          </div>
          <Link to="/stock-management" className="block bg-white rounded-lg shadow p-6 hover:shadow-lg transition-shadow">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-gray-900">{t('dashboard.pending_items')}</h3>
              <ShoppingCart className="w-8 h-8 text-gray-400" />
            </div>
            <div className="space-y-4">
              <div className={materialMetrics.pendingRequirements > 0 ? "flex justify-between items-center py-2 border-l-4 border-yellow-500 pl-4" : "flex justify-between items-center py-2"}>
                <div className="flex items-center gap-2">
                  <span className="text-yellow-600">{t('dashboard.material_requirements')}</span>
                  <SmartTooltip content={t('dashboard.tooltip_material_requirements')} />
                </div>
                <span className="text-2xl font-bold text-yellow-600">{materialMetrics.pendingRequirements}</span>
              </div>
              
              <div className="flex justify-between items-center py-2 border-l-4 border-blue-500 pl-4">
                <div className="flex items-center gap-2">
                  <span className="text-blue-600">{t('dashboard.purchase_orders')}</span>
                  <SmartTooltip content="Purchase orders placed with suppliers (ordered status)" />
                </div>
                <span className="text-2xl font-bold text-blue-600">{materialMetrics.pendingPurchaseOrders}</span>
              </div>
              
              <div className="flex justify-between items-center py-2 border-l-4 border-purple-500 pl-4">
                <div className="flex items-center gap-2">
                  <span className="text-purple-600">{t('dashboard.shipments_to_panelists')}</span>
                  <SmartTooltip content={t('dashboard.tooltip_shipments_to_panelists')} />
                </div>
                <span className="text-2xl font-bold text-purple-600">{materialMetrics.pendingMaterialShipments}</span>
              </div>
            </div>
          </Link>
        </div>

        {/* Stock Alerts Card */}
        <div>
          <div className="flex items-center gap-2 mb-4">
            <h2 className="text-xl font-semibold text-gray-900">{t('dashboard.stock_alerts')}</h2>
            <SmartTooltip content="Stock Alerts: Monitor stock levels and alerts for regulator and panelist locations. Address alerts promptly to avoid shipment delays." />
          </div>
          <Link to="/stock-management" className="block bg-white rounded-lg shadow p-6 hover:shadow-lg transition-shadow">
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-lg font-semibold text-gray-900">{t('dashboard.current_alerts')}</h3>
              <Box className="w-8 h-8 text-gray-400" />
            </div>
            <div className="space-y-4">
              <div className={alertCounts.regulator > 0 ? "flex justify-between items-center py-2 border-l-4 border-red-500 pl-4" : "flex justify-between items-center py-2"}>
                <div className="flex items-center gap-2">
                  <span className="text-red-600">{t('dashboard.regulator_stock')}</span>
                  <SmartTooltip content="Stock alerts in regulator (HAL) warehouse" />
                </div>
                <span className="text-2xl font-bold text-red-600">{alertCounts.regulator}</span>
              </div>
              
              <div className={alertCounts.panelist > 0 ? "flex justify-between items-center py-2 border-l-4 border-orange-500 pl-4" : "flex justify-between items-center py-2"}>
                <div className="flex items-center gap-2">
                  <span className="text-orange-600">{t('dashboard.panelist_stock')}</span>
                  <SmartTooltip content={t('dashboard.tooltip_panelist_stock')} />
                </div>
                <span className="text-2xl font-bold text-orange-600">{alertCounts.panelist}</span>
              </div>
              
              <div className="flex justify-between items-center py-2 border-l-4 border-yellow-500 pl-4">
                <div className="flex items-center gap-2">
                  <span className="text-yellow-600">{t('dashboard.pending_shipments')}</span>
                  <SmartTooltip content={t('dashboard.tooltip_pending_shipments')} />
                </div>
                <span className="text-2xl font-bold text-yellow-600">{alertCounts.pendingShipments}</span>
              </div>
            </div>
          </Link>
        </div>
      </div>

      {/* DELIVERY STANDARDS SECTION - 1 unified card */}
      <div>
        <div className="flex items-center gap-2 mb-4">
          <h2 className="text-xl font-semibold text-gray-900">{t('dashboard.delivery_standards')}</h2>
          <SmartTooltip content="Delivery Standards: Monitor configured delivery standards and coverage. Ensure all routes have complete standards (time and success percentage) for accurate compliance tracking." />
        </div>
        <Link to="/delivery-standards" className="block bg-white rounded-lg shadow p-6 hover:shadow-lg transition-shadow">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-gray-900">{t('dashboard.standards_configuration')}</h3>
            <Scale className="w-8 h-8 text-gray-400" />
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
            <div>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-gray-600">{t('dashboard.total_standards')}</p>
                <SmartTooltip content={t('dashboard.tooltip_total_standards')} />
              </div>
              <p className="text-3xl font-bold text-gray-900">{standardsMetrics.totalStandards}</p>
              <p className="text-xs text-gray-500 mt-2">Configured routes</p>
            </div>

            <div className={standardsMetrics.standardsNeedingReview > 0 ? "border-l-4 border-yellow-500 pl-4" : ""}>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-yellow-600">Needing Review</p>
                <SmartTooltip content={t('dashboard.tooltip_needs_review')} />
              </div>
              <p className="text-3xl font-bold text-yellow-600">{standardsMetrics.standardsNeedingReview}</p>
              <p className="text-xs text-gray-500 mt-2">Incomplete standards</p>
            </div>

            <div>
              <div className="flex items-center gap-2 mb-2">
                <p className="text-sm font-medium text-blue-600">{t('dashboard.coverage_rate')}</p>
                <SmartTooltip content={t('dashboard.tooltip_coverage_rate')} />
              </div>
              <p className="text-3xl font-bold text-blue-600">{standardsMetrics.coverageRate}%</p>
              <p className="text-xs text-gray-500 mt-2">{standardsMetrics.totalStandards - standardsMetrics.standardsNeedingReview} complete</p>
            </div>
          </div>
        </Link>
      </div>

      {/* Management Tip */}
      <div className="bg-blue-50 border-l-4 border-blue-500 p-4 rounded-lg">
        <div className="flex items-start">
          <AlertCircle className="w-5 h-5 text-blue-500 mt-0.5 mr-3 flex-shrink-0" />
          <div>
            <h3 className="text-sm font-semibold text-blue-900">{t('dashboard.management_tip')}</h3>
            <p className="text-sm text-blue-800 mt-1">
              {t('dashboard.management_tip_text')}
            </p>
          </div>
        </div>
      </div>
    </div>
  );
}
