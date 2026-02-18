import { supabase } from '@/lib/supabase';

interface RouteInfo {
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
  segmentType?: 'operational' | 'distribution';
  carrier_id?: string;
  product_id?: string;
  from_postal_center_id?: string;
  to_postal_center_id?: string;
}

/**
 * Download optimized segment samples for external analysis (Power BI, Excel, etc.)
 */
export async function downloadRouteSamples(route: RouteInfo) {
  try {
    // Build query for journey_segments
    let query = supabase
      .from('journey_segments')
      .select('*')
      .order('created_at', { ascending: false });

    // Filter by carrier_id if available
    if (route.carrier_id) {
      query = query.eq('carrier_id', route.carrier_id);
    }

    // Filter by product_id if available
    if (route.product_id) {
      query = query.eq('product_id', route.product_id);
    }

    // Filter by postal centers based on segment type
    if (route.segmentType === 'operational') {
      // For operational segments, from and to are the same center
      if (route.from_postal_center_id) {
        query = query.eq('from_postal_center_id', route.from_postal_center_id);
      }
    } else {
      // For distribution segments, filter by both from and to centers
      if (route.from_postal_center_id) {
        query = query.eq('from_postal_center_id', route.from_postal_center_id);
      }
      if (route.to_postal_center_id) {
        query = query.eq('to_postal_center_id', route.to_postal_center_id);
      }
    }

    const { data: samples, error } = await query;

    if (error) {
      console.error('Error fetching samples:', error);
      alert('Error fetching samples data. Please try again.');
      return;
    }

    if (!samples || samples.length === 0) {
      alert('No samples found for this segment.');
      return;
    }

    // Load lookup data for replacing IDs with names
    const [carriersRes, productsRes, centersRes] = await Promise.all([
      supabase.from('carriers').select('id, name'),
      supabase.from('products').select('id, code, description'),
      supabase.from('postal_centers').select('id, name, city')
    ]);

    const carrierMap = new Map((carriersRes.data || []).map(c => [c.id, c.name]));
    const productMap = new Map((productsRes.data || []).map(p => [p.id, `${p.code} - ${p.description}`]));
    const centerMap = new Map((centersRes.data || []).map(c => [c.id, c.name]));

    // Transform samples to optimized format for analysis
    const transformedSamples = samples.map((row: any) => {
      return {
        // Identification
        'Tag ID': row.tag_id || '',
        'Segment Type': row.segment_type || '',
        
        // Carrier & Product
        'Carrier': carrierMap.get(row.carrier_id) || row.carrier_name_snapshot || '',
        'Product': productMap.get(row.product_id) || row.product_name || '',
        
        // Route Information
        'Origin City': row.origin_city_name || '',
        'Destination City': row.destination_city_name || '',
        'From Center': centerMap.get(row.from_postal_center_id) || row.from_postal_center_name || row.from_postal_center_city || '',
        'To Center': centerMap.get(row.to_postal_center_id) || row.to_postal_center_name || row.to_postal_center_city || '',
        
        // Timestamps
        'Entry Timestamp': row.entry_timestamp || '',
        'Exit Timestamp': row.exit_timestamp || '',
        'Next Entry Timestamp': row.next_entry_timestamp || '',
        
        // Time Metrics (minutes)
        'Natural Time in Center (min)': row.natural_time_in_center_minutes || 0,
        'Working Time in Center (min)': row.working_time_in_center_minutes || 0,
        'Natural Transit Time (min)': row.natural_transit_time_minutes || 0,
        'Working Transit Time (min)': row.working_transit_time_minutes || 0,
        'Actual Time (min)': row.actual_time_minutes || 0,
        'Adjusted Time (min)': row.adjusted_time_minutes || 0,
        'Pre-operational Wait (min)': row.pre_operational_wait_minutes || 0,
        
        // SLA Metrics
        'Expected Time (min)': row.expected_time_minutes || '',
        'SLA Compliance': row.sla_compliance || ''
      };
    });

    // Convert to CSV
    const headers = Object.keys(transformedSamples[0]);
    const csvContent = [
      headers.join(','),
      ...transformedSamples.map(row =>
        headers.map(header => {
          const value = (row as any)[header];
          // Escape values containing commas or quotes
          if (value === null || value === undefined) return '';
          const stringValue = String(value);
          if (stringValue.includes(',') || stringValue.includes('"') || stringValue.includes('\n')) {
            return `"${stringValue.replace(/"/g, '""')}"`;
          }
          return stringValue;
        }).join(',')
      )
    ].join('\n');

    // Download CSV
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    
    // Create filename: segmentType_origin-destination_carrier_product_YYYYMMDD.csv
    const date = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const segType = route.segmentType || 'segment';
    const filename = `${segType}_${route.originCity.replace(/\s+/g, '-')}-${route.destinationCity.replace(/\s+/g, '-')}_${route.carrier.replace(/\s+/g, '-')}_${date}.csv`;
    
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);

    console.log(`Downloaded ${samples.length} samples for segment: ${route.originCity} → ${route.destinationCity} (${route.segmentType})`);
  } catch (err) {
    console.error('Error downloading segment samples:', err);
    alert('An error occurred while downloading samples. Please try again.');
  }
}
