import { useState, useEffect } from 'react';
import { supabase } from '../lib/supabase';

export interface OneDBRecord {
  id: string;
  account_id: string;
  allocation_detail_id: string;
  tag_id: string;
  plan_name: string;
  carrier_name: string;
  product_name: string;
  origin_city_name: string;
  destination_city_name: string;
  sent_at: string;
  received_at: string;
  total_transit_days: number;
  business_transit_days: number | null;
  on_time_delivery: boolean | null;
  created_at: string;
  source_data_snapshot: any;
}

export interface OneDBFilters {
  search?: string;
  carrier_name?: string;
  product_name?: string;
  origin_city_name?: string;
  destination_city_name?: string;
  on_time_delivery?: boolean | null;
  date_from?: string;
  date_to?: string;
}

export const useOneDB = (accountId: string | undefined) => {
  const [records, setRecords] = useState<OneDBRecord[]>([]);
  const [filteredRecords, setFilteredRecords] = useState<OneDBRecord[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRecords = async () => {
    console.log('[useOneDB] fetchRecords called with accountId:', accountId);
    
    if (!accountId) {
      console.log('[useOneDB] No accountId provided, skipping fetch');
      setLoading(false);
      return;
    }

    try {
      setLoading(true);
      setError(null);

      console.log('[useOneDB] Fetching from one_db table with accountId:', accountId);
      
      const { data, error: fetchError } = await supabase
        .from('one_db')
        .select('*')
        .eq('account_id', accountId)
        .order('created_at', { ascending: false });

      console.log('[useOneDB] Query result:', { 
        dataCount: data?.length || 0, 
        error: fetchError?.message || null,
        sampleData: data?.[0] || null 
      });

      if (fetchError) throw fetchError;

      setRecords(data || []);
      setFilteredRecords(data || []);
    } catch (err: any) {
      setError(err.message);
      console.error('Error fetching ONE DB records:', err);
    } finally {
      setLoading(false);
    }
  };

  const applyFilters = (filters: OneDBFilters) => {
    let filtered = [...records];

    // Search filter (tag_id or plan_name)
    if (filters.search) {
      const searchLower = filters.search.toLowerCase();
      filtered = filtered.filter(
        (record) =>
          record.tag_id.toLowerCase().includes(searchLower) ||
          record.plan_name.toLowerCase().includes(searchLower)
      );
    }

    // Carrier filter
    if (filters.carrier_name) {
      filtered = filtered.filter((record) => record.carrier_name === filters.carrier_name);
    }

    // Product filter
    if (filters.product_name) {
      filtered = filtered.filter((record) => record.product_name === filters.product_name);
    }

    // Origin city filter
    if (filters.origin_city_name) {
      filtered = filtered.filter((record) => record.origin_city_name === filters.origin_city_name);
    }

    // Destination city filter
    if (filters.destination_city_name) {
      filtered = filtered.filter(
        (record) => record.destination_city_name === filters.destination_city_name
      );
    }

    // On-time delivery filter
    if (filters.on_time_delivery !== undefined && filters.on_time_delivery !== null) {
      filtered = filtered.filter((record) => record.on_time_delivery === filters.on_time_delivery);
    }

    // Date range filter (sent_at)
    if (filters.date_from) {
      filtered = filtered.filter((record) => record.sent_at >= filters.date_from!);
    }

    if (filters.date_to) {
      filtered = filtered.filter((record) => record.sent_at <= filters.date_to!);
    }

    setFilteredRecords(filtered);
  };

  const exportToCSV = (selectedRecords: OneDBRecord[]) => {
    const dataToExport = selectedRecords.length > 0 ? selectedRecords : filteredRecords;

    const headers = [
      'Tag ID',
      'Plan Name',
      'Carrier',
      'Product',
      'Origin',
      'Destination',
      'Sent At',
      'Received At',
      'Total Transit Days',
      'Business Transit Days',
      'On Time Delivery',
      'Created At',
    ];

    const rows = dataToExport.map((record) => [
      record.tag_id,
      record.plan_name,
      record.carrier_name,
      record.product_name,
      record.origin_city_name,
      record.destination_city_name,
      new Date(record.sent_at).toLocaleString(),
      new Date(record.received_at).toLocaleString(),
      record.total_transit_days,
      record.business_transit_days ?? 'N/A',
      record.on_time_delivery === null ? 'N/A' : record.on_time_delivery ? 'Yes' : 'No',
      new Date(record.created_at).toLocaleString(),
    ]);

    const csvContent = [headers, ...rows].map((row) => row.join(',')).join('\n');

    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    link.setAttribute('href', url);
    link.setAttribute('download', `one_db_export_${new Date().toISOString().split('T')[0]}.csv`);
    link.style.visibility = 'hidden';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  useEffect(() => {
    fetchRecords();
  }, [accountId]);

  return {
    records,
    filteredRecords,
    loading,
    error,
    refetch: fetchRecords,
    applyFilters,
    exportToCSV,
  };
};
