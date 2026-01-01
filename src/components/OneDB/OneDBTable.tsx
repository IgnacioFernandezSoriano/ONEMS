import React from 'react';
import { OneDBRecord } from '../../hooks/useOneDB';
import { SmartTooltip } from '../common/SmartTooltip';
import { useTranslation } from '@/hooks/useTranslation';

interface OneDBTableProps {
  records: OneDBRecord[];
  selectedRecords: string[];
  onSelectRecord: (id: string) => void;
  onSelectAll: () => void;
}

export const OneDBTable: React.FC<OneDBTableProps> = ({
  records,
  selectedRecords,
  onSelectRecord,
  onSelectAll,
}) => {
  const { t } = useTranslation();
  const allSelected = records.length > 0 && selectedRecords.length === records.length;
  const someSelected = selectedRecords.length > 0 && selectedRecords.length < records.length;

  const formatDate = (dateString: string) => {
    return new Date(dateString).toLocaleString('en-US', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const OnTimeDeliveryBadge = ({ value }: { value: boolean | null }) => {
    if (value === null) {
      return (
        <span className="inline-flex items-center gap-1 px-2 py-1 bg-gray-100 text-gray-700 text-xs font-medium rounded-full">
          <span>—</span>
          N/A
        </span>
      );
    }

    if (value) {
      return (
        <span className="inline-flex items-center gap-1 px-2 py-1 bg-green-100 text-green-700 text-xs font-medium rounded-full">
          <span>✓</span>
          {t('onedb.on_time')}
        </span>
      );
    }

    return (
      <span className="inline-flex items-center gap-1 px-2 py-1 bg-red-100 text-red-700 text-xs font-medium rounded-full">
        <span>✕</span>
        {t('reporting.delayed')}
      </span>
    );
  };

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead className="bg-gray-50 border-b border-gray-200">
            <tr>
              <th className="px-4 py-3 text-left">
                <input
                  type="checkbox"
                  checked={allSelected}
                  ref={(input) => {
                    if (input) input.indeterminate = someSelected;
                  }}
                  onChange={onSelectAll}
                  className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
                />
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.tag_id')}
                  <SmartTooltip content="Unique identifier for the shipment. Used to track the package throughout its journey." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.plan')}
                  <SmartTooltip content="Allocation plan name that generated this shipment. Links the record to its source plan." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.carrier')}
                  <SmartTooltip content="Postal carrier that handled the shipment (e.g., DHL, FedEx, UPS)." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.product')}
                  <SmartTooltip content="Service type or product used for the shipment (e.g., Express 24 horas, Standard)." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.route')}
                  <SmartTooltip content="Origin and destination cities for the shipment. Shows the complete route path." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.sent')}
                  <SmartTooltip content="Date and time when the shipment was sent from the origin node." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.received')}
                  <SmartTooltip content="Date and time when the shipment was received at the destination node." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.transit_days')}
                  <SmartTooltip content="Total calendar days from sent to received. Includes weekends and holidays." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.business_days')}
                  <SmartTooltip content="Business days only (excludes weekends and holidays). Used for compliance calculations." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.on_time')}
                  <SmartTooltip content="Delivery performance status. Green (On Time) = met standard, Red (Delayed) = exceeded standard." />
                </div>
              </th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {records.length === 0 ? (
              <tr>
                <td colSpan={11} className="px-4 py-8 text-center text-gray-500">
                  {t('onedb.no_records_to_display')}
                </td>
              </tr>
            ) : (
              records.map((record) => (
                <tr
                  key={record.id}
                  className={`hover:bg-gray-50 transition-colors ${
                    selectedRecords.includes(record.id) ? 'bg-blue-50' : ''
                  }`}
                >
                  <td className="px-4 py-3">
                    <input
                      type="checkbox"
                      checked={selectedRecords.includes(record.id)}
                      onChange={() => onSelectRecord(record.id)}
                      className="w-4 h-4 text-blue-600 border-gray-300 rounded focus:ring-blue-500"
                    />
                  </td>
                  <td className="px-4 py-3 text-sm font-medium text-gray-900">
                    {record.tag_id}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-700">{record.plan_name}</td>
                  <td className="px-4 py-3 text-sm text-gray-700">{record.carrier_name}</td>
                  <td className="px-4 py-3 text-sm text-gray-700">{record.product_name}</td>
                  <td className="px-4 py-3 text-sm text-gray-700">
                    <div className="flex flex-col">
                      <span className="text-xs text-gray-500">{t('onedb.origin')}</span>
                      <span>{record.origin_city_name}</span>
                      <span className="text-xs text-gray-500 mt-1">{t('onedb.destination')}</span>
                      <span>{record.destination_city_name}</span>
                    </div>
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-700">
                    {formatDate(record.sent_at)}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-700">
                    {formatDate(record.received_at)}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-900 font-medium">
                    {record.total_transit_days}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-700">
                    {record.business_transit_days ?? 'N/A'}
                  </td>
                  <td className="px-4 py-3">
                    <OnTimeDeliveryBadge value={record.on_time_delivery} />
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
};
