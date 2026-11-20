import { describe, it, expect, vi } from 'vitest';
vi.mock('../supabase', () => ({ supabase: {} }));
import { applySourceFilter } from '../e2eCalculations';

describe('applySourceFilter', () => {
  it('no filtra cuando el origen esta vacio', () => {
    const q = { eq: vi.fn() };
    const out = applySourceFilter(q, '');
    expect(q.eq).not.toHaveBeenCalled();
    expect(out).toBe(q);
  });
  it('filtra por source cuando viene un origen', () => {
    const next = {};
    const q = { eq: vi.fn().mockReturnValue(next) };
    const out = applySourceFilter(q, 'carrier');
    expect(q.eq).toHaveBeenCalledWith('source', 'carrier');
    expect(out).toBe(next);
  });
});
