import React, { useEffect, useMemo, useRef, useState } from 'react';
import { useAuth } from '../contexts/AuthContext';
import { useNodeLoadBalancing, type NodeDayLoad } from '../hooks/useNodeLoadBalancing';
import { CityLoadCard, type LoadScale } from '../components/NodeLoadBalancing/CityLoadCard';
import { BalancePreviewModal, type BalanceCityResult } from '../components/NodeLoadBalancing/BalancePreviewModal';
import { DeferredSamplesSection } from '../components/NodeLoadBalancing/DeferredSamplesSection';
import { BalancePoliciesPanel } from '../components/NodeLoadBalancing/BalancePoliciesPanel';
import { useDeferredSamples, notifyDeferredSamplesChanged } from '../hooks/useDeferredSamples';
import { useBalancePolicies } from '../hooks/useBalancePolicies';
import { useAccountConfig } from '../hooks/useAccountConfig';
import { workingDowsFromSchedule, type DatePolicy } from '../lib/workingDays';
import { cityIdsToApply, isCityFailed } from '../lib/balanceViews';
import { isUsablePeriod } from '../lib/dateRange';

import { useTranslation } from '@/hooks/useTranslation';
export default function NodeLoadBalancing() {
  const { t } = useTranslation();
  const { user, profile } = useAuth();
  const currentDate = new Date();
  const [startDate, setStartDate] = useState('');
  const [endDate, setEndDate] = useState('');
  const [selectedYear, setSelectedYear] = useState(currentDate.getFullYear());
  const [showFilters, setShowFilters] = useState(true);
  const [referenceLoad, setReferenceLoad] = useState(6); // Default reference samples per node
  const [deviationPercent, setDeviationPercent] = useState(20); // Default 20% deviation
  // Fence: de hoy a esta fecha (incluida) el balanceo no toca nada. Por defecto, el domingo de la semana actual.
  const endOfCurrentWeek = () => {
    const d = new Date();
    d.setDate(d.getDate() + (7 - (d.getDay() || 7)));
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  };
  const [fenceUntil, setFenceUntil] = useState(endOfCurrentWeek);

  // Las fechas que se escriben (startDate/endDate) y las que se consultan (applied) van separadas: mientras se
  // teclea un <input type="date"> salen valores intermedios (anyo 0002, inicio > fin...) y cada uno lanzaba una
  // consulta que sustituia toda la pagina por el indicador de carga. Solo se consulta con un periodo completo y
  // valido, tras una breve pausa sin cambios (el boton Reset, con ambas vacias, se aplica al instante).
  const [applied, setApplied] = useState({ start: '', end: '' });
  useEffect(() => {
    if (!startDate && !endDate) {
      setApplied((prev) => (prev.start === '' && prev.end === '' ? prev : { start: '', end: '' }));
      return;
    }
    if (!isUsablePeriod(startDate, endDate)) return;
    const timer = setTimeout(() => {
      setApplied((prev) => (prev.start === startDate && prev.end === endDate ? prev : { start: startDate, end: endDate }));
    }, 500);
    return () => clearTimeout(timer);
  }, [startDate, endDate]);
  const datesPending = isUsablePeriod(startDate, endDate) && (startDate !== applied.start || endDate !== applied.end);

  const { loadData, dayData, citySummaries, loading, error, refetch, previewBalanceV2, applyBalanceV2, previewAll, applyAll } =
    useNodeLoadBalancing(profile?.account_id || undefined, applied.start, applied.end, referenceLoad, deviationPercent,
      fenceUntil);

  const { summary: deferredSummary } = useDeferredSamples();
  const deferredByCity = useMemo(
    () => new Map((deferredSummary?.by_city ?? []).map((c) => [c.city_id, c.count])),
    [deferredSummary]
  );
  // Ultima vista previa por ciudad: muestras que se apartarian del plan (willRemove de las recomendaciones)
  const [lastPreviewRemoved, setLastPreviewRemoved] = useState<Record<string, number>>({});

  const { weeklySchedule, setWorkingDay } = useAccountConfig();
  const { account: accountPolicy, cities: cityPolicies, updateAccountPolicy, updateCityPolicy, effectiveFor } =
    useBalancePolicies();
  const [scales, setScales] = useState<Record<string, LoadScale>>({});
  const dayDataByCity = useMemo(() => {
    const m = new Map<string, NodeDayLoad[]>();
    (dayData || []).forEach((r) => {
      const arr = m.get(r.city_id);
      if (arr) arr.push(r);
      else m.set(r.city_id, [r]);
    });
    return m;
  }, [dayData]);
  const noDayData = useMemo<NodeDayLoad[]>(() => [], []);

  // Inline notice (replaces alert()): auto-hides after 8 s
  const [notice, setNotice] = useState<{ type: 'ok' | 'error'; text: string } | null>(null);
  const noticeTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const showNotice = (type: 'ok' | 'error', text: string) => {
    if (noticeTimer.current) clearTimeout(noticeTimer.current);
    setNotice({ type, text });
    noticeTimer.current = setTimeout(() => setNotice(null), 8000);
  };
  useEffect(
    () => () => {
      if (noticeTimer.current) clearTimeout(noticeTimer.current);
    },
    []
  );
  const errMsg = (err: unknown) => (err instanceof Error ? err.message : String(err));
  const showFailure = (err?: string) => showNotice('error', `${t('common.error')}: ${err ?? ''}`);

  const handleCityPolicyChange = async (
    cityId: string,
    p: { date_policy?: DatePolicy | null; pobox_enabled?: boolean | null }
  ) => {
    if (applyingRef.current) return;
    try {
      const res = await updateCityPolicy(cityId, p);
      if (!res.success) {
        console.error('[NodeLoadBalancing] Error updating city policy:', res.error);
        showFailure(res.error);
      }
    } catch (err) {
      console.error('[NodeLoadBalancing] Error updating city policy:', err);
      showFailure(errMsg(err));
    }
  };
  const workingDows = useMemo(() => workingDowsFromSchedule(weeklySchedule), [weeklySchedule]);
  // Progress of the all-cities run (preview or apply); also drives the header button
  const [progress, setProgress] = useState<{ done: number; total: number } | null>(null);

  const handleToggleDay = async (dow: number, on: boolean) => {
    if (applyingRef.current) return;
    try {
      const res = await setWorkingDay(dow, on);
      if (res && res.success === false) {
        console.error('[NodeLoadBalancing] Error updating working day:', res.error);
        showFailure(res.error);
      }
    } catch (err) {
      console.error('[NodeLoadBalancing] Error updating working day:', err);
      showFailure(errMsg(err));
    }
  };

  const handleChangePolicy = async (p: { date_policy?: DatePolicy; pobox_enabled?: boolean }) => {
    // POBOX forces the daily policy: store both together so the stored value is consistent
    if (applyingRef.current) return;
    const patch = p.pobox_enabled === true ? { ...p, date_policy: 'daily' as DatePolicy } : p;
    try {
      const res = await updateAccountPolicy(patch);
      if (res && res.success === false) {
        console.error('[NodeLoadBalancing] Error updating policy:', res.error);
        showFailure(res.error);
      }
    } catch (err) {
      console.error('[NodeLoadBalancing] Error updating policy:', err);
      showFailure(errMsg(err));
    }
  };

  const closedModal = {
    isOpen: false,
    mode: 'city' as 'city' | 'all',
    cityId: null as string | null,
    cityName: null as string | null,
    results: [] as BalanceCityResult[],
    loading: false,
  };
  const [modalState, setModalState] = useState(closedModal);
  // Ignore results of a request whose modal was closed (or replaced) meanwhile
  const requestId = useRef(0);
  // True for the whole duration of any apply: locks the modal and every balance button
  const [applying, setApplying] = useState(false);
  const applyingRef = useRef(false);

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
    if (applyingRef.current) return;
    const id = ++requestId.current;
    setModalState({ ...closedModal, isOpen: true, mode: 'city', cityId, cityName, loading: true });
    try {
      const result = await previewBalanceV2(cityId);
      if (id !== requestId.current) return;
      setLastPreviewRemoved((prev) => ({ ...prev, [cityId]: result.success ? result.deferred?.removed ?? 0 : 0 }));
      setModalState((prev) => ({ ...prev, results: [{ cityId, cityName, result }], loading: false }));
    } catch (err) {
      if (id !== requestId.current) return;
      console.error('[NodeLoadBalancing] Error previewing balance:', err);
      setModalState((prev) => ({ ...prev, results: [{ cityId, cityName, error: errMsg(err) }], loading: false }));
    }
  };

  const handleBalanceAll = async () => {
    if (applyingRef.current) return;
    const id = ++requestId.current;
    setModalState({ ...closedModal, isOpen: true, mode: 'all', loading: true });
    setProgress({ done: 0, total: 0 });
    try {
      const results = await previewAll((done, total) => {
        if (id === requestId.current) setProgress({ done, total });
      });
      if (id !== requestId.current) return;
      setLastPreviewRemoved((prev) => {
        const next = { ...prev };
        results.forEach((r) => {
          next[r.cityId] = r.result?.success ? r.result.deferred?.removed ?? 0 : 0;
        });
        return next;
      });
      setModalState((prev) => ({ ...prev, results, loading: false }));
    } catch (err) {
      if (id !== requestId.current) return;
      console.error('[NodeLoadBalancing] Error balancing all cities:', err);
      setModalState(closedModal);
      showFailure(errMsg(err));
    } finally {
      if (id === requestId.current) setProgress(null);
    }
  };

  const handleConfirmBalance = async () => {
    if (applyingRef.current) return;
    applyingRef.current = true;
    setApplying(true);
    try {
      await confirmBalance();
    } finally {
      applyingRef.current = false;
      setApplying(false);
    }
  };

  const confirmBalance = async () => {
    if (modalState.mode === 'all') {
      const id = ++requestId.current;
      // Apply exactly the cities the user saw in the preview (not a fresh pending list)
      const cityIds = cityIdsToApply(modalState.results);
      const names = new Map(modalState.results.map((r) => [r.cityId, r.cityName]));
      setModalState((prev) => ({ ...prev, loading: true }));
      setProgress({ done: 0, total: 0 });
      try {
        const raw = await applyAll((done, total) => {
          if (id === requestId.current) setProgress({ done, total });
        }, cityIds);
        const results = raw.map((r) => ({ ...r, cityName: r.cityName || names.get(r.cityId) || '' }));
        const failed = results.filter(isCityFailed);
        if (id === requestId.current) setModalState(closedModal);
        if (failed.length === 0) {
          showNotice('ok', t('lb2.applied_ok'));
        } else {
          showNotice(
            'error',
            `${t('lb2.applied_error')} ${failed
              .map((f) => `${t('lb2.city_failed', { city: f.cityName })}${f.error ? ` (${f.error})` : ''}`)
              .join('; ')}`
          );
        }
      } catch (err) {
        console.error('[NodeLoadBalancing] Error applying balance to all cities:', err);
        if (id === requestId.current) setModalState(closedModal);
        showNotice('error', `${t('lb2.applied_error')} ${errMsg(err)}`);
      } finally {
        if (id === requestId.current) setProgress(null);
        setLastPreviewRemoved({});
        notifyDeferredSamplesChanged();
        await refetch();
      }
      return;
    }

    if (!modalState.cityId) return;
    const cityId = modalState.cityId;
    const cityName = modalState.cityName ?? '';
    const id = ++requestId.current;
    setModalState((prev) => ({ ...prev, loading: true }));
    try {
      const result = await applyBalanceV2(cityId);
      if (id === requestId.current) setModalState(closedModal);
      if (result.success && !result.error) {
        showNotice('ok', `${cityName}: ${t('lb2.applied_ok')}`);
      } else {
        showNotice('error', `${t('lb2.applied_error')} ${t('lb2.city_failed', { city: cityName })}: ${result.error ?? result.message}`);
      }
    } catch (err) {
      console.error('[NodeLoadBalancing] Error applying balance:', err);
      if (id === requestId.current) setModalState((prev) => ({ ...prev, loading: false }));
      showNotice('error', `${t('lb2.applied_error')} ${errMsg(err)}`);
    } finally {
      setLastPreviewRemoved((prev) => ({ ...prev, [cityId]: 0 }));
      notifyDeferredSamplesChanged();
      await refetch();
    }
  };

  const handleCloseModal = () => {
    if (applyingRef.current) return;
    ++requestId.current;
    setProgress(null);
    setModalState(closedModal);
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
    setFenceUntil(endOfCurrentWeek());
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

  // Pantalla de carga completa solo la primera vez (aun no hay nada que mostrar). En las recargas por cambio de
  // fechas se mantiene la pagina (y el foco en el campo de fecha) y solo se atenua el contenido.
  if (loading && loadData.length === 0 && citySummaries.length === 0) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="flex items-center gap-3 text-gray-600">
          <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-gray-600"></div>
          <span>{t("common.loading_data")}</span>
        </div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      {error && (
        <div className="bg-red-50 border border-red-200 rounded-lg p-4">
          <p className="text-red-700">Error loading data: {error}</p>
        </div>
      )}
      {(loading || datesPending) && (
        <div className="flex items-center gap-2 text-sm text-gray-500" role="status">
          <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-gray-500"></div>
          <span>{t("common.loading_data")}</span>
        </div>
      )}
      {notice && (
        <div
          role={notice.type === 'error' ? 'alert' : 'status'}
          className={`flex items-start justify-between gap-3 rounded-lg border p-4 text-sm ${
            notice.type === 'ok'
              ? 'bg-green-50 border-green-200 text-green-800'
              : 'bg-red-50 border-red-200 text-red-800'
          }`}
        >
          <span>{notice.text}</span>
          <button
            type="button"
            onClick={() => setNotice(null)}
            aria-label={t('common.close')}
            className="text-lg leading-none opacity-60 hover:opacity-100"
          >
            ×
          </button>
        </div>
      )}

      {/* Header with Tooltip */}
      <div className="flex items-center justify-between">
        <div>
          <div className="flex items-center gap-3">
            <h1 className="text-3xl font-bold text-gray-900">{t("node_load_balancing.title")}</h1>
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
                <p className="font-semibold mb-2">{t("node_load_balancing.title")}</p>
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
          <p className="text-gray-600 mt-1">{t("node_load_balancing.subtitle")}</p>
        </div>
        <button
          onClick={refetch}
          className="px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-lg hover:bg-gray-50 transition-colors"
        >
          Refresh
        </button>
      </div>

      <BalancePoliciesPanel
        workingDows={workingDows}
        onToggleDay={handleToggleDay}
        datePolicy={(accountPolicy?.pobox_enabled ?? false) ? 'daily' : (accountPolicy?.date_policy ?? 'daily')}
        pobox={accountPolicy?.pobox_enabled ?? false}
        onChangePolicy={handleChangePolicy}
        onBalanceAll={handleBalanceAll}
        balancingAll={progress}
        disabled={!applied.start || !applied.end || datesPending || applying}
        locked={applying}
        balanceAllHint={t('lb2.balance_all_need_dates')}
      />

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
            <span className="text-lg font-semibold text-gray-900">{t('stock.filters')}</span>
          </div>
        </div>

        {/* Filter Content */}
        {showFilters && (
          <div className="p-4 space-y-4">
            {/* Date Range Filters */}
            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t("common.start_date")}
                </label>
                <input
                  type="date"
                  value={startDate}
                  onChange={(e) => setStartDate(e.target.value)}
                  disabled={applying}
                  className="disabled:opacity-50 disabled:cursor-not-allowed block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t("common.end_date")}
                </label>
                <input
                  type="date"
                  value={endDate}
                  onChange={(e) => setEndDate(e.target.value)}
                  disabled={applying}
                  className="disabled:opacity-50 disabled:cursor-not-allowed block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">
                  {t("node_load_balancing.fence_until")}
                </label>
                <input
                  type="date"
                  value={fenceUntil}
                  onChange={(e) => setFenceUntil(e.target.value)}
                  disabled={applying}
                  title={t("node_load_balancing.fence_until_hint")}
                  className="disabled:opacity-50 disabled:cursor-not-allowed block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
                <p className="mt-1 text-xs text-gray-500">{t("node_load_balancing.fence_until_hint")}</p>
              </div>
            </div>

            {/* Quick Date Selection */}
            <div>
              <label className="block text-sm font-medium text-gray-700 mb-2">
                {t("node_load_balancing.quick_selection")}
              </label>
              <div className="flex items-center gap-2 mb-2">
                <select
                  value={selectedYear}
                  onChange={(e) => setSelectedYear(parseInt(e.target.value))}
                  disabled={applying}
                  className="disabled:opacity-50 disabled:cursor-not-allowed px-3 py-2 border border-gray-300 rounded-md focus:ring-2 focus:ring-blue-500 focus:border-blue-500 text-sm"
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
                    disabled={applying}
                    className="disabled:opacity-50 disabled:cursor-not-allowed px-2 py-1 text-xs font-medium text-gray-700 bg-white border border-gray-300 rounded hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    {month.name}
                  </button>
                ))}
                <button
                  onClick={handleFirstSemesterSelect}
                  disabled={applying}
                  className="disabled:opacity-50 disabled:cursor-not-allowed px-2 py-1 text-xs font-medium rounded border border-green-300 bg-green-50 hover:bg-green-100 hover:border-green-500 focus:outline-none focus:ring-2 focus:ring-green-500"
                >
                  {t("common.first_semester")}
                </button>
                <button
                  onClick={handleSecondSemesterSelect}
                  disabled={applying}
                  className="disabled:opacity-50 disabled:cursor-not-allowed px-2 py-1 text-xs font-medium rounded border border-teal-300 bg-teal-50 hover:bg-teal-100 hover:border-teal-500 focus:outline-none focus:ring-2 focus:ring-teal-500"
                >
                  {t("common.second_semester")}
                </button>
                <button
                  onClick={handleYearSelect}
                  disabled={applying}
                  className="disabled:opacity-50 disabled:cursor-not-allowed px-2 py-1 text-xs font-medium rounded border border-purple-300 bg-purple-50 hover:bg-purple-100 hover:border-purple-500 focus:outline-none focus:ring-2 focus:ring-purple-500"
                >
                  {t("common.year")}
                </button>
              </div>
            </div>

            {/* Load Balancing Criteria */}
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4 pt-4 border-t border-gray-200">
              <div>
                <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
                  {t("node_load_balancing.reference_samples_node")}
                  <span className="group relative">
                    <svg className="w-4 h-4 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                    </svg>
                    <div className="invisible group-hover:visible absolute z-10 w-72 p-3 bg-gray-900 text-white text-xs rounded-lg shadow-lg bottom-full left-0 mb-2">
                      <p className="font-semibold mb-1">{t('node_load_balancing.reference_load')}</p>
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
                  disabled={applying}
                  min="1"
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
                <p className="mt-1 text-xs text-gray-500">{t("node_load_balancing.expected_average_tooltip")}</p>
              </div>
              <div>
                <label className="flex items-center gap-1 text-sm font-medium text-gray-700 mb-1">
                  {t("node_load_balancing.deviation_tolerance")}
                  <span className="group relative">
                    <svg className="w-4 h-4 text-gray-400 cursor-help" fill="currentColor" viewBox="0 0 20 20">
                      <path fillRule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a1 1 0 000 2v3a1 1 0 001 1h1a1 1 0 100-2v-3a1 1 0 00-1-1H9z" clipRule="evenodd" />
                    </svg>
                    <div className="invisible group-hover:visible absolute z-10 w-72 p-3 bg-gray-900 text-white text-xs rounded-lg shadow-lg bottom-full left-0 mb-2">
                      <p className="font-semibold mb-1">{t('node_load_balancing.deviation_tolerance_label')}</p>
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
                  disabled={applying}
                  min="0"
                  max="100"
                  className="block w-full border border-gray-300 rounded-md shadow-sm py-2 px-3 focus:outline-none focus:ring-blue-500 focus:border-blue-500 sm:text-sm"
                />
                <p className="mt-1 text-xs text-gray-500">{t("node_load_balancing.acceptable_deviation_tooltip")}</p>
              </div>
            </div>

            {/* Action Buttons */}
            <div className="flex items-center gap-2 pt-2">
              <button
                onClick={handleResetFilters}
                  disabled={applying}
                className="disabled:opacity-50 disabled:cursor-not-allowed px-4 py-2 text-sm font-medium text-gray-700 bg-white border border-gray-300 rounded-md hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-blue-500"
              >
                {t("common.reset")}
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
                <p className="text-sm font-medium text-red-600 mb-1">{t('nodeLoadBalancing.saturatedNodes')}</p>
                <p className="text-3xl font-bold text-red-700">{totalSaturated}</p>
                <p className="text-xs text-red-500 mt-1">{t('nodeLoadBalancing.saturatedNodesDesc')}</p>
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
                <p className="text-sm font-medium text-orange-600 mb-1">{t('nodeLoadBalancing.highLoadNodes')}</p>
                <p className="text-3xl font-bold text-orange-700">{totalHigh}</p>
                <p className="text-xs text-orange-500 mt-1">{t('nodeLoadBalancing.highLoadNodesDesc')}</p>
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
                <p className="text-sm font-medium text-blue-600 mb-1">{t('nodeLoadBalancing.totalShipments')}</p>
                <p className="text-3xl font-bold text-blue-700">{totalShipments}</p>
                <p className="text-xs text-blue-500 mt-1">{t('nodeLoadBalancing.totalShipmentsDesc')}</p>
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

      <DeferredSamplesSection summary={deferredSummary} />

      {/* Cities */}
      {citySummaries.length === 0 ? (
        <div className="bg-white rounded-lg shadow-sm border border-gray-200 p-8 text-center">
          <p className="text-gray-500">
            {t("node_load_balancing.no_data_message")}
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
              balanceDisabled={applying}
              dayData={dayDataByCity.get(summary.city_id) ?? noDayData}
              deferredPending={deferredByCity.get(summary.city_id) ?? 0}
              willRemove={lastPreviewRemoved[summary.city_id] ?? 0}
              scale={scales[summary.city_id] ?? 'week'}
              onScaleChange={(sc) => setScales((prev) => ({ ...prev, [summary.city_id]: sc }))}
              policy={{
                ...effectiveFor(summary.city_id),
                cityOverride: {
                  date_policy: cityPolicies.find((c) => c.id === summary.city_id)?.date_policy ?? null,
                  pobox_enabled: cityPolicies.find((c) => c.id === summary.city_id)?.pobox_enabled ?? null,
                },
              }}
              onCityPolicyChange={(p) => handleCityPolicyChange(summary.city_id, p)}
            />
          ))}
        </div>
      )}



      {/* Balance Preview Modal */}
      <BalancePreviewModal
        isOpen={modalState.isOpen}
        mode={modalState.mode}
        cityName={modalState.cityName ?? undefined}
        results={modalState.results}
        loading={modalState.loading}
        progress={progress}
        applying={applying}
        onClose={handleCloseModal}
        onConfirm={handleConfirmBalance}
      />
    </div>
  );
}
