import { useTranslation } from '@/hooks/useTranslation';
import { JourneySegment } from '@/hooks/useJourneySegments';
import { CheckCircle, AlertTriangle, XCircle, Clock, MapPin, ArrowRight } from 'lucide-react';

interface JourneySegmentsTableProps {
  segments: JourneySegment[];
  selectedSegments: string[];
  onSelectSegment: (id: string) => void;
  onSelectAll: () => void;
}

export function JourneySegmentsTable({
  segments,
  selectedSegments,
  onSelectSegment,
  onSelectAll,
}: JourneySegmentsTableProps) {
  const { t } = useTranslation();

  const getComplianceBadge = (compliance: string) => {
    const badges: Record<string, { color: string; icon: any; label: string }> = {
      on_time: {
        color: 'bg-green-100 text-green-800',
        icon: CheckCircle,
        label: t('journey_segments.compliance.on_time'),
      },
      warning: {
        color: 'bg-yellow-100 text-yellow-800',
        icon: AlertTriangle,
        label: t('journey_segments.compliance.warning'),
      },
      critical: {
        color: 'bg-orange-100 text-orange-800',
        icon: AlertTriangle,
        label: t('journey_segments.compliance.critical'),
      },
      violated: {
        color: 'bg-red-100 text-red-800',
        icon: XCircle,
        label: t('journey_segments.compliance.violated'),
      },
      no_sla: {
        color: 'bg-gray-100 text-gray-800',
        icon: Clock,
        label: t('journey_segments.compliance.no_sla'),
      },
    };

    const badge = badges[compliance] || badges.no_sla;
    const Icon = badge.icon;

    return (
      <span className={`inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium ${badge.color}`}>
        <Icon className="w-3 h-3" />
        {badge.label}
      </span>
    );
  };

  const getSegmentTypeBadge = (type: string) => {
    if (type === 'operational') {
      return (
        <span className="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium bg-blue-100 text-blue-800">
          <MapPin className="w-3 h-3" />
          {t('journey_segments.type.operational')}
        </span>
      );
    } else {
      return (
        <span className="inline-flex items-center gap-1 px-2 py-1 rounded-full text-xs font-medium bg-purple-100 text-purple-800">
          <ArrowRight className="w-3 h-3" />
          {t('journey_segments.type.distribution')}
        </span>
      );
    }
  };

  const formatDateTime = (dateString: string) => {
    return new Date(dateString).toLocaleString('es-ES', {
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    });
  };

  const formatDuration = (minutes: number) => {
    if (minutes < 60) {
      return `${minutes}m`;
    } else if (minutes < 1440) {
      const hours = Math.floor(minutes / 60);
      const mins = minutes % 60;
      return `${hours}h ${mins}m`;
    } else {
      const days = Math.floor(minutes / 1440);
      const hours = Math.floor((minutes % 1440) / 60);
      return `${days}d ${hours}h`;
    }
  };

  const getCenterDisplay = (segment: JourneySegment) => {
    if (segment.segment_type === 'operational') {
      return (
        <div className="flex items-center gap-2">
          <MapPin className="w-4 h-4 text-blue-600" />
          <div>
            <div className="font-medium text-gray-900">
              {segment.postal_center_code_snapshot}
            </div>
            <div className="text-xs text-gray-500">
              {segment.postal_center_name_snapshot}
            </div>
          </div>
        </div>
      );
    } else {
      return (
        <div className="flex items-center gap-2">
          <div className="flex flex-col">
            <div className="flex items-center gap-1">
              <MapPin className="w-3 h-3 text-purple-600" />
              <span className="text-xs font-medium text-gray-900">
                {segment.from_postal_center_code_snapshot}
              </span>
            </div>
            <div className="text-xs text-gray-500">
              {segment.from_postal_center_name_snapshot}
            </div>
          </div>
          <ArrowRight className="w-4 h-4 text-gray-400" />
          <div className="flex flex-col">
            <div className="flex items-center gap-1">
              <MapPin className="w-3 h-3 text-purple-600" />
              <span className="text-xs font-medium text-gray-900">
                {segment.to_postal_center_code_snapshot}
              </span>
            </div>
            <div className="text-xs text-gray-500">
              {segment.to_postal_center_name_snapshot}
            </div>
          </div>
        </div>
      );
    }
  };

  return (
    <div className="bg-white rounded-lg shadow-sm border border-gray-200 overflow-hidden">
      <div className="overflow-x-auto">
        <table className="min-w-full divide-y divide-gray-200">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-6 py-3 text-left w-12">
                <input
                  type="checkbox"
                  checked={selectedSegments.length === segments.length && segments.length > 0}
                  onChange={onSelectAll}
                  className="rounded border-gray-300 text-purple-600 focus:ring-purple-500"
                />
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('journey_segments.table.tag_id')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('journey_segments.table.type')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('journey_segments.table.centers')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('journey_segments.table.entry_time')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('journey_segments.table.exit_time')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('journey_segments.table.duration')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('journey_segments.table.sla')}
              </th>
              <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                {t('journey_segments.table.compliance')}
              </th>
            </tr>
          </thead>
          <tbody className="bg-white divide-y divide-gray-200">
            {segments.length === 0 ? (
              <tr>
                <td colSpan={9} className="px-6 py-8 text-center text-sm text-gray-500">
                  {t('journey_segments.table.no_segments')}
                </td>
              </tr>
            ) : (
              segments.map((segment) => (
                <tr
                  key={segment.id}
                  className={`hover:bg-gray-50 transition-colors ${
                    selectedSegments.includes(segment.id) ? 'bg-purple-50' : ''
                  }`}
                >
                  <td className="px-6 py-4">
                    <input
                      type="checkbox"
                      checked={selectedSegments.includes(segment.id)}
                      onChange={() => onSelectSegment(segment.id)}
                      className="rounded border-gray-300 text-purple-600 focus:ring-purple-500"
                    />
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm font-medium text-gray-900">{segment.tag_id}</div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    {getSegmentTypeBadge(segment.segment_type)}
                  </td>
                  <td className="px-6 py-4">{getCenterDisplay(segment)}</td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">
                      {formatDateTime(segment.entry_timestamp)}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm text-gray-900">
                      {formatDateTime(segment.exit_timestamp)}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    <div className="text-sm font-medium text-gray-900">
                      {formatDuration(segment.adjusted_time_minutes)}
                    </div>
                    <div className="text-xs text-gray-500">
                      {t('journey_segments.table.actual')}: {formatDuration(segment.actual_time_minutes)}
                    </div>
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    {segment.expected_time_minutes ? (
                      <div className="text-sm text-gray-900">
                        {formatDuration(segment.expected_time_minutes)}
                      </div>
                    ) : (
                      <span className="text-xs text-gray-400">{t('journey_segments.table.no_sla')}</span>
                    )}
                  </td>
                  <td className="px-6 py-4 whitespace-nowrap">
                    {getComplianceBadge(segment.sla_compliance)}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>
    </div>
  );
}
