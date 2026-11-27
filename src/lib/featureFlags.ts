/**
 * Carrier Link visible en DEV y en producción (decisión del propietario, 27/11/2026; antes solo DEV).
 * Dentro de cada cuenta lo limitan los derechos (cl_*), que hoy solo tiene DEMO2. Comprobación en
 * tiempo de ejecución por nombre de host (producción y DEV comparten netlify.toml); un host
 * desconocido queda desactivado.
 * VITE_CARRIER_LINK = 'on' | 'off' fuerza el resultado.
 */
const DEV_HOSTS = ['localhost', '127.0.0.1', 'onem-dev.netlify.app', 'onems.edgeavs.net']
const DEV_PREVIEW_SUFFIX = '--onem-dev.netlify.app'

export function isCarrierLinkEnabled(
  hostname?: string,
  override: string | undefined = import.meta.env?.VITE_CARRIER_LINK,
): boolean {
  if (override === 'on') return true
  if (override === 'off') return false
  const host = (
    hostname ?? (typeof window !== 'undefined' ? window.location?.hostname : '') ?? ''
  ).toLowerCase()
  if (!host) return false
  return DEV_HOSTS.includes(host) || host.endsWith(DEV_PREVIEW_SUFFIX)
}
