import type { JKRouteData, JKCityData, JKRegionData, JKCarrierData } from '@/hooks/reporting/useJKPerformance';
import type { TimeUnit } from '@/lib/accountTime';

// Cada fila se exporta en SU unidad (la columna Unit dice cual): filas en dias -> numero de dias
// (J+n, sin pasar a horas); filas en horas -> horas. La cabecera indica h, d o h/d si mezcla.
function unitSuffix(units: Iterable<TimeUnit | undefined>): string {
  const set = new Set(Array.from(units, u => u ?? 'hours'));
  if (set.size === 0) return 'h';
  return set.size === 1 ? (set.has('days') ? 'd' : 'h') : 'h/d';
}

function jkValue(v: number, unit: TimeUnit | undefined, signed = false): string {
  const sign = signed && v > 0 ? '+' : '';
  if ((unit ?? 'hours') === 'days') {
    // Dias: entero (J+n) si lo es; medias de varias rutas con un decimal
    const txt = Math.abs(v - Math.round(v)) < 0.05 ? String(Math.round(v)) : v.toFixed(1);
    return `${sign}${txt}`;
  }
  return `${sign}${v.toFixed(1)}`;
}

// `unit` es opcional (otras pantallas pasan rutas sin ella): ausente = horas, regla de medida
export function exportRouteCSV(data: Array<Omit<JKRouteData, 'unit'> & { unit?: JKRouteData['unit'] }>) {
  // h / d segun la unidad de las rutas (mezcla: ver columna Unit)
  const sfx = unitSuffix(data.map(r => r.unit));
  const headers = [
    'Origin City',
    'Destination City',
    'Carrier',
    'Product',
    'Total Samples',
    `J+K Standard (${sfx})`,
    `J+K Actual (${sfx})`,
    `Deviation (${sfx})`,
    'STD %',
    'On-Time %',
    'On-Time Samples',
    'Before Standard',
    'After Standard',
    'Status',
    'Unit'
  ];

  const rows: string[][] = [headers];

  data.forEach(route => {
    rows.push([
      route.originCity,
      route.destinationCity,
      route.carrier,
      route.product,
      route.totalSamples.toString(),
      jkValue(route.jkStandard, route.unit),
      jkValue(route.jkActual, route.unit),
      jkValue(route.deviation, route.unit, true),
      route.standardPercentage.toFixed(0) + '%',
      route.onTimePercentage.toFixed(1) + '%',
      route.onTimeSamples.toString(),
      route.beforeStandardSamples.toString(),
      route.afterStandardSamples.toString(),
      route.status === 'compliant' ? 'Compliant' : route.status === 'warning' ? 'Warning' : 'Critical',
      route.unit ?? 'hours'
    ]);
  });

  downloadCSV(rows, 'jk_route_performance');
}

export function exportCityCSV(data: JKCityData[]) {
  const sfx = unitSuffix(data.map(c => c.unit));
  const headers = [
    'City',
    'Direction',
    'Region',
    'Routes',
    'Total Samples',
    `J+K Standard (${sfx})`,
    `J+K Actual (${sfx})`,
    `Deviation (${sfx})`,
    'On-Time %',
    'Status',
    'Unit'
  ];

  const rows: string[][] = [headers];

  data.forEach(city => {
    rows.push([
      city.cityName,
      city.direction === 'inbound' ? 'Inbound' : 'Outbound',
      city.regionName,
      city.routes.toString(),
      city.totalSamples.toString(),
      jkValue(city.jkStandard, city.unit),
      jkValue(city.jkActual, city.unit),
      jkValue(city.deviation, city.unit, true),
      city.onTimePercentage.toFixed(1) + '%',
      city.status === 'compliant' ? 'Compliant' : city.status === 'warning' ? 'Warning' : 'Critical',
      city.unit ?? 'hours'
    ]);
  });

  downloadCSV(rows, 'jk_city_performance');
}

export function exportRegionCSV(data: JKRegionData[]) {
  const sfx = unitSuffix(data.map(r => r.unit));
  const headers = [
    'Region',
    'Direction',
    'Cities',
    'Routes',
    'Total Samples',
    `J+K Standard (${sfx})`,
    `J+K Actual (${sfx})`,
    `Deviation (${sfx})`,
    'On-Time %',
    'Status',
    'Unit'
  ];

  const rows: string[][] = [headers];

  data.forEach(region => {
    rows.push([
      region.regionName,
      region.direction === 'inbound' ? 'Inbound' : 'Outbound',
      region.cities.toString(),
      region.routes.toString(),
      region.totalSamples.toString(),
      jkValue(region.jkStandard, region.unit),
      jkValue(region.jkActual, region.unit),
      jkValue(region.deviation, region.unit, true),
      region.onTimePercentage.toFixed(1) + '%',
      region.status === 'compliant' ? 'Compliant' : region.status === 'warning' ? 'Warning' : 'Critical',
      region.unit ?? 'hours'
    ]);
  });

  downloadCSV(rows, 'jk_region_performance');
}

export function exportCarrierProductCSV(data: JKCarrierData[]) {
  const sfx = unitSuffix(data.flatMap(c => [c.unit, ...c.products.map(p => p.unit)]));
  const headers = [
    'Level',
    'Carrier',
    'Product',
    'Routes',
    'Total Samples',
    `J+K Standard (${sfx})`,
    `J+K Actual (${sfx})`,
    `Deviation (${sfx})`,
    'On-Time %',
    'Problem Routes',
    'Status',
    'Unit'
  ];

  const rows: string[][] = [headers];

  data.forEach(carrier => {
    // Carrier row
    rows.push([
      'Carrier',
      carrier.carrier,
      '',
      carrier.routes.toString(),
      carrier.totalSamples.toString(),
      jkValue(carrier.jkStandard, carrier.unit),
      jkValue(carrier.jkActual, carrier.unit),
      jkValue(carrier.deviation, carrier.unit, true),
      carrier.onTimePercentage.toFixed(1) + '%',
      carrier.problematicRoutes.toString(),
      carrier.status === 'compliant' ? 'Compliant' : carrier.status === 'warning' ? 'Warning' : 'Critical',
      carrier.unit ?? 'hours'
    ]);

    // Product rows
    carrier.products.forEach(product => {
      rows.push([
        'Product',
        carrier.carrier,
        product.product,
        product.routes.toString(),
        product.totalSamples.toString(),
        jkValue(product.jkStandard, product.unit),
        jkValue(product.jkActual, product.unit),
        jkValue(product.deviation, product.unit, true),
        product.onTimePercentage.toFixed(1) + '%',
        '',
        product.status === 'compliant' ? 'Compliant' : product.status === 'warning' ? 'Warning' : 'Critical',
        product.unit ?? 'hours'
      ]);
    });
  });

  downloadCSV(rows, 'jk_carrier_product_performance');
}

export function exportCumulativeCSV(routes: Array<{
  routeKey: string;
  originCity: string;
  destinationCity: string;
  carrier: string;
  product: string;
  jkStandard: number;
  standardPercentage: number;
  distribution: Map<number, number>;
  totalSamples: number;
}>, maxDays: number, unit: 'hours' | 'days' = 'days') {
  const suffix = unit === 'hours' ? 'h' : 'd';
  const cap = unit === 'hours' ? 120 : 20;
  // Find max day needed
  let maxNeededDay = 0;
  routes.forEach(route => {
    let cumulative = 0;
    for (let day = 0; day <= maxDays; day++) {
      cumulative += route.distribution.get(day) || 0;
      const percentage = route.totalSamples > 0 ? (cumulative / route.totalSamples) * 100 : 0;
      if (percentage >= 99.9) {
        maxNeededDay = Math.max(maxNeededDay, day);
        break;
      }
    }
  });

  const days = Array.from({ length: Math.min(maxNeededDay + 1, cap) }, (_, i) => i);

  // Build headers
  const headers = [
    'Route',
    'Carrier',
    'Product',
    `J+K Std (${unit})`,
    'Std %',
    ...days.map(d => `${d}${suffix} Cumulative %`)
  ];

  const rows: string[][] = [headers];

  // Build data rows
  routes.forEach(route => {
    const cumulativePercentages: number[] = [];
    let cumulativeCount = 0;

    days.forEach(day => {
      const count = route.distribution.get(day) || 0;
      cumulativeCount += count;
      const percentage = route.totalSamples > 0 
        ? (cumulativeCount / route.totalSamples) * 100 
        : 0;
      cumulativePercentages.push(percentage);
    });

    rows.push([
      `${route.originCity} → ${route.destinationCity}`,
      route.carrier,
      route.product,
      route.jkStandard.toString(),
      route.standardPercentage.toFixed(0) + '%',
      ...cumulativePercentages.map(p => p.toFixed(1) + '%')
    ]);
  });

  downloadCSV(rows, 'jk_cumulative_distribution');
}

function downloadCSV(rows: string[][], filename: string) {
  const csvContent = rows.map(row => 
    row.map(cell => `"${cell}"`).join(',')
  ).join('\n');

  const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = `${filename}_${new Date().toISOString().split('T')[0]}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
