import React, { useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { useOneDB, OneDBFilters as Filters } from '../hooks/useOneDB';
import { OneDBFilters } from '../components/OneDB/OneDBFilters';
import { OneDBTable } from '../components/OneDB/OneDBTable';
import { OneDBBulkPanel } from '../components/OneDB/OneDBBulkPanel';

export default function OneDB() {
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

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex items-center gap-3 text-gray-600">
          <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-gray-600"></div>
          <span>Loading records...</span>
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
          <span className="text-4xl">🗄️</span>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">ONE DB</h1>
            <p className="text-sm text-gray-600">
              Validated postal quality analytics repository
            </p>
          </div>
        </div>
        <button
          onClick={refetch}
          className="flex items-center gap-2 px-4 py-2 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
        >
          <span>🔄</span>
          Refresh
        </button>
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
          Showing {filteredRecords.length} of {records.length} total records
        </div>
      )}
    </div>
  );
}
