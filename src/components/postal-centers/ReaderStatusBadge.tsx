import React, { useEffect, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { Reader } from '../../lib/types_postal_centers';
import { supabase } from '../../lib/supabase';

interface ReaderStatusBadgeProps {
  reader: Reader;
  accountId: string;
}

type ReaderStatus = 'active' | 'inactive' | 'offline' | 'unknown';

export default function ReaderStatusBadge({ reader, accountId }: ReaderStatusBadgeProps) {
  const { t } = useTranslation();
  const [status, setStatus] = useState<ReaderStatus>('unknown');
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!reader.is_active) {
      setStatus('inactive');
      setLoading(false);
      return;
    }

    const fetchLastEvent = async () => {
      try {
        const { data, error } = await supabase
          .from('rfid_intermediate_db')
          .select('event_time')
          .eq('account_id', accountId)
          .eq('reader_id', reader.reader_id)
          .order('event_time', { ascending: false })
          .limit(1)
          .single();

        if (error || !data) {
          setStatus('unknown');
          return;
        }

        const lastEventTime = new Date(data.event_time);
        const now = new Date();
        const hoursSinceLastEvent = (now.getTime() - lastEventTime.getTime()) / (1000 * 60 * 60);

        if (hoursSinceLastEvent < 24) {
          setStatus('active');
        } else if (hoursSinceLastEvent < 168) {
          // 7 days
          setStatus('inactive');
        } else {
          setStatus('offline');
        }
      } catch (err) {
        console.error('Error fetching reader status:', err);
        setStatus('unknown');
      } finally {
        setLoading(false);
      }
    };

    fetchLastEvent();
  }, [reader, accountId]);

  if (loading) {
    return (
      <span className="inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800">
        {t('common.loading')}
      </span>
    );
  }

  const statusConfig = {
    active: {
      color: 'bg-green-100 text-green-800',
      label: t('readers.status_active'),
    },
    inactive: {
      color: 'bg-yellow-100 text-yellow-800',
      label: t('readers.status_inactive'),
    },
    offline: {
      color: 'bg-red-100 text-red-800',
      label: t('readers.status_offline'),
    },
    unknown: {
      color: 'bg-gray-100 text-gray-800',
      label: t('readers.status_unknown'),
    },
  };

  const config = statusConfig[status];

  return (
    <span className={`inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium ${config.color}`}>
      {config.label}
    </span>
  );
}
