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
 * Download raw samples data for a specific segment from journey_segments table
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

    // Transform samples to replace IDs with names
    const transformedSamples = samples.map((row: any) => {
      const transformed: any = { ...row };
      
      // Replace carrier_id with carrier_name
      if (row.carrier_id && carrierMap.has(row.carrier_id)) {
        transformed.carrier_name = carrierMap.get(row.carrier_id);
        delete transformed.carrier_id;
      }
      
      // Replace product_id with product_name
      if (row.product_id && productMap.has(row.product_id)) {
        transformed.product_name = productMap.get(row.product_id);
        delete transformed.product_id;
      }
      
      // Replace from_postal_center_id with from_postal_center_name
      if (row.from_postal_center_id && centerMap.has(row.from_postal_center_id)) {
        transformed.from_postal_center_name = centerMap.get(row.from_postal_center_id);
        delete transformed.from_postal_center_id;
      }
      
      // Replace to_postal_center_id with to_postal_center_name
      if (row.to_postal_center_id && centerMap.has(row.to_postal_center_id)) {
        transformed.to_postal_center_name = centerMap.get(row.to_postal_center_id);
        delete transformed.to_postal_center_id;
      }
      
      return transformed;
    });

    // Convert to CSV
    const headers = Object.keys(transformedSamples[0]);
    const csvContent = [
      headers.join(','),
      ...transformedSamples.map(row =>
        headers.map(header => {
          const value = row[header];
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
