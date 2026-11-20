import { useEffect, useState } from 'react'
import { useLatestRequest } from '@/lib/latestRequest'
import { generateClQuotasLikeAllocation, buildClGeneratorNodes } from '@/lib/carrierLink/clGenerator'
import type { ClQuota } from '@/lib/carrierLink/quotaCalculator'
import { buildPlanRow, routesWithoutStandard, type PlanForm } from '@/lib/carrierLink/planView'
import { parseQuotaCsv, type QuotaCsvError } from '@/lib/carrierLink/quotaCsv'
import type { CityDistributionMatrix, SeasonalDistribution } from '@/lib/allocationPlanCalculator'
import type { City } from '@/lib/types'
import { useClReadingPoints } from './useClReadingPoints'

/** Lo que la página aporta al generador cuando ofrece la captura Carrier Link. */
export interface ClGeneratorSupport {
  accountId: string
  /** Conectores de la cuenta (se filtran por el carrier elegido). */
  feeds: { id: string; carrier_id: string; name: string }[]
  /** Rutas con estándar de entrega (para marcar ⚠ en la vista previa). */
  standardRoutes: (carrierId: string, productId: string) => Promise<{ origin_city_id: string; destination_city_id: string }[]>
  /** Guarda el plan borrador con sus cuotas. */
  save: (form: PlanForm, quotas: ClQuota[]) => Promise<{ ok: true } | { ok: false; key: string }>
}

export interface ClPreview {
  form: PlanForm
  quotas: ClQuota[]
  requested: number
  generated: number
  noStandard: Set<string>
  source: 'generated' | 'csv'
}

export type ClMessage = { kind: 'error' | 'info'; key: string; vars?: Record<string, string | number> }

/**
 * Generación de un plan de Carrier Link desde el Generador de Asignaciones: mismas entradas que el plan de
 * panelistas (total, fechas, matriz, estacionalidad, días laborables), puntos activos del carrier en lugar de
 * panelistas. Vista previa -> guardar como borrador. Sin `support` (o sin carrier) no consulta nada.
 */
export function useClGeneratorFlow(p: {
  support: ClGeneratorSupport | undefined
  carrierId: string | null
  cities: City[]
  workingDows: Set<number>
  nonWorkingDays: string[]
}) {
  const { support, carrierId, cities, workingDows, nonWorkingDays } = p
  const { points, loading: pointsLoading } = useClReadingPoints(support ? support.accountId : null, support ? carrierId : null, {
    withUnknown: false,
  })
  const begin = useLatestRequest()
  const [preview, setPreview] = useState<ClPreview | null>(null)
  const [message, setMessage] = useState<ClMessage | null>(null)
  const [csvErrors, setCsvErrors] = useState<QuotaCsvError[]>([])
  const [busy, setBusy] = useState(false)
  const [saving, setSaving] = useState(false)

  // Al cambiar de carrier (o dejar Carrier Link) la vista previa deja de valer.
  useEffect(() => {
    begin()
    setPreview(null)
    setCsvErrors([])
    setBusy(false)
  }, [carrierId, begin])

  /** Puntos ya cargados y del carrier elegido (no los del carrier anterior). */
  const pointsReady = !!carrierId && !pointsLoading && points.every((pt) => pt.carrier_id === carrierId)
  const generatorPoints = points
    .filter((pt) => pt.city_id)
    .map((pt) => ({ city_id: pt.city_id as string, e2e_role: pt.e2e_role, is_active: pt.is_active }))

  const checkForm = (form: PlanForm): string | null => {
    const built = buildPlanRow(support?.accountId ?? null, form)
    return built.ok ? null : `cl.plans.error.${built.error}`
  }

  const showPreview = async (form: PlanForm, quotas: ClQuota[], requested: number, source: ClPreview['source']) => {
    const isStale = begin()
    setBusy(true)
    let noStandard = new Set<string>()
    try {
      noStandard = routesWithoutStandard(quotas, await support!.standardRoutes(form.carrier_id, form.product_id))
    } catch {
      // Sin estándares legibles no se marca ⚠; al activar lo avisa la base.
    }
    if (isStale()) return
    setBusy(false)
    const generated = quotas.reduce((a, q) => a + q.samples, 0)
    setPreview({ form, quotas, requested, generated, noStandard, source })
  }

  const generate = async (
    form: PlanForm,
    matrix: CityDistributionMatrix,
    useSeasonal: boolean,
    seasonal: SeasonalDistribution | undefined,
  ) => {
    setMessage(null)
    setCsvErrors([])
    setPreview(null)
    const formError = checkForm(form)
    if (formError) return setMessage({ kind: 'error', key: formError })
    if (!pointsReady) return
    const quotas = generateClQuotasLikeAllocation({
      totalSamples: form.total_samples,
      startDate: form.start_date,
      endDate: form.end_date,
      cityDistributionMatrix: matrix,
      useSeasonalDistribution: useSeasonal,
      seasonalDistribution: seasonal,
      nonWorkingDays,
      workingDows,
      points: generatorPoints,
      cities,
    })
    if (quotas.length === 0) return setMessage({ kind: 'error', key: 'cl.plans.no_routes' })
    await showPreview(form, quotas, form.total_samples, 'generated')
  }

  const importCsv = async (file: File, form: PlanForm) => {
    setMessage(null)
    setCsvErrors([])
    setPreview(null)
    // El total sale del fichero: aquí solo se exigen nombre, carrier, producto y fechas.
    const formError = checkForm({ ...form, total_samples: 1 })
    if (formError) return setMessage({ kind: 'error', key: formError })
    if (!pointsReady) return
    const g = buildClGeneratorNodes(generatorPoints, cities)
    const { quotas, errors } = parseQuotaCsv(await file.text(), {
      cities,
      startDate: form.start_date,
      endDate: form.end_date,
      originCityIds: g.originNodeIds,
      destinationCityIds: g.destinationNodeIds,
    })
    if (errors.length > 0) return setCsvErrors(errors)
    const total = quotas.reduce((a, q) => a + q.samples, 0)
    await showPreview({ ...form, total_samples: total }, quotas, total, 'csv')
  }

  /** Guarda la vista previa como plan borrador; true si se guardó. */
  const save = async (): Promise<boolean> => {
    if (!preview || !support) return false
    setSaving(true)
    setMessage(null)
    const res = await support.save(preview.form, preview.quotas)
    setSaving(false)
    if (!res.ok) {
      setMessage({ kind: 'error', key: res.key })
      return false
    }
    setMessage({ kind: 'info', key: 'cl.generator.saved', vars: { name: preview.form.plan_name, count: preview.quotas.length } })
    setPreview(null)
    return true
  }

  const discard = () => {
    begin()
    setBusy(false)
    setPreview(null)
  }

  return { pointsReady, preview, message, csvErrors, busy, saving, generate, importCsv, save, discard }
}
