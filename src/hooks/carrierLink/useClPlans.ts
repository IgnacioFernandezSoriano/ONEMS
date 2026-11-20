import { useCallback, useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useLatestRequest } from '@/lib/latestRequest'
import { fetchAllPages } from '@/lib/fetchAllPages'
import { workingDowsFromSchedule } from '@/lib/workingDays'
import type { ClQuota } from '@/lib/carrierLink/quotaCalculator'
import { buildPlanRow, LOCKED_WHEN_NOT_DRAFT, type PlanForm, type QuotaInput } from '@/lib/carrierLink/planView'

export type ClPlanStatus = 'draft' | 'active' | 'closed'

export interface ClPlan {
  id: string
  plan_name: string
  carrier_id: string
  carrier_name: string | null
  product_id: string
  product_label: string | null
  feed_id: string | null
  start_date: string
  end_date: string
  total_samples: number
  feed_diagnosis: boolean
  status: ClPlanStatus
}

export interface ClPlanProduct {
  id: string
  carrier_id: string
  code: string
  description: string
}

export interface ClMissingPoint {
  city_id: string
  city_name: string
  missing: 'origin' | 'destination'
}

export interface ClMissingStandard {
  origin_city_id: string
  destination_city_id: string
}

export type ClDbError = { message?: string; code?: string }
export type ClPlanResult = { success: true; id?: string } | { success: false; error: ClDbError; key?: string }

const LIST_LIMIT = 500

const PLAN_COLUMNS =
  'id, plan_name, carrier_id, product_id, feed_id, start_date, end_date, total_samples, feed_diagnosis, status, carrier:carriers(name), product:products(code, description)'

/** Planes de muestreo de Carrier Link de una cuenta (varios a la vez: uno por producto). */
export function useClPlans(accountId: string | null) {
  const beginLoad = useLatestRequest()
  const [plans, setPlans] = useState<ClPlan[]>([])
  const [products, setProducts] = useState<ClPlanProduct[]>([])
  const [cityNames, setCityNames] = useState<Map<string, string>>(new Map())
  const [workingDows, setWorkingDows] = useState<number[]>([1, 2, 3, 4, 5])
  const [nonWorkingDays, setNonWorkingDays] = useState<string[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<ClDbError | null>(null)

  const refetch = useCallback(async () => {
    const isStale = beginLoad()
    if (!accountId) {
      setPlans([])
      setProducts([])
      setCityNames(new Map())
      setError(null)
      setLoading(false)
      return
    }
    setLoading(true)
    const [p, pr, ws, nwd] = await Promise.all([
      supabase.from('cl_plans').select(PLAN_COLUMNS).eq('account_id', accountId).order('created_at', { ascending: false }).limit(LIST_LIMIT),
      supabase
        .from('products')
        .select('id, carrier_id, code, description')
        .eq('account_id', accountId)
        .eq('status', 'active')
        .order('code')
        .limit(LIST_LIMIT),
      supabase.from('weekly_schedule').select('day_of_week, is_working_day').eq('account_id', accountId).is('postal_center_id', null),
      supabase.from('non_working_days').select('date').eq('account_id', accountId).is('postal_center_id', null),
    ])
    let cities: { id: string; name: string }[] = []
    let citiesError: ClDbError | null = null
    try {
      cities = await fetchAllPages<{ id: string; name: string }>((from, to) =>
        supabase.from('cities').select('id, name').eq('account_id', accountId).order('id').range(from, to),
      )
    } catch (e) {
      citiesError = e as ClDbError
    }
    if (isStale()) return
    setError(p.error ?? pr.error ?? citiesError ?? null)
    setPlans(
      ((p.data ?? []) as any[]).map((r) => ({
        id: r.id,
        plan_name: r.plan_name,
        carrier_id: r.carrier_id,
        carrier_name: r.carrier?.name ?? null,
        product_id: r.product_id,
        product_label: r.product ? `${r.product.code} - ${r.product.description}` : null,
        feed_id: r.feed_id ?? null,
        start_date: r.start_date,
        end_date: r.end_date,
        total_samples: r.total_samples,
        feed_diagnosis: r.feed_diagnosis,
        status: r.status,
      })),
    )
    setProducts((pr.data ?? []) as ClPlanProduct[])
    setCityNames(new Map(cities.map((c) => [c.id, c.name])))
    // Calendario de la cuenta como en Allocation Plans: si falla, lunes a viernes sin festivos.
    setWorkingDows(ws.error ? [1, 2, 3, 4, 5] : [...workingDowsFromSchedule((ws.data ?? []) as any[])])
    setNonWorkingDays(nwd.error ? [] : ((nwd.data ?? []) as { date: string }[]).map((d) => d.date))
    setLoading(false)
  }, [accountId, beginLoad])

  useEffect(() => {
    void refetch()
  }, [refetch])

  /** Todas las cuotas del plan (un plan puede tener decenas de miles: se pagina de 1.000 en 1.000). */
  const quotas = useCallback(
    (planId: string): Promise<QuotaInput[]> =>
      fetchAllPages<QuotaInput>((from, to) =>
        supabase
          .from('cl_plan_quotas')
          .select(
            'origin_city_id, destination_city_id, iso_year, iso_week, samples_planned, samples_carried_in, samples_obtained, status',
          )
          .eq('plan_id', planId)
          .order('id')
          .range(from, to),
      ),
    [],
  )

  const create = async (f: PlanForm): Promise<ClPlanResult> => {
    const built = buildPlanRow(accountId, f)
    if (!built.ok) return { success: false, error: { message: built.error }, key: `cl.plans.error.${built.error}` }
    const { data, error: e } = await supabase.from('cl_plans').insert(built.row).select('id').single()
    if (e) return { success: false, error: e }
    await refetch()
    return { success: true, id: (data as { id: string }).id }
  }

  /** Solo columnas que la base deja cambiar; en un plan no borrador no se envían las bloqueadas. */
  const update = async (id: string, f: PlanForm, status: ClPlanStatus): Promise<ClPlanResult> => {
    const built = buildPlanRow(accountId, f)
    if (!built.ok) return { success: false, error: { message: built.error }, key: `cl.plans.error.${built.error}` }
    const fields: Record<string, unknown> = { ...built.row }
    delete fields.account_id
    if (status !== 'draft') for (const k of LOCKED_WHEN_NOT_DRAFT) delete fields[k]
    const { error: e } = await supabase.from('cl_plans').update(fields).eq('id', id).eq('account_id', accountId!)
    if (e) return { success: false, error: e }
    await refetch()
    return { success: true }
  }

  /** Sustituye las cuotas pendientes del plan borrador (la base valida todo antes de borrar). */
  const setQuotas = async (planId: string, q: ClQuota[]): Promise<ClPlanResult> => {
    const { error: e } = await supabase.rpc('cl_plan_set_quotas', { p_plan_id: planId, p_quotas: q })
    if (e) return { success: false, error: e }
    return { success: true }
  }

  const missingPoints = useCallback(
    (planId: string): Promise<ClMissingPoint[]> =>
      fetchAllPages<ClMissingPoint>((from, to) => supabase.rpc('cl_plan_missing_points', { p_plan_id: planId }).range(from, to)),
    [],
  )

  const missingStandards = useCallback(
    (planId: string): Promise<ClMissingStandard[]> =>
      fetchAllPages<ClMissingStandard>((from, to) =>
        supabase.rpc('cl_plan_missing_standards', { p_plan_id: planId }).range(from, to),
      ),
    [],
  )

  /** Rutas con estándar de entrega para el carrier + producto (para marcar ⚠ en la vista previa antes de guardar). */
  const standardRoutes = useCallback(
    (carrierId: string, productId: string): Promise<ClMissingStandard[]> => {
      if (!accountId) return Promise.resolve([])
      return fetchAllPages<ClMissingStandard>((from, to) =>
        supabase
          .from('delivery_standards')
          .select('origin_city_id, destination_city_id')
          .eq('account_id', accountId)
          .eq('carrier_id', carrierId)
          .eq('product_id', productId)
          .order('id')
          .range(from, to),
      )
    },
    [accountId],
  )

  const activate = async (planId: string): Promise<ClPlanResult> => {
    const { error: e } = await supabase.rpc('cl_plan_activate', { p_plan_id: planId })
    if (e) return { success: false, error: e }
    await refetch()
    return { success: true }
  }

  /**
   * Borra un plan borrador (sus cuotas caen en cascada). Si la base no deja borrar la fila (permisos o ya no es
   * borrador) no se borra nada y se devuelve la clave del aviso.
   */
  const remove = async (planId: string): Promise<ClPlanResult> => {
    if (!accountId) return { success: false, error: { message: 'no_account' }, key: 'cl.plans.error.no_account' }
    const { data, error: e } = await supabase
      .from('cl_plans')
      .delete()
      .eq('id', planId)
      .eq('account_id', accountId)
      .eq('status', 'draft')
      .select('id')
    if (e) return { success: false, error: e }
    await refetch()
    if (!data || data.length === 0) return { success: false, error: { message: 'not_deleted' }, key: 'cl.generator.delete_not_allowed' }
    return { success: true }
  }

  const cityName = useCallback((id: string) => cityNames.get(id) ?? id, [cityNames])

  return {
    plans,
    products,
    cityName,
    workingDows,
    nonWorkingDays,
    loading,
    error,
    refetch,
    quotas,
    create,
    update,
    setQuotas,
    missingPoints,
    missingStandards,
    standardRoutes,
    activate,
    remove,
  }
}
