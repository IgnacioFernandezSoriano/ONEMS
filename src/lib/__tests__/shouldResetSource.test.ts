import { describe, it, expect } from 'vitest';
import { shouldResetSource } from '../sourceFilter';

describe('shouldResetSource', () => {
  it('limpia el filtro si la cuenta cargada no tiene carrier', () => {
    expect(shouldResetSource({ loaded: true, carrier: false }, 'carrier')).toBe(true);
  });
  it('no toca nada mientras carga, con carrier o sin filtro', () => {
    expect(shouldResetSource({ loaded: false, carrier: false }, 'carrier')).toBe(false);
    expect(shouldResetSource({ loaded: true, carrier: true }, 'carrier')).toBe(false);
    expect(shouldResetSource({ loaded: true, carrier: false }, '')).toBe(false);
  });
});
