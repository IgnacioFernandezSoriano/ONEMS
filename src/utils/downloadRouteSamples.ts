import { supabase } from '@/lib/supabase';

interface RouteInfo {
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
}

/**
 * Download raw samples data for a specific route from ONE DB
 */
export async function downloadRouteSamples(route: RouteInfo) {
  try {
    // Query ONE DB for samples matching this route
    const { data: samples, error } = await supabase
      .from('one_db')
      .select('*')
      .eq('origin_city_name', route.originCity)
      .eq('destination_city_name', route.destinationCity)
      .eq('carrier_name', route.carrier)
      .eq('product_name', route.product)
      .order('ship_date', { ascending: false });

    if (error) {
      console.error('Error fetching samples:', error);
      alert('Error fetching samples data. Please try again.');
      return;
    }

    if (!samples || samples.length === 0) {
      alert('No samples found for this route.');
      return;
    }

    // Convert to CSV
    const headers = Object.keys(samples[0]);
    const csvContent = [
      headers.join(','),
      ...samples.map(row =>
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
    
    // Create filename: origin-destination_carrier_product_YYYYMMDD.csv
    const date = new Date().toISOString().split('T')[0].replace(/-/g, '');
    const filename = `${route.originCity.replace(/\s+/g, '-')}-${route.destinationCity.replace(/\s+/g, '-')}_${route.carrier.replace(/\s+/g, '-')}_${route.product.replace(/\s+/g, '-')}_${date}.csv`;
    
    link.download = filename;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    URL.revokeObjectURL(url);

    console.log(`Downloaded ${samples.length} samples for route: ${route.originCity} → ${route.destinationCity}`);
  } catch (err) {
    console.error('Error downloading route samples:', err);
    alert('An error occurred while downloading samples. Please try again.');
  }
}
