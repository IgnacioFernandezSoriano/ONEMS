import React, { useEffect, useMemo, useState } from 'react';
import { OneDBRecord } from '../../hooks/useOneDB';
import { SmartTooltip } from '../common/SmartTooltip';
import { TablePagination } from '../common/TablePagination';
import { useTranslation } from '@/hooks/useTranslation';
import { formatInTz, formatDuration, unitSuffix, TimeUnit } from '../../lib/accountTime';

interface OneDBTableProps {
  records: OneDBRecord[];
  selectedRecords: string[];
  onSelectRecord: (id: string) => void;
  onSelectAll: () => void;
  tz: string;
  unit: TimeUnit;
}

export const OneDBTable: React.FC<OneDBTableProps> = ({
  records,
  selectedRecords,
  onSelectRecord,
  onSelectAll,
  tz,
  unit,
}) => {
  const { t } = useTranslation();
  const allSelected = records.length > 0 && selectedRecords.length === records.length;
  const someSelected = selectedRecords.length > 0 && selectedRecords.length < records.length;

  // Only the current page is rendered; `records` stays the whole filtered set so
  // the select-all checkbox and the bulk actions keep covering all of it.
  const [currentPage, setCurrentPage] = useState(1);
  const [pageSize, setPageSize] = useState(100);

  const totalPages = Math.max(1, Math.ceil(records.length / pageSize));

  const pagedRecords = useMemo(
    () => records.slice((currentPage - 1) * pageSize, currentPage * pageSize),
    [records, currentPage, pageSize]
  );

  // `records` is state in useOneDB, so its identity only changes on load or filter
  useEffect(() => {
    setCurrentPage(1);
  }, [records, pageSize]);

  useEffect(() => {
    if (currentPage > totalPages) setCurrentPage(totalPages);
  }, [currentPage, totalPages]);

  const formatDate = (dateString: string) => formatInTz(dateString, tz);
  const unitLabel = unitSuffix(unit);

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
                  {t('onedb.transit_time')} ({unitLabel})
                  <SmartTooltip content="Total calendar days from sent to received. Includes weekends and holidays." />
                </div>
              </th>
              <th className="px-4 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                <div className="flex items-center gap-1">
                  {t('onedb.business_time')} ({unitLabel})
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
              pagedRecords.map((record) => (
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
                    {formatDuration(record.total_transit_hours, unit)}
                  </td>
                  <td className="px-4 py-3 text-sm text-gray-700">
                    {formatDuration(record.business_transit_hours, unit)}
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
      <TablePagination
        idPrefix="onedb"
        currentPage={currentPage}
        totalPages={totalPages}
        pageSize={pageSize}
        totalItems={records.length}
        onPageChange={setCurrentPage}
        onPageSizeChange={setPageSize}
      />
    </div>
  );
};
