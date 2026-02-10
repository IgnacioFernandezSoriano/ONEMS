import { useState } from 'react';
import { ChevronDown, ChevronRight } from 'lucide-react';
import { useTranslation } from '@/hooks/useTranslation';
import { supabase } from '@/lib/supabase';

interface RawEvent {
  id: string;
  event_id: string;
  tag_id: string;
  reader_id: string;
  read_local_datetime: string;
  is_processed: boolean;
  created_at: string;
}

interface IncidentDetailsRowProps {
  incident: {
    id: string;
    tag_id: string;
    incident_type: string;
    description: string;
    detected_at: string;
    resolved: boolean;
    postal_center_name: string;
    metadata?: any;
  };
  getIncidentTypeBadge: (type: string) => string;
  formatDateTime: (dateString: string) => string;
  onReprocess?: () => void;
  onResolve?: (incidentId: string) => void;
}

export function IncidentDetailsRow({
  incident,
  getIncidentTypeBadge,
  formatDateTime,
  onReprocess,
  onResolve,
}: IncidentDetailsRowProps) {
  const { t } = useTranslation();
  const [isExpanded, setIsExpanded] = useState(false);
  const [rawEvents, setRawEvents] = useState<RawEvent[]>([]);
  const [isLoadingEvents, setIsLoadingEvents] = useState(false);

  const loadRawEvents = async () => {
    if (rawEvents.length > 0) return; // Already loaded

    setIsLoadingEvents(true);
    try {
      const readerCode = incident.metadata?.reader_code;
      
      if (!readerCode) {
        console.warn('No reader_code in metadata');
        return;
      }

      const { data, error } = await supabase
        .from('rfid_events_raw')
        .select('*')
        .eq('tag_id', incident.tag_id)
        .eq('reader_id', readerCode)
        .eq('is_processed', false)
        .order('read_local_datetime', { ascending: true });

      if (error) throw error;

      setRawEvents(data || []);
    } catch (error) {
      console.error('Error loading raw events:', error);
    } finally {
      setIsLoadingEvents(false);
    }
  };

  const handleToggleExpand = async () => {
    if (!isExpanded) {
      await loadRawEvents();
    }
    setIsExpanded(!isExpanded);
  };

  const handleCreateReader = () => {
    const readerCode = incident.metadata?.reader_code;
    if (readerCode) {
      // Navigate to Postal Centers page with reader creation modal
      window.location.href = `/postal-centers?createReader=${readerCode}`;
    }
  };

  const handleMarkAsResolved = async () => {
    if (onResolve) {
      onResolve(incident.id);
    }
  };

  const handleReprocess = () => {
    if (onReprocess) {
      onReprocess();
    }
  };

  const getEventCount = () => {
    return incident.metadata?.event_count || rawEvents.length || 0;
  };

  const getSeverity = () => {
    // Map incident types to severity
    const severityMap: Record<string, string> = {
      unknown_reader: 'Low',
      missing_exit: 'Medium',
      missing_entry: 'Medium',
      exit_before_entry: 'Medium',
      sla_violation: 'High',
      stuck_sample: 'Medium',
      missroute: 'Low',
      duplicate_event: 'Low',
      invalid_sequence: 'Medium',
    };
    return severityMap[incident.incident_type] || 'Low';
  };

  return (
    <>
      {/* Main Row */}
      <tr className="hover:bg-gray-50 cursor-pointer" onClick={handleToggleExpand}>
        <td className="px-6 py-4 whitespace-nowrap text-sm">
          <button className="flex items-center text-gray-400 hover:text-gray-600">
            {isExpanded ? (
              <ChevronDown className="w-4 h-4" />
            ) : (
              <ChevronRight className="w-4 h-4" />
            )}
          </button>
        </td>
        <td className="px-6 py-4 whitespace-nowrap text-sm font-medium text-gray-900">
          {incident.tag_id}
        </td>
        <td className="px-6 py-4 whitespace-nowrap text-sm">
          <span className={`px-2 py-1 rounded-full text-xs font-medium ${getIncidentTypeBadge(incident.incident_type)}`}>
            {t(`diagnosis.consolidation.incident_types.${incident.incident_type}`)}
          </span>
        </td>
        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-900">
          {incident.postal_center_name}
        </td>
        <td className="px-6 py-4 text-sm text-gray-500">
          {incident.description}
        </td>
        <td className="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
          {formatDateTime(incident.detected_at)}
        </td>
        <td className="px-6 py-4 whitespace-nowrap text-sm">
          <span className={`px-2 py-1 rounded-full text-xs font-medium ${
            incident.resolved
              ? 'bg-green-100 text-green-800'
              : 'bg-yellow-100 text-yellow-800'
          }`}>
            {incident.resolved
              ? t('diagnosis.consolidation.status.resolved')
              : t('diagnosis.consolidation.status.pending')}
          </span>
        </td>
      </tr>

      {/* Expanded Details Row */}
      {isExpanded && (
        <tr>
          <td colSpan={7} className="px-6 py-4 bg-gray-50">
            <div className="space-y-4">
              {/* Incident Summary */}
              <div className="bg-white rounded-lg border border-gray-200 p-4">
                <h4 className="text-sm font-semibold text-gray-900 mb-3 flex items-center gap-2">
                  📊 {t('diagnosis.consolidation.details.incident_summary')}
                </h4>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                  <div>
                    <span className="text-gray-500">{t('diagnosis.consolidation.details.affected_events')}:</span>
                    <span className="ml-2 font-medium text-gray-900">{getEventCount()}</span>
                  </div>
                  <div>
                    <span className="text-gray-500">{t('diagnosis.consolidation.details.reader_code')}:</span>
                    <span className="ml-2 font-medium text-gray-900">
                      {incident.metadata?.reader_code || 'N/A'}
                    </span>
                  </div>
                  <div>
                    <span className="text-gray-500">{t('diagnosis.consolidation.details.severity')}:</span>
                    <span className="ml-2 font-medium text-gray-900">{getSeverity()}</span>
                  </div>
                  <div>
                    <span className="text-gray-500">{t('diagnosis.consolidation.details.detected_at')}:</span>
                    <span className="ml-2 font-medium text-gray-900">
                      {formatDateTime(incident.detected_at)}
                    </span>
                  </div>
                </div>
              </div>

              {/* Raw EPCIS Events */}
              {isLoadingEvents ? (
                <div className="text-center py-4">
                  <div className="animate-spin rounded-full h-6 w-6 border-b-2 border-blue-500 mx-auto"></div>
                  <p className="text-sm text-gray-500 mt-2">{t('common.loading')}</p>
                </div>
              ) : rawEvents.length > 0 ? (
                <div className="bg-white rounded-lg border border-gray-200 p-4">
                  <h4 className="text-sm font-semibold text-gray-900 mb-3 flex items-center gap-2">
                    📋 {t('diagnosis.consolidation.details.raw_events')} ({rawEvents.length})
                  </h4>
                  <div className="space-y-3">
                    {rawEvents.map((event, index) => (
                      <div
                        key={event.id}
                        className="border border-gray-200 rounded-lg p-3 bg-gray-50"
                      >
                        <div className="text-xs font-semibold text-gray-700 mb-2">
                          {t('diagnosis.consolidation.details.event_of', { current: index + 1, total: rawEvents.length })}
                        </div>
                        <div className="grid grid-cols-1 md:grid-cols-2 gap-2 text-xs">
                          <div>
                            <span className="text-gray-500">{t('diagnosis.consolidation.details.event_id')}:</span>
                            <span className="ml-2 font-mono text-gray-900">{event.event_id}</span>
                          </div>
                          <div>
                            <span className="text-gray-500">{t('diagnosis.consolidation.details.tag_id_epc')}:</span>
                            <span className="ml-2 font-mono text-gray-900">{event.tag_id}</span>
                          </div>
                          <div>
                            <span className="text-gray-500">{t('diagnosis.consolidation.details.reader_id')}:</span>
                            <span className="ml-2 font-mono text-gray-900">{event.reader_id}</span>
                          </div>
                          <div>
                            <span className="text-gray-500">{t('diagnosis.consolidation.details.read_datetime')}:</span>
                            <span className="ml-2 font-mono text-gray-900">
                              {formatDateTime(event.read_local_datetime)}
                            </span>
                          </div>
                          <div>
                            <span className="text-gray-500">{t('diagnosis.consolidation.details.created_at')}:</span>
                            <span className="ml-2 font-mono text-gray-900">
                              {formatDateTime(event.created_at)}
                            </span>
                          </div>
                          <div>
                            <span className="text-gray-500">{t('diagnosis.consolidation.details.is_processed')}:</span>
                            <span className={`ml-2 font-medium ${
                              event.is_processed ? 'text-green-600' : 'text-red-600'
                            }`}>
                              {event.is_processed ? `✅ ${t('diagnosis.consolidation.details.yes')}` : `❌ ${t('diagnosis.consolidation.details.no')}`}
                            </span>
                          </div>
                          <div className="md:col-span-2">
                            <span className="text-gray-500">{t('diagnosis.consolidation.details.internal_id')}:</span>
                            <span className="ml-2 font-mono text-gray-900 text-xs">{event.id}</span>
                          </div>
                        </div>
                      </div>
                    ))}
                  </div>
                </div>
              ) : (
                <div className="bg-white rounded-lg border border-gray-200 p-4 text-center text-sm text-gray-500">
                  {t('diagnosis.consolidation.details.no_raw_events')}
                </div>
              )}

              {/* Quick Actions */}
              {!incident.resolved && (
                <div className="bg-white rounded-lg border border-gray-200 p-4">
                  <h4 className="text-sm font-semibold text-gray-900 mb-3 flex items-center gap-2">
                    🔧 {t('diagnosis.consolidation.details.quick_actions')}
                  </h4>
                  <div className="flex flex-wrap gap-2">
                    {incident.incident_type === 'unknown_reader' && (
                      <button
                        onClick={handleCreateReader}
                        className="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
                      >
                        📝 {t('diagnosis.consolidation.actions.create_reader')}
                      </button>
                    )}
                    <button
                      onClick={handleMarkAsResolved}
                      className="px-4 py-2 bg-green-600 text-white text-sm font-medium rounded-lg hover:bg-green-700 transition-colors"
                    >
                      ✅ {t('diagnosis.consolidation.actions.mark_resolved')}
                    </button>
                    <button
                      onClick={handleReprocess}
                      className="px-4 py-2 bg-purple-600 text-white text-sm font-medium rounded-lg hover:bg-purple-700 transition-colors"
                    >
                      🔄 {t('diagnosis.consolidation.actions.reprocess')}
                    </button>
                  </div>
                </div>
              )}
            </div>
          </td>
        </tr>
      )}
    </>
  );
}
