import { useEffect, useRef } from 'react';
import { MapContainer, TileLayer, CircleMarker, Popup, useMap } from 'react-leaflet';
import type { CityEquityData } from '@/types/reporting';
import 'leaflet/dist/leaflet.css';
import L from 'leaflet';

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
  const mapRef = useRef<L.Map>(null);

  // Filter cities with valid coordinates
  const citiesWithCoords = data.filter(
    (city) => city.latitude != null && city.longitude != null
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
            <Popup>
              <div className="min-w-[250px]">
                <h3 className="font-bold text-lg mb-2">{city.cityName}</h3>
                
                <div className="space-y-1 text-sm">
                  <div className="flex justify-between">
                    <span className="text-gray-600">Region:</span>
                    <span className="font-medium">{city.regionName || 'N/A'}</span>
                  </div>
                  
                  <div className="flex justify-between">
                    <span className="text-gray-600">Population:</span>
                    <span className="font-medium">
                      {city.population ? city.population.toLocaleString() : 'N/A'}
                    </span>
                  </div>

                  <div className="border-t pt-2 mt-2">
                    <div className="flex justify-between">
                      <span className="text-gray-600">Total Shipments:</span>
                      <span className="font-medium">{city.totalShipments}</span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">Compliance:</span>
                      <span
                        className={`font-bold ${
                          city.status === 'compliant'
                            ? 'text-green-600'
                            : city.status === 'warning'
                            ? 'text-amber-600'
                            : 'text-red-600'
                        }`}
                      >
                        {city.actualPercentage.toFixed(1)}%
                      </span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">Standard:</span>
                      <span className="font-medium">{city.standardPercentage.toFixed(1)}%</span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">Deviation:</span>
                      <span
                        className={`font-medium ${
                          city.deviation >= 0 ? 'text-green-600' : 'text-red-600'
                        }`}
                      >
                        {city.deviation >= 0 ? '+' : ''}
                        {city.deviation.toFixed(1)}%
                      </span>
                    </div>
                  </div>

                  <div className="border-t pt-2 mt-2">
                    <div className="flex justify-between">
                      <span className="text-gray-600">Inbound:</span>
                      <span className="font-medium">{city.inboundPercentage.toFixed(1)}%</span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">Outbound:</span>
                      <span className="font-medium">{city.outboundPercentage.toFixed(1)}%</span>
                    </div>

                    <div className="flex justify-between">
                      <span className="text-gray-600">Direction Gap:</span>
                      <span
                        className={`font-medium ${
                          city.directionGap > 5 ? 'text-amber-600' : 'text-gray-900'
                        }`}
                      >
                        {city.directionGap.toFixed(1)}%
                      </span>
                    </div>
                  </div>

                  <div className="border-t pt-2 mt-2">
                    <div className="flex justify-between items-center">
                      <span className="text-gray-600">Status:</span>
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
                          ? '✅ Compliant'
                          : city.status === 'warning'
                          ? '⚠️ Warning'
                          : '❌ Critical'}
                      </span>
                    </div>
                  </div>
                </div>
              </div>
            </Popup>
          </CircleMarker>
        ))}
      </MapContainer>

      {/* Legend */}
      <div className="absolute bottom-4 right-4 bg-white p-3 rounded-lg shadow-lg border border-gray-200 z-[1000]">
        <h4 className="font-semibold text-sm mb-2">Legend</h4>
        <div className="space-y-1 text-xs">
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 rounded-full bg-green-500"></div>
            <span>Compliant</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 rounded-full bg-amber-500"></div>
            <span>Warning</span>
          </div>
          <div className="flex items-center gap-2">
            <div className="w-4 h-4 rounded-full bg-red-500"></div>
            <span>Critical</span>
          </div>
          <div className="border-t pt-1 mt-1">
            <p className="text-gray-600">Circle size = Population</p>
          </div>
        </div>
      </div>
    </div>
  );
}
