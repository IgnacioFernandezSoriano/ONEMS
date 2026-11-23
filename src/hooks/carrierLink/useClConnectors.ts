import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import type { ConnectorStatus, StandardField } from '@/lib/carrierLink/connectorConfig'
import {
  CONTENT_TYPE_BY_FORMAT,
  parseFeedCalendar,
  withGraceHours,
  type ClFeedCalendar,
  type DeliveryFormat,
  type ManualDeliveryApi,
} from '@/lib/carrierLink/deliveryView'

export interface ClFeed {
  id: string
  carrier_id: string
  name: string
  extraction_model: string | null
  status: ConnectorStatus
  emit_days: number[]
  emit_hour: number
  emit_timezone: string | null
  last_batch_at: string | null
  last_error: string | null
  created_at: string
  /** Topes del fichero y margen de no recibido (missing_grace_hours). */
  config: Record<string, unknown> | null
}

export interface ClFeedForm {
  carrier_id: string
  name: string
  extraction_model: string
  emit_days: number[]
  emit_hour: number
  emit_timezone: string
}

export interface ClFieldMapping {
  id: string
  carrier_id: string
  standard_field: StandardField
  carrier_field: string
  format: string | null
  timezone: string | null
}

export interface ClValueMapping {
  id: string
  carrier_id: string
  kind: 'product'
  carrier_value: string
  onems_value: string
}

export interface ClExtraField {
  id: string
  carrier_id: string
  carrier_field: string
}

export interface ClFeedKey {
  id: string
  name: string | null
  key_prefix: string | null
  feed_id: string | null
  is_active: boolean
  created_at: string
  last_used_at: string | null
  usage_count: number
  expires_at: string | null
}

export interface ClProductOption {
  id: string
  carrier_id: string
  code: string
  description: string
}

export type ClDbError = { message?: string; code?: string }
export type ClConnectorResult = { success: true } | { success: false; error: ClDbError }

/** Límite de seguridad de las listas (una cuenta tiene pocos conectores y pocas claves). */
const LIST_LIMIT = 500

const FEED_COLUMNS =
  'id, carrier_id, name, extraction_model, status, emit_days, emit_hour, emit_timezone, last_batch_at, last_error, created_at, config'

/** Configuración de conectores de Carrier Link de una cuenta. Los mapeos son por cuenta + carrier (no por conector). */
export function useClConnectors(accountId: string | null) {
  const beginLoad = useLatestRequest()
  const [feeds, setFeeds] = useState<ClFeed[]>([])
  const [fieldMappings, setFieldMappings] = useState<ClFieldMapping[]>([])
  const [valueMappings, setValueMappings] = useState<ClValueMapping[]>([])
  const [extraFields, setExtraFields] = useState<ClExtraField[]>([])
  const [allKeys, setAllKeys] = useState<ClFeedKey[]>([])
  const [products, setProducts] = useState<ClProductOption[]>([])
  const [keysError, setKeysError] = useState<ClDbError | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<ClDbError | null>(null)

  const refetch = useCallback(async () => {
    const isStale = beginLoad()
    if (!accountId) {
      setFeeds([])
      setFieldMappings([])
      setValueMappings([])
      setExtraFields([])
      setAllKeys([])
      setProducts([])
      setError(null)
      setKeysError(null)
      setLoading(false)
      return
    }
    setLoading(true)
    const [f, fm, vm, ef, k, p] = await Promise.all([
      supabase.from('cl_feeds').select(FEED_COLUMNS).eq('account_id', accountId).order('name').limit(LIST_LIMIT),
      supabase
        .from('cl_field_mappings')
        .select('id, carrier_id, standard_field, carrier_field, format, timezone')
        .eq('account_id', accountId)
        .limit(LIST_LIMIT),
      supabase
        .from('cl_value_mappings')
        .select('id, carrier_id, kind, carrier_value, onems_value')
        .eq('account_id', accountId)
        .eq('kind', 'product')
        .order('carrier_value')
        .limit(LIST_LIMIT),
      supabase
        .from('cl_extra_fields')
        .select('id, carrier_id, carrier_field')
        .eq('account_id', accountId)
        .order('carrier_field')
        .limit(LIST_LIMIT),
      supabase
        .from('api_keys')
        .select('id, name, key_prefix, feed_id, is_active, created_at, last_used_at, usage_count, expires_at')
        .eq('account_id', accountId)
        .eq('scope', 'carrier_feed')
        .order('created_at', { ascending: false })
        .limit(LIST_LIMIT),
      supabase
        .from('products')
        .select('id, carrier_id, code, description')
        .eq('account_id', accountId)
        .eq('status', 'active')
        .order('code')
        .limit(LIST_LIMIT),
    ])
    if (isStale()) return
    setError(f.error ?? fm.error ?? vm.error ?? ef.error ?? p.error ?? null)
    setFeeds((f.data ?? []) as ClFeed[])
    setFieldMappings((fm.data ?? []) as ClFieldMapping[])
    setValueMappings((vm.data ?? []) as ClValueMapping[])
    setExtraFields((ef.data ?? []) as ClExtraField[])
    // El error de claves se expone aparte: la pantalla solo lo muestra a quien puede gestionarlas.
    setAllKeys(k.error ? [] : ((k.data ?? []) as ClFeedKey[]))
    setKeysError(k.error ?? null)
    setProducts((p.data ?? []) as ClProductOption[])
    setLoading(false)
  }, [accountId, beginLoad])

  useEffect(() => {
    void refetch()
  }, [refetch])

  const carrierOf = (feedId: string) => feeds.find((x) => x.id === feedId)?.carrier_id ?? null

  /** Equivalencias del carrier de un conector. */
  const mappings = (feedId: string) => {
    const carrierId = carrierOf(feedId)
    return {
      fields: fieldMappings.filter((m) => m.carrier_id === carrierId),
      values: valueMappings.filter((m) => m.carrier_id === carrierId),
      extras: extraFields.filter((m) => m.carrier_id === carrierId),
      products: products.filter((m) => m.carrier_id === carrierId),
    }
  }

  const keys = (feedId: string) => allKeys.filter((k) => k.feed_id === feedId)

  const run = async (op: PromiseLike<{ error: ClDbError | null }>): Promise<ClConnectorResult> => {
    const { error: e } = await op
    if (e) return { success: false, error: e }
    await refetch()
    return { success: true }
  }

  const noAccount: ClConnectorResult = { success: false, error: { message: 'CL_FORBIDDEN' } }

  const feedRow = (f: ClFeedForm) => ({
    carrier_id: f.carrier_id,
    name: f.name.trim(),
    extraction_model: f.extraction_model.trim() || null,
    emit_days: [...f.emit_days].sort((a, b) => a - b),
    emit_hour: f.emit_hour,
    emit_timezone: f.emit_timezone.trim() || null,
  })

  const saveFeed = async (id: string | null, f: ClFeedForm): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    if (id) {
      // El carrier no se cambia: las claves, los planes y los mapeos cuelgan de él.
      const { carrier_id: _c, ...fields } = feedRow(f)
      void _c
      return run(supabase.from('cl_feeds').update(fields).eq('id', id).eq('account_id', accountId))
    }
    return run(supabase.from('cl_feeds').insert({ ...feedRow(f), account_id: accountId }))
  }

  const removeFeed = async (id: string): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    return run(supabase.from('cl_feeds').delete().eq('id', id).eq('account_id', accountId))
  }

  const setStatus = async (feedId: string, status: ConnectorStatus): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    return run(supabase.from('cl_feeds').update({ status }).eq('id', feedId).eq('account_id', accountId))
  }

  /** Alta o cambio del campo del carrier para un campo estándar (único por cuenta + carrier + campo). */
  const saveFieldMapping = async (
    carrierId: string,
    m: { standard_field: StandardField; carrier_field: string; format: string; timezone: string },
  ): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    return run(
      supabase.from('cl_field_mappings').upsert(
        {
          account_id: accountId,
          carrier_id: carrierId,
          standard_field: m.standard_field,
          carrier_field: m.carrier_field.trim(),
          format: m.format.trim() || null,
          timezone: m.timezone.trim() || null,
        },
        { onConflict: 'account_id,carrier_id,standard_field' },
      ),
    )
  }

  const removeFieldMapping = async (id: string): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    return run(supabase.from('cl_field_mappings').delete().eq('id', id).eq('account_id', accountId))
  }

  const saveValueMapping = async (carrierId: string, carrierValue: string, onemsValue: string): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    return run(
      supabase.from('cl_value_mappings').insert({
        account_id: accountId,
        carrier_id: carrierId,
        kind: 'product',
        carrier_value: carrierValue.trim(),
        onems_value: onemsValue,
      }),
    )
  }

  const removeValueMapping = async (id: string): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    return run(supabase.from('cl_value_mappings').delete().eq('id', id).eq('account_id', accountId))
  }

  const saveExtraField = async (carrierId: string, carrierField: string): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    return run(
      supabase.from('cl_extra_fields').insert({ account_id: accountId, carrier_id: carrierId, carrier_field: carrierField.trim() }),
    )
  }

  const removeExtraField = async (id: string): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    return run(supabase.from('cl_extra_fields').delete().eq('id', id).eq('account_id', accountId))
  }

  /** Emite una clave del conector. El texto completo solo se conoce ahora. */
  const issueKey = async (feedId: string, name: string, expiresAt: string | null): Promise<{ id: string; api_key: string }> => {
    if (!accountId) throw { message: 'CL_FORBIDDEN' }
    const { data, error: e } = await supabase.rpc('api_key_issue', {
      p_account_id: accountId,
      p_name: name.trim(),
      p_scope: 'carrier_feed',
      p_feed_id: feedId,
      p_expires_at: expiresAt,
    })
    if (e) throw e
    const issued = Array.isArray(data) ? data[0] : data
    if (!issued?.api_key) throw { message: 'API key was not returned' }
    await refetch()
    return { id: issued.id, api_key: issued.api_key }
  }

  const deactivateKey = async (id: string): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    return run(supabase.rpc('api_key_deactivate', { p_key_id: id }))
  }

  /**
   * Cambia el margen de "no recibido" (config.missing_grace_hours) sin tocar las demas claves del config. Se parte del
   * config cargado; la escritura va por id + cuenta.
   */
  const saveGraceHours = async (feedId: string, hours: number): Promise<ClConnectorResult> => {
    if (!accountId) return noAccount
    const current = feeds.find((f) => f.id === feedId)
    if (!current) return noAccount
    return run(
      supabase
        .from('cl_feeds')
        .update({ config: withGraceHours(current.config, hours) })
        .eq('id', feedId)
        .eq('account_id', accountId),
    )
  }

  /**
   * Subida manual de una entrega (mismo camino que la API del conector): abrir con la huella, subir el fichero con la
   * sesion del usuario a la ruta que decide la base (sin reemplazar) y completar. Ver runManualDelivery.
   */
  const manualDeliveryApi = (feedId: string, file: Blob): ManualDeliveryApi => ({
    open: async ({ periodStart, periodEnd, sha256, format }) => {
      const { data, error: e } = await supabase.rpc('cl_manual_delivery_open', {
        p_feed_id: feedId,
        p_period_start: periodStart,
        p_period_end: periodEnd,
        p_sha256: sha256,
        p_control_totals: [],
        p_format: format,
      })
      if (e) throw e
      return data
    },
    upload: async (path: string, format: DeliveryFormat) => {
      const { error: e } = await supabase.storage
        .from('cl-deliveries')
        .upload(path, file, { contentType: CONTENT_TYPE_BY_FORMAT[format], upsert: false })
      return { error: e ? { message: e.message, statusCode: (e as { statusCode?: string | number }).statusCode } : null }
    },
    complete: async (deliveryId: string) => {
      const { data, error: e } = await supabase.rpc('cl_manual_delivery_complete', { p_feed_id: feedId, p_delivery_id: deliveryId })
      if (e) throw e
      return data
    },
  })

  return {
    feeds,
    loading,
    error,
    refetch,
    mappings,
    keys,
    keysError,
    saveFeed,
    removeFeed,
    setStatus,
    saveFieldMapping,
    removeFieldMapping,
    saveValueMapping,
    removeValueMapping,
    saveExtraField,
    removeExtraField,
    issueKey,
    deactivateKey,
    saveGraceHours,
    manualDeliveryApi,
  }
}

/** Calendario de entregas de un conector (frecuencia, proximo periodo, margen). `version` fuerza la recarga. */
export function useClFeedCalendar(feedId: string | null, version: unknown) {
  const beginLoad = useLatestRequest()
  const [calendar, setCalendar] = useState<ClFeedCalendar | null>(null)
  const [error, setError] = useState<ClDbError | null>(null)
  useEffect(() => {
    const isStale = beginLoad()
    if (!feedId) {
      setCalendar(null)
      setError(null)
      return
    }
    void supabase.rpc('cl_feed_delivery_calendar', { p_feed_id: feedId }).then(({ data, error: e }) => {
      if (isStale()) return
      setError(e ?? null)
      setCalendar(e ? null : parseFeedCalendar(data))
    })
  }, [feedId, version, beginLoad])
  return { calendar, error }
}
