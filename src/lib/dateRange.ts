/**
 * Un periodo es utilizable cuando ambas fechas estan completas (yyyy-MM-dd), con anyo razonable y inicio <= fin.
 * Un <input type="date"> emite valores intermedios mientras se teclea (anyo 0002, 0020, 0202...): no se debe
 * consultar la base con ellos.
 */
export function isUsablePeriod(start: string, end: string): boolean {
  const re = /^(\d{4})-(\d{2})-(\d{2})$/
  const a = re.exec(start)
  const b = re.exec(end)
  if (!a || !b) return false
  const ya = Number(a[1])
  const yb = Number(b[1])
  if (ya < 2000 || ya > 2100 || yb < 2000 || yb > 2100) return false
  return start <= end
}
