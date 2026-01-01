import React, { useState, useMemo } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { useOneDB, OneDBFilters as Filters } from '../hooks/useOneDB';
import { OneDBFilters } from '../components/OneDB/OneDBFilters';
import { OneDBTable } from '../components/OneDB/OneDBTable';
import { OneDBBulkPanel } from '../components/OneDB/OneDBBulkPanel';
import { Database, CheckCircle, XCircle, Clock } from 'lucide-react';
import { SmartTooltip } from '../components/common/SmartTooltip';

import { useTranslation } from '@/hooks/useTranslation';
export default function OneDB() {
  const { t } = useTranslation();
  const { user, profile } = useAuth();
  const { records, filteredRecords, loading, error, refetch, applyFilters, exportToCSV } =
    useOneDB(profile?.account_id || undefined);

  const [selectedRecords, setSelectedRecords] = useState<string[]>([]);

  const handleSelectRecord = (id: string) => {
    setSelectedRecords((prev) =>
      prev.includes(id) ? prev.filter((recordId) => recordId !== id) : [...prev, id]
    );
  };

  const handleSelectAll = () => {
    if (selectedRecords.length === filteredRecords.length) {
      setSelectedRecords([]);
    } else {
      setSelectedRecords(filteredRecords.map((r) => r.id));
    }
  };

  const handleExport = () => {
    const recordsToExport = filteredRecords.filter((r) => selectedRecords.includes(r.id));
    exportToCSV(recordsToExport);
  };

  const handleClearSelection = () => {
    setSelectedRecords([]);
  };

  const handleFilterChange = (filters: Filters) => {
    applyFilters(filters);
    setSelectedRecords([]); // Clear selection when filters change
  };

  // Calculate KPIs (must be before early returns to follow hooks rules)
  const kpis = useMemo(() => {
    const total = filteredRecords.length;
    const onTime = filteredRecords.filter(r => r.on_time_delivery === true).length;
    const delayed = filteredRecords.filter(r => r.on_time_delivery === false).length;
    const avgTransitDays = total > 0
      ? (filteredRecords.reduce((sum, r) => sum + (r.total_transit_days || 0), 0) / total).toFixed(1)
      : '0.0';
    
    return { total, onTime, delayed, avgTransitDays };
  }, [filteredRecords]);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex items-center gap-3 text-gray-600">
          <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-gray-600"></div>
          <span>{t('onedb.loading_records')}</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-4">
        <p className="text-red-700">Error loading records: {error}</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-3 bg-blue-50 rounded-lg">
            <Database className="w-8 h-8 text-blue-600" />
          </div>
          <div>
            <div className="flex items-center gap-2">
              <h1 className="text-2xl font-bold text-gray-900">ONE DB</h1>
              <SmartTooltip content="ONE DB stores all validated shipment records with complete transit information, delivery performance metrics, and quality analytics for reporting and compliance tracking." />
            </div>
            <p className="text-sm text-gray-600 mt-1">
              {t('onedb.validated_postal_quality_analytics_repository')}
            </p>
          </div>
        </div>
      </div>

      {/* KPI Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {/* Total Records */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('onedb.total_records')}</p>
              <p className="text-3xl font-bold text-gray-900">{kpis.total}</p>
              <p className="text-xs text-gray-500 mt-1">{t('onedb.all_shipment_records')}</p>
            </div>
            <div className="p-3 bg-blue-50 rounded-lg">
              <Database className="w-6 h-6 text-blue-600" />
            </div>
          </div>
        </div>

        {/* On-Time Deliveries */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('onedb.on_time')}</p>
              <p className="text-3xl font-bold text-green-600">{kpis.onTime}</p>
              <p className="text-xs text-gray-500 mt-1">{t('onedb.met_delivery_standard')}</p>
            </div>
            <div className="p-3 bg-green-50 rounded-lg">
              <CheckCircle className="w-6 h-6 text-green-600" />
            </div>
          </div>
        </div>

        {/* Delayed Deliveries */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('reporting.delayed')}</p>
              <p className="text-3xl font-bold text-red-600">{kpis.delayed}</p>
              <p className="text-xs text-gray-500 mt-1">{t('onedb.exceeded_standard')}</p>
            </div>
            <div className="p-3 bg-red-50 rounded-lg">
              <XCircle className="w-6 h-6 text-red-600" />
            </div>
          </div>
        </div>

        {/* Average Transit Days */}
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
          <div className="flex items-center justify-between">
            <div>
              <p className="text-sm text-gray-600 mb-1">{t('onedb.avg_transit_days')}</p>
              <p className="text-3xl font-bold text-gray-900">{kpis.avgTransitDays}</p>
              <p className="text-xs text-gray-500 mt-1">{t('onedb.business_days_average')}</p>
            </div>
            <div className="p-3 bg-gray-50 rounded-lg">
              <Clock className="w-6 h-6 text-gray-600" />
            </div>
          </div>
        </div>
      </div>

      {/* Filters */}
      <OneDBFilters records={records} onFilterChange={handleFilterChange} />

      {/* Table */}
      <OneDBTable
        records={filteredRecords}
        selectedRecords={selectedRecords}
        onSelectRecord={handleSelectRecord}
        onSelectAll={handleSelectAll}
      />

      {/* Bulk Operations Panel */}
      <OneDBBulkPanel
        selectedCount={selectedRecords.length}
        totalCount={filteredRecords.length}
        onExport={handleExport}
        onClearSelection={handleClearSelection}
      />

      {/* Footer Info */}
      {records.length > 0 && (
        <div className="text-center text-sm text-gray-500">
          {t('onedb.showing_records', { filtered: filteredRecords.length, total: records.length })}
        </div>
      )}
    </div>
  );
}
