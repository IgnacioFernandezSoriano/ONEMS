import { ACCESS_OPTIONS, type AccessOption } from './access'

const CL_OPTIONS: AccessOption[] = ACCESS_OPTIONS.filter(o => o.group === 'carrier_link').map(o => o.key)

/**
 * Detalles de Carrier Link dentro de pantallas comunes (Carriers, Eventos procesados): solo con Carrier Link
 * habilitado en esta web Y si la cuenta tiene algún derecho de Carrier Link. Así las cuentas sin Carrier Link
 * (Kenya, Senegal) ven las pantallas de siempre aunque Carrier Link esté visible en producción.
 */
export function carrierLinkUiVisible(flagOn: boolean, canView: (o: AccessOption) => boolean): boolean {
  return flagOn && CL_OPTIONS.some(o => canView(o))
}
