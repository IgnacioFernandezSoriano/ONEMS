export interface CityRunOutcome<T> {
  cityId: string
  result?: T
  error?: string
}

/**
 * Ejecuta `run` para cada ciudad, de una en una. Nunca lanza: un fallo se
 * registra como `error` y se continua con la siguiente ciudad.
 */
export async function runForCities<T>(
  cityIds: string[],
  run: (cityId: string) => Promise<T>,
  onProgress: (done: number, total: number) => void
): Promise<Array<CityRunOutcome<T>>> {
  const out: Array<CityRunOutcome<T>> = []
  const total = cityIds.length
  for (let i = 0; i < total; i++) {
    const cityId = cityIds[i]
    try {
      out.push({ cityId, result: await run(cityId) })
    } catch (err: unknown) {
      out.push({ cityId, error: err instanceof Error ? err.message : String(err) })
    }
    try {
      onProgress(i + 1, total)
    } catch {
      // un fallo al notificar progreso no debe detener el proceso
    }
  }
  return out
}
