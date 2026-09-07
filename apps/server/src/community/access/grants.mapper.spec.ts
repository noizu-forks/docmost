import { ForbiddenException, NotFoundException } from '@nestjs/common';
import { GrantsMapper } from './grants.mapper';
import { PagePermissionRole } from '../../common/helpers/types/permission';
import { executeWithCursorPagination } from '@docmost/db/pagination/cursor-pagination';

const { READER, WRITER } = PagePermissionRole;

jest.mock('@docmost/db/pagination/cursor-pagination', () => ({
  executeWithCursorPagination: jest.fn(),
}));

(executeWithCursorPagination as jest.Mock).mockResolvedValue({
  items: [{ id: 'grant_1', userId: 'user_1', role: 'writer' }],
  meta: { hasNextPage: false },
});

describe('GrantsMapper', () => {
  function createMapper(rows: Record<string, unknown>[] = []) {
    const builder: any = {
      selectFrom: jest.fn().mockReturnThis(),
      selectAll: jest.fn().mockReturnThis(),
      select: jest.fn().mockReturnThis(),
      where: jest.fn().mockReturnThis(),
      updateTable: jest.fn().mockReturnThis(),
      set: jest.fn().mockReturnThis(),
      deleteFrom: jest.fn().mockReturnThis(),
      executeTakeFirst: jest.fn(async () => rows[0]),
      execute: jest.fn().mockResolvedValue(undefined),
    };
    const mapper = new GrantsMapper(builder);
    return { mapper, builder };
  }

  describe('static row mappers', () => {
    it('maps user grants onto the userId column', () => {
      expect(
        GrantsMapper.toGrantRows('access_1', [
          { type: 'user', principalId: 'user_1', role: WRITER },
        ], 'admin_1'),
      ).toEqual([
        {
          pageAccessId: 'access_1',
          userId: 'user_1',
          groupId: undefined,
          role: WRITER,
          addedById: 'admin_1',
        },
      ]);
    });

    it('maps group grants onto the groupId column', () => {
      expect(
        GrantsMapper.toGrantRows('access_1', [
          { type: 'group', principalId: 'group_1', role: READER },
        ], 'admin_1'),
      ).toEqual([
        {
          pageAccessId: 'access_1',
          userId: undefined,
          groupId: 'group_1',
          role: READER,
          addedById: 'admin_1',
        },
      ]);
    });

    it('maps rows with a userId back to user grants', () => {
      expect(
        GrantsMapper.toGrantDto({
          id: 'grant_1',
          userId: 'user_1',
          groupId: null,
          role: WRITER,
        } as any),
      ).toEqual({
        id: 'grant_1',
        type: 'user',
        principalId: 'user_1',
        role: WRITER,
      });
    });

    it('maps rows without a userId back to group grants', () => {
      expect(
        GrantsMapper.toGrantDto({
          id: 'grant_2',
          userId: null,
          groupId: 'group_1',
          role: READER,
        } as any),
      ).toEqual({
        id: 'grant_2',
        type: 'group',
        principalId: 'group_1',
        role: READER,
      });
    });
  });

  describe('listGrants', () => {
    it('returns paginated grants through the cursor executor', async () => {
      const { mapper, builder } = createMapper();

      const result = await mapper.listGrants('access_1', { limit: 25, cursor: 'c1' } as any);

      expect(executeWithCursorPagination).toHaveBeenCalledWith(
        builder,
        expect.objectContaining({ perPage: 25, cursor: 'c1' }),
      );
      expect(result.items).toEqual([
        { id: 'grant_1', type: 'user', principalId: 'user_1', role: WRITER },
      ]);
    });
  });

  describe('findGrantById', () => {
    it('resolves a grant by id', async () => {
      const { mapper } = createMapper([
        { id: 'grant_1', userId: 'user_1', role: WRITER, pageAccessId: 'access_1' },
      ]);

      const grant = await mapper.findGrantById('grant_1');

      expect(grant.type).toBe('user');
    });

    it('404s on an unknown grant id', async () => {
      const { mapper } = createMapper([]);

      await expect(mapper.findGrantById('missing')).rejects.toThrow(
        NotFoundException,
      );
    });
  });

  describe('updateRoleById', () => {
    it('updates the role when the grant belongs to the page access', async () => {
      const { mapper, builder } = createMapper([
        { id: 'grant_1', pageAccessId: 'access_1' },
      ]);

      await mapper.updateRoleById('grant_1', 'access_1', WRITER);

      expect(builder.updateTable).toHaveBeenCalledWith('pagePermissions');
      expect(builder.set).toHaveBeenCalledWith(
        expect.objectContaining({ role: WRITER }),
      );
    });

    it('forbids the update when the grant lives on another page access', async () => {
      const { mapper } = createMapper([
        { id: 'grant_1', pageAccessId: 'access_other' },
      ]);

      await expect(
        mapper.updateRoleById('grant_1', 'access_1', WRITER),
      ).rejects.toThrow(ForbiddenException);
    });
  });

  describe('deleteById', () => {
    it('is a no-op for an unknown grant', async () => {
      const { mapper, builder } = createMapper([]);

      await mapper.deleteById('missing', 'access_1');

      expect(builder.deleteFrom).not.toHaveBeenCalled();
    });

    it('forbids deleting a grant owned by another page access', async () => {
      const { mapper, builder } = createMapper([
        { id: 'grant_1', pageAccessId: 'access_other' },
      ]);

      await expect(
        mapper.deleteById('grant_1', 'access_1'),
      ).rejects.toThrow(ForbiddenException);
      expect(builder.deleteFrom).not.toHaveBeenCalled();
    });

    it('deletes the grant when ownership matches', async () => {
      const { mapper, builder } = createMapper([
        { id: 'grant_1', pageAccessId: 'access_1' },
      ]);

      await mapper.deleteById('grant_1', 'access_1');

      expect(builder.deleteFrom).toHaveBeenCalledWith('pagePermissions');
      expect(builder.execute).toHaveBeenCalled();
    });
  });
});
