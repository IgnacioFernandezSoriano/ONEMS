import { useEffect, useRef, useState } from 'react'
import { AlertTriangle, Loader2 } from 'lucide-react'
import { useTranslation } from '@/hooks/useTranslation'
import { clErrorKey } from '@/lib/carrierLink/clErrors'
import { routeKey } from '@/lib/carrierLink/planView'
import type { ClMissingPoint, ClMissingStandard, ClPlan, ClPlanResult } from '@/hooks/carrierLink/useClPlans'

const btnPrimary = 'inline-flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 disabled:opacity-50'
const btnDanger = 'inline-flex items-center gap-2 px-4 py-2 bg-red-600 text-white rounded-md hover:bg-red-700 disabled:opacity-50'
const btnSecondary = 'inline-flex items-center gap-2 px-4 py-2 border border-gray-300 rounded-md hover:bg-gray-50 disabled:opacity-50'

/** Máximo de rutas sin estándar listadas en el aviso. */
const STANDARD_LIST_LIMIT = 30

export type ClPlanAction = 'activate' | 'delete'

interface Props {
  plan: ClPlan
  action: ClPlanAction
  cityName: (id: string) => string
  /** Número de cuotas del plan (contado en el servidor). */
  quotaCount: (planId: string) => Promise<number>
  missingPoints: (planId: string) => Promise<ClMissingPoint[]>
  missingStandards: (planId: string) => Promise<ClMissingStandard[]>
  activate: (planId: string) => Promise<ClPlanResult>
  remove: (planId: string) => Promise<ClPlanResult>
  /** Cierra el panel; con mensaje si la acción terminó (o falló). */
  onClose: (message?: { kind: 'error' | 'info'; key: string; vars?: Record<string, string | number> }) => void
}

interface Checks {
  quotaCount: number
  missingPoints: ClMissingPoint[]
  missingStandards: ClMissingStandard[]
}

/** Confirmación en página de "Aplicar" (activar) o "Eliminar" un plan borrador de Carrier Link. */
export function ClPlanActionPanel({ plan, action, cityName, quotaCount, missingPoints, missingStandards, activate, remove, onClose }: Props) {
  const { t } = useTranslation()
  const [checks, setChecks] = useState<Checks | null>(null)
  const [loadError, setLoadError] = useState<string | null>(null)
  const [running, setRunning] = useState(false)
  const confirmRef = useRef<HTMLButtonElement | null>(null)
  const focused = useRef(false)

  // Antes de activar: cuotas guardadas, puntos que faltan y rutas sin estándar.
  useEffect(() => {
    if (action !== 'activate') return
    let cancelled = false
    setChecks(null)
    setLoadError(null)
    void Promise.all([quotaCount(plan.id), missingPoints(plan.id), missingStandards(plan.id)])
      .then(([n, mp, ms]) => {
        if (!cancelled) setChecks({ quotaCount: n, missingPoints: mp, missingStandards: ms })
      })
      .catch((e) => {
        if (!cancelled) setLoadError(clErrorKey(e as { message?: string; code?: string }))
      })
    return () => {
      cancelled = true
    }
  }, [action, plan.id, quotaCount, missingPoints, missingStandards])

  const run = async () => {
    setRunning(true)
    const res = action === 'activate' ? await activate(plan.id) : await remove(plan.id)
    setRunning(false)
    if (!res.success) {
      onClose({ kind: 'error', key: res.key ?? clErrorKey(res.error) })
      return
    }
    onClose({ kind: 'info', key: action === 'activate' ? 'cl.generator.activated' : 'cl.generator.deleted', vars: { name: plan.plan_name } })
  }

  // Foco en el botón de confirmar en cuanto esté disponible (tras cargar las comprobaciones al activar).
  const confirmReady = action === 'delete' || (!!checks && !!plan.feed_id && checks.quotaCount > 0 && checks.missingPoints.length === 0)
  useEffect(() => {
    if (confirmReady && !focused.current) {
      focused.current = true
      confirmRef.current?.focus()
    }
  }, [confirmReady])

  if (action === 'delete') {
    return (
      <div className="rounded-lg border border-red-200 bg-red-50 p-4 space-y-3">
        <p className="text-sm text-red-900">{t('cl.generator.delete_confirm', { name: plan.plan_name })}</p>
        <div className="flex gap-2">
          <button type="button" onClick={() => onClose()} disabled={running} className={btnSecondary}>
            {t('common.cancel')}
          </button>
          <button ref={confirmRef} type="button" onClick={() => void run()} disabled={running} className={btnDanger}>
            {running && <Loader2 className="w-4 h-4 animate-spin" />}
            {t('allocation_generator.delete')}
          </button>
        </div>
      </div>
    )
  }

  // Un borrador antiguo sin conector no se puede activar (la base daría CL_NO_FEED) ni editar desde aquí.
  const noFeed = !plan.feed_id
  const blocked = noFeed || !checks || checks.quotaCount === 0 || checks.missingPoints.length > 0
  return (
    <div className="rounded-lg border border-blue-200 bg-blue-50 p-4 space-y-3">
      <p className="text-sm text-blue-900">{t('cl.plans.activate_confirm', { name: plan.plan_name })}</p>
      {noFeed && <p className="text-sm text-red-700">{t('cl.generator.needs_connector')}</p>}
      {!checks && !loadError && <p className="text-sm text-gray-500">{t('common.loading')}</p>}
      {loadError && <p className="text-sm text-red-600">{t(loadError)}</p>}
      {checks && checks.quotaCount === 0 && <p className="text-sm text-red-700">{t('cl.generator.no_quotas')}</p>}

      {checks && checks.missingPoints.length > 0 && (
        <div className="rounded-lg border border-red-200 bg-red-50 p-3 space-y-1">
          <p className="font-medium text-red-900">{t('cl.plans.missing_points_title')}</p>
          <p className="text-sm text-red-900">{t('cl.plans.missing_points_help')}</p>
          <ul className="text-sm text-red-900 list-disc ps-5">
            {checks.missingPoints.map((m) => (
              <li key={`${m.city_id}|${m.missing}`}>
                {m.city_name}: {t(`cl.plans.missing.${m.missing}`)}
              </li>
            ))}
          </ul>
        </div>
      )}

      {checks && checks.missingStandards.length > 0 && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-3 space-y-1">
          <p className="font-medium text-amber-900 inline-flex items-center gap-2">
            <AlertTriangle className="w-4 h-4" />
            {t('cl.plans.missing_standards_title', { count: checks.missingStandards.length })}
          </p>
          <p className="text-sm text-amber-900">{t('cl.plans.missing_standards_help')}</p>
          <ul className="text-sm text-amber-900 list-disc ps-5">
            {checks.missingStandards.slice(0, STANDARD_LIST_LIMIT).map((s) => (
              <li key={routeKey(s.origin_city_id, s.destination_city_id)}>
                {cityName(s.origin_city_id)} → {cityName(s.destination_city_id)}: ⚠ {t('cl.plans.no_standard')}
              </li>
            ))}
          </ul>
          {checks.missingStandards.length > STANDARD_LIST_LIMIT && (
            <p className="text-sm text-amber-900">{t('cl.generator.more_routes', { count: checks.missingStandards.length - STANDARD_LIST_LIMIT })}</p>
          )}
        </div>
      )}

      <div className="flex gap-2">
        <button type="button" onClick={() => onClose()} disabled={running} className={btnSecondary}>
          {t('common.cancel')}
        </button>
        <button
          ref={confirmRef}
          type="button"
          onClick={() => void run()}
          disabled={running || blocked}
          title={checks && checks.missingPoints.length > 0 ? t('cl.plans.activate_blocked') : undefined}
          className={btnPrimary}
        >
          {running && <Loader2 className="w-4 h-4 animate-spin" />}
          {t('allocation_generator.apply')}
        </button>
      </div>
    </div>
  )
}
