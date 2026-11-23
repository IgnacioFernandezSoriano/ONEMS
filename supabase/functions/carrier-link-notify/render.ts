// Carrier Link v4.1: textos de los correos de incidencias (D26). Escuetos, en el idioma de la cuenta (en es fr ar pt;
// cualquier otro -> en). Solo nombre del conector, periodos y recuentos: nunca datos de envios ni textos de error.

export type IncidentType = 'missing_delivery' | 'delivery_rejected' | 'high_rejection' | 'unknown_data' | 'quota_unfilled'
export type Lang = 'en' | 'es' | 'fr' | 'ar' | 'pt'

export interface PeriodEntry {
  period_start?: string
  period_end?: string
  rejected?: number
  shipments?: number
  ratio?: number
  products?: number
  points?: number
  missing?: number
}

/** Un aviso tal como lo devuelve cl_notify_claim. */
export interface NotifyItem {
  notification_id: string
  recipient_kind: 'account_manager' | 'carrier'
  to: string[]
  language: string
  incident_type: IncidentType
  event: 'opened' | 'appended'
  connector: string
  open_periods: number
  periods: PeriodEntry[]
}

export interface Email { subject: string; text: string }

interface Texts {
  title: Record<IncidentType, string>
  body: Record<IncidentType, string>
  open: string
  footerAccount: string
  footerCarrier: string
}

// Marcadores: {connector} {periods} {open} {rejected} {shipments} {pct} {products} {points} {missing}
const T: Record<Lang, Texts> = {
  en: {
    title: {
      missing_delivery: 'Delivery not received', delivery_rejected: 'Delivery rejected',
      high_rejection: 'Many shipments rejected', unknown_data: 'Unknown points or products',
      quota_unfilled: 'Weekly quota not met',
    },
    body: {
      missing_delivery: 'No delivery has been received from connector {connector} for: {periods}.',
      delivery_rejected: 'The delivery of connector {connector} for {periods} was rejected. Please send it again.',
      high_rejection: 'In the delivery of connector {connector} for {periods}, {rejected} of {shipments} shipments were rejected ({pct}%).',
      unknown_data: 'The delivery of connector {connector} for {periods} contains {products} unknown products and {points} unknown reading points.',
      quota_unfilled: 'The week {periods} of connector {connector} closed with {missing} samples missing.',
    },
    open: 'Periods still pending in this incident: {open}.',
    footerAccount: 'Details in ONEMS > Carrier Link > Incidents.',
    footerCarrier: 'This is an automatic notice from ONEMS.',
  },
  es: {
    title: {
      missing_delivery: 'Entrega no recibida', delivery_rejected: 'Entrega rechazada',
      high_rejection: 'Muchos envíos rechazados', unknown_data: 'Puntos o productos desconocidos',
      quota_unfilled: 'Cuota semanal no cubierta',
    },
    body: {
      missing_delivery: 'No se ha recibido la entrega del conector {connector} de: {periods}.',
      delivery_rejected: 'La entrega del conector {connector} de {periods} ha sido rechazada. Envíela de nuevo, por favor.',
      high_rejection: 'En la entrega del conector {connector} de {periods} se rechazaron {rejected} de {shipments} envíos ({pct} %).',
      unknown_data: 'La entrega del conector {connector} de {periods} trae {products} productos y {points} puntos de lectura desconocidos.',
      quota_unfilled: 'La semana {periods} del conector {connector} se cerró con {missing} muestras de menos.',
    },
    open: 'Periodos pendientes en esta incidencia: {open}.',
    footerAccount: 'Detalle en ONEMS > Carrier Link > Incidencias.',
    footerCarrier: 'Aviso automático de ONEMS.',
  },
  fr: {
    title: {
      missing_delivery: 'Livraison non reçue', delivery_rejected: 'Livraison rejetée',
      high_rejection: 'Nombreux envois rejetés', unknown_data: 'Points ou produits inconnus',
      quota_unfilled: 'Quota hebdomadaire non atteint',
    },
    body: {
      missing_delivery: 'Aucune livraison du connecteur {connector} n’a été reçue pour : {periods}.',
      delivery_rejected: 'La livraison du connecteur {connector} pour {periods} a été rejetée. Merci de la renvoyer.',
      high_rejection: 'Dans la livraison du connecteur {connector} pour {periods}, {rejected} envois sur {shipments} ont été rejetés ({pct} %).',
      unknown_data: 'La livraison du connecteur {connector} pour {periods} contient {products} produits et {points} points de lecture inconnus.',
      quota_unfilled: 'La semaine {periods} du connecteur {connector} s’est terminée avec {missing} échantillons manquants.',
    },
    open: 'Périodes encore en attente dans cet incident : {open}.',
    footerAccount: 'Détails dans ONEMS > Carrier Link > Incidents.',
    footerCarrier: 'Avis automatique d’ONEMS.',
  },
  ar: {
    title: {
      missing_delivery: 'لم يتم استلام التسليم', delivery_rejected: 'تم رفض التسليم',
      high_rejection: 'رفض عدد كبير من الشحنات', unknown_data: 'نقاط أو منتجات غير معروفة',
      quota_unfilled: 'لم تكتمل الحصة الأسبوعية',
    },
    body: {
      missing_delivery: 'لم يتم استلام أي تسليم من الموصل {connector} للفترة: {periods}.',
      delivery_rejected: 'تم رفض تسليم الموصل {connector} للفترة {periods}. يرجى إرساله مرة أخرى.',
      high_rejection: 'في تسليم الموصل {connector} للفترة {periods} تم رفض {rejected} من أصل {shipments} شحنة ({pct}%).',
      unknown_data: 'يحتوي تسليم الموصل {connector} للفترة {periods} على {products} منتجات و{points} نقاط قراءة غير معروفة.',
      quota_unfilled: 'أُغلق أسبوع {periods} للموصل {connector} مع نقص {missing} عينات.',
    },
    open: 'الفترات التي لا تزال معلقة في هذه الحادثة: {open}.',
    footerAccount: 'التفاصيل في ONEMS > Carrier Link > الحوادث.',
    footerCarrier: 'هذا إشعار تلقائي من ONEMS.',
  },
  pt: {
    title: {
      missing_delivery: 'Entrega não recebida', delivery_rejected: 'Entrega rejeitada',
      high_rejection: 'Muitos envios rejeitados', unknown_data: 'Pontos ou produtos desconhecidos',
      quota_unfilled: 'Quota semanal não cumprida',
    },
    body: {
      missing_delivery: 'Não foi recebida a entrega do conector {connector} de: {periods}.',
      delivery_rejected: 'A entrega do conector {connector} de {periods} foi rejeitada. Por favor, envie-a novamente.',
      high_rejection: 'Na entrega do conector {connector} de {periods} foram rejeitados {rejected} de {shipments} envios ({pct} %).',
      unknown_data: 'A entrega do conector {connector} de {periods} contém {products} produtos e {points} pontos de leitura desconhecidos.',
      quota_unfilled: 'A semana {periods} do conector {connector} fechou com {missing} amostras em falta.',
    },
    open: 'Períodos ainda pendentes neste incidente: {open}.',
    footerAccount: 'Detalhes em ONEMS > Carrier Link > Incidentes.',
    footerCarrier: 'Aviso automático do ONEMS.',
  },
}

export const LANGS = Object.keys(T) as Lang[]
export const TYPES: IncidentType[] = ['missing_delivery', 'delivery_rejected', 'high_rejection', 'unknown_data', 'quota_unfilled']

export function pickLang(l: string | null | undefined): Lang {
  const k = String(l ?? '').toLowerCase().slice(0, 2)
  return (LANGS as string[]).includes(k) ? k as Lang : 'en'
}

const DATE = /^\d{4}-\d{2}-\d{2}$/
const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) && v >= 0 ? v : 0)
const sum = (ps: PeriodEntry[], k: keyof PeriodEntry) => ps.reduce((a, p) => a + num(p[k]), 0)

/** "2026-11-16" o "2026-11-16 – 2026-11-22"; lo que no sea una fecha se descarta. */
export function formatPeriods(ps: PeriodEntry[]): string {
  return ps
    .filter((p) => DATE.test(String(p.period_start)) && DATE.test(String(p.period_end ?? p.period_start)))
    .map((p) => (p.period_end && p.period_end !== p.period_start ? `${p.period_start} – ${p.period_end}` : String(p.period_start)))
    .join(', ')
}

/** Nombre del conector sin saltos de linea ni caracteres de control (va en el asunto). */
function clean(s: string): string {
  // deno-lint-ignore no-control-regex
  return String(s ?? '').replace(/[\u0000-\u001f\u007f]+/g, ' ').trim().slice(0, 120)
}

export function renderEmail(item: NotifyItem): Email {
  const lang = pickLang(item.language)
  const t = T[lang]
  const type = (TYPES as string[]).includes(item.incident_type) ? item.incident_type : 'missing_delivery'
  const ps = Array.isArray(item.periods) ? item.periods : []
  const rejected = sum(ps, 'rejected')
  const shipments = sum(ps, 'shipments')
  const vars: Record<string, string> = {
    connector: clean(item.connector),
    periods: formatPeriods(ps),
    open: String(num(item.open_periods)),
    rejected: String(rejected),
    shipments: String(shipments),
    pct: shipments > 0 ? String(Math.round((rejected * 1000) / shipments) / 10) : '0',
    products: String(sum(ps, 'products')),
    points: String(sum(ps, 'points')),
    missing: String(sum(ps, 'missing')),
  }
  const fill = (s: string) => s.replace(/\{(\w+)\}/g, (_, k) => vars[k] ?? '')
  const lines = [fill(t.body[type])]
  if (type === 'missing_delivery' && num(item.open_periods) > ps.length) lines.push(fill(t.open))
  lines.push('', item.recipient_kind === 'carrier' ? t.footerCarrier : t.footerAccount)
  return { subject: `[ONEMS Carrier Link] ${t.title[type]} – ${vars.connector}`, text: lines.join('\n') }
}
