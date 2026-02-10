import { useState, useEffect } from 'react';
import { useTranslation } from '@/hooks/useTranslation';
import { supabase } from '@/lib/supabase';
import { Button } from '@/components/common/Button';
import { RefreshCw, AlertTriangle, CheckCircle, Clock } from 'lucide-react';

interface ConsolidationMetrics {
  pending_events: number;
  total_incidents: number;
  last_consolidation: string | null;
}

interface Incident {
  id: string;
  tag_id: string;
  incident_type: string;
  description: string;
  detected_at: string;
  resolved: boolean;
  postal_center_name: string;
}

export function EventConsolidation() {
  const { t } = useTranslation();
  const [metrics, setMetrics] = useState<ConsolidationMetrics>({
    pending_events: 0,
    total_incidents: 0,
    last_consolidation: null,
  });
  const [incidents, setIncidents] = useState<Incident[]>([]);
  const [isConsolidating, setIsConsolidating] = useState(false);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    loadMetrics();
    loadIncidents();
  }, []);

  const loadMetrics = async () => {
    try {
      // Get pending events count
      const { count: pendingCount } = await supabase
        .from('rfid_events_raw')
        .select('*', { count: 'exact', head: true })
        .eq('is_processed', false);

      // Get total incidents count
      const { count: incidentsCount } = await supabase
        .from('incidents')
        .select('*', { count: 'exact', head: true });

      // Get last consolidation timestamp from most recent incident
      const { data: lastIncident } = await supabase
        .from('incidents')
        .select('detected_at')
        .order('detected_at', { ascending: false })
        .limit(1)
        .maybeSingle();

      setMetrics({
        pending_events: pendingCount || 0,
        total_incidents: incidentsCount || 0,
        last_consolidation: lastIncident?.detected_at || null,
      });
    } catch (error) {
      console.error('Error loading metrics:', error);
    } finally {
      setIsLoading(false);
    }
  };

  const loadIncidents = async () => {
    try {
      const { data, error } = await supabase
        .from('incidents')
        .select(`
          id,
          tag_id,
          incident_type,
          description,
          detected_at,
          is_resolved,
          postal_centers!incidents_postal_center_id_fkey(name)
        `)
        .order('detected_at', { ascending: false })
        .limit(50);

      if (error) throw error;

      const formattedIncidents = data.map((incident: any) => ({
        id: incident.id,
        tag_id: incident.tag_id,
        incident_type: incident.incident_type,
        description: incident.description,
        detected_at: incident.detected_at,
        resolved: incident.is_resolved,
        postal_center_name: incident.postal_centers?.name || 'N/A',
      }));

      setIncidents(formattedIncidents);
    } catch (error) {
      console.error('Error loading incidents:', error);
    }
  };

  const runConsolidation = async () => {
    setIsConsolidating(true);
    try {
      // Get user's account_id
      const { data: { user } } = await supabase.auth.getUser();
      
      if (!user) {
        alert(t('diagnosis.consolidation.error_no_session'));
        return;
      }

      const { data: profile } = await supabase
        .from('profiles')
        .select('account_id')
        .eq('id', user.id)
        .single();

      if (!profile) {
        alert('Profile not found');
        return;
      }

      // Call SQL function directly
      const { data: result, error } = await supabase.rpc('consolidate_rfid_events', {
        p_account_id: profile.account_id,
      });

      if (error) {
        throw error;
      }

      alert(t('diagnosis.consolidation.success', {
        processed: result?.events_processed || 0,
        incidents: result?.incidents_detected || 0,
      }));

      // Reload metrics and incidents
      await loadMetrics();
      await loadIncidents();
    } catch (error: any) {
      console.error('Consolidation error:', error);
      alert(t('diagnosis.consolidation.error', { 
        message: error.message 
      }));
    } finally {
      setIsConsolidating(false);
    }
  };

  const getIncidentTypeBadge = (type: string) => {
    const colors: Record<string, string> = {
      'missing_exit': 'bg-red-100 text-red-800',
      'unknown_reader': 'bg-yellow-100 text-yellow-800',
      'data_quality': 'bg-orange-100 text-orange-800',
    };
    return colors[type] || 'bg-gray-100 text-gray-800';
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

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <RefreshCw className="w-8 h-8 animate-spin text-blue-500" />
      </div>
    );
  }

  return (
    <div className="space-y-6 p-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">
            {t('diagnosis.consolidation.title')}
          </h1>
          <p className="mt-1 text-sm text-gray-500">
            {t('diagnosis.consolidation.description')}
          </p>
        </div>
        <Button
          onClick={runConsolidation}
          disabled={isConsolidating || metrics.pending_events === 0}
          className="flex items-center gap-2"
        >
          <RefreshCw className={`w-4 h-4 ${isConsolidating ? 'animate-spin' : ''}`} />
          {t('diagnosis.consolidation.run_button')}
        </Button>
      </div>

      {/* Metrics Cards */}
      <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-blue-100 rounded-lg">
              <Clock className="w-6 h-6 text-blue-600" />
            </div>
            <div>
              <p className="text-sm font-medium text-gray-600">
                {t('diagnosis.consolidation.pending_events')}
              </p>
              <p className="text-2xl font-bold text-gray-900">
                {metrics.pending_events}
              </p>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-yellow-100 rounded-lg">
              <AlertTriangle className="w-6 h-6 text-yellow-600" />
            </div>
            <div>
              <p className="text-sm font-medium text-gray-600">
                {t('diagnosis.consolidation.total_incidents')}
              </p>
              <p className="text-2xl font-bold text-gray-900">
                {metrics.total_incidents}
              </p>
            </div>
          </div>
        </div>

        <div className="bg-white rounded-lg shadow p-6">
          <div className="flex items-center gap-4">
            <div className="p-3 bg-green-100 rounded-lg">
              <CheckCircle className="w-6 h-6 text-green-600" />
            </div>
            <div>
              <p className="text-sm font-medium text-gray-600">
                {t('diagnosis.consolidation.last_consolidation')}
              </p>
              <p className="text-sm font-medium text-gray-900">
                {metrics.last_consolidation
                  ? formatDateTime(metrics.last_consolidation)
                  : t('diagnosis.consolidation.never')}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* Incidents Table */}
      <div className="bg-white rounded-lg shadow">
        <div className="px-6 py-4 border-b border-gray-200">
          <h2 className="text-lg font-semibold text-gray-900">
            {t('diagnosis.consolidation.incidents_table_title')}
          </h2>
        </div>
        <div className="overflow-x-auto">
          <table className="min-w-full divide-y divide-gray-200">
            <thead className="bg-gray-50">
              <tr>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('diagnosis.consolidation.columns.tag_id')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('diagnosis.consolidation.columns.incident_type')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('diagnosis.consolidation.columns.postal_center')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('diagnosis.consolidation.columns.description')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('diagnosis.consolidation.columns.detected_at')}
                </th>
                <th className="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">
                  {t('diagnosis.consolidation.columns.status')}
                </th>
              </tr>
            </thead>
            <tbody className="bg-white divide-y divide-gray-200">
              {incidents.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-6 py-4 text-center text-sm text-gray-500">
                    {t('diagnosis.consolidation.no_incidents')}
                  </td>
                </tr>
              ) : (
                incidents.map((incident) => (
                  <tr key={incident.id}>
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
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}
