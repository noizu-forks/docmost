import { toDataEnvelope, toPaginationOptions } from './pagination';

describe('pagination envelope remap (v1)', () => {
  it('maps items to data and passes the cursor when there is a next page', () => {
    const result = toDataEnvelope({
      items: [{ id: 'a' }],
      meta: { hasNextPage: true, nextCursor: 'cursor_2' },
    } as any);

    expect(result).toEqual({
      data: [{ id: 'a' }],
      meta: { nextCursor: 'cursor_2' },
    });
  });

  it('returns a null nextCursor on the last page even when a cursor exists', () => {
    const result = toDataEnvelope({
      items: [],
      meta: { hasNextPage: false, nextCursor: 'unused' },
    } as any);

    expect(result).toEqual({ data: [], meta: { nextCursor: null } });
  });

  it('defaults the limit to 20 and passes the cursor through', () => {
    expect(toPaginationOptions(undefined, 'cursor_1')).toEqual({
      limit: 20,
      cursor: 'cursor_1',
    });
  });

  it('keeps an explicit limit and tolerates a missing cursor', () => {
    expect(toPaginationOptions(50)).toEqual({ limit: 50, cursor: undefined });
  });
});
