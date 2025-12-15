import React, { useState } from 'react';
import { CheckCircle, XCircle, Search, Download } from 'lucide-react';
import type { ShipmentTracking } from '@/types/reporting';

interface ShipmentsTableProps {
  data: ShipmentTracking[];
}

export function ShipmentsTable({ data }: ShipmentsTableProps) {
  const [searchTerm, setSearchTerm] = useState('');

  const filteredData = data.filter(shipment =>
    shipment.tagId.toLowerCase().includes(searchTerm.toLowerCase()) ||
    shipment.originCityName.toLowerCase().includes(searchTerm.toLowerCase()) ||
    shipment.destinationCityName.toLowerCase().includes(searchTerm.toLowerCase())
  );

  // CSV Export function
  const exportToCSV = () => {
    // Define CSV headers
    const headers = [
      'TAG ID',
      'Origin City',
      'Destination City',
      'Carrier',
      'Product',
      'Sent At',
      'Received At',
      'Transit Days (Business)',
      'Transit Days (Total)',
      'Status',
      'On Time Delivery'
    ];

    // Convert data to CSV rows
    const rows = filteredData.map(shipment => [
      shipment.tagId,
      shipment.originCityName,
      shipment.destinationCityName,
      shipment.carrierName,
      shipment.productName,
      shipment.sentAt.toISOString().split('T')[0], // YYYY-MM-DD format
      shipment.receivedAt.toISOString().split('T')[0],
      shipment.businessTransitDays.toString(),
      shipment.totalTransitDays.toString(),
      shipment.onTimeDelivery ? 'On Time' : 'Delayed',
      shipment.onTimeDelivery ? 'TRUE' : 'FALSE'
    ]);

    // Combine headers and rows
    const csvContent = [
      headers.join(','),
      ...rows.map(row => row.map(cell => `"${cell}"`).join(','))
    ].join('\n');

    // Create blob and download
    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    const url = URL.createObjectURL(blob);
    
    link.setAttribute('href', url);
    link.setAttribute('download', `shipment_details_${new Date().toISOString().split('T')[0]}.csv`);
    link.style.visibility = 'hidden';
    
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  if (data.length === 0) {
    return (
      <div className="text-center py-8 text-gray-500">
        No shipment data available
      </div>
    );
  }

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400 w-5 h-5" />
          <input
            type="text"
            placeholder="Search by TAG ID, origin, or destination..."
            value={searchTerm}
            onChange={(e) => setSearchTerm(e.target.value)}
            className="w-full pl-10 pr-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          />
        </div>
        
        <button
          onClick={exportToCSV}
          className="flex items-center gap-2 px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 transition-colors"
          title="Export filtered data to CSV"
        >
          <Download className="w-4 h-4" />
          Export CSV
        </button>
      </div>

      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                TAG ID
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Route
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Carrier / Product
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Sent At
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Received At
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Standard
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Actual
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                Status
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {filteredData.map((shipment) => (
              <tr key={shipment.id} className="hover:bg-gray-50">
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600">
                  {shipment.tagId}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {shipment.originCityName} → {shipment.destinationCityName}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {shipment.carrierName} / {shipment.productName}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {shipment.sentAt.toLocaleDateString()}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                  {shipment.receivedAt.toLocaleDateString()}
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-blue-600">
                  {shipment.timeUnit === 'days' ? shipment.standardDeliveryHours : (shipment.standardDeliveryHours / 24).toFixed(1)} days
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
                  {shipment.businessTransitDays} days
                </td>
                <td className="px-6 py-4 whitespace-nowrap text-sm">
                  <div className="flex items-center">
                    {shipment.onTimeDelivery ? (
                      <>
                        <CheckCircle className="w-4 h-4 text-green-500 mr-2" />
                        <span className="text-green-600 font-medium">On Time</span>
                      </>
                    ) : (
                      <>
                        <XCircle className="w-4 h-4 text-red-500 mr-2" />
                        <span className="text-red-600 font-medium">Delayed</span>
                      </>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="text-sm text-gray-500">
        Showing {filteredData.length} of {data.length} shipments
      </div>
    </div>
  );
}
