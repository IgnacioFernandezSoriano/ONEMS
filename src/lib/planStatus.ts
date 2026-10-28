// Estados de una muestra del plan que cuentan como "pendientes" (aun sin enviar).
// 'deferred' = muestra apartada al registro "por compensar" (fila sintetica de la vista, solo lectura).
export function isPendingLike(status: string | null | undefined): boolean {
  return status === 'pending' || status === 'notified' || status === 'deferred'
}

export function isDeferredStatus(status: string | null | undefined): boolean {
  return status === 'deferred'
}

// Quita las filas sinteticas "por compensar": no estan en transito (no cuentan en totales operativos, retrasos
// ni alertas de disponibilidad del Dashboard).
export function withoutDeferred<T extends { status?: string | null }>(rows: T[]): T[] {
  return rows.filter(r => !isDeferredStatus(r.status))
}
