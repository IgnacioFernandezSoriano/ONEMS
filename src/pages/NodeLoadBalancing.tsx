import React, { useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { useNodeLoadBalancing, BalanceResult } from '../hooks/useNodeLoadBalancing';
import { CityLoadCard } from '../components/NodeLoadBalancing/CityLoadCard';
import { BalancePreviewModal } from '../components/NodeLoadBalancing/BalancePreviewModal';

export default function NodeLoadBalancing() {
  const { user, profile } = useAuth();
  const currentDate = new Date();
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [selectedYear, setSelectedYear] = useState(currentDate.getFullYear());
  const [showFilters, setShowFilters] = useState(true);
  const [referenceLoad, setReferenceLoad] = useState(6); // Default reference samples per node
  const [deviationPercent, setDeviationPercent] = useState(20); // Default 20% deviation

  const { loadData, citySummaries, loading, error, refetch, previewBalance, applyBalance } =
    useNodeLoadBalancing(profile?.account_id || undefined, startDate, endDate, referenceLoad, deviationPercent);

  const [modalState, setModalState] = useState<{
    isOpen: boolean;
    cityId: string | null;
    cityName: string | null;
    previewResult: BalanceResult | null;
    loading: boolean;
  }>({
    isOpen: false,
    cityId: null,
    cityName: null,
    previewResult: null,
    loading: false,
  });

  // Group load data by city
  const citiesData = loadData.reduce((acc, item) => {
    if (!acc[item.city_id]) {
      acc[item.city_id] = {
        cityName: item.city_name,
        data: [],
      };
    }
    acc[item.city_id].data.push(item);
    return acc;
  }, {} as { [cityId: string]: { cityName: string; data: typeof loadData } });

  const handleBalanceClick = async (cityId: string, cityName: string) => {
    setModalState({
      isOpen: true,
      cityId,
      cityName,
      previewResult: null,
      loading: true,
    });

    const result = await previewBalance(cityId);

    setModalState((prev) => ({
      ...prev,
      previewResult: result,
      loading: false,
    }));
  };

  const handleConfirmBalance = async () => {
    if (!modalState.cityId) return;

    setModalState((prev) => ({ ...prev, loading: true }));

    const result = await applyBalance(modalState.cityId);

    if (result.success) {
      // Wait for data to refresh (loading becomes false)
      // Poll until loading is false or timeout after 5 seconds
      const startTime = Date.now();
      while (loading && Date.now() - startTime < 5000) {
        await new Promise(resolve => setTimeout(resolve, 100));
      }
      
      alert(`Balance applied successfully!\n${result.message}\nMoved: ${result.movements_count} shipments\nImprovement: ${result.improvement_percentage.toFixed(1)}%`);
      
      setModalState({
        isOpen: false,
        cityId: null,
        cityName: null,
        previewResult: null,
        loading: false,
      });
    } else {
      alert(`Error applying balance: ${result.error}`);
      setModalState((prev) => ({ ...prev, loading: false }));
    }
  };

  const handleCloseModal = () => {
    setModalState({
      isOpen: false,
      cityId: null,
      cityName: null,
      previewResult: null,
      loading: false,
    });
  };

  // Date formatting helper
  const formatDateLocal = (date: Date) => {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  };

  // Month selection handlers
  const handleMonthSelect = (year: number, month: number) => {
    const firstDay = new Date(year, month - 1, 1);
    const lastDay = new Date(year, month, 0);
    setStartDate(formatDateLocal(firstDay));
    setEndDate(formatDateLocal(lastDay));
  };

  const handleFirstSemesterSelect = () => {
    const currentYear = new Date().getFullYear();
    const firstDay = new Date(currentYear, 0, 1);
    const lastDay = new Date(currentYear, 5, 30);
    setStartDate(formatDateLocal(firstDay));
    setEndDate(formatDateLocal(lastDay));
  };

  const handleSecondSemesterSelect = () => {
    const currentYear = new Date().getFullYear();
    const firstDay = new Date(currentYear, 6, 1);
    const lastDay = new Date(currentYear, 11, 31);
    setStartDate(formatDateLocal(firstDay));
    setEndDate(formatDateLocal(lastDay));
  };

  const handleYearSelect = () => {
    const currentYear = new Date().getFullYear();
    const firstDay = new Date(currentYear, 0, 1);
    const lastDay = new Date(currentYear, 11, 31);
    setStartDate(formatDateLocal(firstDay));
    setEndDate(formatDateLocal(lastDay));
  };

  const handleResetFilters = () => {
    setStartDate('');
    setEndDate('');
    setSelectedYear(new Date().getFullYear());
    setReferenceLoad(63);
    setDeviationPercent(20);
  };

  // Month names for buttons
  const months = [
    { num: 1, name: 'Jan' }, { num: 2, name: 'Feb' }, { num: 3, name: 'Mar' },
    { num: 4, name: 'Apr' }, { num: 5, name: 'May' }, { num: 6, name: 'Jun' },
    { num: 7, name: 'Jul' }, { num: 8, name: 'Aug' }, { num: 9, name: 'Sep' },
    { num: 10, name: 'Oct' }, { num: 11, name: 'Nov' }, { num: 12, name: 'Dec' }
  ];

  // Generate year range
  const yearRange = React.useMemo(() => {
    const currentYear = new Date().getFullYear();
    const years = [];
    for (let i = currentYear; i <= currentYear + 10; i++) {
      years.push(i);
    }
    return years;
  }, []);

  // Calculate system-wide stats
  const totalSaturated = citySummaries.reduce((sum, city) => sum + city.saturated_nodes, 0);
  const totalHigh = citySummaries.reduce((sum, city) => sum + city.high_nodes, 0);
  const avgStddev =
    citySummaries.length > 0
      ? citySummaries.reduce((sum, city) => sum + city.monthly_stddev, 0) / citySummaries.length
      : 0;
  const totalShipments = citySummaries.reduce((sum, city) => sum + city.total_shipments, 0);

  const getStddevStatus = (stddev: number) => {
    if (stddev < 5) return { text: 'Excellent', color: 'text-green-700' };
    if (stddev < 10) return { text: 'Good', color: 'text-blue-700' };
    if (stddev < 15) return { text: 'Fair', color: 'text-orange-700' };
    return { text: 'Poor', color: 'text-red-700' };
  };

  const stddevStatus = getStddevStatus(avgStddev);

  if (loading) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex items-center gap-3 text-gray-600">
          <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-gray-600"></div>
          <span>Loading node load data...</span>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="bg-red-50 border border-red-200 rounded-lg p-4">
        <p className="text-red-700">Error loading data: {error}</p>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {/* Header with Tooltip */}
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold text-gray-900">Node Load Balancing</h1>
            <span className="group relative">
              <svg
                className="w-5 h-5 text-gray-400 cursor-help"
                fill="currentColor"
                viewBox="0 0 20 20"
              >
                <path
                  fillRule="evenodd"
                  d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z"
                  clipRule="evenodd"
                />
              </svg>
              <div className="invisible group-hover:visible absolute z-10 w-96 p-3 bg-gray-900 text-white text-sm rounded-lg shadow-lg top-0 left-8">
                <p className="font-semibold mb-2">Node Load Balancing</p>
                <p className="mb-2">
                  <strong>Purpose:</strong> Visualize and optimize shipment distribution across nodes within each city to prevent overload and improve efficiency.
                </p>
                <p className="mb-2">
                  <strong>How it works:</strong> View weekly shipment loads in a matrix format (nodes × weeks). The system identifies saturated nodes and suggests rebalancing to distribute workload more evenly.
                </p>
                <p>
                  <strong>Usage:</strong> Select month/year, review load matrices by city, click "Balance" to preview and apply automatic rebalancing.
                </p>
              </div>
            </span>
          </div>
          <p className="text-gray-600 mt-1">Optimize shipment distribution across nodes and weeks</p>
        </div>
        <button
          onClick={refetch}
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
        >
          Refresh
        </button>
      </div>

      {/* Filters */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200">
        {/* Filter Header */}
        <div className="flex items-center justify-between p-4 border-b border-gray-200">
          <div className="flex items-center gap-3">
            <button
              onClick={() => setShowFilters(!showFilters)}
              className="p-1 hover:bg-gray-100 rounded transition-colors"
            >
              <svg
                className={`w-5 h-5 text-gray-600 transition-transform ${showFilters ? '' : 'rotate-180'}`}
                fill="currentColor"
                viewBox="0 0 20 20"
              >
                <path fillRule="evenodd" d="M5 15l7-7 7 7" clipRule="evenodd" />
              </svg>
            </button>
            <svg className="w-5 h-5 text-gray-600" fill="currentColor" viewBox="0 0 20 20">
              <path fillRule="evenodd" d="M3 3a1 1 0 011-1h12a1 1 0 011 1v3a1 1 0 01-.293.707L12 11.414V15a1 1 0 01-.293.707l-2 2A1 1 0 018 17v-5.586L3.293 6.707A1 1 0 013 6V3z" clipRule="evenodd" />
            </svg>
            <span className="text-lg font-semibold text-gray-900">Filters</span>
          </div>
        </div>

        {/* Filter Content */}
        {showFilters && (
          <div className="p-4 space-y-4">
            {/* Date Range Filters */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  Start Date
                </label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  End Date
                </label>
                <input
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
              </div>
            </div>

            {/* Quick Date Selection */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                Quick Selection
              </label>
              <div className="flex items-center gap-2 mb-2">
                <select
                  value={selectedYear}
                  onChange={(e) => setSelectedYear(parseInt(e.target.value))}
                  className="px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm"
                >
                  {yearRange.map(year => (
                    <option key={year} value={year}>{year}</option>
                  ))}
                </select>
              </div>
              <div className="flex flex-wrap gap-1">
                {months.map(month => (
                  <button
                    key={month.num}
                    onClick={() => handleMonthSelect(selectedYear, month.num)}
                    className="px-2 py-1 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    {month.name}
                  </button>
                ))}
                <button
                  onClick={handleFirstSemesterSelect}
                  className="px-2 py-1 text-xs font-medium rounded border border-green-300 bg-green-50 hover:bg-green-100 hover:border-green-500 focus:outline-none focus:ring-2 focus:ring-green-500"
                >
                  1st Semester
                </button>
                <button
                  onClick={handleSecondSemesterSelect}
                  className="px-2 py-1 text-xs font-medium rounded border border-teal-300 bg-teal-50 hover:bg-teal-100 hover:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500"
                >
                  2nd Semester
                </button>
                <button
                  onClick={handleYearSelect}
                  className="px-2 py-1 text-xs font-medium rounded border border-purple-300 bg-purple-50 hover:bg-purple-100 hover:border-purple-500 focus:outline-none focus:ring-2 focus:ring-purple-500"
                >
                  Year
                </button>
              </div>
            </div>

            {/* Load Balancing Criteria */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-4 border-t border-gray-200">
              <div>
                <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
                  Reference Samples/Node
                  <span className="group relative">
                    <svg className="w-4 h-4 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                    </svg>
                    <div className="invisible group-hover:visible absolute z-10 w-72 p-3 bg-gray-900 text-white text-xs rounded-lg shadow-lg bottom-full left-0 mb-2">
                      <p className="font-semibold mb-1">Reference Load</p>
                      <p className="mb-2">Define el número esperado de samples que cada nodo debería manejar en promedio durante el periodo seleccionado.</p>
                      <p className="mb-2"><strong>Ejemplo:</strong> Si esperas 63 samples por nodo, este será tu valor de referencia.</p>
                      <p>Este valor se usa junto con el % de desviación para clasificar nodos como Normal, High Load o Saturated.</p>
                    </div>
                  </span>
                </label>
                <input
                  type="number"
                  value={referenceLoad}
                  onChange={(e) => setReferenceLoad(Number(e.target.value))}
                  min="1"
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
                <p className="mt-1 text-xs text-gray-500">Expected average samples per node</p>
              </div>
              <div>
                <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
                  Deviation Tolerance (%)
                  <span className="group relative">
                    <svg className="w-4 h-4 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                    </svg>
                    <div className="invisible group-hover:visible absolute z-10 w-72 p-3 bg-gray-900 text-white text-xs rounded-lg shadow-lg bottom-full left-0 mb-2">
                      <p className="font-semibold mb-1">Deviation Tolerance</p>
                      <p className="mb-2">Porcentaje de desviación aceptable respecto al valor de referencia.</p>
                      <p className="mb-2"><strong>Clasificación:</strong></p>
                      <p className="mb-1">• <strong>Normal:</strong> &lt; Ref × (1 + %)</p>
                      <p className="mb-1">• <strong>High Load:</strong> ≥ Ref × (1 + %)</p>
                      <p className="mb-2">• <strong>Saturated:</strong> ≥ Ref × (1 + % × 1.5)</p>
                      <p><strong>Ejemplo:</strong> Con Ref=63 y %=20, Normal &lt; 75.6, High ≥ 75.6, Saturated ≥ 81.9</p>
                    </div>
                  </span>
                </label>
                <input
                  type="number"
                  value={deviationPercent}
                  onChange={(e) => setDeviationPercent(Number(e.target.value))}
                  min="0"
                  max="100"
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
                <p className="mt-1 text-xs text-gray-500">Acceptable deviation from reference</p>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex items-center gap-2 pt-2">
              <button
                onClick={handleResetFilters}
                className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                Reset
              </button>
            </div>
          </div>
        )}
      </div>

      {/* KPI Cards */}
      {citySummaries.length > 0 && (
        <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
          {/* Saturated Nodes */}
          <div className="bg-gradient-to-br from-red-50 to-white rounded-lg shadow-sm border border-red-100 p-6 hover:shadow-md transition-shadow">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-red-600 mb-1">Saturated Nodes</p>
                <p className="text-3xl font-bold text-red-700">{totalSaturated}</p>
                <p className="text-xs text-red-500 mt-1">Nodes over 150% avg load</p>
              </div>
              <div className="w-12 h-12 bg-red-100 rounded-full flex items-center justify-center">
                <svg className="w-6 h-6 text-red-600" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                </svg>
              </div>
            </div>
          </div>

          {/* High Load Nodes */}
          <div className="bg-gradient-to-br from-orange-50 to-white rounded-lg shadow-sm border border-orange-100 p-6 hover:shadow-md transition-shadow">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-orange-600 mb-1">High Load Nodes</p>
                <p className="text-3xl font-bold text-orange-700">{totalHigh}</p>
                <p className="text-xs text-orange-500 mt-1">Nodes at 120-150% avg load</p>
              </div>
              <div className="w-12 h-12 bg-orange-100 rounded-full flex items-center justify-center">
                <svg className="w-6 h-6 text-orange-600" fill="currentColor" viewBox="0 0 20 20">
                  <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7 4a1 1 0 11-2 0 1 1 0 012 0zm-1-9a1 1 0 00-1 1v4a1 1 0 102 0V6a1 1 0 00-1-1z" clipRule="evenodd" />
                </svg>
              </div>
            </div>
          </div>

          {/* Total Shipments */}
          <div className="bg-gradient-to-br from-blue-50 to-white rounded-lg shadow-sm border border-blue-100 p-6 hover:shadow-md transition-shadow">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm font-medium text-blue-600 mb-1">Total Shipments</p>
                <p className="text-3xl font-bold text-blue-700">{totalShipments}</p>
                <p className="text-xs text-blue-500 mt-1">All shipments in period</p>
              </div>
              <div className="w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center">
                <svg className="w-6 h-6 text-blue-600" fill="currentColor" viewBox="0 0 20 20">
                  <path d="M3 1a1 1 0 000 2h1.22l.305 1.222a.997.997 0 00.01.042l1.358 5.43-.893.892C3.74 11.846 4.632 14 6.414 14H15a1 1 0 000-2H6.414l1-1H14a1 1 0 00.894-.553l3-6A1 1 0 0017 3H6.28l-.31-1.243A1 1 0 005 1H3zM16 16.5a1.5 1.5 0 11-3 0 1.5 1.5 0 013 0zM6.5 18a1.5 1.5 0 100-3 1.5 1.5 0 000 3z" />
                </svg>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Cities */}
      {citySummaries.length === 0 ? (
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-8 text-center">
          <p className="text-gray-500">
            No data available for the selected period. Try selecting a different month.
          </p>
        </div>
      ) : (
        <div className="space-y-6">
          {citySummaries.map((summary) => (
            <CityLoadCard
              key={summary.city_id}
              cityName={summary.city_name}
              cityData={citiesData[summary.city_id].data}
              onBalance={() => handleBalanceClick(summary.city_id, summary.city_name)}
            />
          ))}
        </div>
      )}



      {/* Balance Preview Modal */}
      <BalancePreviewModal
        isOpen={modalState.isOpen}
        cityName={modalState.cityName || ''}
        previewResult={modalState.previewResult}
        loading={modalState.loading}
        onClose={handleCloseModal}
        onConfirm={handleConfirmBalance}
      />
    </div>
  );
}
