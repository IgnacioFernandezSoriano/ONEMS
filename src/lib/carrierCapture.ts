/** Forma de captura de un carrier (columna carriers.capture_method). */
export type CaptureMethod = 'panelists' | 'carrier_link' | 'both'

/** Captura concreta de una asignación: por panelistas o por Carrier Link. */
export type Capture = 'panelists' | 'carrier_link'

export const CAPTURE_METHODS: CaptureMethod[] = ['panelists', 'carrier_link', 'both']

/** Clave de traducción de cada forma de captura. */
export const CAPTURE_METHOD_LABEL_KEY: Record<CaptureMethod, string> = {
  panelists: 'cl.capture_method.panelists',
  carrier_link: 'cl.capture_method.carrier_link',
  both: 'cl.capture_method.both',
}

/** Forma de captura de un carrier; sin valor (o desconocido) cuenta como 'panelists', lo de siempre. */
export function captureMethodOf(carrier: { capture_method?: string | null }): CaptureMethod {
  const m = carrier.capture_method
  return m === 'carrier_link' || m === 'both' ? m : 'panelists'
}

/** Carriers que admiten una captura: 'panelists' los de panelistas o ambos; 'carrier_link' los de Carrier Link o ambos. */
export function carriersForCapture<T extends { capture_method?: string | null }>(carriers: T[], capture: Capture): T[] {
  return carriers.filter((c) => {
    const m = captureMethodOf(c)
    return m === 'both' || m === capture
  })
}

/** Capturas que admite un carrier: 'both' -> las dos; si no, solo la suya. */
export function captureOptionsFor(carrier: { capture_method?: string | null }): Capture[] {
  const m = captureMethodOf(carrier)
  return m === 'both' ? ['panelists', 'carrier_link'] : [m]
}

/**
 * Datos de alta/edición de un carrier listos para enviar: sin Carrier Link habilitado se quita capture_method,
 * para que producción funcione igual que antes (aunque la columna aún no exista).
 */
export function carrierWritePayload<T extends { capture_method?: unknown }>(
  data: T,
  carrierLinkOn: boolean,
): T | Omit<T, 'capture_method'> {
  if (carrierLinkOn) return data
  const out: Partial<T> = { ...data }
  delete out.capture_method
  return out as Omit<T, 'capture_method'>
}
