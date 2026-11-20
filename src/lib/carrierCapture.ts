/** Forma de captura de un carrier (columna carriers.capture_method). */
export type CaptureMethod = 'panelists' | 'carrier_link' | 'both'

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

/** Carriers que ofrece cada generador: 'panelists' (E2E) los de panelistas o ambos; 'carrier_link' los de Carrier Link o ambos. */
export function carriersForCapture<T extends { capture_method?: string | null }>(
  carriers: T[],
  generator: 'panelists' | 'carrier_link',
): T[] {
  return carriers.filter((c) => {
    const m = captureMethodOf(c)
    return m === 'both' || m === generator
  })
}
