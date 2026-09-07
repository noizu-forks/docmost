import { CursorPaginationResult } from '@docmost/db/pagination/cursor-pagination';
import { PaginationOptions } from '@docmost/db/pagination/pagination-options';

/**
 * Principle 2: core cursor pagination returns {items, meta}; v1 lists use
 * {data, meta.nextCursor}. Single remap point.
 */
export function toDataEnvelope<T>(result: CursorPaginationResult<T>): {
  data: T[];
  meta: { nextCursor: string | null };
} {
  return {
    data: result.items,
    meta: { nextCursor: result.meta.hasNextPage ? result.meta.nextCursor : null },
  };
}

/** Build core PaginationOptions from v1 ?limit=&cursor= query params. */
export function toPaginationOptions(
  limit?: number,
  cursor?: string,
): PaginationOptions {
  return { limit: limit ?? 20, cursor } as PaginationOptions;
}
