import { useEffect, useRef } from 'react';
import { MapContainer, TileLayer, CircleMarker, Tooltip, useMap } from 'react-leaflet';
import { formatNumber } from '@/lib/formatNumber';
import type { CityEquityData } from '@/types/reporting';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

import { useTranslation } from '@/hooks/useTranslation';
// Fix for default marker icons in Leaflet with Webpack/Vite
delete (L.Icon.Default.prototype as any)._getIconUrl;
L.Icon.Default.mergeOptions({
  iconRetinaUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon-2x.png',
  iconUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-icon.png',
  shadowUrl: 'https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.7.1/images/marker-shadow.png',
});

interface TerritoryEquityMapProps {
  data: CityEquityData[];
}

// Component to auto-fit bounds
function AutoFitBounds({ data }: { data: CityEquityData[] }) {
  const map = useMap();

  useEffect(() => {
    if (data.length === 0) return;

    const validCities = data.filter(
      (city) => city.latitude != null && city.longitude != null
    );

    if (validCities.length === 0) return;

    const bounds = L.latLngBounds(
      validCities.map((city) => [city.latitude!, city.longitude!])
    );

    map.fitBounds(bounds, { padding: [50, 50] });
  }, [data, map]);

  return null;
}

export function TerritoryEquityMap({ data }: TerritoryEquityMapProps) {
  const { t } = useTranslation();
  const mapRef = useRef<L.Map>(null);

  // Filter cities with valid coordinates and at least one valid direction
  const citiesWithCoords = data.filter(
    (city) => 
      city.latitude != null && 
      city.longitude != null &&
      ((city.inboundShipments > 0 || city.inboundStandardDays > 0) ||
       (city.outboundShipments > 0 || city.outboundStandardDays > 0))
  );

  if (citiesWithCoords.length === 0) {
    return (
      <div className="bg-gray-50 border border-gray-200 rounded-lg p-8 text-center">
        <p className="text-gray-600">
          No cities with geographic coordinates available. Please add latitude and longitude data to cities.
        </p>
      </div>
    );
  }

  // Calculate circle radius based on population
  const getRadius = (population: number | null) => {
    if (!population) return 8;
    // Square root scale for better visual differentiation
    // 100k = 10px, 500k = 22px, 1M = 32px, 2M = 45px, 5M = 71px (capped at 50)
    return Math.max(8, Math.min(50, Math.sqrt(population / 10000)));
  };

  // Get color based on equity status
  const getColor = (status: string) => {
    switch (status) {
      case 'compliant':
        return '#10b981'; // green-500
      case 'warning':
        return '#f59e0b'; // amber-500
      case 'critical':
        return '#ef4444'; // red-500
      default:
        return '#6b7280'; // gray-500
    }
  };

  // Default center (Spain)
  const defaultCenter: [number, number] = [40.4168, -3.7038]; // Madrid

  return (
    <div className="w-full h-[600px] rounded-lg overflow-hidden border border-gray-200">
      <MapContainer
        center={defaultCenter}
        zoom={6}
        className="w-full h-full"
        ref={mapRef}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />

        <AutoFitBounds data={citiesWithCoords} />

        {citiesWithCoords.map((city) => (
          <CircleMarker
            key={city.cityId}
            center={[city.latitude!, city.longitude!]}
            radius={getRadius(city.population)}
            pathOptions={{
              fillColor: getColor(city.status),
              fillOpacity: 0.7,
              color: getColor(city.status),
              weight: 2,
              opacity: 0.9,
            }}
          >
            <Tooltip direction="top" offset={[0, -10]} opacity={0.95}>
              <div className="min-w-[250px]">
                <h3 className="font-bold text-lg mb-2">{city.cityName}</h3>
                
                <div className="space-y-1 text-sm">
                  <div className="flex justify-between">
                    <span className="text-gray-600">{t('reporting.region')}</span>
                    <span className="font-medium">{city.regionName || 'N/A'}</span>
                  </div>
                  
                  <div className="flex justify-between">
                    <span className="text-gray-600">{t('reporting.population')}:</span>
                    <span className="font-medium">
                      {city.population ? city.population.toLocaleString() : 'N/A'}
                    </span>
                  </div>

                  <div className="border-t pt-2 mt-2">
                    <div className="flex justify-between">
                      <span className="text-gray-600">{t('reporting.total_shipments')}</span>
                      <span className="font-medium">{city.totalShipments}</span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">{t('reporting.compliance')}</span>
                      <span
                        className={`font-bold ${
                          city.status === 'compliant'
                            ? 'text-green-600'
                            : city.status === 'warning'
                            ? 'text-amber-600'
                            : 'text-red-600'
                        }`}
                      >
                        {formatNumber(city.actualPercentage)}%
                      </span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">{t('reporting.standard')}</span>
                      <span className="font-medium">{formatNumber(city.standardPercentage)}%</span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">{t('reporting.deviation')}:</span>
                      <span
                        className={`font-medium ${
                          city.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                        }`}
                      >
                        {city.deviation >= 0 ? '+' : ''}
                        {formatNumber(city.deviation)}%
                      </span>
                    </div>
                  </div>

                  <div className="border-t pt-2 mt-2">
                    <div className="flex justify-between">
                      <span className="text-gray-600">{t('reporting.inbound')}:</span>
                      <span className="font-medium">{formatNumber(city.inboundPercentage)}%</span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">{t('reporting.outbound')}:</span>
                      <span className="font-medium">{formatNumber(city.outboundPercentage)}%</span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">{t('reporting.direction_gap')}</span>
                      <span
                        className={`font-medium ${
                          city.directionGap > 5 ? 'text-amber-600' : 'text-gray-900'
                        }`}
                      >
                        {formatNumber(city.directionGap)}%
                      </span>
                    </div>
                  </div>

                  <div className="border-t pt-2 mt-2">
                    <div className="flex justify-between items-center">
                      <span className="text-gray-600">{t('common.status')}:</span>
                      <span
                        className={`px-2 py-1 rounded text-xs font-semibold ${
                          city.status === 'compliant'
                            ? 'bg-green-100 text-green-800'
                            : city.status === 'warning'
                            ? 'bg-amber-100 text-amber-800'
                            : 'bg-red-100 text-red-800'
                        }`}
                      >
                        {city.status === 'compliant'
                          ? `✅ ${t('reporting.compliant')}`
                          : city.status === 'warning'
                          ? `⚠️ ${t('reporting.warning')}`
                          : `❌ ${t('reporting.critical')}`}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </Tooltip>
          </CircleMarker>
        ))}
      </MapContainer>

      {/* Legend */}
      <div className="absolute bottom-4 right-4 bg-white p-3 rounded-lg shadow-lg border border-gray-200 z-[1000]">
        <h4 className="font-semibold text-sm mb-2">{t('reporting.legend')}</h4>
        <div className="space-y-1 text-xs">
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 rounded-full bg-green-500"></div>
            <span>{t('reporting.compliant')}</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 rounded-full bg-amber-500"></div>
            <span>{t('reporting.warning')}</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 rounded-full bg-red-500"></div>
            <span>{t('reporting.critical')}</span>
          </div>
          <div className="border-t pt-1 mt-1">
            <p className="text-gray-600">{t('reporting.circle_size_population')}</p>
          </div>
        </div>
      </div>
    </div>
  );
}
