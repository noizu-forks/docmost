import { Injectable, ForbiddenException, NotFoundException } from '@nestjs/common';
import { InjectKysely } from 'nestjs-kysely';
import { KyselyDB } from '@docmost/db/types/kysely.types';
import { PagePermission } from '@docmost/db/types/entity.types';
import {
  CursorPaginationResult,
  executeWithCursorPagination,
} from '@docmost/db/pagination/cursor-pagination';
import { PaginationOptions } from '@docmost/db/pagination/pagination-options';
import { PagePermissionRole } from '../../common/helpers/types/permission';

export type V1GrantType = 'user' | 'group';
export type V1GrantRole = PagePermissionRole;

export interface V1Grant {
  id: string;
  type: V1GrantType;
  principalId: string;
  role: V1GrantRole;
}

export interface V1GrantInput {
  type: V1GrantType;
  principalId: string;
  role: V1GrantRole;
}

/**
 * The single place where v1 grant shapes map onto page_permissions storage
 * (principle 8: page_permissions.id is the stable grant id).
 */
@Injectable()
export class GrantsMapper {
  constructor(@InjectKysely() private readonly db: KyselyDB) {}

  static toGrantRows(
    pageAccessId: string,
    grants: V1GrantInput[],
    addedById: string,
  ) {
    return grants.map((grant) => ({
      pageAccessId,
      userId: grant.type === 'user' ? grant.principalId : undefined,
      groupId: grant.type === 'group' ? grant.principalId : undefined,
      role: grant.role,
      addedById,
    }));
  }

  static toGrantDto(row: PagePermission): V1Grant {
    if (row.userId) {
      return { id: row.id, type: 'user', principalId: row.userId, role: row.role as V1GrantRole };
    }
    return { id: row.id, type: 'group', principalId: row.groupId!, role: row.role as V1GrantRole };
  }

  /**
   * Cursor-paginated grant list straight from page_permissions so items
   * carry the stable permission id (principle 8), unlike the repo's
   * principal-oriented member listing.
   */
  async listGrants(
    pageAccessId: string,
    pagination: PaginationOptions,
  ): Promise<CursorPaginationResult<V1Grant>> {
    const query = this.db
      .selectFrom('pagePermissions')
      .selectAll()
      .where('pageAccessId', '=', pageAccessId);

    const result = await executeWithCursorPagination(query, {
      perPage: pagination.limit,
      cursor: pagination.cursor,
      fields: [{ expression: 'id', direction: 'asc' }],
      parseCursor: (cursor) => ({ id: cursor.id }),
    } as any);

    return { ...result, items: result.items.map((row) => GrantsMapper.toGrantDto(row)) };
  }

  /**
   * Look a grant up by id and resolve the user-vs-group column, so
   * PATCH/DELETE by grantId can target the right principal.
   */
  async findGrantById(grantId: string): Promise<V1Grant> {
    const row = await this.db
      .selectFrom('pagePermissions')
      .selectAll()
      .where('id', '=', grantId)
      .executeTakeFirst();

    if (!row) {
      throw new NotFoundException('Grant not found');
    }

    return GrantsMapper.toGrantDto(row);
  }

  /** Update by grant id; verifies the grant belongs to the given page access. */
  async updateRoleById(
    grantId: string,
    expectedPageAccessId: string,
    role: V1GrantRole,
  ): Promise<void> {
    const grant = await this.findGrantById(grantId);
    if (
      !(await this.belongsToPageAccess(grant.id, expectedPageAccessId))
    ) {
      throw new ForbiddenException();
    }

    await this.db
      .updateTable('pagePermissions')
      .set({ role, updatedAt: new Date() })
      .where('id', '=', grantId)
      .execute();
  }

  /** Idempotent delete by grant id (principle 6). */
  async deleteById(grantId: string, expectedPageAccessId: string): Promise<void> {
    const row = await this.db
      .selectFrom('pagePermissions')
      .selectAll()
      .where('id', '=', grantId)
      .executeTakeFirst();

    if (!row) {
      return;
    }

    if (row.pageAccessId !== expectedPageAccessId) {
      throw new ForbiddenException();
    }

    await this.db
      .deleteFrom('pagePermissions')
      .where('id', '=', grantId)
      .execute();
  }

  private async belongsToPageAccess(
    grantId: string,
    pageAccessId: string,
  ): Promise<boolean> {
    const row = await this.db
      .selectFrom('pagePermissions')
      .select('pageAccessId')
      .where('id', '=', grantId)
      .executeTakeFirst();
    return row?.pageAccessId === pageAccessId;
  }
}
