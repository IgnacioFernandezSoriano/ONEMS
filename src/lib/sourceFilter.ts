/** Un filtro de origen fijado no puede quedar aplicado si la cuenta ya no tiene filas carrier. */
export function shouldResetSource(
  presence: { loaded: boolean; carrier: boolean },
  value: string
): boolean {
  return presence.loaded && !presence.carrier && value !== '';
}
