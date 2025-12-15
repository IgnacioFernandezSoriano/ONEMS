import React, { useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { useNodeLoadBalancing, BalanceResult } from '../hooks/useNodeLoadBalancing';
import { CityLoadCard } from '../components/NodeLoadBalancing/CityLoadCard';
import { BalancePreviewModal } from '../components/NodeLoadBalancing/BalancePreviewModal';

export default function NodeLoadBalancing() {
  const { user, profile } = useAuth();
  const currentDate = new Date();
  const [selectedMonth, setSelectedMonth] = useState(currentDate.getMonth() + 1);
  const [selectedYear, setSelectedYear] = useState(currentDate.getFullYear());

  const { loadData, citySummaries, loading, error, refetch, previewBalance, applyBalance } =
    useNodeLoadBalancing(profile?.account_id || undefined, selectedMonth, selectedYear);

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

  const handleViewDetails = (cityId: string) => {
    // TODO: Implement detailed view
    alert('Detailed view coming soon!');
  };

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
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <span className="text-4xl">🔄</span>
          <div>
            <h1 className="text-2xl font-bold text-gray-900">Node Load Balancing</h1>
            <p className="text-sm text-gray-600">
              Matrix-based workload distribution across nodes and weeks
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
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
        <div className="flex items-center gap-4">
          <div className="flex items-center gap-2">
            <label className="text-sm font-medium text-gray-700">📅 Month:</label>
            <select
              value={selectedMonth}
              onChange={(e) => setSelectedMonth(Number(e.target.value))}
              className="border border-gray-300 rounded-md px-3 py-2 text-sm"
            >
              {Array.from({ length: 12 }, (_, i) => i + 1).map((month) => (
                <option key={month} value={month}>
                  {new Date(2000, month - 1).toLocaleString('en', { month: 'long' })}
                </option>
              ))}
            </select>
          </div>
          <div className="flex items-center gap-2">
            <label className="text-sm font-medium text-gray-700">Year:</label>
            <select
              value={selectedYear}
              onChange={(e) => setSelectedYear(Number(e.target.value))}
              className="border border-gray-300 rounded-md px-3 py-2 text-sm"
            >
              {[2024, 2025, 2026].map((year) => (
                <option key={year} value={year}>
                  {year}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>

      {/* System Overview */}
      {citySummaries.length > 0 && (
        <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-4">
          <h3 className="font-semibold text-yellow-900 mb-3">System Overview</h3>
          <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
            <div className="flex items-center gap-3">
              <span className="text-2xl">🔴</span>
              <div>
                <div className="text-sm text-yellow-700">Saturated Nodes</div>
                <div className="text-2xl font-bold text-yellow-900">{totalSaturated}</div>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-2xl">🟡</span>
              <div>
                <div className="text-sm text-yellow-700">High Load Nodes</div>
                <div className="text-2xl font-bold text-yellow-900">{totalHigh}</div>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-2xl">📊</span>
              <div>
                <div className="text-sm text-yellow-700">Avg Std Deviation</div>
                <div className={`text-2xl font-bold ${stddevStatus.color}`}>
                  {avgStddev.toFixed(1)} ({stddevStatus.text})
                </div>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <span className="text-2xl">📦</span>
              <div>
                <div className="text-sm text-yellow-700">Total Shipments</div>
                <div className="text-2xl font-bold text-yellow-900">{totalShipments}</div>
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
              onViewDetails={() => handleViewDetails(summary.city_id)}
            />
          ))}
        </div>
      )}

      {/* Legend */}
      <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-4">
        <div className="flex items-center gap-6 text-sm">
          <span className="font-medium text-gray-700">Legend:</span>
          <div className="flex items-center gap-2">
            <span>🟢</span>
            <span className="text-gray-600">Normal (&lt; 120% avg)</span>
          </div>
          <div className="flex items-center gap-2">
            <span>🟡</span>
            <span className="text-gray-600">High (120-150% avg)</span>
          </div>
          <div className="flex items-center gap-2">
            <span>🔴</span>
            <span className="text-gray-600">Saturated (&gt; 150% avg)</span>
          </div>
        </div>
      </div>

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
